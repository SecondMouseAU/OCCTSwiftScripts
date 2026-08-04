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
# this on its own. This points OCCTKIT_SCRIPTS_PATH at a symlink with a
# deliberately different basename, which reproduces the failure without copying
# the tree.
#
# Only the generated manifest is asserted on, not the build result, so this stays
# fast and does not need the script's dependency graph to resolve.
#
# Usage:
#   Scripts/run-identity-check.sh
#
# Env:
#   OCCTKIT   path to the occtkit binary (default: .build/release/occtkit)
set -euo pipefail

OCCTKIT="${OCCTKIT:-.build/release/occtkit}"
WORKSPACE="$HOME/.occtswift-scripts/runner-cache/workspace"
ALIAS="$(mktemp -d)/deliberately-renamed"

fail() { echo "FAIL: $*" >&2; exit 1; }
cleanup() { rm -rf "$(dirname "$ALIAS")"; }
trap cleanup EXIT

[ -x "$OCCTKIT" ] || fail "occtkit not found or not executable at $OCCTKIT"
[ -f recipes/01-mounting-bracket/main.swift ] || fail "run from the repo root"

ln -sfn "$PWD" "$ALIAS"
expected="$(basename "$ALIAS")"

rm -rf "$WORKSPACE"
# `ensureWorkspace()` writes the manifest before `buildAndRun()` is reached, so
# there is no need to wait for (or succeed at) the build. Start the run, poll for
# the manifest, then stop it. `timeout` is GNU coreutils and absent on macOS,
# where CI runs, hence the manual poll.
OCCTKIT_SCRIPTS_PATH="$ALIAS" "$OCCTKIT" run recipes/01-mounting-bracket/main.swift \
    --output "$(dirname "$ALIAS")/out" >/dev/null 2>&1 &
runner=$!

manifest="$WORKSPACE/Package.swift"
for _ in $(seq 1 60); do
    [ -f "$manifest" ] && break
    kill -0 "$runner" 2>/dev/null || break   # exited before writing it
    sleep 0.5
done
kill "$runner" 2>/dev/null || true
wait "$runner" 2>/dev/null || true

[ -f "$manifest" ] || fail "occtkit run did not generate $manifest"

identity="$(grep -oE 'package: "[^"]+"' "$manifest" | head -1 | sed 's/package: "//; s/"$//')"
[ -n "$identity" ] || fail "no 'package: \"...\"' found in the generated manifest"

deppath="$(grep -oE '\.package\(path: "[^"]+"\)' "$manifest" | head -1 | sed 's/.*path: "//; s/")$//')"
[ -n "$deppath" ] || fail "generated manifest declares no path dependency; expected one via OCCTKIT_SCRIPTS_PATH"

[ "$identity" = "$expected" ] || \
    fail "manifest identity is '$identity' but the dependency path basename is '$expected'; occtkit run will fail here"
[ "$(basename "$deppath")" = "$identity" ] || \
    fail "dependency path '$deppath' and identity '$identity' disagree"

echo "run-identity-check: identity '$identity' matches the dependency path basename"
