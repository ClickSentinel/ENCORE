#!/bin/sh

# Configure prefix features that Live relies on at runtime.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
. "$SCRIPT_DIR/ableton-profile.sh"

ableton_binary=$(encore_resolve_ableton_executable \
    "$ENCORE_PREFIX" "${ENCORE_ABLETON-}") || exit 1
encore_ableton_profile_from_executable "$ableton_binary" || \
    die "unsupported Ableton executable: $ableton_binary"
dosdevices="$ENCORE_PREFIX/dosdevices"
root_drive=

[ -x "$WINE_BINARY" ] || die "Wine is not built: $WINE_BINARY"
[ -f "$ENCORE_PREFIX/user.reg" ] || die "Ableton prefix does not exist: $ENCORE_PREFIX"

if "$SCRIPT_DIR/process-is-running.sh" "$ableton_binary"; then
    die "Ableton Live is running; close it before configuring the prefix"
fi

mkdir -p "$dosdevices"

for drive in "$dosdevices"/[a-z]:; do
    [ -L "$drive" ] || continue
    [ "$(readlink -- "$drive")" = / ] || continue
    root_drive=${drive##*/}
    break
done

if [ -z "$root_drive" ]; then
    for letter in z y x w v u t s r q p o n m l k j i h g f e d; do
        drive="$dosdevices/$letter:"
        [ -e "$drive" ] || [ -L "$drive" ] || {
            ln -s / "$drive"
            root_drive="$letter:"
            break
        }
    done
fi

[ -n "$root_drive" ] || die "no free Wine drive letter is available for host folders"

WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
    "$WINE_BINARY" reg.exe add \
    "HKCU\\Software\\Wine\\AppDefaults\\$ENCORE_ABLETON_EXE\\X11 Driver" \
    /v FileDialogPortal /t REG_SZ /d always /f >/dev/null

say "Native folder picker enabled for Ableton; host files are available through $root_drive"

# WineASIO: register the driver into the prefix if it was built (opt-in,
# built by scripts/build-wineasio.sh). Live then lists it under ASIO devices.
# See docs/wineasio.md for the low-latency JACK/PipeWire audio path.
if [ -f "$WINEASIO_ROOT/wineasio64.dll" ] && [ -f "$WINEASIO_ROOT/wineasio64.dll.so" ]; then
    system32="$ENCORE_PREFIX/drive_c/windows/system32"
    for name in wineasio64.dll wineasio.dll; do
        cp -f "$WINEASIO_ROOT/wineasio64.dll" "$system32/$name"
    done
    WINEPREFIX="$ENCORE_PREFIX" WINEDEBUG=-all \
        WINEDLLPATH="$WINEASIO_ROOT${WINEDLLPATH:+:$WINEDLLPATH}" \
        "$WINE_BINARY" regsvr32 "$WINEASIO_ROOT/wineasio64.dll.so" >/dev/null 2>&1
    say "WineASIO registered for low-latency JACK/PipeWire audio"
fi
