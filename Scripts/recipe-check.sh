#!/usr/bin/env bash
# recipe-check.sh — smoke-test a recipe and (optionally) compare to its reference BREP.
#
# For one recipe directory:
#   1. Run `occtkit run <dir>/main.swift --format brep` into a temp dir.
#   2. Assert manifest.json parses and body-0.brep is non-empty.
#   3. Assert the emitted volume is > 0 (via `occtkit metrics`).
#   4. If <dir>/output.brep exists, compare volume + bounding box within tolerance.
#
# Usage:
#   Scripts/recipe-check.sh recipes/01-mounting-bracket
#   Scripts/recipe-check.sh                 # all recipes/*/ that contain main.swift
#
# Env:
#   OCCTKIT   path to the occtkit binary (default: `swift run occtkit`)
#   TOL       relative tolerance for the reference compare (default: 1e-3)
set -euo pipefail

export OCCTKIT="${OCCTKIT:-swift run occtkit}"
export TOL="${TOL:-1e-3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

check_one() {
  local dir="${1%/}"
  local name; name="$(basename "$dir")"
  echo "▶ $name"
  if [ ! -f "$dir/main.swift" ]; then echo "  ✗ no main.swift in $dir" >&2; return 1; fi

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  if ! $OCCTKIT run "$dir/main.swift" --format brep --output "$tmp" >/dev/null 2>&1; then
    echo "  ✗ occtkit run failed" >&2; return 1
  fi

  # All validation + (optional) reference compare happens in one Python pass.
  # Args: <emitted-dir> <reference-output.brep>. occtkit metrics is shelled out for
  # both the emitted body and the reference; no data is piped over stdin.
  python3 - "$tmp" "$dir/output.brep" <<'PY'
import json, os, subprocess, sys

emitted_dir, ref = sys.argv[1], sys.argv[2]
tol = float(os.environ.get("TOL", "1e-3"))
occtkit = os.environ.get("OCCTKIT", "swift run occtkit").split()

def die(msg):
    print(f"  ✗ {msg}", file=sys.stderr); sys.exit(1)

manifest = os.path.join(emitted_dir, "manifest.json")
body = os.path.join(emitted_dir, "body-0.brep")
if not os.path.getsize(manifest): die("manifest.json missing/empty")
try:
    json.load(open(manifest))
except Exception as e:
    die(f"manifest.json invalid JSON: {e}")
if not os.path.exists(body) or not os.path.getsize(body): die("body-0.brep missing/empty")

def metrics(path):
    out = subprocess.check_output(occtkit + ["metrics", path, "--metrics", "volume,boundingBox"])
    return json.loads(out)

cur = metrics(body)
v = cur.get("volume")
if v is None or v <= 0: die(f"volume not > 0: {v}")
print(f"  ✓ volume = {v:.3f}")

if os.path.exists(ref):
    r = metrics(ref); rv = r["volume"]
    rel = abs(v - rv) / max(abs(rv), 1e-9)
    if rel > tol: die(f"volume drift {rel:.2e} > tol {tol:.1e} (ref {rv:.3f})")
    for key in ("min", "max"):
        for a, b in zip(cur["boundingBox"][key], r["boundingBox"][key]):
            if abs(a - b) > 1e-3 + tol * max(abs(b), 1.0):
                die(f"bbox {key} drift {abs(a-b):.2e}")
    print(f"  ✓ matches reference output.brep (Δvol {rel:.2e})")
else:
    print("  · no reference output.brep — skipping compare")
PY
  echo "  ✓ $name OK"
}

status=0
if [ "$#" -ge 1 ]; then
  check_one "$1" || status=1
else
  for d in "$ROOT"/recipes/*/; do
    [ -f "$d/main.swift" ] || continue
    check_one "${d%/}" || status=1
  done
fi
exit $status
