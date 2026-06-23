---
title: occtkit CLI basics
parent: Cookbook
nav_order: 5
---

# occtkit CLI basics

`occtkit` is a busybox-style multi-call binary: one binary, 29 verbs, three invocation styles.
This page covers the mechanics — how to install it, the two input forms every verb accepts, and
the `--serve` JSONL envelope that powers OCCTMCP. For the full verb list see the
[Reference](../../reference/).

## Installation

```bash
# Install to /usr/local/bin (builds first if needed, then creates one symlink per verb)
make install

# Install to a custom prefix (e.g. ~/.local/bin — make sure it is on $PATH)
make install PREFIX=$HOME/.local

# Remove all symlinks and the binary
make uninstall
```

`make install` writes a symlink for each verb name (`graph-validate`, `drawing-export`, …)
alongside the `occtkit` binary itself.

## Three ways to invoke a verb

After install, all three forms are equivalent:

```bash
# 1. Installed symlink — shortest, busybox-style
graph-validate body.brep

# 2. Umbrella binary — useful when the symlinks are not on $PATH
occtkit graph-validate body.brep

# 3. From a checkout — no install needed
swift run occtkit graph-validate body.brep
```

The dispatcher checks `argv[0]`'s basename first (symlink form), then `argv[1]` (umbrella form),
then prints help.

```bash
# List all verbs with one-line summaries
occtkit --help
```

## Flag-form vs JSON-form input

Every verb accepts **both** input styles. Use whichever fits your pipeline.

**Flag-form** — positional arguments and `--flags`, familiar from Unix tools:

```bash
# Validate a B-Rep graph and emit warnings to stdout
graph-validate body.brep

# Export a single HLR view to DXF
dxf-export bracket.brep bracket.dxf --view 0,0,1

# Graph ML export with custom sampling density
graph-ml part.brep --uv-samples 16 --edge-samples 32 > part.json
```

**JSON-form** — a JSON object on stdin (or a file path as the sole argv argument). Same verbs,
richer inputs:

```bash
# drawing-export reads its full spec from stdin — too many fields for flags
echo '{
  "shape": "bracket.brep",
  "output": "bracket.dxf",
  "sheet": {"size": "a3", "orientation": "landscape",
             "projection": "third", "scale": "auto"},
  "title": {"title": "Bracket"},
  "views": [{"name": "front"}, {"name": "top"}, {"name": "right"}]
}' | drawing-export

# reconstruct builds a BREP from a feature list
echo '{
  "outputDir": "/tmp/out",
  "outputName": "shaft",
  "features": [{
    "kind": "revolve",
    "id": "shaft",
    "profile_points_2d": [[0,0],[10,0],[10,40],[0,40]],
    "axis_origin": [0,0,0],
    "axis_direction": [0,0,1],
    "angle_deg": 360
  }]
}' | reconstruct
```

Verbs that accept a JSON file path as argv (instead of stdin) work the same way — pass the `.json`
file as the sole positional argument.

## The `--serve` JSONL protocol

Any verb can be switched into a long-lived service with `--serve`. In this mode the verb reads
`{"args":[...]}` lines from stdin and writes exactly one JSON **envelope** per line to stdout:

```
{"error":"<msg>","exit":<int>,"ok":true|false,"stdout":"<captured>","stderr":"<captured>"}
```

Key properties:

- **One envelope per request line.** Blank lines are silently ignored.
- **Output is fully captured.** The subcommand's own stdout and stderr — including output from any
  child process the verb spawns (e.g. `swift build` invoked by `occtkit run`) — are redirected into
  the envelope via per-request FD redirection. They do not leak to the terminal.
- **`error` is present only when `ok` is false.** On success the field is omitted (keys are
  sorted, so `exit`/`ok`/`stdout`/`stderr` always appear).
- **EOF on stdin exits 0.** The server loop terminates cleanly; no teardown handshake needed.
- **Verbs throw rather than `exit()`**, so a single bad request returns an error envelope and the
  loop continues — it does not kill the server.

This is how **OCCTMCP** drives `occtkit`: it spawns one `occtkit <verb> --serve` process per verb
family and multiplexes requests over stdin/stdout.

### Example: `graph-validate --serve`

Feed two requests — one valid path, one that will fail:

```bash
printf '{"args":["good.brep"]}\n{"args":["missing.brep"]}\n' \
  | occtkit graph-validate --serve
```

Example output (one envelope per line):

```json
{"exit":0,"ok":true,"stderr":"","stdout":"graph-validate: OK (42 nodes, 0 warnings)\n"}
{"error":"file not found: missing.brep","exit":1,"ok":false,"stderr":"","stdout":""}
```

The `--serve` flag can appear anywhere in the args; `dispatch()` in `main.swift` strips it before
forwarding the remainder to the verb.

### Malformed request handling

If a request line is not valid JSON the server emits an error envelope and continues:

```bash
printf 'not json\n{"args":["body.brep"]}\n' \
  | occtkit graph-validate --serve
```

```json
{"error":"invalid request JSON: ...","exit":1,"ok":false,"stderr":"","stdout":""}
{"exit":0,"ok":true,"stderr":"","stdout":"graph-validate: OK (42 nodes, 0 warnings)\n"}
```

## Deprecated standalone targets

Each verb also existed as a standalone executable (`GraphValidate`, `OCCTRunner`, etc.). These are
**deprecated**: they print a notice to stderr on startup and will be removed in a future release.
Migrate to `occtkit <verb>` at your convenience.

---

For the full schema of every verb's flag-form and JSON-form inputs, see the
[Reference](../../reference/).
