#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$ROOT/scripts/load-runtime-config.sh"
. "$ROOT/scripts/ableton-profile.sh"
PREFIX=${ENCORE_PREFIX:-"$ROOT/ableton-prefix"}
default_wine="$ROOT/runtime/wine/bin/wine"
[ -x "$default_wine" ] || default_wine="$ROOT/build/wine64/wine"
WINE=${ENCORE_WINE:-"$default_wine"}
ABLETON=$(encore_resolve_ableton_executable "$PREFIX" "${ENCORE_ABLETON-}") || exit 1

default_webview_flags='--use-gl=angle --use-angle=swiftshader --disable-gpu-compositing --disable-gpu-rasterization --disable-direct-composition --disable-features=ForceSWDCompWhenDCompFallbackRequired --edge-webview-foreground-boost-opt-out --no-sandbox'
webview_flags=${ENCORE_WEBVIEW2_FLAGS-"$default_webview_flags"}
webview_arguments=${WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS-}
if [ -n "$webview_flags" ]; then
    webview_arguments="${webview_arguments:+$webview_arguments }$webview_flags"
fi

wine_dll_overrides="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}mscoree,mshtml,winemenubuilder.exe,dcomp="

# WineASIO (low-latency audio, on by default unless --no-wineasio): bundled
# nested inside the prebuilt runtime, or built to the plain top-level
# directory by scripts/build-wineasio.sh for a source build - same
# prebuilt-vs-source signal as $default_wine above. See docs/wineasio.md.
wineasio_root="$ROOT/runtime/wine/wineasio"
[ -f "$wineasio_root/wineasio64.dll.so" ] || wineasio_root="$ROOT/runtime/wineasio"
wineasio_enabled=0
if [ -f "$wineasio_root/wineasio64.dll.so" ]; then
    wineasio_enabled=1
    WINEDLLPATH="$wineasio_root${WINEDLLPATH:+:$WINEDLLPATH}"
fi

if [ "${ENCORE_CPU_TOPOLOGY+x}" = x ]; then
    cpu_topology=$ENCORE_CPU_TOPOLOGY
elif [ "${WINE_CPU_TOPOLOGY+x}" = x ]; then
    cpu_topology=$WINE_CPU_TOPOLOGY
else
    cpu_topology=$("$ROOT/scripts/select-cpu-topology.sh")
fi

if [ "${ENCORE_DRY_RUN:-0}" = 1 ]; then
    printf 'WINEPREFIX=%s\n' "$PREFIX"
    printf 'WINE=%s\n' "$WINE"
    printf 'ABLETON=%s\n' "$ABLETON"
    printf 'WINEDLLOVERRIDES=%s\n' "$wine_dll_overrides"
    printf 'WINE_DISABLE_UNIX_MOUNT_REPARSE=1\n'
    printf 'ENCORE_NATIVE_VST3_DECORATIONS=%s\n' "${ENCORE_NATIVE_VST3_DECORATIONS-1}"
    printf 'ENCORE_NATIVE_VST3_DPI=%s\n' "${ENCORE_NATIVE_VST3_DPI-1}"
    printf 'ENCORE_VST3_RESIZE_REPAINT=%s\n' "${ENCORE_VST3_RESIZE_REPAINT-1}"
    printf 'ENCORE_ABLETON_MENU_THEME=%s\n' "${ENCORE_ABLETON_MENU_THEME-1}"
    printf 'WINE_CPU_TOPOLOGY=%s\n' "$cpu_topology"
    printf 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=%s\n' "$webview_arguments"
    if [ "$wineasio_enabled" = 1 ]; then
        printf 'WINEDLLPATH=%s\n' "$WINEDLLPATH"
        printf 'WINEASIO_NUMBER_INPUTS=%s\n' "${WINEASIO_NUMBER_INPUTS:-2}"
        printf 'WINEASIO_NUMBER_OUTPUTS=%s\n' "${WINEASIO_NUMBER_OUTPUTS:-2}"
        printf 'WINEASIO_FIXED_BUFFERSIZE=%s\n' "${WINEASIO_FIXED_BUFFERSIZE:-on}"
        printf 'WINEASIO_PREFERRED_BUFFERSIZE=%s\n' "${WINEASIO_PREFERRED_BUFFERSIZE:-256}"
        printf 'WINEASIO_CONNECT_TO_HARDWARE=%s\n' "${WINEASIO_CONNECT_TO_HARDWARE:-on}"
        printf 'jacklinkd=%s\n' "$wineasio_root/jacklinkd"
    fi
    exit 0
fi

mkdir -p "$ROOT/.tmp"
export TMPDIR="$ROOT/.tmp"
export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="$wine_dll_overrides"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINE_DISABLE_UNIX_MOUNT_REPARSE=1
export ENCORE_X11_MIN_VISIBLE_SIZE="${ENCORE_X11_MIN_VISIBLE_SIZE-800x643}"
export ENCORE_NATIVE_VST3_DECORATIONS="${ENCORE_NATIVE_VST3_DECORATIONS-1}"
export ENCORE_NATIVE_VST3_DPI="${ENCORE_NATIVE_VST3_DPI-1}"
export ENCORE_VST3_RESIZE_REPAINT="${ENCORE_VST3_RESIZE_REPAINT-1}"
export ENCORE_ABLETON_MENU_THEME="${ENCORE_ABLETON_MENU_THEME-1}"
if [ -n "$cpu_topology" ]; then
    export WINE_CPU_TOPOLOGY="$cpu_topology"
else
    unset WINE_CPU_TOPOLOGY
fi
export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="$webview_arguments"

# Force Live's GDI backend. Live's own GPU/GL renderer misrenders under Wine -
# large black/blank content regions (most visibly the account sign-in dialog,
# which never paints until the window is resized) plus a persistent CPU spin
# on software GL. Ableton reads -_ForceGdiBackend from Options.txt in its
# versioned Preferences directory, which Live creates on first run, so this
# can't be placed ahead of time during setup; ensure the flag in every
# existing Live Preferences directory on each launch instead - idempotent and
# self-healing across Live version updates. Opt out with ENCORE_LIVE_GPU=1.
#
# Originally identified and fixed by shibco (shibacomputer, cade@parare.al) in
# shibco/ableton-linux, and ported here by Jae (jaesharp) in their ENCORE fork
# (https://github.com/jaesharp/ENCORE), who tracked it down to this exact
# Options.txt mechanism and verified it against a real CPU-usage drop. Brought
# into ENCORE from that fork with full credit to both.
if [ "${ENCORE_LIVE_GPU:-0}" != 1 ]; then
    for _encore_pref in "$PREFIX"/drive_c/users/*/AppData/Roaming/Ableton/"Live "*/Preferences; do
        [ -d "$_encore_pref" ] || continue
        if ! grep -qx -- '-_ForceGdiBackend' "$_encore_pref/Options.txt" 2>/dev/null; then
            printf -- '-_ForceGdiBackend\n' >> "$_encore_pref/Options.txt"
        fi
    done
fi

if [ "$wineasio_enabled" = 1 ]; then
    export WINEDLLPATH
    export WINEASIO_NUMBER_INPUTS="${WINEASIO_NUMBER_INPUTS:-2}"
    export WINEASIO_NUMBER_OUTPUTS="${WINEASIO_NUMBER_OUTPUTS:-2}"
    export WINEASIO_FIXED_BUFFERSIZE="${WINEASIO_FIXED_BUFFERSIZE:-on}"
    export WINEASIO_PREFERRED_BUFFERSIZE="${WINEASIO_PREFERRED_BUFFERSIZE:-256}"
    export WINEASIO_CONNECT_TO_HARDWARE="${WINEASIO_CONNECT_TO_HARDWARE:-on}"
    # The system libjack.so.0 may resolve to a real standalone JACK server
    # (e.g. installed as a build dependency) instead of PipeWire's own
    # JACK-compatible replacement, which lives in a separate directory meant
    # to be found via LD_LIBRARY_PATH - the same mechanism PipeWire's own
    # pw-jack wrapper uses. Without this, WineASIO loads the real libjack,
    # finds no standalone JACK server running, and fails to open the device.
    # ${LIB} is a dynamic-linker token (expands to lib/lib64/lib/<triplet>
    # depending on the distro), not a shell variable - left unexpanded here
    # on purpose. A nonexistent path in LD_LIBRARY_PATH is silently ignored,
    # so this is safe on systems without PipeWire's JACK shim installed.
    # shellcheck disable=SC2016
    export LD_LIBRARY_PATH='/usr/${LIB}/pipewire-0.3/jack'"${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [ -x "$wineasio_root/jacklinkd" ] && ! pgrep -x jacklinkd >/dev/null 2>&1; then
        "$wineasio_root/jacklinkd" >/dev/null 2>&1 &
    fi
fi

exec "$WINE" "$ABLETON" "$@"
