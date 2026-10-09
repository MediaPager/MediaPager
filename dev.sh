#!/bin/sh
# MediaPager dev environment runner (SQLite :5074/:5173, PostgreSQL :5075/:5174).
#
#   ./dev.sh up            bring both database variants up (logs under ~/.MediaPager/dev)
#   ./dev.sh down          stop both API/SPA pairs (PostGIS stays running)
#   ./dev.sh restart       down (if up), then up
#   ./dev.sh show          print the clickable URLs for the env
#   ./dev.sh secrets       print all secrets/passwords in use
#   ./dev.sh --refresh     drop both dev databases, then migrate + seed them from scratch
#   ./dev.sh help|--help   print this help
#
# Optional creds come from ~/.MediaPager/dev/credentials.sh (or legacy ~/.zsh/.creds/mediapager):
#   MEDIAPAGER_TMDB_API_KEY (read directly by the TMDB plugin; saved Settings value wins)
#   MEDIAPAGER_Auth__SigningKey (JWT signing key, stable tokens)
#   MEDIAPAGER_SEED_USER    -> MEDIAPAGER_Auth__SeedEmail (initial super-admin email)
#   MEDIAPAGER_SEED_PASS    -> MEDIAPAGER_Auth__SeedPassword (initial super-admin password)
set -eu
cd "$(dirname "$0")"

if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$(printf '\033[0m')
  C_BOLD=$(printf '\033[1m')
  C_CYAN=$(printf '\033[1;36m')
  C_GREEN=$(printf '\033[1;32m')
  C_ORANGE=$(printf '\033[1;38;5;208m')
  C_YELLOW=$(printf '\033[1;33m')
else
  C_RESET=''
  C_BOLD=''
  C_CYAN=''
  C_GREEN=''
  C_ORANGE=''
  C_YELLOW=''
fi

say_info() { printf '%s%s%s\n' "$C_CYAN" "$1" "$C_RESET"; }
say_success() { printf '%s%s%s\n' "$C_GREEN" "$1" "$C_RESET"; }
say_warning() { printf '%s%s%s\n' "$C_YELLOW" "$1" "$C_RESET"; }

report_log_errors() {
  report_file="$1"
  error_lines="$(grep -iE 'error|ERR!|exception|fatal|failed|failure|fail:|unhandled|cannot|could not|does not exist|not found|deps\.json|MSB[0-9]+' "$report_file" 2>/dev/null | tail -n 20 || :)"
  if [ -n "$error_lines" ]; then
    printf '%s\n' "$error_lines" >&2
  else
    printf 'No error lines were recognized; full log: %s\n' "$report_file" >&2
  fi
}

API_PORT=5074
SPA_PORT=5173
POSTGRES_API_PORT=5075
POSTGRES_SPA_PORT=5174
RUN_DIR="$HOME/.MediaPager/dev"
DEFAULT_CREDS_FILE="$RUN_DIR/credentials.sh"
LEGACY_CREDS_FILE="$HOME/.zsh/.creds/mediapager"
CREDS_FILE="${MEDIAPAGER_DEV_CREDENTIALS_FILE:-$DEFAULT_CREDS_FILE}"
API_PID_FILE="$RUN_DIR/api.pid"
SPA_PID_FILE="$RUN_DIR/spa.pid"
API_LOG="$RUN_DIR/api.log"
SPA_LOG="$RUN_DIR/spa.log"
POSTGRES_API_PID_FILE="$RUN_DIR/postgres-api.pid"
POSTGRES_SPA_PID_FILE="$RUN_DIR/postgres-spa.pid"
POSTGRES_API_LOG="$RUN_DIR/postgres-api.log"
POSTGRES_SPA_LOG="$RUN_DIR/postgres-spa.log"
POSTGRES_PUBLISH_LOG="$RUN_DIR/postgres-publish.log"
POSTGRES_DROP_LOG="$RUN_DIR/postgres-drop.log"
REFRESH_BUILD_LOG="$RUN_DIR/refresh-build.log"
NPM_INSTALL_LOG="$RUN_DIR/npm-install.log"
POSTGRES_PLUGIN_DIR="$RUN_DIR/postgres-plugins"
POSTGRES_APP_DIR="$RUN_DIR/postgres-app"
POSTGRES_DB="mediapager_dev"
POSTGRES_CONTAINER="postgis"
POSTGRES_IMAGE="imresamu/postgis:18-3.6"
POSTGRES_VOLUME="mediapager-dev-postgis-data"
POSTGRES_DEFAULT_CONNECTION_STRING="Host=127.0.0.1;Port=5432;Database=mediapager_dev;Username=postgres;Password=password"
DEFAULT_DEV_SIGNING_KEY="your_32_byte_sign_key_placeholder_here"

if [ -n "${MEDIAPAGER_DEV_CREDENTIALS_FILE:-}" ]; then
  CREDS_FILE="$MEDIAPAGER_DEV_CREDENTIALS_FILE"
elif [ ! -f "$CREDS_FILE" ] && [ -f "$LEGACY_CREDS_FILE" ]; then
  CREDS_FILE="$LEGACY_CREDS_FILE"
fi
# Use only a seed user explicitly set in the local credentials file; ignore a stale value
# inherited from a shell that sourced an older credentials file.
unset MEDIAPAGER_SEED_USER
if [ -f "$CREDS_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$CREDS_FILE"
  set +a
fi

if [ -z "${MEDIAPAGER_Auth__SigningKey:-}" ] && [ -n "${MEDIAPAGER_EKEY:-}" ]; then
  export MEDIAPAGER_Auth__SigningKey="$MEDIAPAGER_EKEY"
fi
if [ -z "${MEDIAPAGER_Auth__SigningKey:-}" ]; then
  export MEDIAPAGER_Auth__SigningKey="$DEFAULT_DEV_SIGNING_KEY"
fi
export MEDIAPAGER_EKEY="$MEDIAPAGER_Auth__SigningKey"
USING_DEFAULT_DEV_SIGNING_KEY=0
if [ "$MEDIAPAGER_Auth__SigningKey" = "$DEFAULT_DEV_SIGNING_KEY" ]; then
  USING_DEFAULT_DEV_SIGNING_KEY=1
fi
export MEDIAPAGER_SEED_USER="${MEDIAPAGER_SEED_USER:-admin@mediapager.local}"
if [ -z "${MEDIAPAGER_SEED_PASS:-}" ]; then
  MEDIAPAGER_SEED_PASS='DefaultPasswordChangeMe'
fi
export MEDIAPAGER_SEED_PASS
export MEDIAPAGER_Auth__SeedEmail="${MEDIAPAGER_SEED_USER:-}"
export MEDIAPAGER_Auth__SeedPassword="${MEDIAPAGER_SEED_PASS:-}"
export ASPNETCORE_ENVIRONMENT=Development

DB_FILE="${MEDIAPAGER_DB_PATH:-${MPAGER_AUTH_DB_PATH:-$HOME/.MediaPager/db/mediapager.db}}"
USING_DEFAULT_POSTGRES_SETTINGS=0
if [ -z "${MEDIAPAGER_Database__Provider:-}" ] || [ -z "${MEDIAPAGER_ConnectionStrings__AuthDatabase:-}" ]; then
  USING_DEFAULT_POSTGRES_SETTINGS=1
fi
export MEDIAPAGER_Database__Provider="${MEDIAPAGER_Database__Provider:-PostgreSQL}"
POSTGRES_CONNECTION_STRING="${MEDIAPAGER_ConnectionStrings__AuthDatabase:-$POSTGRES_DEFAULT_CONNECTION_STRING}"
export MEDIAPAGER_ConnectionStrings__AuthDatabase="$POSTGRES_CONNECTION_STRING"

usage() {
  printf '\n%s%s%s\n\n' "$C_BOLD" 'MediaPager dev environment' "$C_RESET"
  printf '  %sSQLite%s     API http://localhost:%s · SPA http://localhost:%s\n' "$C_ORANGE" "$C_RESET" "$API_PORT" "$SPA_PORT"
  printf '  %sPostgreSQL%s API http://localhost:%s · SPA http://localhost:%s\n\n' "$C_ORANGE" "$C_RESET" "$POSTGRES_API_PORT" "$POSTGRES_SPA_PORT"
  printf '%sCommands%s\n' "$C_BOLD" "$C_RESET"
  printf '  %-22s %s\n' './dev.sh up' 'start both database variants'
  printf '  %-22s %s\n' './dev.sh down' 'stop both API/SPA pairs (PostGIS stays running)'
  printf '  %-22s %s\n' './dev.sh restart' 'down, then up'
  printf '  %-22s %s\n' './dev.sh show' 'show URLs and service status'
  printf '  %-22s %s\n' './dev.sh secrets' 'show configured settings'
  printf '  %-22s %s\n' './dev.sh --refresh' 'drop both dev databases and reseed'
  printf '  %-22s %s\n\n' './dev.sh help' 'show this help (also the no-argument default)'
  printf 'Credentials: %s\n' "$CREDS_FILE"
  printf 'Logs: %s · %s · %s · %s\n\n' "$API_LOG" "$SPA_LOG" "$POSTGRES_API_LOG" "$POSTGRES_SPA_LOG"
}

port_pids() {
  lsof -ti "tcp:$1" -sTCP:LISTEN 2>/dev/null || :
}

port_up() {
  [ -n "$(port_pids "${1}")" ]
}

pid_alive() {
  pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

service_pid() {
  cat "$1" 2>/dev/null || :
}

kill_port() {
  port="$1"
  pids="$(port_pids "$port")"
  if [ -z "$pids" ]; then
    return 0
  fi
  say_info "→ killing listener(s) on :${port} (pid $(printf '%s' "$pids" | tr '\n' ' '))"
  # shellcheck disable=SC2086
  printf '%s\n' $pids | xargs kill -9 2>/dev/null || true
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ! port_up "$port"; then
      return 0
    fi
    sleep 0.3
  done
  say_warning "!! something still holds :${port}" >&2
  return 1
}

stop_service() {
  name="$1"
  pidfile="$2"
  port="$3"
  pid="$(service_pid "$pidfile")"
  if pid_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    for attempt in 1 2 3 4 5 6 7 8; do
      pid_alive "$pid" || break
      sleep 0.25
    done
    if pid_alive "$pid"; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pidfile"
  # dotnet run / npm spawn children that inherit the port — free it regardless.
  kill_port "$port" || true
}

stop_env() {
  had=""
  if pid_alive "$(service_pid "$API_PID_FILE")" || port_up "$API_PORT"; then
    had=1
    stop_service "api" "$API_PID_FILE" "$API_PORT"
  fi
  if pid_alive "$(service_pid "$SPA_PID_FILE")" || port_up "$SPA_PORT"; then
    had=1
    stop_service "spa" "$SPA_PID_FILE" "$SPA_PORT"
  fi
  if pid_alive "$(service_pid "$POSTGRES_API_PID_FILE")" || port_up "$POSTGRES_API_PORT"; then
    had=1
    stop_service "PostgreSQL API" "$POSTGRES_API_PID_FILE" "$POSTGRES_API_PORT"
  fi
  if pid_alive "$(service_pid "$POSTGRES_SPA_PID_FILE")" || port_up "$POSTGRES_SPA_PORT"; then
    had=1
    stop_service "PostgreSQL SPA" "$POSTGRES_SPA_PID_FILE" "$POSTGRES_SPA_PORT"
  fi
}

plugins_root() {
  echo "${MEDIAPAGER_Plugins__Directory:-$HOME/.MediaPager/plugins}"
}

cmd_down() {
  say_info 'Stopping MediaPager dev services...'
  stop_env
  say_success 'MediaPager dev services stopped.'
}

wait_for_service() {
  label="$1"
  port="$2"
  pidfile="$3"
  log="$4"
  timeout="$5"
  deadline=$((timeout * 2))
  attempt=0
  say_info "Waiting for ${label}..."
  while [ "$attempt" -lt "$deadline" ]; do
    if port_up "$port"; then
      say_success "${label} is ready at http://localhost:${port}"
      return 0
    fi
    pid="$(service_pid "$pidfile")"
    if [ -n "$pid" ] && ! pid_alive "$pid"; then
      say_warning "ERROR: ${label} exited during startup." >&2
      report_log_errors "$log"
      return 1
    fi
    sleep 0.5
    attempt=$((attempt + 1))
  done
  say_warning "ERROR: ${label} did not come up within ${timeout}s." >&2
  report_log_errors "$log"
  return 1
}

ensure_postgres() {
  if [ "$POSTGRES_CONNECTION_STRING" != "$POSTGRES_DEFAULT_CONNECTION_STRING" ]; then
    say_info 'Checking configured PostgreSQL connection...'
    return 0
  fi
  say_info 'Checking local PostGIS...'
  command -v docker >/dev/null 2>&1 || {
    say_warning "!! Docker is required for the default local PostGIS database. Install Docker Desktop or configure MEDIAPAGER_ConnectionStrings__AuthDatabase." >&2
    return 1
  }
  docker info >/dev/null 2>&1 || {
    say_warning "!! Docker is installed but not running. Start Docker Desktop and retry." >&2
    return 1
  }

  if docker container inspect "$POSTGRES_CONTAINER" >/dev/null 2>&1; then
    running="$(docker inspect --format '{{.State.Running}}' "$POSTGRES_CONTAINER")"
    if [ "$running" != "true" ]; then
      say_info "Starting PostGIS container $POSTGRES_CONTAINER..."
      docker start "$POSTGRES_CONTAINER" >/dev/null 2>&1
    fi
  else
    if lsof -ti "tcp:5432" -sTCP:LISTEN >/dev/null 2>&1; then
      say_warning "!! Port 5432 is already in use but the $POSTGRES_CONTAINER container does not exist." >&2
      printf '   Free port 5432 or set MEDIAPAGER_ConnectionStrings__AuthDatabase to your PostgreSQL connection.\n' >&2
      return 1
    fi
    docker volume inspect "$POSTGRES_VOLUME" >/dev/null 2>&1 || docker volume create "$POSTGRES_VOLUME" >/dev/null
    say_info "Creating local PostGIS container ($POSTGRES_IMAGE)..."
    docker run -d --name "$POSTGRES_CONTAINER" \
      -e POSTGRES_PASSWORD=password \
      -p 5432:5432 \
      -v "$POSTGRES_VOLUME:/var/lib/postgresql" \
      "$POSTGRES_IMAGE" >/dev/null 2>&1
  fi

  attempt=0
  while [ "$attempt" -lt 90 ]; do
    if docker exec "$POSTGRES_CONTAINER" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
      say_success 'PostGIS is ready.'
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  say_warning 'ERROR: PostGIS did not become ready. Relevant container errors:' >&2
  docker logs --tail 100 "$POSTGRES_CONTAINER" 2>&1 | grep -iE 'error|exception|fatal|failed|failure|cannot|could not' | tail -n 20 >&2 || :
  return 1
}

ensure_ui_dependencies() {
  if [ ! -d MediaPager.App.Ui/node_modules ]; then
    say_info 'Installing SPA dependencies...'
    if ! ( cd MediaPager.App.Ui && npm ci ) >"$NPM_INSTALL_LOG" 2>&1; then
      say_warning 'ERROR: npm ci failed. Relevant errors:' >&2
      report_log_errors "$NPM_INSTALL_LOG"
      return 1
    fi
  fi
}

print_dev_summary() {
  seed_user_display="$MEDIAPAGER_SEED_USER"
  seed_password_note='Custom MEDIAPAGER_SEED_PASS override; used only when creating a new admin.'
  if [ "$MEDIAPAGER_SEED_PASS" = 'DefaultPasswordChangeMe' ]; then
    seed_password_note='DefaultPasswordChangeMe is used for a fresh database or after --refresh.'
  fi

  printf '\n%s%s%s\n' "$C_CYAN" '============================================================' "$C_RESET"
  printf '%sYour MediaPager dev environment is UP%s\n' "$C_BOLD" "$C_RESET"
  printf '%s%s%s\n\n' "$C_CYAN" '============================================================' "$C_RESET"
  printf '%sPostgreSQL%s\n' "$C_ORANGE" "$C_RESET"
  printf '\n  Site: %s  %s← use this to access the app%s\n  API:  %s\n  User: %s\n  Pass: %s\n\n  %sNote:%s %s\n\n' \
    "http://localhost:$POSTGRES_SPA_PORT" "$C_GREEN" "$C_RESET" "http://localhost:$POSTGRES_API_PORT" "$seed_user_display" "$MEDIAPAGER_SEED_PASS" "$C_YELLOW" "$C_RESET" "$seed_password_note"
  printf '%sSQLite%s\n' "$C_ORANGE" "$C_RESET"
  printf '\n  Site: %s  %s← use this to access the app%s\n  API:  %s\n  User: %s\n  Pass: %s\n\n  %sNote:%s %s\n' \
    "http://localhost:$SPA_PORT" "$C_GREEN" "$C_RESET" "http://localhost:$API_PORT" "$seed_user_display" "$MEDIAPAGER_SEED_PASS" "$C_YELLOW" "$C_RESET" "$seed_password_note"
  printf '  Existing account passwords are unchanged.\n'
  if [ "$USING_DEFAULT_POSTGRES_SETTINGS" -eq 1 ]; then
    printf '  PostgreSQL defaults were used for this session; no credentials file was changed.\n'
  fi
  if [ "$USING_DEFAULT_DEV_SIGNING_KEY" -eq 1 ]; then
    say_warning "  Development signing key: $DEFAULT_DEV_SIGNING_KEY (never use in production)."
  fi
  if [ -z "${MEDIAPAGER_TMDB_API_KEY:-}" ]; then
    printf '  Optional metadata needs a TMDB API key: MEDIAPAGER_TMDB_API_KEY.\n'
  fi
  printf '%s%s%s\n\n' "$C_CYAN" '============================================================' "$C_RESET"
  printf '%sOptional persistent environment settings%s\n' "$C_GREEN" "$C_RESET"
  printf '\n'
  printf 'Copy into %s to customize future sessions:\n' "$DEFAULT_CREDS_FILE"
  cat <<'EOF'
  export MEDIAPAGER_Database__Provider='PostgreSQL'
  export MEDIAPAGER_ConnectionStrings__AuthDatabase='Host=127.0.0.1;Port=5432;Database=mediapager_dev;Username=postgres;Password=password'
  export MEDIAPAGER_Auth__SigningKey='your_32_byte_sign_key_placeholder_here'
  export MEDIAPAGER_DB_PATH="$HOME/.MediaPager/db/mediapager.db"
  export MEDIAPAGER_SEED_USER='admin@mediapager.local'
  export MEDIAPAGER_SEED_PASS='DefaultPasswordChangeMe'
  # Optional: set MEDIAPAGER_TMDB_API_KEY after creating a TMDB API key.
EOF
  printf '%s%s%s\n\n' "$C_CYAN" '============================================================' "$C_RESET"
}

cmd_up() {
  mkdir -p "$RUN_DIR" "$POSTGRES_PLUGIN_DIR/community"
  if [ "$USING_DEFAULT_POSTGRES_SETTINGS" -eq 1 ]; then
    say_info 'Using the standard local PostgreSQL defaults (postgres/password, mediapager_dev).'
  fi
  ensure_postgres
  ensure_ui_dependencies

  if port_up "$API_PORT" && port_up "$SPA_PORT" &&
     port_up "$POSTGRES_API_PORT" && port_up "$POSTGRES_SPA_PORT"; then
    say_info 'Both dev environments are already running.'
    print_dev_summary
    return 0
  fi

  # Publish PostgreSQL first: its dotnet publish builds the shared project references.
  # Starting dotnet run first would build the same output tree concurrently.
  if ! port_up "$POSTGRES_API_PORT" && ! pid_alive "$(service_pid "$POSTGRES_API_PID_FILE")"; then
    say_info 'Building/publishing PostgreSQL API...'
    : >"$POSTGRES_PUBLISH_LOG"
    if ! dotnet publish MediaPager.App.Api/MediaPager.App.Api.csproj -c Debug -o "$POSTGRES_APP_DIR" \
      -p:MediaPagerOfficialPluginsDir="$POSTGRES_PLUGIN_DIR/official" --nologo -v:q >"$POSTGRES_PUBLISH_LOG" 2>&1; then
      say_warning 'ERROR: PostgreSQL API publish failed.' >&2
      report_log_errors "$POSTGRES_PUBLISH_LOG"
      return 1
    fi
    say_info 'Starting PostgreSQL API...'
    : >"$POSTGRES_API_LOG"
    (
      cd "$POSTGRES_APP_DIR"
      exec nohup env \
        ASPNETCORE_URLS="http://localhost:${POSTGRES_API_PORT}" \
        MEDIAPAGER_Database__Provider=PostgreSQL \
        MEDIAPAGER_DB_PATH= \
        MEDIAPAGER_ConnectionStrings__AuthDatabase="$POSTGRES_CONNECTION_STRING" \
        MEDIAPAGER_Auth__SigningKeyPath="$RUN_DIR/postgres-signing.key" \
        MEDIAPAGER_Plugins__Directory="$POSTGRES_PLUGIN_DIR" \
        dotnet MediaPager.App.Api.dll
    ) >"$POSTGRES_API_LOG" 2>&1 &
    echo $! >"$POSTGRES_API_PID_FILE"
  elif port_up "$POSTGRES_API_PORT"; then
    :
  fi

  if ! port_up "$API_PORT" && ! pid_alive "$(service_pid "$API_PID_FILE")"; then
    say_info 'Starting SQLite API...'
    : >"$API_LOG"
    nohup env \
      ASPNETCORE_URLS="http://localhost:${API_PORT}" \
      MEDIAPAGER_Database__Provider=Sqlite \
      MEDIAPAGER_DB_PATH="$DB_FILE" \
      MEDIAPAGER_ConnectionStrings__AuthDatabase="Data Source=$DB_FILE" \
      MEDIAPAGER_Auth__SigningKeyPath="$(dirname "$DB_FILE")/signing.key" \
      MEDIAPAGER_Plugins__Directory="$(plugins_root)" \
      dotnet run --no-launch-profile --project MediaPager.App.Api/MediaPager.App.Api.csproj >"$API_LOG" 2>&1 &
    echo $! >"$API_PID_FILE"
  elif port_up "$API_PORT"; then
    :
  fi

  if ! port_up "$SPA_PORT" && ! pid_alive "$(service_pid "$SPA_PID_FILE")"; then
    say_info 'Starting SQLite SPA...'
    : >"$SPA_LOG"
    ( cd MediaPager.App.Ui && exec env VITE_API_BASE_URL="http://localhost:${API_PORT}" nohup npm run dev -- --port "$SPA_PORT" --strictPort ) >"$SPA_LOG" 2>&1 &
    echo $! >"$SPA_PID_FILE"
  elif port_up "$SPA_PORT"; then
    :
  fi

  if ! port_up "$POSTGRES_SPA_PORT" && ! pid_alive "$(service_pid "$POSTGRES_SPA_PID_FILE")"; then
    say_info 'Starting PostgreSQL SPA...'
    : >"$POSTGRES_SPA_LOG"
    ( cd MediaPager.App.Ui && exec env VITE_API_BASE_URL="http://localhost:${POSTGRES_API_PORT}" nohup npm run dev -- --port "$POSTGRES_SPA_PORT" --strictPort ) >"$POSTGRES_SPA_LOG" 2>&1 &
    echo $! >"$POSTGRES_SPA_PID_FILE"
  elif port_up "$POSTGRES_SPA_PORT"; then
    :
  fi

  wait_for_service "SQLite API" "$API_PORT" "$API_PID_FILE" "$API_LOG" 120
  wait_for_service "SQLite SPA" "$SPA_PORT" "$SPA_PID_FILE" "$SPA_LOG" 60
  wait_for_service "PostgreSQL API" "$POSTGRES_API_PORT" "$POSTGRES_API_PID_FILE" "$POSTGRES_API_LOG" 120
  wait_for_service "PostgreSQL SPA" "$POSTGRES_SPA_PORT" "$POSTGRES_SPA_PID_FILE" "$POSTGRES_SPA_LOG" 60
  print_dev_summary
}

cmd_restart() {
  say_info 'Restarting MediaPager dev services...'
  stop_env
  cmd_up
}

cmd_wipe_and_up() {
  say_info 'Stopping dev services for a full database reset...'
  stop_env
  if [ -z "$POSTGRES_CONNECTION_STRING" ]; then
    say_warning '!! PostgreSQL connection string is missing; cannot refresh both databases.' >&2
    return 1
  fi
  say_info 'Building API tooling before the EF database drop...'
  if ! dotnet build MediaPager.App.Api/MediaPager.App.Api.csproj --nologo -v:q >"$REFRESH_BUILD_LOG" 2>&1; then
    say_warning 'ERROR: API build failed before PostgreSQL refresh.' >&2
    report_log_errors "$REFRESH_BUILD_LOG"
    return 1
  fi
  say_info 'Dropping configured PostgreSQL database with EF Core...'
  if ! MEDIAPAGER_DB_PATH= MEDIAPAGER_Database__Provider=PostgreSQL \
      MEDIAPAGER_ConnectionStrings__AuthDatabase="$POSTGRES_CONNECTION_STRING" \
      dotnet ef database drop --force \
        --project MediaPager.App.Api/MediaPager.App.Api.csproj \
        --startup-project MediaPager.App.Api/MediaPager.App.Api.csproj \
        --context AuthDbContext --no-build >"$POSTGRES_DROP_LOG" 2>&1; then
    say_warning 'ERROR: PostgreSQL database drop failed; SQLite data has not been deleted.' >&2
    report_log_errors "$POSTGRES_DROP_LOG"
    return 1
  fi

  db_dir="$(dirname "$DB_FILE")"
  say_info 'Deleting SQLite database and signing key...'
  rm -f "$DB_FILE" "$DB_FILE-wal" "$DB_FILE-shm" \
        "$db_dir/mediapager-auth.db" "$db_dir/mediapager-auth.db-wal" "$db_dir/mediapager-auth.db-shm" \
        "$db_dir/signing.key"
  say_info 'Cleaning build and plugin artifacts...'
  if ! dotnet clean MediaPager.App.Api/MediaPager.App.Api.csproj --nologo -v:q >"$REFRESH_BUILD_LOG" 2>&1; then
    say_warning 'ERROR: dotnet clean failed during refresh.' >&2
    report_log_errors "$REFRESH_BUILD_LOG"
    return 1
  fi
  # Compiled plugin folders go too: otherwise a leftover community folder would load
  # (presence = install) while its list entry just reset — a half-clean state. Shipped
  # officials redeploy into the root on the next build.
  root="$(plugins_root)"
  case "$root" in
    /*) if [ "$root" != "/" ]; then
          rm -rf "$root"
        fi ;;
  esac
  rm -rf "$POSTGRES_PLUGIN_DIR" "$POSTGRES_APP_DIR"
  say_info 'Recreating databases, applying migrations, and reseeding...'
  cmd_up
  say_success 'Database refresh complete.'
}

cmd_show() {
  api_state="down"
  spa_state="down"
  postgres_api_state="down"
  postgres_spa_state="down"
  port_up "$API_PORT" && api_state="up"
  port_up "$SPA_PORT" && spa_state="up"
  port_up "$POSTGRES_API_PORT" && postgres_api_state="up"
  port_up "$POSTGRES_SPA_PORT" && postgres_spa_state="up"
  if [ "$api_state" = "up" ] && [ "$spa_state" = "up" ] &&
     [ "$postgres_api_state" = "up" ] && [ "$postgres_spa_state" = "up" ]; then
    print_dev_summary
    return 0
  fi

  printf '\n%s%s%s\n' "$C_CYAN" '============================================================' "$C_RESET"
  printf '%sMediaPager dev environment is not fully running%s\n' "$C_BOLD" "$C_RESET"
  printf '%s%s%s\n\n' "$C_CYAN" '============================================================' "$C_RESET"
  printf '  %s%-11s%s SPA http://localhost:%s  (%s)\n' "$C_ORANGE" 'SQLite' "$C_RESET" "$SPA_PORT" "$spa_state"
  printf '  %s%-11s%s API http://localhost:%s  (%s)\n' "$C_ORANGE" 'SQLite' "$C_RESET" "$API_PORT" "$api_state"
  printf '  %s%-11s%s SPA http://localhost:%s  (%s)\n' "$C_ORANGE" 'PostgreSQL' "$C_RESET" "$POSTGRES_SPA_PORT" "$postgres_spa_state"
  printf '  %s%-11s%s API http://localhost:%s  (%s)\n\n' "$C_ORANGE" 'PostgreSQL' "$C_RESET" "$POSTGRES_API_PORT" "$postgres_api_state"
  printf 'Start services: ./dev.sh up   (or ./dev.sh restart)\n'
  printf 'Full reset:     ./dev.sh --refresh\n'
  say_warning 'Note: --refresh deletes both dev databases and local plugin state; source/media files are untouched.'
}

cmd_secrets() {
  signing_key_file="$(dirname "$DB_FILE")/signing.key"
  signing_key_val="(not created yet)"
  postgres_connection_state="not configured"
  configured_signing_key_state="not set"
  seed_user_state="not set (application default)"
  [ -n "$POSTGRES_CONNECTION_STRING" ] && postgres_connection_state="configured"
  [ -n "${MEDIAPAGER_Auth__SigningKey:-}" ] && configured_signing_key_state="set"
  [ -n "${MEDIAPAGER_SEED_USER:-}" ] && seed_user_state="custom address configured"
  if [ -f "$signing_key_file" ]; then
    if LC_ALL=C grep -q '[^[:print:]]' "$signing_key_file" 2>/dev/null; then
      signing_key_val="($(wc -c <"$signing_key_file" | tr -d ' ') bytes) base64=$(base64 <"$signing_key_file" | tr -d '\n')"
    else
      signing_key_val="= $(cat "$signing_key_file")"
    fi
  fi
  printf '\n%s%s%s\n' "$C_BOLD" 'Local development settings' "$C_RESET"
  printf 'Credentials file: %s%s\n' "$CREDS_FILE" "$( [ -f "$CREDS_FILE" ] || printf ' (missing)' )"
  cat <<EOF
  MEDIAPAGER_TMDB_API_KEY = ${MEDIAPAGER_TMDB_API_KEY:-<unset>}
  MEDIAPAGER_Auth__SigningKey = ${configured_signing_key_state}
  MEDIAPAGER_SEED_USER    = ${seed_user_state}
  MEDIAPAGER_SEED_PASS    = ${MEDIAPAGER_SEED_PASS:-<unset>}

  Exported to the API as:
  MEDIAPAGER_TMDB_API_KEY         = ${MEDIAPAGER_TMDB_API_KEY:-<unset>}
  MEDIAPAGER_Auth__SigningKey   = ${MEDIAPAGER_Auth__SigningKey:-}
  MEDIAPAGER_Auth__SeedEmail    = ${seed_user_state}
  MEDIAPAGER_Auth__SeedPassword = ${MEDIAPAGER_Auth__SeedPassword:-}
  PostgreSQL provider/connection = ${MEDIAPAGER_Database__Provider:-<set per service>} / ${postgres_connection_state}

Database:            ${DB_FILE}$([ -f "$DB_FILE" ] && echo "  (exists)" || echo "  (not created yet)")
Persisted JWT key:   ${signing_key_file}  ${signing_key_val}
PostgreSQL JWT key:  $RUN_DIR/postgres-signing.key
EOF
}

cmd="${1:-help}"
case "$cmd" in
  help|--help|-h) usage ;;
  up) cmd_up ;;
  down) cmd_down ;;
  restart) cmd_restart ;;
  show) cmd_show ;;
  secrets) cmd_secrets ;;
  --refresh) cmd_wipe_and_up ;;
  *)
    echo "unknown command: $cmd" >&2
    usage >&2
    exit 1
    ;;
esac
