#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234
WINE_REMOTE=https://gitlab.winehq.org/wine/wine.git
WINE_SOURCE=${WINE_SOURCE:-"$PROJECT_ROOT/wine"}
WINE_BUILD=${WINE_BUILD:-"$PROJECT_ROOT/build/wine64"}
WINE_BINARY=${ENCORE_WINE:-"$WINE_BUILD/wine"}
ENCORE_PREFIX=${ENCORE_PREFIX:-"$PROJECT_ROOT/ableton-prefix"}
WINE_PATCH="$PROJECT_ROOT/patches/encore-wine.patch"

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
