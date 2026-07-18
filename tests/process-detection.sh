#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROCESS_CHECK="$ROOT/scripts/process-is-running.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/encore-process-test.XXXXXX")
sleeper_pid=

cleanup()
{
    if [[ -n $sleeper_pid ]]; then
        kill "$sleeper_pid" 2>/dev/null || true
        wait "$sleeper_pid" 2>/dev/null || true
    fi
    case $TEST_ROOT in
        "${TMPDIR:-/tmp}"/encore-process-test.*) rm -rf -- "$TEST_ROOT" ;;
    esac
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail()
{
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

start_process()
{
    local argv0=$1 first= attempt

    if [[ -n $sleeper_pid ]]; then
        kill "$sleeper_pid" 2>/dev/null || true
        wait "$sleeper_pid" 2>/dev/null || true
        sleeper_pid=
    fi

    bash -c 'exec -a "$1" python3 -c "import time; time.sleep(60)"' _ "$argv0" &
    sleeper_pid=$!
    for attempt in {1..50}; do
        first=$(tr '\000' '\n' < "/proc/$sleeper_pid/cmdline" 2>/dev/null | sed -n '1p') || true
        [[ $first == "$argv0" ]] && return 0
        sleep 0.02
    done
    fail "synthetic process did not expose the requested argv[0]: $argv0"
}

stop_process()
{
    [[ -n $sleeper_pid ]] || return 0
    kill "$sleeper_pid" 2>/dev/null || true
    wait "$sleeper_pid" 2>/dev/null || true
    sleeper_pid=
}

assert_running()
{
    local stderr_file="$TEST_ROOT/process-check.stderr"

    : > "$stderr_file"
    "$PROCESS_CHECK" "$1" 2>"$stderr_file" || fail "expected running process: $1"
    [[ ! -s $stderr_file ]] || fail "process check wrote to stderr: $(<"$stderr_file")"
}

assert_not_running()
{
    local stderr_file="$TEST_ROOT/process-check.stderr"

    : > "$stderr_file"
    if "$PROCESS_CHECK" "$1" 2>"$stderr_file"; then
        fail "unexpected running process: $1"
    fi
    [[ ! -s $stderr_file ]] || fail "process check wrote to stderr: $(<"$stderr_file")"
}

command -v python3 >/dev/null 2>&1 || fail 'python3 is required for this test'

probe_name="ENCORE Process Probe $$.exe"
unix_target="$TEST_ROOT/Prefix A/drive_c/Program Files/$probe_name"

start_process "$unix_target"
assert_running "$unix_target"
stop_process

start_process "C:\\Program Files\\ENCORE\\$probe_name"
assert_running "$unix_target"
stop_process

# Matching a second prefix is deliberately conservative. Refusing a launch or
# mutation is safer than changing a prefix while the same Live edition runs.
start_process "Z:\\Other Prefix\\$probe_name"
assert_running "$unix_target"
stop_process

start_process "C:\\Program Files\\ENCORE\\Different Probe $$.exe"
assert_not_running "$unix_target"
stop_process

plain_name="ENCORE Process Probe $$"
start_process "C:\\Program Files\\ENCORE\\$plain_name"
assert_not_running "$TEST_ROOT/$plain_name"
stop_process

if "$PROCESS_CHECK" >/dev/null 2>&1; then
    fail 'zero arguments should fail'
else
    status=$?
    [[ $status -eq 2 ]] || fail "zero arguments returned $status instead of 2"
fi

if "$PROCESS_CHECK" one two >/dev/null 2>&1; then
    fail 'two arguments should fail'
else
    status=$?
    [[ $status -eq 2 ]] || fail "two arguments returned $status instead of 2"
fi

fixture_root="$TEST_ROOT/launcher-fixture"
fixture_prefix="$fixture_root/prefix"
ableton="$fixture_prefix/drive_c/ProgramData/Ableton/Live 12 Suite/Program/Ableton Live 12 Suite.exe"
callback='ableton://authorize?code=encore-test&state=callback-test'
launcher_log="$fixture_root/logs/ableton-dock.log"

mkdir -p "${ableton%/*}"
cp -a "$ROOT/scripts" "$fixture_root/scripts"
: > "$ableton"

start_process 'C:\\ProgramData\\Ableton\\Live 12 Suite\\Program\\Ableton Live 12 Suite.exe'

env \
    ENCORE_PREFIX="$fixture_prefix" \
    ENCORE_ABLETON="$ableton" \
    ENCORE_WINE=/bin/echo \
    ENCORE_RUNTIME_CONFIG="$fixture_root/missing-runtime.conf" \
    "$fixture_root/scripts/launch-ableton.sh"

[[ ! -e $launcher_log ]] || fail 'bare launch should exit before invoking Wine'

env \
    ENCORE_PREFIX="$fixture_prefix" \
    ENCORE_ABLETON="$ableton" \
    ENCORE_WINE=/bin/echo \
    ENCORE_RUNTIME_CONFIG="$fixture_root/missing-runtime.conf" \
    "$fixture_root/scripts/launch-ableton.sh" "$callback"

[[ -f $launcher_log ]] || fail 'callback launch did not invoke Wine'
actual=$(<"$launcher_log")
expected="$ableton $callback"
[[ $actual == "$expected" ]] || fail "callback arguments changed: $actual"

stop_process
printf 'PASS: process detection and callback forwarding\n'
