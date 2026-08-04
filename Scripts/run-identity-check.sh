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

# Mirror of escapedForManifest in Sources/occtkit/Commands/Run.swift: backslash
# first, then quote, so the expected literal can be built without parsing the
# generated manifest back out.
escape_for_literal() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

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

# check_alias <basename> [path-suffix]
#
# Symlinks the repo at $TMP/<basename>, points OCCTKIT_SCRIPTS_PATH at it (plus
# any suffix, used for the trailing-slash case), and asserts the generated
# manifest's identity and dependency path both come back as <basename>.
check_alias() {
    local name="$1" suffix="${2-}"          # ${2-} is the set -u safe form, bash 3.2 ok
    local alias_path="$TMP/$name"
    ln -sfn "$PWD" "$alias_path"

    rm -rf "$WORKSPACE"
    OCCTKIT_SCRIPTS_PATH="$alias_path$suffix" "$OCCTKIT" run "$script" --output "$TMP/out" >/dev/null 2>&1 &
    local runner=$!

    # Poll for the manifest rather than bounding the run with `timeout`: that is
    # GNU coreutils and absent on macOS, where CI runs. Do not "simplify" this
    # into a `timeout` call.
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

    # Assert on the exact escaped literals rather than parsing them back out.
    # A name containing `"` is emitted as `\"`, which no `[^"]+` pattern can
    # extract correctly, and getting that wrong would make this check fail on
    # correct output. Comparing against the expected literal tests the escaping
    # itself, which is the point.
    local esc_name esc_path
    esc_name="$(escape_for_literal "$name")"
    esc_path="$(escape_for_literal "$alias_path")"

    grep -Fq "package: \"$esc_name\")" "$MANIFEST" || {
        echo "  manifest lines:" >&2
        grep -F 'package' "$MANIFEST" >&2
        fail "[$name] expected identity literal 'package: \"$esc_name\"'; occtkit run will fail here"
    }
    grep -Fq ".package(path: \"$esc_path\")" "$MANIFEST" || {
        echo "  manifest lines:" >&2
        grep -F 'package' "$MANIFEST" >&2
        fail "[$name] expected dependency literal '.package(path: \"$esc_path\")'"
    }

    echo "  $name: identity and dependency path both emitted correctly"
}

# A deliberately renamed directory: the #98 failure case.
check_alias "deliberately-renamed"
# Regression: a directory that IS named after the repo must still work.
check_alias "OCCTSwiftScripts"
# A trailing slash must not change the derived identity. This goes through the
# same assertions as the others, including the dependency-path check, which holds
# because the declaration is standardized before it is emitted.
check_alias "trailing-slash-case" "/"
# Quotes and backslashes are legal in APFS path components and must survive into
# the generated manifest as valid Swift string literals on both sides.
check_alias 'quote"and\backslash'

echo "run-identity-check: 4 scenarios passed"
