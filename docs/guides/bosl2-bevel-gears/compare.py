#!/usr/bin/env python3
"""Numeric comparison between the BOSL2 reference meshes and the OCCTSwift solids.

Both sides are reduced to a triangle mesh first and then measured by the SAME code, so a
difference in the numbers is a difference in the geometry rather than in the measurement.

    openscad -o /tmp/ex2-bosl2.stl docs/guides/bosl2-bevel-gears/example2.scad
    swift run occtkit run docs/guides/bosl2-bevel-gears/example2.swift \
        --format brep --output /tmp/ex2
    swift run occtkit mesh /tmp/ex2/body-0.brep --output /tmp/ex2-occt-0.stl \
        --linear-deflection 0.005 --angular-deflection 0.1 --no-return-geometry
    swift run occtkit mesh /tmp/ex2/body-1.brep --output /tmp/ex2-occt-1.stl \
        --linear-deflection 0.005 --angular-deflection 0.1 --no-return-geometry

    python3 docs/guides/bosl2-bevel-gears/compare.py \
        --bosl2 /tmp/ex2-bosl2.stl --occt /tmp/ex2-occt-0.stl /tmp/ex2-occt-1.stl

Three measurements, in increasing order of how much they can catch:

  volume     signed-tetrahedron sum over every triangle, so the exact volume enclosed by each
             mesh. Cheap, and it does catch a systematically over-deep tooth valley or a
             missing backing. It cannot catch a gear built with the wrong hand or the wrong
             spiral: a mirrored gear has exactly the same volume.

  bbox       per-axis min/max over all vertices. Catches a misplaced or wrongly scaled body.
             Also blind to handedness.

  deviation  distance from every vertex of one mesh to the nearest point on the other mesh's
             SURFACE (not its nearest vertex). This is the measurement that can fail: it sees
             placement, tooth phase, profile shape, the lengthwise trace and faceting all at
             once, so a small number here is a much stronger statement than a matching volume.

             One degree of freedom is fitted out first. Which tooth sits at angle zero is a
             convention, not geometry: this port centres a tooth SPACE where BOSL2 centres a
             TOOTH, so a single gear compared as built is half a tooth pitch out of phase. So
             `--align` rotates each OCCT body about its own axis, scans a whole tooth pitch,
             and reports the residual at the best angle along with the angle itself. A gear of
             the wrong hand cannot be rescued by any rotation about its axis, because the
             spiral would still run the other way, so the residual stays large. That is what
             makes this check able to fail.
"""

import argparse
import json
import math
import re
import struct
import sys

import numpy as np


# ---------------------------------------------------------------- STL loading

def load_stl(path):
    """Return an (n, 3, 3) float64 array of triangles. Handles ASCII and binary STL."""
    with open(path, "rb") as fh:
        head = fh.read(5)
        fh.seek(0)
        if head == b"solid":
            text = fh.read().decode("utf-8", "replace")
            if "facet" in text and "vertex" in text:
                verts = re.findall(r"vertex\s+(\S+)\s+(\S+)\s+(\S+)", text)
                if len(verts) % 3:
                    raise ValueError(f"{path}: vertex count {len(verts)} is not a multiple of 3")
                return np.array(verts, dtype=np.float64).reshape(-1, 3, 3)
        fh.seek(80)
        (count,) = struct.unpack("<I", fh.read(4))
        data = np.frombuffer(fh.read(count * 50), dtype=np.uint8)
        if data.size != count * 50:
            raise ValueError(f"{path}: truncated binary STL")
        data = data.reshape(count, 50)
        floats = data[:, 12:48].copy().view(np.float32).reshape(count, 3, 3)
        return floats.astype(np.float64)


def mesh_volume(tris):
    """Volume enclosed by a closed triangle mesh (divergence theorem)."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    return float(abs(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6.0)


def mesh_bbox(tris):
    pts = tris.reshape(-1, 3)
    return pts.min(axis=0), pts.max(axis=0)


# ---------------------------------------------------- point to surface distance

def _point_triangle_distance(p, tris):
    """Distance from one point to each of `tris` (m, 3, 3). Vectorised over triangles."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    ab, ac, ap = b - a, c - a, p - a

    d1 = np.einsum("ij,ij->i", ab, ap)
    d2 = np.einsum("ij,ij->i", ac, ap)
    bp = p - b
    d3 = np.einsum("ij,ij->i", ab, bp)
    d4 = np.einsum("ij,ij->i", ac, bp)
    cp = p - c
    d5 = np.einsum("ij,ij->i", ab, cp)
    d6 = np.einsum("ij,ij->i", ac, cp)

    vc = d1 * d4 - d3 * d2
    vb = d5 * d2 - d1 * d6
    va = d3 * d6 - d5 * d4
    denom = va + vb + vc

    closest = np.empty_like(a)

    # vertex regions
    m = (d1 <= 0) & (d2 <= 0)
    closest[m] = a[m]
    m2 = (~m) & (d3 >= 0) & (d4 <= d3)
    closest[m2] = b[m2]
    done = m | m2
    m3 = (~done) & (d6 >= 0) & (d5 <= d6)
    closest[m3] = c[m3]
    done |= m3

    # edge regions
    with np.errstate(divide="ignore", invalid="ignore"):
        m4 = (~done) & (vc <= 0) & (d1 >= 0) & (d3 <= 0)
        v = np.where(m4, d1 / np.where(d1 - d3 == 0, 1.0, d1 - d3), 0.0)
        closest[m4] = a[m4] + v[m4, None] * ab[m4]
        done |= m4

        m5 = (~done) & (vb <= 0) & (d2 >= 0) & (d6 <= 0)
        w = np.where(m5, d2 / np.where(d2 - d6 == 0, 1.0, d2 - d6), 0.0)
        closest[m5] = a[m5] + w[m5, None] * ac[m5]
        done |= m5

        m6 = (~done) & (va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0)
        den6 = (d4 - d3) + (d5 - d6)
        w6 = np.where(m6, (d4 - d3) / np.where(den6 == 0, 1.0, den6), 0.0)
        closest[m6] = b[m6] + w6[m6, None] * (c[m6] - b[m6])
        done |= m6

        # interior
        rest = ~done
        dn = np.where(denom == 0, 1.0, denom)
        vv = vb / dn
        ww = vc / dn
        closest[rest] = a[rest] + vv[rest, None] * ab[rest] + ww[rest, None] * ac[rest]

    return np.linalg.norm(closest - p, axis=1)


class TriangleGrid:
    """Uniform spatial hash over triangle AABBs, enough to make nearest-surface tractable."""

    def __init__(self, tris, target_per_cell=4.0):
        self.tris = tris
        lo, hi = mesh_bbox(tris)
        self.lo = lo
        extent = np.maximum(hi - lo, 1e-9)
        volume = float(np.prod(extent))
        self.cell = max((volume * target_per_cell / max(len(tris), 1)) ** (1 / 3), 1e-6)
        self.dims = np.maximum((extent / self.cell).astype(int) + 1, 1)

        tlo = np.floor((tris.min(axis=1) - lo) / self.cell).astype(int)
        thi = np.floor((tris.max(axis=1) - lo) / self.cell).astype(int)
        tlo = np.clip(tlo, 0, self.dims - 1)
        thi = np.clip(thi, 0, self.dims - 1)

        buckets = {}
        for idx in range(len(tris)):
            for i in range(tlo[idx, 0], thi[idx, 0] + 1):
                for j in range(tlo[idx, 1], thi[idx, 1] + 1):
                    for k in range(tlo[idx, 2], thi[idx, 2] + 1):
                        buckets.setdefault((i, j, k), []).append(idx)
        self.buckets = {key: np.array(v) for key, v in buckets.items()}

    def nearest_distance(self, point, max_rings=12):
        base = np.clip(np.floor((point - self.lo) / self.cell).astype(int), 0, self.dims - 1)
        seen = []
        best = math.inf
        for ring in range(max_rings):
            found = []
            for i in range(base[0] - ring, base[0] + ring + 1):
                for j in range(base[1] - ring, base[1] + ring + 1):
                    for k in range(base[2] - ring, base[2] + ring + 1):
                        if ring and max(abs(i - base[0]), abs(j - base[1]), abs(k - base[2])) != ring:
                            continue
                        b = self.buckets.get((i, j, k))
                        if b is not None:
                            found.append(b)
            if found:
                seen.append(np.concatenate(found))
                cand = np.unique(np.concatenate(seen))
                best = float(_point_triangle_distance(point, self.tris[cand]).min())
                # A triangle outside the searched rings cannot be closer than the gap to the
                # ring boundary, so stop as soon as the current best is inside that gap.
                if best <= ring * self.cell:
                    return best
        return best


def deviation(points, grid, sample=None, seed=0):
    if sample is not None and len(points) > sample:
        rng = np.random.default_rng(seed)
        points = points[rng.choice(len(points), sample, replace=False)]
    d = np.array([grid.nearest_distance(p) for p in points])
    return {
        "samples": int(len(d)),
        "mean_mm": float(d.mean()),
        "p50_mm": float(np.percentile(d, 50)),
        "p95_mm": float(np.percentile(d, 95)),
        "p99_mm": float(np.percentile(d, 99)),
        "max_mm": float(d.max()),
    }


def rotate_about(tris, axis, degrees):
    """Rotate triangles about the line through the origin along `axis`."""
    k = np.asarray(axis, dtype=np.float64)
    k = k / np.linalg.norm(k)
    t = math.radians(degrees)
    c, s_ = math.cos(t), math.sin(t)
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    R = np.eye(3) * c + s_ * K + (1 - c) * np.outer(k, k)
    return tris @ R.T


def best_alignment(tris, grid, axis, teeth, probe=600, seed=0):
    """Scan one tooth pitch of rotation about `axis` for the smallest mean deviation.

    Coarse scan at 1/48 of a pitch, then a local refinement, using a fixed random subset of
    the vertices so every candidate angle is scored on the same points.
    """
    pts = np.unique(tris.reshape(-1, 3), axis=0)
    rng = np.random.default_rng(seed)
    if len(pts) > probe:
        pts = pts[rng.choice(len(pts), probe, replace=False)]
    pitch = 360.0 / teeth

    def score(angle):
        rp = rotate_about(pts.reshape(-1, 1, 3), axis, angle).reshape(-1, 3)
        return float(np.mean([grid.nearest_distance(p) for p in rp]))

    coarse = [(a, score(a)) for a in np.linspace(0.0, pitch, 48, endpoint=False)]
    best_a, best_s = min(coarse, key=lambda x: x[1])
    step = pitch / 48
    for _ in range(4):
        step /= 4
        for a in (best_a - step, best_a + step):
            v = score(a)
            if v < best_s:
                best_a, best_s = a, v
    return {"angle_deg": float(best_a), "mean_mm": best_s,
            "scan": [float(v) for _, v in coarse]}


# ----------------------------------------------------------------------- main

def describe(tris, label):
    lo, hi = mesh_bbox(tris)
    return {
        "label": label,
        "triangles": int(len(tris)),
        "volume_mm3": mesh_volume(tris),
        "bbox_min": [float(v) for v in lo],
        "bbox_max": [float(v) for v in hi],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bosl2", required=True, help="STL exported from the .scad reference")
    ap.add_argument("--occt", required=True, nargs="+",
                    help="one STL per body emitted by the .swift example")
    ap.add_argument("--deviation", action="store_true",
                    help="also measure vertex-to-surface deviation both ways (slow)")
    ap.add_argument("--align", metavar="TEETH:AX,AY,AZ", action="append", default=[],
                    help="one per --occt body: its tooth count and its own axis direction, "
                         "used to scan out the tooth-phase convention before measuring")
    ap.add_argument("--sample", type=int, default=8000,
                    help="cap on deviation query points per direction (default 8000)")
    ap.add_argument("--probe", type=int, default=600,
                    help="query points used during the alignment scan (default 600)")
    ap.add_argument("--json", action="store_true", help="emit the raw report as JSON")
    args = ap.parse_args()

    bosl2 = load_stl(args.bosl2)
    occt = [load_stl(p) for p in args.occt]
    occt_all = np.concatenate(occt, axis=0)

    report = {"bosl2": describe(bosl2, args.bosl2),
              "occt_bodies": [describe(t, p) for p, t in zip(args.occt, occt)]}

    total = sum(b["volume_mm3"] for b in report["occt_bodies"])
    lo = np.min([b["bbox_min"] for b in report["occt_bodies"]], axis=0)
    hi = np.max([b["bbox_max"] for b in report["occt_bodies"]], axis=0)
    report["occt_total"] = {"volume_mm3": total,
                            "bbox_min": [float(v) for v in lo],
                            "bbox_max": [float(v) for v in hi]}
    bv = report["bosl2"]["volume_mm3"]
    report["volume_delta_pct"] = (total - bv) / bv * 100.0
    report["bbox_delta_mm"] = {
        "min": [float(a - b) for a, b in zip(lo, report["bosl2"]["bbox_min"])],
        "max": [float(a - b) for a, b in zip(hi, report["bosl2"]["bbox_max"])],
    }

    if args.deviation:
        bosl2_grid = TriangleGrid(bosl2)
        report["deviation"] = []
        aligned = []
        for i, (path, tris) in enumerate(zip(args.occt, occt)):
            spec = args.align[i] if i < len(args.align) else None
            if spec is None:
                raise SystemExit("--deviation needs one --align TEETH:AX,AY,AZ per --occt body")
            teeth_s, axis_s = spec.split(":")
            teeth = int(teeth_s)
            axis = np.array([float(v) for v in axis_s.split(",")])
            best = best_alignment(tris, bosl2_grid, axis, teeth, args.probe)
            rotated = rotate_about(tris, axis, best["angle_deg"])
            aligned.append(rotated)
            d = deviation(np.unique(rotated.reshape(-1, 3), axis=0), bosl2_grid, args.sample)
            d["label"] = path
            d["teeth"] = teeth
            d["best_angle_deg"] = best["angle_deg"]
            d["tooth_pitch_deg"] = 360.0 / teeth
            d["scan_mean_mm"] = best["scan"]
            report["deviation"].append(d)
        occt_grid = TriangleGrid(np.concatenate(aligned, axis=0))
        report["deviation_reverse"] = deviation(
            np.unique(bosl2.reshape(-1, 3), axis=0), occt_grid, args.sample)

    if args.json:
        json.dump(report, sys.stdout, indent=2)
        print()
        return

    def fmt(v):
        return "[" + ", ".join(f"{x:.4f}" for x in v) + "]"

    b = report["bosl2"]
    print(f"BOSL2 mesh   {args.bosl2}")
    print(f"  triangles {b['triangles']}   volume {b['volume_mm3']:.4f} mm3")
    print(f"  bbox min {fmt(b['bbox_min'])}  max {fmt(b['bbox_max'])}")
    for body in report["occt_bodies"]:
        print(f"OCCT body    {body['label']}")
        print(f"  triangles {body['triangles']}   volume {body['volume_mm3']:.4f} mm3")
        print(f"  bbox min {fmt(body['bbox_min'])}  max {fmt(body['bbox_max'])}")
    print(f"OCCT total   volume {total:.4f} mm3   delta vs BOSL2 {report['volume_delta_pct']:+.3f}%")
    print(f"  bbox min {fmt(report['occt_total']['bbox_min'])}  max {fmt(report['occt_total']['bbox_max'])}")
    print(f"  bbox delta min {fmt(report['bbox_delta_mm']['min'])}  max {fmt(report['bbox_delta_mm']['max'])}")
    for d in report.get("deviation", []):
        frac = d["best_angle_deg"] / d["tooth_pitch_deg"]
        print(f"Deviation    {d['label']} vertices -> BOSL2 surface ({d['samples']} points)")
        print(f"  best alignment {d['best_angle_deg']:+.4f} deg about its own axis "
              f"= {frac:.4f} of the {d['tooth_pitch_deg']:.4f} deg tooth pitch")
        print(f"  scan mean deviation over a whole pitch: best {min(d['scan_mean_mm']):.4f}  "
              f"worst {max(d['scan_mean_mm']):.4f} mm")
        print(f"  mean {d['mean_mm']:.4f}  median {d['p50_mm']:.4f}  p95 {d['p95_mm']:.4f}  "
              f"p99 {d['p99_mm']:.4f}  max {d['max_mm']:.4f}  (mm)")
    if "deviation_reverse" in report:
        d = report["deviation_reverse"]
        print(f"Deviation    BOSL2 vertices -> aligned OCCT surface ({d['samples']} points)")
        print(f"  mean {d['mean_mm']:.4f}  median {d['p50_mm']:.4f}  p95 {d['p95_mm']:.4f}  "
              f"p99 {d['p99_mm']:.4f}  max {d['max_mm']:.4f}  (mm)")


if __name__ == "__main__":
    main()
