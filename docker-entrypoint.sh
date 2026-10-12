#!/bin/sh
set -u

APP_DLL="${1:-MediaPager.App.Api.dll}"
if [ "$#" -gt 0 ]; then shift; fi

# User-overridden non-root containers bootstrap in their writable tools directory. The
# published image normally starts as root only for the detached tools installer below.
if [ "$(id -u)" -ne 0 ]; then
    exec dotnet "$APP_DLL" "$@"
fi

TOOLS_DIR="${MEDIAPAGER_Tools__Directory:-/app/tools}"
STATUS_FILE="$TOOLS_DIR/.bootstrap-status.json"
mkdir -p "$TOOLS_DIR"
rm -f "$STATUS_FILE"

export MEDIAPAGER_TOOLS_BOOTSTRAP_EXTERNAL=true
export MEDIAPAGER_TOOLS_BOOTSTRAP_STATUS="$STATUS_FILE"
export MEDIAPAGER_TOOLS_RUNTIME_UID="$(id -u mediapager)"
export MEDIAPAGER_TOOLS_RUNTIME_GID="$(id -g mediapager)"

dotnet "$APP_DLL" --bootstrap-managed-tools "$TOOLS_DIR" "$STATUS_FILE" &
BOOTSTRAP_PID=$!

export HOME=/home/mediapager
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
