#!/usr/bin/env bash
# run-identity-check.sh: assert `occtkit run` generates a workspace whose package
# identity matches the dependency path it points at.
#
# occtkit run writes a throwaway SwiftPM manifest that declares a path dependency
# on this package and refers to it by identity. SwiftPM derives a path
# dependency's identity from the directory basename, not from the `name:` in its
# manifest, so hardcoding the identity broke `occtkit run` in every checkout not
# literally named OCCTSwiftScripts: forks, second checkouts, git worktrees, and
# any OCCTKIT_SCRIPTS_PATH pointing somewhere named differently
# (OCCTSwiftScripts#98).
#
# CI always checks out into a directory named after the repo, so it cannot catch
# this on its own. This points OCCTKIT_SCRIPTS_PATH at symlinks with deliberately
# different basenames, which reproduces the failure without copying the tree.
#
# Only the generated manifest is asserted on, not the build result:
# `ensureWorkspace()` writes the manifest before `buildAndRun()` is reached, so
# the run is stopped as soon as the file appears. That keeps this at roughly zero
# seconds and independent of whether the script's dependency graph resolves.
#
# SCOPE LIMIT: this covers resolution branch 1 only, the OCCTKIT_SCRIPTS_PATH
# override. Branch 2, argv[0] auto-detection, is equally affected by #98 and is
# what most users hit, but it structurally cannot be covered by this technique:
# that branch calls `resolvingSymlinksInPath()` on argv[0], so an aliased path
# resolves straight back to the real checkout name. Covering it would need a
# genuinely renamed copy of the tree. Branch 3, the remote fallback, is a URL
# dependency whose identity is fixed and so cannot drift.
#
# Usage:
#   Scripts/run-identity-check.sh
#
# Env:
#   OCCTKIT   path to the occtkit binary (default: .build/release/occtkit)
set -euo pipefail

OCCTKIT="${OCCTKIT:-.build/release/occtkit}"
WORKSPACE="$HOME/.occtswift-scripts/runner-cache/workspace"
MANIFEST="$WORKSPACE/Package.swift"
TMP="$(mktemp -d)"
SAVED="$TMP/saved-workspace"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The workspace cache is shared by every `occtkit run` on this machine and holds
# a resolved dependency graph plus .build. Blowing it away would cost the
# developer a full cold rebuild on their next real run, so it is moved aside and
# restored. Overriding HOME would not isolate it: occtkit takes the cache path
# from FileManager.homeDirectoryForCurrentUser, which ignores $HOME.
cleanup() {
    rm -rf "$WORKSPACE"
    if [ -d "$SAVED" ]; then
        mkdir -p "$(dirname "$WORKSPACE")"
        mv "$SAVED" "$WORKSPACE"
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

[ -x "$OCCTKIT" ] || fail "occtkit not found or not executable at $OCCTKIT"
# Package.swift is the repo-root sentinel resolveScriptsDep itself probes for.
[ -f Package.swift ] || fail "run from the repo root (no Package.swift here)"

[ -d "$WORKSPACE" ] && mv "$WORKSPACE" "$SAVED"

# The run is killed before the build matters, so the script only has to survive
# the `fileExists` guard in `parse()`. Not coupling to a real recipe keeps this
# check working if the recipes are renamed or renumbered.
script="$TMP/probe.swift"
printf 'import ScriptHarness\n' > "$script"

# Job control on, so the whole process group can be signalled below.
set -m

check_alias() {
    local name="$1"
    local alias_path="$TMP/$name"
    ln -sfn "$PWD" "$alias_path"

    rm -rf "$WORKSPACE"
    OCCTKIT_SCRIPTS_PATH="$alias_path" "$OCCTKIT" run "$script" --output "$TMP/out" >/dev/null 2>&1 &
    local runner=$!

    local i
    for i in $(seq 1 60); do
        [ -f "$MANIFEST" ] && break
        kill -0 "$runner" 2>/dev/null || break   # exited before writing it
        sleep 0.5
    done
    # Signal the whole group: by now buildAndRun() may have spawned `swift build`,
    # which would otherwise survive and keep resolving against an alias this
    # script is about to delete.
    kill -- -"$runner" 2>/dev/null || true
    wait "$runner" 2>/dev/null || true

    [ -f "$MANIFEST" ] || fail "[$name] occtkit run did not generate $MANIFEST"

    local identity deppath
    identity="$(grep -oE 'package: "[^"]+"' "$MANIFEST" | head -1 | sed 's/package: "//; s/"$//')"
    [ -n "$identity" ] || fail "[$name] no 'package: \"...\"' found in the generated manifest"

    deppath="$(grep -oE '\.package\(path: "[^"]+"\)' "$MANIFEST" | head -1 | sed 's/.*path: "//; s/")$//')"
    [ -n "$deppath" ] || fail "[$name] manifest declares no path dependency; expected one via OCCTKIT_SCRIPTS_PATH"

    [ "$identity" = "$name" ] || \
        fail "[$name] manifest identity is '$identity' but the dependency path basename is '$name'; occtkit run will fail here"
    [ "$(basename "$deppath")" = "$identity" ] || \
        fail "[$name] dependency path '$deppath' and identity '$identity' disagree"

    echo "  $name: identity '$identity' matches the dependency path basename"
}

# A deliberately renamed directory: the #98 failure case.
check_alias "deliberately-renamed"
# Regression: a directory that IS named after the repo must still work.
check_alias "OCCTSwiftScripts"

# A trailing slash must not change the derived identity.
ln -sfn "$PWD" "$TMP/trailing-slash-case"
rm -rf "$WORKSPACE"
OCCTKIT_SCRIPTS_PATH="$TMP/trailing-slash-case/" "$OCCTKIT" run "$script" --output "$TMP/out" >/dev/null 2>&1 &
runner=$!
for _ in $(seq 1 60); do
    [ -f "$MANIFEST" ] && break
    kill -0 "$runner" 2>/dev/null || break
    sleep 0.5
done
kill -- -"$runner" 2>/dev/null || true
wait "$runner" 2>/dev/null || true
[ -f "$MANIFEST" ] || fail "[trailing slash] occtkit run did not generate $MANIFEST"
identity="$(grep -oE 'package: "[^"]+"' "$MANIFEST" | head -1 | sed 's/package: "//; s/"$//')"
[ "$identity" = "trailing-slash-case" ] || \
    fail "[trailing slash] identity is '$identity', expected 'trailing-slash-case'"
echo "  trailing-slash-case: trailing slash does not change the derived identity"

echo "run-identity-check: 3 scenarios passed"
