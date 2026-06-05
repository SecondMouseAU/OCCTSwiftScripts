#!/usr/bin/env bash
# render-recipe.sh — render a recipe's output.png via the render-preview verb.
#
# Runs the recipe to a temp dir, then renders body-0.brep to <dir>/output.png with the
# OCCTSwiftViewport OffscreenRenderer. If render-preview fails (no Metal / headless CI),
# it warns and skips without erroring — the PNG is a locally-generated artifact, never a
# CI gate (see issue #16).
#
# Usage:
#   Scripts/render-recipe.sh recipes/01-mounting-bracket
#   Scripts/render-recipe.sh                 # all recipes/*/ that contain main.swift
#
# Env:
#   OCCTKIT   path to the occtkit binary (default: `swift run occtkit`)
#   CAMERA    camera preset (default: iso)
#   BG        background (default: dark)
#   WIDTH / HEIGHT  pixel size (default: 800 / 600)
set -euo pipefail

OCCTKIT="${OCCTKIT:-swift run occtkit}"
CAMERA="${CAMERA:-iso}"
BG="${BG:-dark}"
WIDTH="${WIDTH:-800}"
HEIGHT="${HEIGHT:-600}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

render_one() {
  local dir="${1%/}"
  local name; name="$(basename "$dir")"
  echo "▶ rendering $name"
  if [ ! -f "$dir/main.swift" ]; then echo "  · no main.swift, skip"; return 0; fi

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  $OCCTKIT run "$dir/main.swift" --format brep --output "$tmp" >/dev/null 2>&1 || {
    echo "  ! recipe run failed, skip" >&2; return 0; }

  if $OCCTKIT render-preview "$tmp/body-0.brep" --output "$dir/output.png" \
        --camera "$CAMERA" --background "$BG" --width "$WIDTH" --height "$HEIGHT" \
        >/dev/null 2>&1 && [ -s "$dir/output.png" ]; then
    echo "  ✓ wrote $dir/output.png"
  else
    echo "  ! render-preview unavailable (headless / no Metal) — PNG skipped" >&2
  fi
}

if [ "$#" -ge 1 ]; then
  render_one "$1"
else
  for d in "$ROOT"/recipes/*/; do render_one "$d"; done
fi
