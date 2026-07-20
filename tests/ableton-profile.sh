#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/ableton-profile.sh
. "$ROOT/scripts/ableton-profile.sh"

fail()
{
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq()
{
    local description=$1 expected=$2 actual=$3
    [[ $actual == "$expected" ]] ||
        fail "$description: expected '$expected', got '$actual'"
}

# --- encore_ableton_profile_from_executable: a supported, already-installed exe ---

encore_ableton_profile_from_executable \
    "/prefix/drive_c/ProgramData/Ableton/Live 11 Suite/Program/Ableton Live 11 Suite.exe" ||
    fail 'Live 11 Suite executable should be recognized'
assert_eq 'major' 11 "$ENCORE_ABLETON_MAJOR"
assert_eq 'edition' Suite "$ENCORE_ABLETON_EDITION"
assert_eq 'product' 'Ableton Live 11 Suite' "$ENCORE_ABLETON_PRODUCT"
assert_eq 'folder' 'Live 11 Suite' "$ENCORE_ABLETON_FOLDER"
assert_eq 'exe' 'Ableton Live 11 Suite.exe' "$ENCORE_ABLETON_EXE"
assert_eq 'icon' live_suite.ico "$ENCORE_ABLETON_ICON_BASENAME"

# --- encore_ableton_profile_from_installer: expects the post-install exe name,
# not the installer's own filename, since nothing is installed yet ---

encore_ableton_profile_from_installer \
    "/home/user/Downloads/Ableton Live 12 Trial Installer.exe" ||
    fail 'Live 12 Trial installer should be recognized'
assert_eq 'major' 12 "$ENCORE_ABLETON_MAJOR"
assert_eq 'edition' Trial "$ENCORE_ABLETON_EDITION"
assert_eq 'folder' 'Live 12 Trial' "$ENCORE_ABLETON_FOLDER"
assert_eq 'exe (expected post-install name, not the installer filename)' \
    'Ableton Live 12 Trial.exe' "$ENCORE_ABLETON_EXE"

# --- unsupported filenames are rejected and clear prior state ---

if encore_ableton_profile_from_executable '/tmp/Ableton Live 13 Suite.exe'; then
    fail 'a nonexistent major version should not be recognized'
fi
[[ -z ${ENCORE_ABLETON_MAJOR-} ]] || fail 'rejected profile should clear ENCORE_ABLETON_MAJOR'

if encore_ableton_profile_from_installer '/tmp/Ableton Live 11 Suite.exe'; then
    fail 'an already-installed exe name should not match the installer pattern'
fi

# --- encore_ableton_path_is_supported: folder and executable name must agree ---

encore_ableton_path_is_supported \
    '/prefix/drive_c/ProgramData/Ableton/Live 11 Suite/Program/Ableton Live 11 Suite.exe' ||
    fail 'matching folder and executable should be supported'

if encore_ableton_path_is_supported \
    '/prefix/drive_c/ProgramData/Ableton/Live 11 Suite/Program/Ableton Live 12 Suite.exe'; then
    fail 'a folder/executable version mismatch should be rejected'
fi

if encore_ableton_path_is_supported \
    '/prefix/drive_c/ProgramData/Ableton/Live 11 Standard/Program/Ableton Live 11 Suite.exe'; then
    fail 'a folder/executable edition mismatch should be rejected'
fi

if encore_ableton_path_is_supported \
    '/prefix/drive_c/ProgramData/Ableton/Live 11 Suite/Ableton Live 11 Suite.exe'; then
    fail 'an executable directly under the Live folder (not under Program) should be rejected'
fi

printf 'PASS: Ableton profile detection\n'
