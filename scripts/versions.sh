# shellcheck shell=sh
# This file is sourced, never executed, so it carries a shell directive instead
# of a shebang.
#
# Single source of truth for ENCORE's version identifiers and pinned build
# inputs.
#
# Sourced by scripts/common.sh and directly by install.sh (which deliberately
# does not source common.sh). Contains only plain POSIX-sh assignments - no
# logic, no side effects - so any script, sh or bash, can source it safely.
#
# Every asset filename, download URL, and version assertion elsewhere in the
# tree derives from the values here. To cut a new release, change them here and
# nowhere else; common.sh builds the asset names from them, and the scripts and
# CI read them rather than repeating literals.

# Upstream Wine: the released version string, and the exact pinned commit.
WINE_VERSION=11.13
WINE_REVISION=6eb2e4c32cc9e271856146df11ed3a5c2cf29234

# ENCORE application release version (git tag / bundle version).
ENCORE_RELEASE_VERSION=v0.1.4

# Prebuilt Wine runtime identity. ENCORE_RUNTIME_REVISION bumps whenever the
# ENCORE patch or the Wine build changes but the upstream Wine version does not,
# so the runtime archive name changes and existing installs see it as outdated.
ENCORE_RUNTIME_VERSION=v0.1.0
ENCORE_RUNTIME_REVISION=r2

# Minimum host glibc the prebuilt runtime supports.
ENCORE_GLIBC_MIN=2.39

# SHA-256 of the published prebuilt runtime archive. Bumped together with
# ENCORE_RUNTIME_REVISION whenever the runtime is rebuilt, so a release cut
# changes this file and nothing else.
#
# Deliberately ${VAR-default}, not ${VAR:-default}: package-wine-release.sh gates
# its checksum comparison on [ -n "$ENCORE_RUNTIME_SHA256" ], treating an empty
# value as "there is no pin to check against" - which is what CI needs when it
# builds a patch change that legitimately produces a new hash. With :- an
# explicitly empty override was substituted back to the pin and the gate stayed
# armed. Unset still gets the pin; only an explicit blank disables the gate.
ENCORE_RUNTIME_SHA256=${ENCORE_RUNTIME_SHA256-c19d2d6ed94e7f0e43d5e060e9869e5958a7e60b77a8809fa3dc1255a1a040df}
