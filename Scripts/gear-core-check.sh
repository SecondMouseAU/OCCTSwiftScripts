#!/usr/bin/env bash
# gear-core-check.sh: assert the copied gear core in the BOSL2 bevel gear examples has not
# drifted between copies.
#
# `docs/guides/bosl2-bevel-gears/example1.swift`, `example2.swift` and `example3.swift` each
# carry an identical block of construction code, delimited by BEGIN/END marker comments.
# The duplication is deliberate: `occtkit run` compiles exactly one `Sources/Script/main.swift`
# whose only dependency is the `ScriptHarness` product, so an example that imported a shared
# gear module could not be run the way the page says to run it, and promoting the gear code to
# a library product is a permanent public-API commitment this repo has not made. That is the
# same rule `recipes/README.md` already states for recipes.
#
# Three copies of 400-odd lines drift. This is what stops them.
#
# Checks:
#   1. Every example file has exactly one BEGIN marker and one END marker, in that order.
#   2. The extracted block is long enough to be the real core, so an empty or truncated
#      extraction fails loudly instead of making every copy trivially equal. Without this the
#      check would pass on three files that had all lost the block.
#   3. All copies hash identically, byte for byte.
#
# This is the same shape of guard as `Scripts/policy-check.sh` and `Scripts/verb-check.sh`,
# and runs in the same CI workflow as the first of those (no Swift build needed).
#
# Usage:
#   Scripts/gear-core-check.sh
set -euo pipefail

BEGIN_MARKER='BEGIN SHARED GEAR CORE'
END_MARKER='END SHARED GEAR CORE'
MIN_LINES=300
DIR="docs/guides/bosl2-bevel-gears"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -d "$DIR" ] || fail "$DIR not found; run from the repo root"

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$DIR" -maxdepth 1 -name 'example*.swift' | sort)
[ "${#files[@]}" -ge 2 ] || fail "expected at least two example*.swift in $DIR, found ${#files[@]}"

hash=""
reference=""
for f in "${files[@]}"; do
    begins="$(grep -c "$BEGIN_MARKER" "$f" || true)"
    ends="$(grep -c "$END_MARKER" "$f" || true)"
    [ "$begins" = "1" ] || fail "$f has $begins '$BEGIN_MARKER' markers, expected exactly 1"
    [ "$ends" = "1" ] || fail "$f has $ends '$END_MARKER' markers, expected exactly 1"

    begin_line="$(grep -n "$BEGIN_MARKER" "$f" | cut -d: -f1)"
    end_line="$(grep -n "$END_MARKER" "$f" | cut -d: -f1)"
    [ "$begin_line" -lt "$end_line" ] || fail "$f has its END marker at line $end_line, before its BEGIN marker at $begin_line"

    core="$(awk -v a="$begin_line" -v b="$end_line" 'NR>=a && NR<=b' "$f")"
    lines="$(printf '%s\n' "$core" | wc -l | tr -d ' ')"
    [ "$lines" -ge "$MIN_LINES" ] || fail "$f's shared core is only $lines lines, expected at least $MIN_LINES; the markers have moved or the block has been gutted"

    this="$(printf '%s\n' "$core" | shasum -a 256 | cut -d' ' -f1)"
    if [ -z "$hash" ]; then
        hash="$this"
        reference="$f"
    elif [ "$this" != "$hash" ]; then
        echo "FAIL: the shared gear core in $f differs from $reference" >&2
        echo "Diff (reference on the left):" >&2
        diff <(awk -v a="$(grep -n "$BEGIN_MARKER" "$reference" | cut -d: -f1)" \
                   -v b="$(grep -n "$END_MARKER" "$reference" | cut -d: -f1)" \
                   'NR>=a && NR<=b' "$reference") \
             <(printf '%s\n' "$core") >&2 || true
        exit 1
    fi
done

echo "gear-core-check: ${#files[@]} example scripts share an identical $lines line core ($hash)"
