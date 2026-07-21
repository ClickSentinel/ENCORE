#!/bin/sh
# Guard: README.md's advertised release version and asset names must match the
# single source of truth (scripts/versions.sh, via common.sh's derivations).
#
# README is static documentation - it can't derive values at render time - so
# it's the one place a version bump has to be mirrored by hand. This test makes
# that drift a loud, automatic failure on every PR (tests.yml runs tests/*.sh)
# instead of a silently-stale download link discovered after release.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
readme="$ROOT/README.md"
[ -f "$readme" ] || { echo "README.md not found at $readme" >&2; exit 1; }

# Read the release version and the derived asset names from the single source
# of truth, without duplicating the derivation. common.sh resolves its paths
# from $0, so run it via `sh -c` (whose $0 is "sh") from inside scripts/, the
# same way the real scripts reach it. Each value is a single whitespace-free
# token, so iterating the newline-separated output is safe.
expected_values=$(cd "$ROOT/scripts" && sh -c '. ./common.sh && printf "%s\n%s\n%s\n%s\n" \
    "$ENCORE_RELEASE_VERSION" "$ENCORE_RUNTIME_ASSET" "$ENCORE_SOURCE_ASSET" "$ENCORE_BUNDLE_ASSET"')

status=0
for expected in $expected_values; do
    if ! grep -Fq -- "$expected" "$readme"; then
        echo "README.md is out of sync with scripts/versions.sh: missing '$expected'" >&2
        echo "  (bump scripts/versions.sh, then update README.md to match)" >&2
        status=1
    fi
done

[ "$status" -eq 0 ] && echo "README version references match scripts/versions.sh"
exit "$status"
