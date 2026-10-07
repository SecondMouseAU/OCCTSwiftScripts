#!/usr/bin/env bash
# serve-check.sh: assert `occtkit --serve` answers every request with one envelope and
# keeps going after a failure.
#
# `--serve` is implemented once, in Sources/occtkit/Serve.swift, so it cannot be driven
# in-process by the unit tests. The contract it carries is what OCCTMCP depends on:
#
#   1. One JSONL envelope per request, in order, success or failure:
#      {"ok": bool, "exit": int, "stdout": str, "stderr": str, "error": str?}
#   2. A failing request (here, a missing input file) yields ok=false and a non-zero exit,
#      and the NEXT request is still answered. That is the reason verbs throw instead of
#      calling exit().
#   3. A verb's own stdout lands in the envelope's `stdout`, not on occtkit's stdout.
#   4. EOF on stdin exits 0.
#
# Run by CI (.github/workflows/integration.yml).
#
# Usage:
#   Scripts/serve-check.sh
#
# Env:
#   OCCTKIT   path to the occtkit binary (default: .build/release/occtkit)
set -euo pipefail

OCCTKIT="${OCCTKIT:-.build/release/occtkit}"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -x "$OCCTKIT" ] || fail "$OCCTKIT is not an executable; build it first"

brep="$(find recipes -name output.brep | sort | head -1)"
[ -n "$brep" ] || fail "no recipes/*/output.brep fixture found"

requests="$(printf '%s\n%s\n%s\n' \
    "{\"args\": [\"$brep\"]}" \
    '{"args": ["/nonexistent/missing.brep"]}' \
    "{\"args\": [\"$brep\", \"--metrics\", \"solidCount\"]}")"

out="$(printf '%s\n' "$requests" | "$OCCTKIT" metrics --serve)" \
    || fail "occtkit metrics --serve exited non-zero on EOF"

python3 - "$out" <<'PY'
import json, sys

lines = [l for l in sys.argv[1].splitlines() if l.strip()]
if len(lines) != 3:
    sys.exit(f"FAIL: expected 3 envelopes, got {len(lines)}:\n{sys.argv[1]}")

env = [json.loads(l) for l in lines]
for i, e in enumerate(env):
    for key in ("ok", "exit", "stdout", "stderr"):
        if key not in e:
            sys.exit(f"FAIL: envelope {i} is missing '{key}': {e}")

ok_first, failed, ok_last = env
if not (ok_first["ok"] and ok_first["exit"] == 0):
    sys.exit(f"FAIL: request 1 should succeed: {ok_first}")
if "volume" not in json.loads(ok_first["stdout"]):
    sys.exit(f"FAIL: request 1 stdout is not the metrics JSON: {ok_first['stdout'][:200]}")
if failed["ok"] or failed["exit"] == 0:
    sys.exit(f"FAIL: request 2 (missing file) should fail: {failed}")
if not (failed.get("error") or failed["stderr"]):
    sys.exit(f"FAIL: request 2 failed with no error text: {failed}")
if not (ok_last["ok"] and ok_last["exit"] == 0):
    sys.exit(f"FAIL: request 3 did not run after a failure, the loop did not recover: {ok_last}")
if json.loads(ok_last["stdout"]).get("solidCount") != 1:
    sys.exit(f"FAIL: request 3 stdout is wrong: {ok_last['stdout'][:200]}")
print("serve-check: 3 envelopes, failure isolated, loop recovered")
PY
