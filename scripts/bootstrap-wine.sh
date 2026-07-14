#!/bin/sh

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

require_command git
require_command mktemp
require_command rm
[ -f "$WINE_PATCH" ] || die "missing patch: $WINE_PATCH"

if [ ! -e "$WINE_SOURCE" ]; then
    source_parent=$(dirname -- "$WINE_SOURCE")
    source_name=$(basename -- "$WINE_SOURCE")
    temporary_source="$source_parent/.${source_name}.clone.$$"
    mkdir -p "$source_parent"
    [ ! -e "$temporary_source" ] || die "temporary clone path already exists: $temporary_source"
    cleanup_clone()
    {
        rm -rf -- "$temporary_source"
    }
    trap cleanup_clone EXIT HUP INT TERM
    say "Cloning Wine into $WINE_SOURCE"
    git clone --filter=blob:none "$WINE_REMOTE" "$temporary_source"
    mv "$temporary_source" "$WINE_SOURCE"
    trap - EXIT HUP INT TERM
fi

[ "$(git -C "$WINE_SOURCE" rev-parse --is-inside-work-tree 2>/dev/null || true)" = true ] ||
    die "$WINE_SOURCE is not a Git checkout"

source_matches_patch()
(
    temporary_index=$(mktemp "${TMPDIR:-/tmp}/encore-wine-index.XXXXXX")
    rm -f "$temporary_index"
    trap 'rm -f "$temporary_index"' EXIT HUP INT TERM
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" read-tree HEAD || exit 1
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" apply --cached "$WINE_PATCH" || exit 1
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" update-index --refresh >/dev/null 2>&1 || exit 1
    GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" diff-files --quiet || exit 1
    [ -z "$(GIT_INDEX_FILE=$temporary_index git -C "$WINE_SOURCE" ls-files --others --exclude-standard)" ]
)

head=$(git -C "$WINE_SOURCE" rev-parse HEAD)
if [ "$head" != "$WINE_REVISION" ]; then
    if [ -n "$(git -C "$WINE_SOURCE" status --porcelain)" ]; then
        die "Wine is at $head with local changes; expected clean revision $WINE_REVISION"
    fi
    if ! git -C "$WINE_SOURCE" cat-file -e "$WINE_REVISION^{commit}" 2>/dev/null; then
        say "Fetching pinned Wine revision"
        git -C "$WINE_SOURCE" fetch --filter=blob:none origin
    fi
    git -C "$WINE_SOURCE" switch --detach "$WINE_REVISION"
fi

if git -C "$WINE_SOURCE" apply --reverse --check "$WINE_PATCH" >/dev/null 2>&1; then
    source_matches_patch || die "Wine contains changes beyond the ENCORE patch"
    say "Wine source is already patched at $WINE_REVISION"
    exit 0
fi

if [ -n "$(git -C "$WINE_SOURCE" status --porcelain)" ]; then
    die "Wine has changes that do not exactly match the ENCORE patch"
fi

git -C "$WINE_SOURCE" apply --check "$WINE_PATCH"
git -C "$WINE_SOURCE" apply "$WINE_PATCH"
say "Applied ENCORE patch to Wine $WINE_REVISION"
