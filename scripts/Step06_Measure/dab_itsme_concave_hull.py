#!/usr/bin/env python3
"""
dab_itsme_concave_hull.py -- Python twin of dab_itsme_concave_hull.R: the ITSMe
diameter_slice_pc() method, re-implemented in Python.

ITSMe is an R package (Terryn et al., github.com/lmterryn/ITSMe) with no
Python equivalent, so this file is a PORT of what dab_itsme_concave_hull.R gets
from ITSMe 2.0.0, written independently from the published source, not a call
into R. The two are cross-checked at the results stage like the other
Python/R twins (compare_hull_methods.R), and any difference between them is a
porting question to look into, not a method difference. Added 2026-09-30 (DJ).

What diameter_slice_pc() does, and this file repeats step for step:
  1. cut a band of +/- thickness/2 around the height (ITSMe measures height
     from the lowest point of the cloud, so the band limits are computed the
     same way: lowest_point + (height - lowest_point) -/+ thickness/2),
  2. drop every point whose nearest neighbour is more than 5 cm away,
  3. fit a circle: centre by L-BFGS-B minimisation of the spread of the
     point-to-centre distances, radius = their MEDIAN (how = "median"), and a
     radius over 1.5 m is rejected as a failed fit,
  4. three quality checks on that circle: arc coverage (18 degree sectors with
     a point within 5 cm of the circle), inner circle empty, all points in the
     +/- 5 cm donut,
  5. the "functional" diameter: a CONCAVE hull of the unique band points
     (mapbox concaveman, concavity 4, the algorithm ITSMe calls through the R
     concaveman package), and the diameter of the circle with the same AREA
     as that hull. That functional diameter is what goes to the sheet.

concaveman is ported from the JavaScript the R package runs (concaveman
1.2.0, js/concaveman-bundle.js), including two details that change results:
the points are handed to it rounded to 4 decimal places (jsonlite's default
digits; 0.1 mm here), and its orientation test falls back to exact
arithmetic near ties. The R-tree index the JS uses only speeds up the
nearest-point search; this port uses a KD-tree for the same search, which
returns the same candidate. The circle fit uses scipy's L-BFGS-B with R
optim()'s defaults (central-difference gradient, step 1e-3, factr 1e7,
lmm 5, maxit 100), so the fitted centre can differ from R's by optimiser
round-off, far below a millimetre.

Incomplete scans: as in the R version, where an arc of the ring is missing
the concave hull cuts inward into the gap and underestimates. Read a low
value against the slice's MaxEdgeFrac before treating it as real.

USAGE (clouds are Y-up -> --up-axis y, as in the R version):
    python dab_itsme_concave_hull.py <slice-or-section.ply> --height-z 2.31 --up-axis y \\
        [--tree-id 1234] [--thickness 0.06] [--out results/dab_itsme_py.csv]
    python dab_itsme_concave_hull.py --from-sheet --up-axis y [--out ...]
"""

from __future__ import annotations
import argparse
import math
import os
import sys
from collections import deque
from fractions import Fraction

# =============================================================================
# CONFIG -- edit these for your own dataset before running with --from-sheet.
# Ignored otherwise (single-file CLI usage above is unaffected). Same values as
# dab_itsme_concave_hull.R's CONFIG, except OUTPUT_COL names the Python column.
# See scripts/sheet_batch.py, which these values get handed to.
# =============================================================================
SHEET_PATH = "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx"  # the working sheet; Tree_Tag matches the .ply file names
SHEET_NAME = 0                        # tab name (string) or 0-based index
TREE_ID_COL = "Tree_Tag"              # column holding each tree's ID
HEIGHT_COL = "Y_value_Dendrometer"    # column holding the picked cut height (m); swap to
                                      # Y_value_TopFlag / Y_value_LowerFlag / Y_value_PaintMarker for those sites
OUTPUT_COL = "Dendrometer_DabItsme_ConcaveHull_pythonScript_Diameter_mm"  # column the diameter (mm) is written into
PLY_FOLDER = "C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"  # step 5 output: polished slices, <tag>__<Site>.ply
PLY_FILENAME_PATTERN = "{tree_id}__{site}.ply"   # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL = "Dendrometer"            # substituted into {site} in the pattern

import numpy as np

try:
    from plyfile import PlyData
except ImportError:
    sys.exit("Missing dependency: pip install plyfile  (see requirements.txt)")
try:
    from scipy.optimize import minimize
    from scipy.spatial import cKDTree
except ImportError:
    sys.exit("Missing dependency: pip install scipy  (see requirements.txt)")


# ----------------------------------------------------------------------------- IO
def load_xyz(path: str) -> np.ndarray:
    """Nx3 array of XYZ from a PLY file."""
    v = PlyData.read(path)["vertex"]
    return np.c_[np.asarray(v["x"]), np.asarray(v["y"]), np.asarray(v["z"])].astype(float)


# ------------------------------------------------------------- concaveman (port)
_EPSILON = 1.1102230246251565e-16
_ERRBOUND3 = (3.0 + 16.0 * _EPSILON) * _EPSILON


def _orient(a, b, c) -> float:
    """robust-orientation's orientation3: the float determinant, with an exact
    fallback when it is too close to zero to trust. Only its sign is used."""
    l = (a[1] - c[1]) * (b[0] - c[0])
    r = (a[0] - c[0]) * (b[1] - c[1])
    det = l - r
    if l > 0:
        if r <= 0:
            return det
        s = l + r
    elif l < 0:
        if r >= 0:
            return det
        s = -(l + r)
    else:
        return det
    tol = _ERRBOUND3 * s
    if det >= tol or det <= -tol:
        return det
    ax, ay, bx, by, cx, cy = (Fraction(float(v)) for v in (a[0], a[1], b[0], b[1], c[0], c[1]))
    exact = (ay - cy) * (bx - cx) - (ax - cx) * (by - cy)
    return (exact > 0) - (exact < 0)


def _points_in_quad(P: np.ndarray, quad: np.ndarray) -> np.ndarray:
    """point-in-polygon's ray casting (pnpoly), vectorised over P for a 4-gon."""
    x, y = P[:, 0], P[:, 1]
    inside = np.zeros(len(P), dtype=bool)
    j = len(quad) - 1
    with np.errstate(divide="ignore", invalid="ignore"):
        for i in range(len(quad)):
            xi, yi = quad[i]
            xj, yj = quad[j]
            crosses = (yi > y) != (yj > y)
            xint = (xj - xi) * (y - yi) / (yj - yi) + xi
            inside ^= crosses & (x < xint)
            j = i
    return inside


def _monotone_hull(P: np.ndarray, idx: list[int]) -> list[int]:
    """monotone-convex-hull-2d on the points P[idx]; returns positions into idx."""
    n = len(idx)
    if n < 3:
        if n == 2 and P[idx[0], 0] == P[idx[1], 0] and P[idx[0], 1] == P[idx[1], 1]:
            return [0]
        return list(range(n))
    order = sorted(range(n), key=lambda k: (P[idx[k], 0], P[idx[k], 1]))   # stable, like V8's sort
    lower, upper = [order[0], order[1]], [order[0], order[1]]
    for k in order[2:]:
        p = P[idx[k]]
        while len(lower) > 1 and _orient(P[idx[lower[-2]]], P[idx[lower[-1]]], p) <= 0:
            lower.pop()
        lower.append(k)
        while len(upper) > 1 and _orient(P[idx[upper[-2]]], P[idx[upper[-1]]], p) >= 0:
            upper.pop()
        upper.append(k)
    return lower + upper[-2:0:-1]


def _fast_convex_hull(P: np.ndarray) -> list[int]:
    """concaveman's fastConvexHull: cull points inside the quadrilateral of the
    4 extreme points, then the monotone-chain hull. Returns point indices."""
    left, top = int(np.argmin(P[:, 0])), int(np.argmin(P[:, 1]))     # first occurrence, as in the JS loop
    right, bottom = int(np.argmax(P[:, 0])), int(np.argmax(P[:, 1]))
    cull = [left, top, right, bottom]
    outside = np.nonzero(~_points_in_quad(P, P[cull]))[0].tolist()
    filtered = cull + outside
    return [filtered[k] for k in _monotone_hull(P, filtered)]


def _sq_seg_dist(px, py, p1, p2):
    """concaveman's sqSegDist, vectorised over the points (px, py)."""
    x, y = p1[0], p1[1]
    dx, dy = p2[0] - x, p2[1] - y
    qx = np.full_like(px, x)
    qy = np.full_like(py, y)
    if dx != 0 or dy != 0:
        t = ((px - x) * dx + (py - y) * dy) / (dx * dx + dy * dy)
        far = t > 1
        mid = (t > 0) & ~far
        qx = np.where(far, p2[0], np.where(mid, x + dx * t, x))
        qy = np.where(far, p2[1], np.where(mid, y + dy * t, y))
    ex, ey = px - qx, py - qy
    return ex * ex + ey * ey


def _sq_dist(p1, p2) -> float:
    dx, dy = p1[0] - p2[0], p1[1] - p2[1]
    return dx * dx + dy * dy


def concaveman(P: np.ndarray, concavity: float = 2.0, length_threshold: float = 0.0) -> np.ndarray:
    """Port of mapbox concaveman (as bundled in the R concaveman package 1.2.0).
    P: Nx2 array. Returns the closed hull ring as an Mx2 array (first point repeated)."""
    concavity = max(0.0, concavity)
    hull = _fast_convex_hull(P)
    kd = cKDTree(P)
    used = np.zeros(len(P), dtype=bool)      # points removed from the JS R-tree

    # doubly linked list of hull nodes; each node's edge runs from it to its next
    cap = len(P) + 8
    node_p = np.empty(cap, dtype=np.int64)
    prv = np.empty(cap, dtype=np.int64)
    nxt = np.empty(cap, dtype=np.int64)
    bb = np.empty((cap, 4))                 # minX, minY, maxX, maxY of each node's edge
    count = 0

    def insert_node(p: int, prev: int | None) -> int:
        nonlocal count
        k = count
        count += 1
        node_p[k] = p
        if prev is None:
            prv[k] = nxt[k] = k
        else:
            nxt[k] = nxt[prev]
            prv[k] = prev
            prv[nxt[prev]] = k
            nxt[prev] = k
        return k

    def update_bbox(k: int) -> None:
        a, b = P[node_p[k]], P[node_p[nxt[k]]]
        bb[k] = (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))

    queue: deque[int] = deque()
    last = None
    for p in hull:
        used[p] = True
        last = insert_node(p, last)
        queue.append(last)
    for k in list(queue):
        update_bbox(k)

    def no_intersections(ia: int, ib: int) -> bool:
        a, b = P[ia], P[ib]
        qx0, qy0, qx1, qy1 = min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])
        box = bb[:count]
        hits = np.nonzero((box[:, 0] <= qx1) & (box[:, 1] <= qy1) & (box[:, 2] >= qx0) & (box[:, 3] >= qy0))[0]
        for e in hits:
            i1, i2 = node_p[e], node_p[nxt[e]]
            if i1 == ib or i2 == ia:      # the JS compares point objects: shared endpoints don't count
                continue
            p1, q1 = P[i1], P[i2]
            if (_orient(p1, q1, a) > 0) != (_orient(p1, q1, b) > 0) and \
               (_orient(a, b, p1) > 0) != (_orient(a, b, q1) > 0):
                return False
        return True

    def find_candidate(ia: int, ib: int, ic: int, id_: int, max_dist: float):
        a, b, c, d = P[ia], P[ib], P[ic], P[id_]
        # every unused point within max_dist of edge (b, c) lies within this ball
        radius = 0.5 * math.sqrt(_sq_dist(b, c)) + math.sqrt(max_dist) + 1e-12
        cand = np.array(kd.query_ball_point(((b[0] + c[0]) / 2, (b[1] + c[1]) / 2), radius), dtype=np.int64)
        if cand.size == 0:
            return None
        cand = cand[~used[cand]]
        if cand.size == 0:
            return None
        dist = _sq_seg_dist(P[cand, 0], P[cand, 1], b, c)
        keep = dist <= max_dist
        cand, dist = cand[keep], dist[keep]
        for j in np.argsort(dist, kind="stable"):     # best-first order, as the JS priority queue gives
            ip = int(cand[j])
            px, py = P[ip:ip + 1, 0], P[ip:ip + 1, 1]
            d0 = float(_sq_seg_dist(px, py, a, b)[0])
            d1 = float(_sq_seg_dist(px, py, c, d)[0])
            if dist[j] < d0 and dist[j] < d1 and no_intersections(ib, ip) and no_intersections(ic, ip):
                return ip
        return None

    sq_conc = concavity * concavity
    sq_len_threshold = length_threshold * length_threshold
    while queue:
        k = queue.popleft()
        ia, ib = node_p[k], node_p[nxt[k]]
        a, b = P[ia], P[ib]
        sq_len = _sq_dist(a, b)
        if sq_len < sq_len_threshold:
            continue
        max_sq_len = sq_len / sq_conc if sq_conc > 0 else math.inf
        p = find_candidate(node_p[prv[k]], ia, ib, node_p[nxt[nxt[k]]], max_sq_len)
        if p is not None and min(_sq_dist(P[p], a), _sq_dist(P[p], b)) <= max_sq_len:
            queue.append(k)
            new = insert_node(p, k)
            queue.append(new)
            used[p] = True
            update_bbox(k)
            update_bbox(new)

    ring = []
    k = last
    while True:
        ring.append(node_p[k])
        k = nxt[k]
        if k == last:
            break
    ring.append(node_p[k])
    return P[ring]


# ------------------------------------------------------------ ITSMe's pieces
def _round_like_jsonlite(v: np.ndarray, digits: int = 4) -> np.ndarray:
    """The R concaveman package passes points through jsonlite::toJSON, which
    keeps 4 decimal places by default. Correctly rounded %.4f matches it on all
    but a handful of exact-tie coordinates per slice."""
    fmt = f"%.{digits}f"
    return np.array([float(fmt % x) for x in v.ravel()]).reshape(v.shape)


def _radius(Ri: np.ndarray, how) -> float:
    """ITSMe's get_radius(): mean, median, or a trimmed mean (numeric how = total % trimmed)."""
    if isinstance(how, str):
        h = how.strip().lower()
        if h == "mean":
            return float(np.mean(Ri))
        if h == "median":
            return float(np.median(Ri))
        how = float(h)
    if how == 0:
        return float(np.mean(Ri))
    q = how / 2 / 100
    lo, hi = np.quantile(Ri, q), np.quantile(Ri, 1 - q)        # numpy linear = R type 7
    return float(np.mean(Ri[(Ri >= lo) & (Ri <= hi)]))


def _arc_coverage(x, y, R, xc, yc, arc_min_angle=18.0, arc_tolerance=0.05) -> float:
    dx, dy = x - xc, y - yc
    ang = np.degrees(np.arctan2(dy, dx))
    ang = np.where(ang < 0, ang + 360, ang)
    dist = np.hypot(dx, dy)
    sel = ang[(dist > R - arc_tolerance) & (dist < R + arc_tolerance)]
    if sel.size == 0:
        return 0.0
    starts = np.arange(0, 360 - arc_min_angle + 1e-9, arc_min_angle)
    return float(np.mean([np.any((sel >= s) & (sel < s + arc_min_angle)) for s in starts]))


def _inner_circle_empty(x, y, R, xc, yc, min_inner_buffer=0.06, inner_buffer_fraction=0.5):
    inner = R - max(min_inner_buffer, inner_buffer_fraction * R)
    if inner <= 0:
        return None
    return bool(not np.any(np.hypot(x - xc, y - yc) < inner))


def _all_points_in_donut(x, y, R, xc, yc, arc_tolerance=0.05) -> bool:
    d = np.hypot(x - xc, y - yc)
    return bool(np.all((d >= R - arc_tolerance) & (d <= R + arc_tolerance)))


def _fit_centre(x: np.ndarray, y: np.ndarray):
    """ITSMe's optim(par = mean centre, fn = f, method = "L-BFGS-B"), with
    R optim()'s defaults: central-difference gradient (ndeps 1e-3),
    factr 1e7, pgtol 0, lmm 5, maxit 100."""
    def f(c):
        Ri = np.hypot(x - c[0], y - c[1])
        return float(np.sum((Ri - Ri.mean()) ** 2))

    def grad(c, h=1e-3):
        g = np.empty(2)
        for i in range(2):
            e = np.zeros(2)
            e[i] = h
            g[i] = (f(c + e) - f(c - e)) / (2 * h)
        return g

    res = minimize(f, x0=np.array([x.mean(), y.mean()]), jac=grad, method="L-BFGS-B",
                   options={"maxcor": 5, "ftol": 1e7 * np.finfo(float).eps, "gtol": 0.0, "maxiter": 100})
    return res.x


def diameter_slice(X, Y, Z, slice_height, slice_thickness=0.06, concavity=4.0, how="median") -> dict:
    """Port of ITSMe::diameter_slice_pc(functional = TRUE, no DTM). Heights in m."""
    nan = {"diameter": math.nan, "R2": math.nan, "center": None, "fdiameter": math.nan,
           "arc_coverage": math.nan, "inner_circle_empty": None, "all_points_in_donut": None}
    lp = float(Z.min())
    if not (Z.max() - lp > slice_height):
        return nan
    band = (Z > lp + slice_height - slice_thickness / 2) & (Z < lp + slice_height + slice_thickness / 2)
    x, y = X[band], Y[band]
    if len(x) <= 3:
        return nan
    # drop points whose nearest other point is more than 5 cm away (nabor::knn, k = 2)
    d, _ = cKDTree(np.c_[x, y]).query(np.c_[x, y], k=2)
    keep = ~(d[:, 1] > 0.05)
    x, y = x[keep], y[keep]

    xc, yc = _fit_centre(x, y)
    Ri = np.hypot(x - xc, y - yc)
    R = _radius(Ri, how)
    out = {
        "R2": float(np.sum((Ri - R) ** 2) / len(Ri)),
        "diameter": 2 * R,
        "center": (float(xc), float(yc)),
        "arc_coverage": _arc_coverage(x, y, R, xc, yc),
        "inner_circle_empty": _inner_circle_empty(x, y, R, xc, yc),
        "all_points_in_donut": _all_points_in_donut(x, y, R, xc, yc),
    }

    # functional diameter: concave hull of the unique points (first occurrence
    # kept, as R's unique()), equal-area circle
    xy = np.c_[x, y]
    _, first = np.unique(xy, axis=0, return_index=True)
    pts = _round_like_jsonlite(xy[np.sort(first)])
    ring = concaveman(pts, concavity)
    area = 0.5 * abs(np.dot(ring[:-1, 0], ring[1:, 1]) - np.dot(ring[1:, 0], ring[:-1, 1]))
    out["fdiameter"] = math.sqrt(area / math.pi) * 2

    if R > 1.5:                                # ITSMe rejects implausible circle fits
        out.update(diameter=math.nan, center=None, arc_coverage=math.nan,
                   inner_circle_empty=None, all_points_in_donut=None)
    return out


# --------------------------------------------------------------------- measure
def measure_one(path: str, tree_id: str, height_z: float, thickness: float,
                concavity: float, how, up_axis: str) -> dict:
    xyz = load_xyz(path)
    if len(xyz) == 0:
        raise ValueError(f"No points read from {path}")
    X, Y, Z = xyz[:, 0], xyz[:, 1], xyz[:, 2]
    if up_axis == "y":            # ITSMe assumes Z is up: swap Y and Z, as the R version does
        Y, Z = Z, Y
    elif up_axis == "x":
        X, Z = Z, X
    lp = float(Z.min())
    slice_height = height_z - lp  # height ABOVE the lowest point

    res = diameter_slice(X, Y, Z, slice_height, thickness, concavity, how)
    diam_cm = 100 * res["diameter"]
    fdiam_cm = 100 * res["fdiameter"]
    r2 = res["R2"]
    rms_mm = math.sqrt(r2) * 1000 if not math.isnan(r2) else math.nan
    cx, cy = res["center"] if res["center"] else (math.nan, math.nan)
    low_conf = math.isnan(res["diameter"]) or res["inner_circle_empty"] is False \
        or res["all_points_in_donut"] is False

    def rnd(v, n):
        return round(v, n) if not math.isnan(v) else math.nan

    return {
        "tree_id": tree_id,
        "section_file": os.path.basename(path),
        "method": "ITSMe diameter_slice_pc, Python port",
        "height_z_m": round(height_z, 4),
        "slice_height_above_lp_m": round(slice_height, 4),
        "slice_thickness_m": thickness,
        "itsme_circle_diameter_cm": rnd(diam_cm, 2),
        "itsme_circle_circumference_cm": rnd(math.pi * diam_cm, 2),
        "itsme_circle_rms_mm": rnd(rms_mm, 2),
        "itsme_func_diameter_cm": rnd(fdiam_cm, 2),
        "itsme_func_circumference_cm": rnd(math.pi * fdiam_cm, 2),
        "itsme_arc_coverage": res["arc_coverage"],
        "itsme_center_x": rnd(cx, 4),
        "itsme_center_y": rnd(cy, 4),
        "radius_how": how,
        "low_confidence": bool(low_conf),
    }


def report_row(row: dict) -> None:
    flag = "  ** LOW CONFIDENCE **" if row["low_confidence"] else ""
    print(f"{row['tree_id']:<14} D_circle={row['itsme_circle_diameter_cm']:.1f} cm  "
          f"C_func={row['itsme_func_circumference_cm']:.1f} cm  "
          f"rms={row['itsme_circle_rms_mm']:.1f} mm{flag}")


# ------------------------------------------------------------------------ run
def main() -> None:
    ap = argparse.ArgumentParser(description="ITSMe diameter_slice_pc, Python port (twin of dab_itsme_concave_hull.R).")
    ap.add_argument("path", nargs="?", default=None, help="A .ply slice or trunk section. Not used with --from-sheet.")
    ap.add_argument("--from-sheet", action="store_true",
                    help="Batch-run using the CONFIG block at the top of this file: read tree ID, height "
                         "and ply path from SHEET_PATH, and write the functional diameter back into OUTPUT_COL.")
    ap.add_argument("--tree-id", default=None)
    ap.add_argument("--height-z", type=float, default=None,
                    help="The picked height along the up axis (m). Required unless --from-sheet.")
    ap.add_argument("--thickness", type=float, default=0.06)
    ap.add_argument("--concavity", type=float, default=4.0)
    ap.add_argument("--how", default="median", help="ITSMe radius summary: median, mean, or a trim %%.")
    ap.add_argument("--up-axis", choices=["x", "y", "z"], default="z",
                    help="Trunk axis. Default z (ITSMe's convention); ForestScanner clouds are Y-up -> pass y.")
    ap.add_argument("--out", default=None, help="CSV to write/append results to.")
    args = ap.parse_args()

    rows = []
    if args.from_sheet:
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from sheet_batch import SheetConfig, load_manifest, write_back_all
        cfg = SheetConfig(sheet_path=SHEET_PATH, tree_id_col=TREE_ID_COL, ply_folder=PLY_FOLDER,
                          ply_filename_pattern=PLY_FILENAME_PATTERN, site_label=SITE_LABEL,
                          height_col=HEIGHT_COL, output_col=OUTPUT_COL, sheet_name=SHEET_NAME)
        manifest = load_manifest(cfg)
        if not manifest:
            sys.exit("No rows to process -- check the CONFIG block values at the top of this file.")
        updates = []
        for m in manifest:
            try:
                row = measure_one(m["path"], m["tree_id"], m["height"], args.thickness,
                                  args.concavity, args.how, args.up_axis)
            except Exception as e:
                print(f"[skip] {m['tree_id']}: {e}", file=sys.stderr)
                continue
            rows.append(row)
            report_row(row)
            if not math.isnan(row["itsme_func_diameter_cm"]):
                # tenths of a mm, as the R version writes
                updates.append((m["row"], round(row["itsme_func_diameter_cm"] * 10, 1)))
            else:
                print(f"[skip write-back] {m['tree_id']}: functional diameter is NaN, nothing to write")
        write_back_all(cfg, updates)
    else:
        if not args.path:
            ap.error("path is required unless --from-sheet is given.")
        if args.height_z is None:
            ap.error("--height-z is required (the picked height along the up axis, in metres) unless --from-sheet is given.")
        tree_id = args.tree_id or os.path.splitext(os.path.basename(args.path))[0]
        row = measure_one(args.path, tree_id, args.height_z, args.thickness, args.concavity, args.how, args.up_axis)
        report_row(row)
        rows.append(row)

    if args.out and rows:
        import csv
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        new_file = not os.path.exists(args.out)
        with open(args.out, "a", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            if new_file:
                w.writeheader()
            w.writerows(rows)
        print(f"Wrote {len(rows)} row(s) -> {args.out}")


if __name__ == "__main__":
    main()
