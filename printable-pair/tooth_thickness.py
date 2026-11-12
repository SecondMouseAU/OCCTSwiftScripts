#!/usr/bin/env python3
"""
Circumferential tooth thickness, measured identically on both sides.

"2 mm thick at the root" is a CIRCUMFERENTIAL dimension: the arc width of the
tooth where it meets the gear body. An inward-normal ray cast does not measure it
(on a tooth end face that ray runs lengthwise and returns the face width instead),
so this samples a circle of points at a given (radius, z), tests each for being
inside the solid, and measures the angular runs of material. Each run is one tooth;
its arc width is run_angle * radius.

Inside/outside is a parity test: cast one ray per point and count mesh crossings.
Odd is inside. The ray direction is deliberately off-axis so it does not run
parallel to the flat top, root or end faces, where grazing hits would corrupt the count.
"""
import sys
from pathlib import Path

import numpy as np

import meshtools as M

RAY = np.array([0.1357, 0.2891, 0.9476])
RAY = RAY / np.linalg.norm(RAY)


def crossings(points, tris, eps=1e-9):
    """Count forward ray-triangle crossings per point (Möller-Trumbore)."""
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    P = np.cross(RAY, e2)
    det = np.einsum("jk,jk->j", P, e1)
    ok = np.abs(det) > 1e-14
    inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
    out = np.zeros(len(points), dtype=np.int64)
    for s in range(0, len(points), 256):
        T = points[s : s + 256][:, None, :] - v0[None, :, :]
        u = np.einsum("ijk,jk->ij", T, P) * inv
        Q = np.cross(T, e1[None, :, :])
        v = (Q @ RAY) * inv
        t = np.einsum("ijk,jk->ij", Q, e2) * inv
        hit = ok[None, :] & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > eps)
        out[s : s + 256] = hit.sum(axis=1)
    return out


def runs_at(tris, radius, z, n_ang=1440):
    ang = np.linspace(0, 2 * np.pi, n_ang, endpoint=False)
    pts = np.stack([radius * np.cos(ang), radius * np.sin(ang), np.full(n_ang, z)], axis=1)
    inside = (crossings(pts, tris) % 2) == 1
    if inside.all():
        return 1.0, []
    if not inside.any():
        return 0.0, []
    # Rotate so index 0 starts outside, then collect contiguous inside runs.
    start = int(np.argmin(inside))
    rolled = np.roll(inside, -start)
    lens, cur = [], 0
    for b in rolled:
        if b:
            cur += 1
        elif cur:
            lens.append(cur)
            cur = 0
    if cur:
        lens.append(cur)
    step = 2 * np.pi / n_ang
    return inside.mean(), [L * step * radius for L in lens]


def profile(path, label, teeth, z_frac=(0.25, 0.5, 0.75)):
    tris = M.load_stl(path)
    v = tris.reshape(-1, 3)
    zmin, zmax = v[:, 2].min(), v[:, 2].max()
    rmax = np.hypot(v[:, 0], v[:, 1]).max()
    print(f"\n{label}   ({len(tris)} triangles, dia {2*rmax:.4f} mm)")
    print(f"    {'z':>7s} {'radius':>7s} {'occupancy':>10s} {'teeth':>6s} {'arc thickness (mm)':>20s}")
    results = []
    for zf in z_frac:
        z = zmin + (zmax - zmin) * zf
        # Walk outward until the section stops being solid: that radius is the root.
        found = None
        for r in np.arange(0.30 * rmax, 1.0 * rmax, 0.02 * rmax):
            occ, widths = runs_at(tris, r, z)
            if occ < 0.995 and len(widths) == teeth:
                found = (r, occ, widths)
                break
        if found is None:
            print(f"    {z:7.3f}       -- no clean {teeth}-tooth section")
            continue
        r, occ, widths = found
        w = np.array(widths)
        print(f"    {z:7.3f} {r:7.3f} {occ:10.3f} {len(widths):6d}   "
              f"min {w.min():.3f}  mean {w.mean():.3f}  max {w.max():.3f}")
        results.append(w.mean())
    return results


if __name__ == "__main__":
    here = Path(__file__).parent
    for f, lbl, t in (
        ("bosl2-pinion.stl", "BOSL2     pinion 7t", 7),
        ("occt-pinion-7t.stl", "OCCTSwift pinion 7t", 7),
        ("bosl2-gear.stl", "BOSL2     gear 14t", 14),
        ("occt-gear-14t.stl", "OCCTSwift gear 14t", 14),
    ):
        p = here / f
        if p.exists():
            profile(p, lbl, t)
        else:
            print(f"MISSING {f}")
