#!/usr/bin/env bash
set -Eeuo pipefail

# These checks all live in install.sh's argument-parsing prologue, before
# main() runs any Wine/network/filesystem work, so they exit in milliseconds
# regardless of whether any of the paths involved actually exist.

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL="$ROOT/install.sh"

fail()
{
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_rejected()
{
    local description=$1 expected_status=$2 expected_message=$3
    shift 3
    local status=0 output

    output=$(timeout 5 "$INSTALL" "$@" </dev/null 2>&1) || status=$?
    [[ $status -eq $expected_status ]] ||
        fail "$description: expected exit $expected_status, got $status (output: $output)"
    grep -qF -- "$expected_message" <<<"$output" ||
        fail "$description: expected message not found: $expected_message (output: $output)"
}

assert_rejected 'conflicting --live-dir and --live-installer' 2 \
    'use either --live-dir or --live-installer, not both' \
    --live-dir /tmp/encore-test-live-dir --live-installer /tmp/encore-test-installer.exe

assert_rejected 'conflicting --scale and --dpi' 2 \
    'use either --scale or --dpi, not both' \
    --scale 100 --dpi 96

assert_rejected '--live-installer without an interactive terminal or --dry-run' 2 \
    '--live-installer requires an interactive terminal' \
    --live-installer /tmp/encore-test-installer.exe

assert_rejected 'conflicting --prebuilt and --wine' 2 \
    'cannot be combined with a source build, --no-build, or --wine' \
    --prebuilt --wine /tmp/encore-test-wine

assert_rejected 'conflicting --build-from-source and --no-build' 2 \
    'cannot be combined with --no-build or --wine' \
    --build-from-source --no-build

assert_rejected 'conflicting --build-only and --replace-live' 2 \
    'cannot be combined with --build-only/--configure-only' \
    --build-only --replace-live

# --dry-run is explicitly exempt from the --live-installer interactivity
# guard (it only previews the plan, so nothing needs a real terminal).
# Confirm the guard's own message does not fire - it still fails shortly
# after, once it tries to validate an installer path that does not exist,
# which is a fine, distinct, fast failure to hit here.
dry_run_status=0
dry_run_output=$(timeout 5 "$INSTALL" \
    --live-installer /tmp/encore-test-installer-missing.exe --dry-run \
    </dev/null 2>&1) || dry_run_status=$?
[[ $dry_run_status -ne 2 ]] ||
    fail "--dry-run should be exempt from the interactivity guard (got exit 2: $dry_run_output)"
if grep -qF 'requires an interactive terminal' <<<"$dry_run_output"; then
    fail "--dry-run should be exempt from the interactivity guard: $dry_run_output"
fi

printf 'PASS: install.sh argument validation\n'
