#!/usr/bin/env bash
# policy-check.sh: assert the OKF policy list is consistent everywhere it appears.
#
# `okf/policies/` is the source of truth. Two places re-list it: `okf/index.md`, the
# bundle entry point, and `CLAUDE.md`, which inlines the policies so an agent reading
# the always-loaded reference does not need a second hop to discover them. That
# inlining is deliberate, but it makes CLAUDE.md a hand-maintained second copy, and
# a hand-maintained second copy drifts. It drifted three times in a single day as
# code-structure and issue-tracking landed.
#
# Checks:
#   1. Every okf/policies/*.md is linked from okf/index.md.
#   2. Every okf/policies/*.md is linked from CLAUDE.md.
#   3. Neither document links a policy file that does not exist.
#   4. CLAUDE.md's "All <N> are mandatory" count matches the file count.
#
# This is the same guard `Scripts/verb-check.sh` provides for the verb inventory, per
# okf/decisions/single-source-verb-inventory.md.
#
# Usage:
#   Scripts/policy-check.sh
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -d okf/policies ] || fail "okf/policies/ not found; run from the repo root"

on_disk="$(find okf/policies -maxdepth 1 -name '*.md' ! -name 'index.md' -exec basename {} \; | sort)"
count="$(printf '%s\n' "$on_disk" | grep -c . || true)"
[ "$count" -gt 0 ] || fail "no policy files found in okf/policies/"

# Policies linked from a document, as bare filenames.
linked_in() {
    grep -oE '\(([^)]*/)?policies/[a-z0-9-]+\.md\)' "$1" \
        | sed 's/.*\///; s/)$//' | sort -u
}

for doc in okf/index.md CLAUDE.md; do
    [ -f "$doc" ] || fail "$doc not found"
    linked="$(linked_in "$doc")"
    [ -n "$linked" ] || fail "$doc links no policy files; has the format changed?"

    missing="$(comm -23 <(printf '%s\n' "$on_disk") <(printf '%s\n' "$linked"))"
    extra="$(comm -13 <(printf '%s\n' "$on_disk") <(printf '%s\n' "$linked"))"

    [ -z "$missing" ] || fail "$doc does not link: $(echo $missing)"
    [ -z "$extra" ]   || fail "$doc links non-existent policy files: $(echo $extra)"
done

# CLAUDE.md states the count in prose; keep it honest.
stated="$(grep -oE 'All (one|two|three|four|five|six|seven|eight|nine|ten|[0-9]+) are mandatory' CLAUDE.md || true)"
[ -n "$stated" ] || fail "CLAUDE.md has no 'All <N> are mandatory' line; update this check if the wording changed deliberately"

word="$(printf '%s' "$stated" | awk '{print $2}')"
case "$word" in
    one) n=1 ;; two) n=2 ;; three) n=3 ;; four) n=4 ;; five) n=5 ;;
    six) n=6 ;; seven) n=7 ;; eight) n=8 ;; nine) n=9 ;; ten) n=10 ;;
    *) n="$word" ;;
esac
[ "$n" = "$count" ] || fail "CLAUDE.md says '$stated' but okf/policies/ has $count policies"

echo "policy-check: $count policies, okf/index.md and CLAUDE.md both in sync"
