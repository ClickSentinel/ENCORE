#!/usr/bin/env bash
set -Eeuo pipefail

# detect_dpi() lives in install.sh, which isn't designed to be sourced as a
# library (it parses "$@" as a whole script at the top level). Extract just
# the function body from the real source instead of keeping a hand-copied
# duplicate here, so this test can't silently drift from what's shipped.

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/encore-detect-dpi-test.XXXXXX")
BIN="$SCRATCH/bin"

cleanup()
{
    rm -rf -- "$SCRATCH"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail()
{
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

function_body=$(awk '/^detect_dpi\(\)$/{p=1} p{print} p && /^}$/{exit}' "$ROOT/install.sh")
[[ -n $function_body ]] || fail 'could not extract detect_dpi() from install.sh'
eval "$function_body"

# A controlled PATH with only what detect_dpi needs, and deliberately no
# gsettings, regardless of what the host or CI runner actually has installed -
# otherwise a GNOME desktop's real scaling-factor setting would take over and
# this test would depend on whoever runs it rather than the code being tested.
mkdir -p "$BIN"
for real_tool in awk grep tail; do
    tool_path=$(command -v "$real_tool") || fail "$real_tool not found on this system"
    ln -s "$tool_path" "$BIN/$real_tool"
done

cat >"$BIN/xrandr" <<'FAKE_XRANDR'
#!/bin/sh
printf '%s\n' "$FAKE_XRANDR_OUTPUT"
FAKE_XRANDR
chmod +x "$BIN/xrandr"

run_detect_dpi()
{
    local output_line=$1
    ( PATH="$BIN" DISPLAY=:0 FAKE_XRANDR_OUTPUT="$output_line" detect_dpi; \
      printf '%s %s\n' "$dpi_recommendation" "$dpi_reason" )
}

assert_dpi()
{
    local description=$1 xrandr_line=$2 expected_dpi=$3
    local result actual_dpi

    result=$(run_detect_dpi "$xrandr_line")
    actual_dpi=${result%% *}
    [[ $actual_dpi == "$expected_dpi" ]] ||
        fail "$description: expected $expected_dpi DPI, got: $result"
}

# This is the exact real-world case that motivated calculating true PPI from
# physical size instead of guessing from resolution alone: a 27" 2560x1440
# monitor. The old resolution-only heuristic recommended 150% (144 DPI); the
# real physical size (597mm x 336mm here) gives a true PPI of about 109,
# which is a standard-density display, so 100% (96 DPI) is correct.
assert_dpi '27" 2560x1440 monitor (597mm x 336mm, true PPI ~109)' \
    'HDMI-1 connected primary 2560x1440+0+0 (normal left inverted right x axis y axis) 597mm x 336mm' \
    96

# A genuinely high-density 13" laptop panel (2560x1600, 293mm x 183mm,
# true PPI ~222) should still land in the HiDPI tier.
assert_dpi '13" 2560x1600 laptop panel (293mm x 183mm, true PPI ~222)' \
    'eDP-1 connected primary 2560x1600+0+0 (normal left inverted right x axis y axis) 293mm x 183mm' \
    192

# Some virtual/projector outputs report 0mm x 0mm for physical size. Without
# a usable physical size, detect_dpi falls back to the old resolution-only
# heuristic rather than dividing by zero.
assert_dpi '4K output with no reported physical size falls back to resolution' \
    'VIRTUAL-1 connected primary 3840x2160+0+0 (normal left inverted right x axis y axis) 0mm x 0mm' \
    192

# No connected display information at all falls back to the 100% default.
assert_dpi 'no usable xrandr output' '' 96

printf 'PASS: detect_dpi PPI calculation\n'
