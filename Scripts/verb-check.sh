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
#   3. `--verbs` reports the same name twice.
#   4. docs/reference/occtkit-verbs.md, the canonical per-verb reference and the one
#      remaining hand-maintained list, drifts from the registry in either direction.
#   5. README.md's stated count disagrees with the registry.
#
# Run by CI (.github/workflows/verbs.yml) on any change to the registry, the
# Makefile, or the documents above.
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

# 4. the canonical per-verb reference documents exactly the registered verbs.
#    docs/reference/occtkit-verbs.md is the one remaining hand-maintained list
#    (CLAUDE.md, README.md and the okf/ indexes now defer to it), so it is the
#    list that can still drift. Asserted as set equality, both directions.
#
#    An earlier version of this script instead ran every verb and grepped for
#    "Unknown subcommand". That could never fail: --verbs is Registry.all mapped
#    to .name, and Registry.find searches Registry.all by that same name.
VERB_DOC="docs/reference/occtkit-verbs.md"
[ -f "$VERB_DOC" ] || fail "$VERB_DOC not found (canonical per-verb reference)"

doc_verbs="$(grep -oE '^### `[a-z0-9-]+`' "$VERB_DOC" | tr -d '#` ' | sort)"
[ -n "$doc_verbs" ] || fail "no '### \`verb\`' headings found in $VERB_DOC; has the format changed?"

missing="$(comm -23 <(printf '%s\n' "$verbs" | sort) <(printf '%s\n' "$doc_verbs"))"
extra="$(comm -13 <(printf '%s\n' "$verbs" | sort) <(printf '%s\n' "$doc_verbs"))"
[ -z "$missing" ] || fail "registered but undocumented in $VERB_DOC: $(echo $missing)"
[ -z "$extra" ]   || fail "documented in $VERB_DOC but not registered: $(echo $extra)"

# 5. README's stated count matches the registry. A missing pattern is a failure,
#    not a skip: if the sentence is reworded, this check must break loudly rather
#    than silently stop guarding the thing it exists to guard.
readme_line="$(grep -oE 'Subcommands \([0-9]+ verbs\)' README.md || true)"
[ -n "$readme_line" ] || fail "README.md has no 'Subcommands (N verbs)' line; update this check if the wording changed deliberately"
readme_count="${readme_line//[!0-9]/}"
[ "$readme_count" = "$count" ] || fail "README.md says $readme_count verbs, occtkit --verbs reports $count"

echo "verb-check: $count verbs, $VERB_DOC in sync, README agrees"
