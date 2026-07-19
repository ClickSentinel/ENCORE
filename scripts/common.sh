#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234
WINE_SOURCE_DATE_EPOCH=1783719732
WINE_REMOTE=https://gitlab.winehq.org/wine/wine.git
ENCORE_RELEASE_VERSION=v0.1.3
ENCORE_RUNTIME_VERSION=v0.1.0
ENCORE_RUNTIME_REVISION=r2
ENCORE_RUNTIME_ASSET=encore-wine-11.13-r2-x86_64-linux-gnu.tar.xz
ENCORE_SOURCE_ASSET=encore-wine-11.13-r2-source.tar.xz
ENCORE_BUNDLE_ASSET=ENCORE-v0.1.3-linux-x86_64.tar.xz
ENCORE_GLIBC_MIN=2.39
# r2's archive contents changed (bundled WineASIO, manifest schema V2), so the
# r1 checksum can't carry over; left unset until a real r2 build publishes one
# (download-wine-runtime.sh already fails clearly on an unset/short value).
ENCORE_RUNTIME_SHA256=${ENCORE_RUNTIME_SHA256:-}
ENCORE_RELEASE_BASE_URL=${ENCORE_RELEASE_BASE_URL:-https://github.com/wowitsjack/ENCORE/releases/download/$ENCORE_RELEASE_VERSION}
ENCORE_RUNTIME_ROOT=${ENCORE_RUNTIME_ROOT:-"$PROJECT_ROOT/runtime/wine"}
WINE_SOURCE=${WINE_SOURCE:-"$PROJECT_ROOT/wine"}
WINE_BUILD=${WINE_BUILD:-"$PROJECT_ROOT/build/wine64"}
WINE_BINARY=${ENCORE_WINE:-"$WINE_BUILD/wine"}
WINE_INSTALL_PREFIX=${WINE_INSTALL_PREFIX:-/opt/encore-wine}
ENCORE_PREFIX=${ENCORE_PREFIX:-"$PROJECT_ROOT/ableton-prefix"}
WINE_PATCH="$PROJECT_ROOT/patches/encore-wine.patch"

WINEASIO_REMOTE=${WINEASIO_REMOTE:-https://github.com/wineasio/wineasio.git}
WINEASIO_REVISION=${WINEASIO_REVISION:-b5e668103ad13e6f51f4118ed7090592213e5ca2}   # v1.3.0
WINEASIO_VERSION=1.3.0
WINEASIO_PATCH_DIR="$PROJECT_ROOT/patches/wineasio"
WINEASIO_SOURCE=${WINEASIO_SOURCE:-"$PROJECT_ROOT/build/wineasio-src"}
# The prebuilt runtime bundles WineASIO nested inside itself; a
# --build-from-source install has no such tree yet, so build-wineasio.sh
# installs to its own independent top-level directory instead. Detected by
# Wine binary presence (same signal run-ableton.sh already uses), not by
# WineASIO's own files, to avoid a stale leftover from an unrelated prior
# run in the same project directory picking the wrong location.
if [ -z "${WINEASIO_ROOT:-}" ]; then
    if [ -x "$ENCORE_RUNTIME_ROOT/bin/wine" ]; then
        WINEASIO_ROOT="$ENCORE_RUNTIME_ROOT/wineasio"
    else
        WINEASIO_ROOT="$PROJECT_ROOT/runtime/wineasio"
    fi
fi

say()
{
    printf '%s\n' "$*"
}

die()
{
    printf 'ENCORE: %s\n' "$*" >&2
    exit 1
}

require_command()
{
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

make_absolute_path()
{
    case $1 in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$PWD" "$1" ;;
    esac
}
