#!/usr/bin/env python3
"""
STL -> 3MF packaging, and a tooth-thickness measurement that runs identically on
both sides so a difference in the numbers is a difference in the geometry.

Thickness method: cast a ray from each triangle centroid along the INWARD normal
and take the distance to the first forward hit on the mesh. On a tooth flank that
ray crosses to the opposite flank, so the distance is the tooth's local thickness.
This is the same quantity `occtkit check-thickness` computes on a B-Rep, and it is
what actually governs printability.
"""
import math
import re
import struct
import sys
import zipfile
from pathlib import Path

import numpy as np


# ─────────────────────────────── STL ────────────────────────────────
def load_stl(path):
    d = Path(path).read_bytes()
    if d[:5] == b"solid" and b"facet normal" in d[:2000]:
        v = np.array(
            re.findall(rb"vertex\s+([-\d.eE+]+)\s+([-\d.eE+]+)\s+([-\d.eE+]+)", d),
            dtype=np.float64,
        )
        return v.reshape(-1, 3, 3)
    n = struct.unpack("<I", d[80:84])[0]
    t = np.frombuffer(
        d[84 : 84 + n * 50],
        dtype=np.dtype([("n", "<3f4"), ("v", "<3f4", (3,)), ("a", "<u2")]),
        count=n,
    )
    return t["v"].astype(np.float64)


# ─────────────────────────────── 3MF ────────────────────────────────
CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>"""

RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>"""


def write_3mf(tris, out_path, name="model"):
    """Weld vertices and write a minimal conformant 3MF (millimetre units)."""
    flat = tris.reshape(-1, 3)
    # Weld on a 1e-6 mm grid so the 3MF carries a manifold index set, not soup.
    keys = np.round(flat / 1e-6).astype(np.int64)
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    verts = flat[first]
    faces = inverse.reshape(-1, 3)
    # Drop degenerate triangles created by welding.
    good = (faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])
    faces = faces[good]

    v_xml = "".join(
        f'<vertex x="{x:.6f}" y="{y:.6f}" z="{z:.6f}"/>' for x, y, z in verts
    )
    t_xml = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in faces)
    model = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" xml:lang="en-US" '
        'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">'
        f"<metadata name=\"Title\">{name}</metadata>"
        "<resources>"
        f'<object id="1" type="model"><mesh>'
        f"<vertices>{v_xml}</vertices><triangles>{t_xml}</triangles>"
        "</mesh></object></resources>"
        '<build><item objectid="1"/></build></model>'
    )
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", RELS)
        z.writestr("3D/3dmodel.model", model)
    return len(verts), len(faces)


# ──────────────────────── thickness by ray cast ─────────────────────
def ray_mesh_min_distance(origins, dirs, tris, eps=1e-3, chunk=64, facing=0.2):
    """
    Möller-Trumbore, vectorised over triangles, chunked over rays.

    Only EXIT hits count. STL normals point out of the material, so where the ray
    leaves the far side of the tooth the hit triangle's normal points along the ray
    (dot > 0). A ray grazing another triangle of the surface it started from hits a
    normal pointing back at it (dot ~ -1). Without this filter those grazing hits
    dominate the minimum and report thicknesses near zero on correct geometry.
    """
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    tn = np.cross(e1, e2)
    tn = tn / np.maximum(np.linalg.norm(tn, axis=1), 1e-300)[:, None]
    out = np.full(len(origins), np.inf)
    for s in range(0, len(origins), chunk):
        O = origins[s : s + chunk][:, None, :]
        D = dirs[s : s + chunk][:, None, :]
        P = np.cross(D, e2[None, :, :])
        det = np.einsum("ijk,jk->ij", P, e1)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        T = O - v0[None, :, :]
        u = np.einsum("ijk,ijk->ij", T, P) * inv
        Q = np.cross(T, e1[None, :, :])
        v = np.einsum("ijk,ijk->ij", D, Q) * inv
        t = np.einsum("ijk,jk->ij", Q, e2) * inv
        exiting = np.einsum("ijk,jk->ij", D, tn) > facing
        hit = ok & exiting & (u >= -1e-9) & (v >= -1e-9) & (u + v <= 1 + 1e-9) & (t > eps)
        t = np.where(hit, t, np.inf)
        out[s : s + chunk] = t.min(axis=1)
    return out


def tooth_thickness(path, min_radius, label):
    tris = load_stl(path)
    c = tris.mean(axis=1)
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    ln = np.linalg.norm(n, axis=1)
    keep = ln > 1e-12
    tris_v, c, n, ln = tris[keep], c[keep], n[keep], ln[keep]
    n = n / ln[:, None]

    r = np.hypot(c[:, 0], c[:, 1])
    # Tooth flanks only: out in the tooth band, and facing mostly sideways rather
    # than up/down, so the inward ray crosses the tooth rather than running along it.
    axial = np.abs(n[:, 2])
    sel = (r >= min_radius) & (axial < 0.5)
    if sel.sum() == 0:
        return None
    origins = c[sel] - n[sel] * 1e-4
    dirs = -n[sel]
    d = ray_mesh_min_distance(origins, dirs, tris_v)
    d = d[np.isfinite(d)]
    if d.size == 0:
        return None
    return dict(label=label, n=d.size, tris=len(tris_v),
                min=d.min(), p1=np.percentile(d, 1), p5=np.percentile(d, 5),
                median=np.median(d), mean=d.mean(), max=d.max())


if __name__ == "__main__":
    here = Path(__file__).parent
    jobs = [
        ("occt-pinion-7t.stl", 3.2, "OCCTSwift pinion 7t"),
        ("bosl2-pinion.stl", 3.2, "BOSL2     pinion 7t"),
        ("occt-gear-14t.stl", 8.6, "OCCTSwift gear 14t"),
        ("bosl2-gear.stl", 8.6, "BOSL2     gear 14t"),
    ]
    print(f"{'body':22s} {'tris':>7s} {'samples':>8s} {'min':>8s} {'p1':>8s} "
          f"{'p5':>8s} {'median':>8s}")
    print("-" * 74)
    for f, rmin, label in jobs:
        p = here / f
        if not p.exists():
            print(f"{label:22s} MISSING {f}")
            continue
        s = tooth_thickness(p, rmin, label)
        if s is None:
            print(f"{label:22s} no samples")
            continue
        print(f"{s['label']:22s} {s['tris']:7d} {s['n']:8d} {s['min']:8.3f} "
              f"{s['p1']:8.3f} {s['p5']:8.3f} {s['median']:8.3f}")

    print()
    for stem, name in (("occt-pinion-7t", "pinion-7t"), ("occt-gear-14t", "gear-14t")):
        src = here / f"{stem}.stl"
        if not src.exists():
            continue
        nv, nf = write_3mf(load_stl(src), here / f"{stem}.3mf", name=name)
        size = (here / f"{stem}.3mf").stat().st_size
        print(f"wrote {stem}.3mf  ({nv} verts, {nf} triangles, {size} bytes)")
