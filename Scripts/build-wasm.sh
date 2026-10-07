#!/usr/bin/env bash
# build-wasm.sh: build occtkit for wasm32-unknown-wasip1 (the verbs that can run on WASI).
#
# The WASI build leaves out run, render-preview, graph-ml, graph-query and simplify-mesh, and has
# no --serve; see the OCCTSWIFT_WASI block at the end of Package.swift. Recipe and pins follow
# OCCTSwift's docs/guides/wasm-consumer-setup.md.
#
# Needs, before you run it:
#   - the swift.org Swift 6.4.0 toolchain on PATH (Xcode's has no wasm-ld)
#   - its wasm SDK:  swift sdk install <swift-6.4.0-RELEASE_wasm.artifactbundle.tar.gz>
#   - a wasi-sdk 34.0 unpacked somewhere, named by WASI_SDK_PREFIX
#
# Usage:
#   WASI_SDK_PREFIX=/opt/wasi-sdk-34.0-x86_64-linux Scripts/build-wasm.sh
#
# Output: .build/out/Products/Release-webassembly-wasm32/occtkit.wasm
#
# Run it with node, preopening the directories the verbs touch, at absolute paths:
#   OCCTMCP_OCCTKIT_WASM=<occtkit.wasm> node <OCCTMCP>/dist/wasi-run.js <occtkit.wasm> metrics /abs/a.brep
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

: "${WASI_SDK_PREFIX:?set WASI_SDK_PREFIX to an unpacked wasi-sdk 34.0}"
SDK_ID="${SWIFT_WASM_SDK_ID:-swift-6.4.0-RELEASE_wasm}"
TOOLSET="${TOOLSET:-.build/wasi-toolset.json}"

export OCCTSWIFT_WASI=1

# Resolving under OCCTSWIFT_WASI drops every pin but OCCTSwift's. Put the committed lockfile back on
# exit so a build never leaves lockfile churn in the tree.
RESOLVED_BACKUP="$(mktemp)"
cp Package.resolved "$RESOLVED_BACKUP"
trap 'cp "$RESOLVED_BACKUP" Package.resolved; rm -f "$RESOLVED_BACKUP"' EXIT

swift package resolve
OCCTSWIFT="$(pwd)/.build/checkouts/OCCTSwift"

# The prebuilt, checksum-verified wasm kernel (about 38 MB); a no-op when it is already unpacked.
(cd "$OCCTSWIFT" && Scripts/fetch-occt-wasm.sh)

command -v python3 >/dev/null || { echo "build-wasm: python3 not found on PATH" >&2; exit 1; }
[[ -f "$OCCTSWIFT/Scripts/make-wasi-toolset.py" ]] \
    || { echo "build-wasm: $OCCTSWIFT/Scripts/make-wasi-toolset.py not found" >&2; exit 1; }
python3 "$OCCTSWIFT/Scripts/make-wasi-toolset.py" --wasi-sdk "$WASI_SDK_PREFIX" -o "$TOOLSET"

swift build --toolset "$TOOLSET" --swift-sdk "$SDK_ID" \
    --triple wasm32-unknown-wasip1 -c release --product occtkit

echo "built: $(pwd)/.build/out/Products/Release-webassembly-wasm32/occtkit.wasm"
