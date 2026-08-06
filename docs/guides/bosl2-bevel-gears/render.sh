#!/usr/bin/env bash
# render.sh: regenerate every figure and every measurement on the BOSL2 bevel gear page.
#
# Run from the repo root:
#   docs/guides/bosl2-bevel-gears/render.sh            # figures only
#   docs/guides/bosl2-bevel-gears/render.sh --compare  # figures plus the numeric comparison
#
# ── Matching the two cameras ──────────────────────────────────────────────────────────
# The two renderers use different fields of view, both vertical:
#
#   OpenSCAD                22.5 degrees   (measured, not assumed: a 20mm cube centred at the
#                                          origin viewed from (0,0,100) covers 336 of 600 px,
#                                          which puts tan(fov/2) at 0.1984)
#   occtkit render-preview  45.0 degrees   (OCCTSwiftViewport CameraState.fieldOfView default,
#                                          used by every perspective render)
#
# Moving one camera closer or further to compensate would change the perspective as well as
# the framing, so the two images would still not be comparable. Instead BOTH cameras sit at
# exactly the same eye point, looking at the same target with the same up vector, and the
# occtkit frame is cropped to the central 22.5 degrees afterwards:
#
#   crop = tan(11.25 deg) / tan(22.5 deg) = 0.4802158
#
# Cropping a perspective image to a narrower field is exactly what a narrower lens from the
# same eye point would have produced, so after the crop the two projections are identical and
# any difference in the pair is a difference in the geometry.
#
# Both sides render at 2400x1800 and land at 800x600, so both get the same supersampling.
#
# ── One workaround ────────────────────────────────────────────────────────────────────
# `occtkit render-preview --camera-position P --camera-target T` puts the camera at the
# REFLECTION of P through T, so the scene is rendered from the opposite side. Verified on a
# single bevel gear on the +Z axis: `--camera-position 0,0,300` shows the wide back face,
# `--camera-position 0,0,-300` shows the narrow flat top. The named presets (`--camera iso`
# and friends) are unaffected, since they derive the position internally. Rather than touch
# a pinned dependency or the verb, this script reflects the eye point itself and passes
# 2*T - P, which lands the camera where the comment above says it is.
#
# ── What is NOT matched, and cannot be ────────────────────────────────────────────────
# Material, lighting and edge shading. OpenSCAD's Tomorrow colour scheme and
# OCCTSwiftViewport's shaded mode are different renderers. The OCCT side uses
# `shaded-with-edges`, because in plain `shaded` the tooth flanks of a part this size have
# too little tonal contrast to read at 800x600. The background is matched by hand (#f8f8f8)
# and the body colour is overridden in the .scad files, because `occtkit render-preview`
# paints every input body one fixed colour and has no flag to change it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$HERE}"
WORK="${WORK:-${TMPDIR:-/tmp}/bosl2-bevel-gears}"
OCCTKIT="${OCCTKIT:-swift run occtkit}"
COMPARE=0
[ "${1:-}" = "--compare" ] && COMPARE=1

BIG_W=2400
BIG_H=1800
CROP=0.4802158
BG="#f8f8f8"

mkdir -p "$WORK"

# example : eye : target : teeth-and-axis per body (for --align)
render_one() {
    local name="$1" eye="$2" target="$3"; shift 3

    echo "== $name: BOSL2 reference =="
    openscad -o "$WORK/$name-bosl2-big.png" --imgsize=$BIG_W,$BIG_H --projection=p \
        --colorscheme=Tomorrow --camera="$eye,$target" "$HERE/$name.scad"
    openscad -o "$WORK/$name-bosl2.stl" "$HERE/$name.scad"

    echo "== $name: OCCTSwift =="
    $OCCTKIT run "$HERE/$name.swift" --format brep --output "$WORK/$name"
    local breps=("$WORK/$name"/body-*.brep)
    # Reflect the eye point through the target, see the workaround note at the top.
    local reflected
    reflected="$(python3 -c "
import sys
e = [float(v) for v in sys.argv[1].split(',')]
t = [float(v) for v in sys.argv[2].split(',')]
print(','.join(f'{2*ti-ei:.4f}' for ei, ti in zip(e, t)))" "$eye" "$target")"
    $OCCTKIT render-preview "${breps[@]}" --output "$WORK/$name-occt-big.png" \
        --camera-position "$reflected" --camera-target "$target" --camera-up 0,0,1 \
        --width $BIG_W --height $BIG_H --display-mode shaded-with-edges --background "$BG"

    python3 - "$WORK/$name-bosl2-big.png" "$OUT/$name-bosl2.png" \
               "$WORK/$name-occt-big.png" "$OUT/$name-occt.png" "$CROP" <<'PY'
import sys
from PIL import Image
scad_in, scad_out, occt_in, occt_out, crop = sys.argv[1:6]
crop = float(crop)
Image.open(scad_in).convert("RGB").resize((800, 600), Image.LANCZOS).save(scad_out)
im = Image.open(occt_in).convert("RGB")
w, h = im.size
bw, bh = w * crop, h * crop
box = ((w - bw) / 2, (h - bh) / 2, (w + bw) / 2, (h + bh) / 2)
im.resize((800, 600), Image.LANCZOS, box=box).save(occt_out)
print(f"  wrote {scad_out} and {occt_out}")
PY

    if [ "$COMPARE" = 1 ]; then
        local stls=()
        for b in "${breps[@]}"; do
            local s="$WORK/$name-occt-$(basename "$b" .brep).stl"
            $OCCTKIT mesh "$b" --output "$s" --linear-deflection 0.005 \
                --angular-deflection 0.1 --no-return-geometry > /dev/null
            stls+=("$s")
        done
        echo "== $name: numeric comparison =="
        local align=()
        for spec in "$@"; do align+=(--align "$spec"); done
        python3 "$HERE/compare.py" --bosl2 "$WORK/$name-bosl2.stl" --occt "${stls[@]}" \
            "${align[@]}" --deviation --sample 3000 --probe 300 | tee "$WORK/$name-compare.txt"
    fi
}

# Eye points: target is the union bounding box centre, and the eye sits far enough back that
# the part fills about 85% of the 22.5 degree frame.
render_one example1 "150.803,-150.803,137.679" "0.000,0.000,4.469"   36:0,0,1
render_one example2 "174.781,-76.358,96.632" "0.000,0.108,-1.682"  16:0,-1,0 28:0,0,1
render_one example3 "171.139,-74.772,94.580" "0.000,0.101,-1.686"  14:0,-1,0 28:0,0,1

echo "done: figures in $OUT, working files in $WORK"
