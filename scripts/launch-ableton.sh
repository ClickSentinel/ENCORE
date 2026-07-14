#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT/scripts/load-runtime-config.sh"
PREFIX=${ENCORE_PREFIX:-"$ROOT/ableton-prefix"}
ABLETON=${ENCORE_ABLETON:-"$PREFIX/drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe"}
LOG="$ROOT/logs/ableton-dock.log"
PROCESS_CHECK="$ROOT/scripts/process-is-running.sh"

if [ "${ENCORE_DRY_RUN:-0}" = 1 ]; then
    exec "$SCRIPT_DIR/run-ableton.sh"
fi

mkdir -p "$ROOT/logs"

if "$PROCESS_CHECK" "$ABLETON"; then
    exit 0
fi

exec "$SCRIPT_DIR/run-ableton.sh" >>"$LOG" 2>&1
