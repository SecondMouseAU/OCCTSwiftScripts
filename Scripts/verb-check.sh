#!/usr/bin/env bash
# verb-check.sh: assert the verb inventory is single-sourced and self-consistent.
#
# The verb list used to be hand-copied into the Makefile, CLAUDE.md, README.md and
# the okf/ indexes. It drifted, and `make install` silently stopped symlinking
# graph-select (OCCTSwiftScripts#82). The Makefile now reads `occtkit --verbs`, so
# this script guards the remaining ways that can go wrong:
#
#   1. `--verbs` prints nothing (an older binary falls through to help), which would
#      make `make install` a silent no-op.
#   2. `--verbs` prints something that is not a verb name, which would scatter junk
#      symlinks across BINDIR.
#   3. A name `--verbs` reports does not actually dispatch.
#   4. Registry and the documented count in README.md disagree.
#
# Usage:
#   Scripts/verb-check.sh
#
# Env:
#   OCCTKIT   path to the occtkit binary (default: `swift run occtkit`)
set -euo pipefail

OCCTKIT="${OCCTKIT:-swift run occtkit}"
fail() { echo "FAIL: $*" >&2; exit 1; }

verbs="$($OCCTKIT --verbs)" || fail "'occtkit --verbs' exited non-zero"
count="$(printf '%s\n' "$verbs" | grep -c . || true)"

# 1. non-empty
[ "$count" -gt 0 ] || fail "'occtkit --verbs' produced no verb names"

# 2. every line looks like a verb name
while IFS= read -r v; do
    [ -n "$v" ] || continue
    case "$v" in
        *[!a-z0-9-]*) fail "verb name '$v' contains unexpected characters" ;;
    esac
done <<< "$verbs"

# 3. no duplicates
dupes="$(printf '%s\n' "$verbs" | sort | uniq -d)"
[ -z "$dupes" ] || fail "duplicate verb names: $dupes"

# 4. every reported verb actually dispatches. A registered verb run with no
#    arguments reports a usage or input error; an unregistered one is reported
#    as unknown by the dispatcher.
while IFS= read -r v; do
    [ -n "$v" ] || continue
    out="$($OCCTKIT "$v" </dev/null 2>&1 || true)"
    case "$out" in
        *"Unknown subcommand"*) fail "'$v' is listed by --verbs but does not dispatch" ;;
    esac
done <<< "$verbs"

# 5. README's stated count matches the registry
readme_count="$(grep -oE 'Subcommands \([0-9]+ verbs\)' README.md | grep -oE '[0-9]+' || true)"
if [ -n "$readme_count" ] && [ "$readme_count" != "$count" ]; then
    fail "README.md says $readme_count verbs, occtkit --verbs reports $count"
fi

echo "verb-check: $count verbs, all dispatch, README agrees"
