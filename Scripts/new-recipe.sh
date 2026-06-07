#!/usr/bin/env bash
# new-recipe.sh — scaffold a new recipe folder (invoked by `make recipe NAME=widget`).
#
# Creates recipes/NN-<name>/ with a skeleton main.swift + README.md, where NN is the
# next available two-digit number (max existing + 1). output.png / output.brep are left
# for the author to generate via Scripts/render-recipe.sh and `occtkit run`.
set -euo pipefail

NAME="${1:-}"
[ -n "$NAME" ] || { echo "usage: make recipe NAME=<kebab-name>" >&2; exit 2; }
# normalise to kebab-case
slug="$(echo "$NAME" | tr '[:upper:] _' '[:lower:]--' | sed -E 's/[^a-z0-9-]//g; s/-+/-/g; s/^-|-$//g')"
[ -n "$slug" ] || { echo "invalid NAME" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/recipes"

# next number = max existing NN-... + 1
max=0
for d in "$ROOT"/recipes/[0-9][0-9]-*/; do
  [ -d "$d" ] || continue
  n=$(basename "$d" | cut -c1-2)
  n=$((10#$n))
  [ "$n" -gt "$max" ] && max=$n
done
nn=$(printf "%02d" $((max + 1)))
dir="$ROOT/recipes/${nn}-${slug}"
[ -e "$dir" ] && { echo "already exists: $dir" >&2; exit 1; }
mkdir -p "$dir"

title="$(echo "$slug" | tr '-' ' ')"

cat > "$dir/main.swift" <<EOF
// Recipe ${nn} — ${title}
//
// Inputs:  none (edit the parameter block below)
// Outputs: one solid body — TODO describe the part.
// Notes:   TODO any gotchas (orientation, axis choice, profile placement).
//
// Run:  swift run occtkit run recipes/${nn}-${slug}/main.swift --format brep

import OCCTSwift
import ScriptHarness

// ── Parameters ──────────────────────────────────────────────────────────────
let size: Double = 20   // TODO replace with real parameters

let ctx = ScriptContext(metadata: ManifestMetadata(
    name: "${title}",
    source: "OCCTSwiftScripts recipe ${nn}",
    tags: ["${slug}"]
))
let C = ScriptContext.Colors.self

// ── Build the part ───────────────────────────────────────────────────────────
let body = Shape.box(width: size, height: size, depth: size)!   // TODO real geometry

try ctx.add(body, color: C.steel, name: "${title}")
try ctx.emit(description: "${title}")
EOF

cat > "$dir/README.md" <<EOF
# ${nn} — ${title}

TODO one-line description.

![${title}](output.png)

## Parameters

| Name   | Default | Description | Valid range |
|--------|---------|-------------|-------------|
| \`size\` | \`20\`    | TODO        | \`> 0\`       |

## Algorithm

TODO 3–8 sentences.

## OCCTSwift APIs used

- \`Shape.box(width:height:depth:)\` — TODO

## Gotchas

- TODO
EOF

echo "Created $dir"
echo "  edit main.swift, then: swift run occtkit run recipes/${nn}-${slug}/main.swift --format brep --output /tmp/${slug}"
echo "  render preview:        Scripts/render-recipe.sh recipes/${nn}-${slug}"
