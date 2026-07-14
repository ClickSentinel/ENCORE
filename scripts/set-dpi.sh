#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

dpi=${1:-192}
case "$dpi" in
    ''|*[!0-9]*) die "DPI must be an integer between 72 and 384" ;;
esac
[ "$dpi" -ge 72 ] && [ "$dpi" -le 384 ] || die "DPI must be between 72 and 384"

[ -x "$WINE_BINARY" ] || die "Wine is not built: $WINE_BINARY"
[ -f "$ENCORE_PREFIX/user.reg" ] || die "Ableton prefix does not exist: $ENCORE_PREFIX"
ableton_binary=${ENCORE_ABLETON:-"$ENCORE_PREFIX/drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe"}

if "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then
    die "Ableton Live is running; close it before changing prefix DPI"
fi

WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
    "$WINE_BINARY" reg.exe add 'HKCU\Control Panel\Desktop' \
    /v LogPixels /t REG_DWORD /d "$dpi" /f

say "Wine DPI set to $dpi in $ENCORE_PREFIX"
