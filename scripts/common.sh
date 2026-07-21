#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

# Version identifiers and pinned build inputs live in versions.sh, the single
# source of truth (also sourced standalone by install.sh). Everything below
# derives from those - do not reintroduce version literals here.
. "$SCRIPT_DIR/versions.sh"

WINE_SOURCE_DATE_EPOCH=1783719732
WINE_REMOTE=https://gitlab.winehq.org/wine/wine.git
# Release asset names, derived from the version identifiers above so a version
# bump in versions.sh renames them automatically and can never drift.
ENCORE_RUNTIME_ASSET="encore-wine-$WINE_VERSION-$ENCORE_RUNTIME_REVISION-x86_64-linux-gnu.tar.xz"
ENCORE_SOURCE_ASSET="encore-wine-$WINE_VERSION-$ENCORE_RUNTIME_REVISION-source.tar.xz"
ENCORE_BUNDLE_ASSET="ENCORE-$ENCORE_RELEASE_VERSION-linux-x86_64.tar.xz"
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
WINEASIO_ROOT=${WINEASIO_ROOT:-"$PROJECT_ROOT/runtime/wineasio"}

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
