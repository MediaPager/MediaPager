#!/bin/sh
set -u

APP_DLL="${1:-MediaPager.App.Api.dll}"
if [ "$#" -gt 0 ]; then shift; fi

DATA_DIR="${MEDIAPAGER_Settings__Storage__Root:-/data}"
TOOLS_DIR="${MEDIAPAGER_Settings__Storage__Tools__Directory:-$DATA_DIR/tools}"
COMMUNITY_DIR="${MEDIAPAGER_Settings__Storage__Plugins__CommunityDirectory:-$DATA_DIR/plugins/community}"
OFFICIAL_DIR="${MEDIAPAGER_Settings__Storage__Plugins__InstalledOfficialDirectory:-$DATA_DIR/plugins/official}"
CONFIG_DIR="${MEDIAPAGER_Settings__Storage__Config__Directory:-$DATA_DIR/config}"
ARTWORK_DIR="$DATA_DIR/artwork"
KEYS_DIR="$DATA_DIR/keys"
CACHE_DIR="$DATA_DIR/cache"
mkdir -p "$DATA_DIR" "$TOOLS_DIR" "$COMMUNITY_DIR" "$OFFICIAL_DIR" "$CONFIG_DIR" \
    "$ARTWORK_DIR" "$KEYS_DIR" "$CACHE_DIR" "$DATA_DIR/home"

# One-time import from the old named volumes. Never remove the source volumes and do
# not overwrite content already installed under /data.
if [ -d /migration/legacy-tools ] && [ ! -f "$DATA_DIR/.tools-volume-migrated" ]; then
    cp -an /migration/legacy-tools/. "$TOOLS_DIR/" 2>/dev/null || true
    touch "$DATA_DIR/.tools-volume-migrated"
fi
if [ -d /migration/legacy-community ] && [ ! -f "$DATA_DIR/.community-volume-migrated" ]; then
    cp -an /migration/legacy-community/. "$COMMUNITY_DIR/" 2>/dev/null || true
    touch "$DATA_DIR/.community-volume-migrated"
fi

# User-overridden non-root containers must mount /data writable by that uid. The
# published image starts as root to prepare the shared persistent directories and
# launch the detached tools bootstrapper; the API itself runs unprivileged.
if [ "$(id -u)" -ne 0 ]; then
    exec dotnet "$APP_DLL" "$@"
fi

RUNTIME_UID="$(id -u mediapager)"
RUNTIME_GID="$(id -g mediapager)"
if [ ! -f "$DATA_DIR/.runtime-owner-v1" ]; then
    chown -R "$RUNTIME_UID:$RUNTIME_GID" "$DATA_DIR/db" "$DATA_DIR/config" "$DATA_DIR/keys" \
        "$DATA_DIR/artwork" "$DATA_DIR/cache" "$DATA_DIR/tools" "$DATA_DIR/plugins" "$DATA_DIR/home"
    touch "$DATA_DIR/.runtime-owner-v1"
fi

STATUS_FILE="$TOOLS_DIR/.bootstrap-status.json"
mkdir -p "$TOOLS_DIR"
rm -f "$STATUS_FILE"

export MEDIAPAGER_TOOLS_BOOTSTRAP_EXTERNAL=true
export MEDIAPAGER_TOOLS_BOOTSTRAP_STATUS="$STATUS_FILE"
export MEDIAPAGER_TOOLS_RUNTIME_UID="$RUNTIME_UID"
export MEDIAPAGER_TOOLS_RUNTIME_GID="$RUNTIME_GID"

dotnet "$APP_DLL" --bootstrap-managed-tools "$TOOLS_DIR" "$STATUS_FILE" &
BOOTSTRAP_PID=$!

export HOME="$DATA_DIR/home"
export USER=mediapager
export LOGNAME=mediapager
runuser --preserve-environment --user mediapager -- dotnet "$APP_DLL" "$@" &
API_PID=$!

shutdown_children() {
    trap - TERM INT
    kill -TERM "$API_PID" "$BOOTSTRAP_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
    wait "$BOOTSTRAP_PID" 2>/dev/null || true
}
trap 'shutdown_children; exit 0' TERM INT

set +e
wait "$API_PID"
API_EXIT_CODE=$?
set -e

if kill -0 "$BOOTSTRAP_PID" 2>/dev/null; then
    kill -TERM "$BOOTSTRAP_PID" 2>/dev/null || true
fi
wait "$BOOTSTRAP_PID" 2>/dev/null || true
exit "$API_EXIT_CODE"
