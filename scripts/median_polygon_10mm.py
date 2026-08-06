#!/usr/bin/env python3
"""
median_polygon.py — convex hull of a MEDIAN-RADIUS surface polygon (Python),
fixed arc-length angular bins (default 10mm).

FIXED-ARC-LENGTH vs. FIXED-DEGREE: TWO STANDALONE VARIANTS
------------------------------------------------------------
This is a SEPARATE, independent script from scripts/median_polygon_2deg.py,
not a superset of it: median_polygon_2deg.py bins by a fixed ANGLE (2 deg)
instead of a fixed arc length. Both are kept available on purpose -- the
goal is to make the best method available to whoever's using this, not to
silently overwrite an earlier choice with a newer one; which variant
actually performs better can depend on the size range of what you're
measuring, so both stay available to test against your own data.

THIS SCRIPT (the unsuffixed, arc-length one) deliberately holds the plain
name: its bin width is size-normalized, so its smoothing behavior stays
predictable across a wide range of object sizes, where
median_polygon_2deg.py's fixed-degree bin scales silently with size (a
constant angular bin covers far more arc length on a large object than a
small one -- see the next section). A future user reaching for the plain
`median_polygon.py` name on something much bigger than anything they've
tested it on before gets the variant that degrades predictably.

WHAT THIS MEASURES (and why)
----------------------------
scripts/dendro_tape.py argues that a taut tape/dendrometer band traces the
CONVEX HULL of the raw slice points, and that is still true here. The problem
this script targets is a known weakness of that raw-point hull: a convex
hull is NOT outlier-robust — a single stray point left in an imperfectly
cleaned slice ring inflates the tape reading, because one bad point can BE
a hull vertex.

The fix: denoise the ring before taking the hull, not by removing points by
hand, but by resampling it into a MEDIAN SURFACE POLYGON —

  1. bin the slice points by angle around the ring centroid, using a bin
     width chosen so each bin spans a fixed ARC LENGTH (default 10 mm) of
     the ring rather than a fixed number of degrees. A fixed-degree bin
     covers wildly different amounts of bark depending on trunk size (2 deg
     is ~8 mm of arc on a 450 mm stem but ~33 mm on a 1900 mm giant — 4x the
     denoising power on the giant, 4x less on the small stem, for no
     principled reason). A fixed ~10 mm arc length instead approximates the
     real contact width of a tape/dendrometer band, consistently across
     tree sizes. The arc-length -> angle conversion uses the ring's mean
     raw-point radius (computed once, before binning) as the representative
     radius — this is an approximation of the true (possibly fluted)
     surface arc length, not an exact measurement of it, since the real
     surface isn't defined until after this same binning step builds it.
  2. take the MEDIAN radius within each bin (a bin's median ignores a single
     outlier point the same way a median always ignores one bad sample; a
     lone stray point can pull a raw convex hull outward, but it cannot pull
     a per-bin MEDIAN outward),
  3. connect the per-bin (angle, median-radius) vertices in angular order
     into a closed polygon — this traces the actual trunk surface, flutes and
     all, so it is reported too (informational, NOT the primary metric — it
     is conceptually adjacent to ITSMe's concave "functional" diameter, but
     computed completely differently and independently),
  4. take the CONVEX HULL of THAT polygon (not of the raw points) — this is
     the primary metric this script exists to produce: a taut-tape-style
     wrap that is robust to single-point noise because it wraps a denoised
     surface, not the raw cloud.

This is a comparison tool, not a replacement: it exists to check whether
"convex hull of the raw points" (dendro_tape.py) and "convex hull of the
median-radius polygon" (this script) agree. Where they diverge, that tree's
slice likely has exactly the outlier-hull-vertex problem this script is
built to route around.

Gaps: an angular bin with zero points (occlusion, or a bin narrower than the
point spacing) has no median to report. Its radius is filled by circular
linear interpolation between the nearest populated bins on either side, so
the polygon stays closed; `n_bins_populated` / `max_gap_deg` say how much of
the ring is real vs interpolated, and `coverage_deg` (identical definition to
dendro_tape.py, computed on the RAW points, not the bins) plus `max_edge_frac`
on the final hull gate `median_hull_valid` exactly as in dendro_tape.py.

Companion R tool: scripts/median_polygon.R computes the same fixed-arc-length
median-binned convex hull independently in R (median_polygon_2deg.R is its
fixed-degree counterpart, same relationship as this file to
median_polygon_2deg.py). Deliberately no shared code with dendro_tape.py/.R
or fit_dab.py/dab_itsme.R (same project convention: two independent
implementations, compared only at the results stage).

No lean correction here (no --axis-ply), matching dendro_tape.py's
minimalism — this script is scoped to the same near-vertical/dendrometer-site
comparisons dendro_tape.py targets, not the general leaning-stem case.

USAGE
-----
Cut a band at a picked height on a trunk SECTION (clouds are Y-up -> --up-axis y):
    python median_polygon.py section.ply --tree-id 1234 --up-axis y \
        --slice-height 2.31 --slice-thickness 0.06 --bin-width-mm 10 \
        --out results/median_polygon_python_10mm.csv

Measure an already-cut thin slice/disc as-is (omit --slice-height):
    python median_polygon.py slice.ply --tree-id 1234 --up-axis y

Batch a folder of *.ply (one row each):
    python median_polygon.py slices/ --batch --up-axis y --out results/median_polygon_python_10mm.csv
"""

from __future__ import annotations
import argparse
import glob
import math
import os
import sys

import numpy as np

# =============================================================================
# CONFIG -- edit these for your own dataset before running with --from-sheet.
# Ignored otherwise (single-file/--batch CLI usage above is unaffected).
#
# This is the "point at your own spreadsheet and column names" section: a
# future researcher with a differently-shaped manifest only has to edit the
# values below, not the measurement code (analyze_slice etc.), to run this
# script's --from-sheet batch mode against their own project. See also
# scripts/sheet_batch.py, which this block's values get handed to.
# =============================================================================
SHEET_PATH = "C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"  # anonymized sheet -- .ply files are named with the same anonymized codes
SHEET_NAME = 0                        # tab name (string) or 0-based index (see fit_dab.py's
                                      # CONFIG for the R-side 1-based-index note)
TREE_ID_COL = "Tree_Tag"              # column holding each tree's ID
HEIGHT_COL = None                     # None -> measure each .ply as an already-cut, already-
                                      # polished disc (the normal workflow for this script);
                                      # set to e.g. "Y_value_Dendrometer" to cut on the fly instead
OUTPUT_COL = "Dendrometer_MedianPolygon10mm_pythonScript_Diameter_mm"
PLY_FOLDER = "C:/Projects/LiDAR_Project/Working/Polished_Slices_ply"  # already-cut, polished discs
PLY_FILENAME_PATTERN = "{tree_id}__{site}.ply"   # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL = "Dendrometer"            # substituted into {site} in the pattern

try:
    from plyfile import PlyData
except ImportError:
    sys.exit("Missing dependency: pip install plyfile  (see requirements.txt)")

try:
    from scipy.spatial import ConvexHull
except ImportError:
    sys.exit("Missing dependency: pip install scipy  (see requirements.txt)")


def load_xyz(path: str) -> np.ndarray:
    """Load an Nx3 array of XYZ from a PLY file."""
    ply = PlyData.read(path)
    v = ply["vertex"]
    return np.c_[np.asarray(v["x"]), np.asarray(v["y"]), np.asarray(v["z"])].astype(float)


def angular_coverage_deg(xy: np.ndarray) -> float:
    """Largest covered arc (deg) about the slice centroid. Identical definition
    to dendro_tape.py's angular_coverage_deg, kept separate so the two scripts'
    coverage_deg numbers are directly comparable, not just similarly-named."""
    cx, cy = xy[:, 0].mean(), xy[:, 1].mean()
    ang = np.sort(np.arctan2(xy[:, 1] - cy, xy[:, 0] - cx))
    gaps = np.diff(np.r_[ang, ang[0] + 2 * math.pi])
    return math.degrees(2 * math.pi - gaps.max())


def max_empty_run(populated: np.ndarray) -> int:
    """Longest run of consecutive empty (False) bins, treating the bin array as
    circular (wraps past the last bin back to the first)."""
    n = len(populated)
    if populated.all():
        return 0
    if not populated.any():
        return n
    start = int(np.argmax(populated))          # rotate to start on a populated bin,
    m = np.roll(populated, -start)              # so a run isn't split across the wrap
    best = cur = 0
    for v in m:
        if v:
            cur = 0
        else:
            cur += 1
            best = max(best, cur)
    return best


def median_surface_polygon(xy: np.ndarray, bin_width_mm: float) -> dict:
    """Bin `xy` by angle about its centroid, take the median radius per bin,
    circularly interpolate empty bins, and return the closed polygon plus
    coverage diagnostics. See module docstring for the full rationale.

    Bin width is specified as a target ARC LENGTH (mm) rather than a fixed
    angle: the ring's mean raw-point radius sets the angle-per-mm conversion
    (n_bins = ring circumference / bin_width_mm), so the physical amount of
    bark averaged into each bin stays consistent across tree sizes."""
    cx, cy = xy[:, 0].mean(), xy[:, 1].mean()
    dx, dy = xy[:, 0] - cx, xy[:, 1] - cy
    ang = np.arctan2(dy, dx) % (2 * math.pi)        # [0, 2pi)
    radii = np.hypot(dx, dy)

    ring_radius_m = float(radii.mean())
    ring_radius_mm = 1000.0 * ring_radius_m
    n_bins = max(int(round(2 * math.pi * ring_radius_mm / bin_width_mm)), 3)
    bin_w_rad = 2 * math.pi / n_bins
    bin_idx = np.clip((ang // bin_w_rad).astype(int), 0, n_bins - 1)
    bin_centers = (np.arange(n_bins) + 0.5) * bin_w_rad

    med_r = np.full(n_bins, np.nan)
    for i in range(n_bins):
        sel = radii[bin_idx == i]
        if sel.size:
            med_r[i] = np.median(sel)
    populated = ~np.isnan(med_r)
    n_populated = int(populated.sum())
    if n_populated == 0:
        raise ValueError("no populated angular bins — slice has too few/too "
                          "clustered points to build a surface polygon")

    # Circular linear interpolation for empty bins: extend the populated
    # (angle, radius) samples by +/- 2*pi so np.interp wraps correctly across
    # the 0/2*pi seam, then fill every bin center (populated bins interpolate
    # back to their own exact value at zero distance).
    pop_ang = bin_centers[populated]
    pop_r = med_r[populated]
    order = np.argsort(pop_ang)
    pop_ang, pop_r = pop_ang[order], pop_r[order]
    ext_ang = np.concatenate([pop_ang - 2 * math.pi, pop_ang, pop_ang + 2 * math.pi])
    ext_r = np.tile(pop_r, 3)
    filled_r = np.interp(bin_centers, ext_ang, ext_r)

    poly_xy = np.c_[cx + filled_r * np.cos(bin_centers), cy + filled_r * np.sin(bin_centers)]
    max_gap_deg = math.degrees(max_empty_run(populated) * bin_w_rad)

    return {
        "poly_xy": poly_xy,
        "n_bins": n_bins,
        "n_bins_populated": n_populated,
        "max_gap_deg": round(max_gap_deg, 1),
        "ring_radius_mm": round(ring_radius_mm, 1),
        "bin_width_deg_equiv": round(math.degrees(bin_w_rad), 2),
    }


def polygon_perimeter_m(loop_xy: np.ndarray) -> float:
    """Perimeter (m) of an already-closed-order vertex loop (NOT yet closed —
    this function appends the first vertex to close it)."""
    closed = np.vstack([loop_xy, loop_xy[0]])
    return float(np.linalg.norm(np.diff(closed, axis=0), axis=1).sum())


def convex_hull_tape(xy: np.ndarray) -> dict:
    """Convex-hull perimeter of `xy` = the taut-tape wrap (same construction as
    dendro_tape.py's taut_band, reused here on the MEDIAN POLYGON's vertices
    rather than on the raw slice points)."""
    h = ConvexHull(xy)
    loop = xy[h.vertices]
    loop = np.vstack([loop, loop[0]])
    edges = np.linalg.norm(np.diff(loop, axis=0), axis=1)
    per_m = float(edges.sum())
    equiv_diam_m = per_m / math.pi
    return {
        "circumference_cm": 100 * per_m,
        "equiv_diameter_cm": 100 * equiv_diam_m,
        "max_edge_frac": float(edges.max() / equiv_diam_m) if equiv_diam_m > 0 else float("inf"),
        "loop": loop,   # closed hull loop, same 2D frame as the input `xy`
    }


# ------------------------------------------------------------------ visualization
def write_ply_xyzrgb(path: str, xyz: np.ndarray, rgb) -> None:
    """Write an ASCII PLY of colored points. `rgb` is one (r,g,b) 0-255 or an Nx3 array.
    Same minimal writer as fit_dab.py's, duplicated rather than imported so the two
    scripts stay independent (see module docstring)."""
    xyz = np.asarray(xyz, float)
    rgb = np.asarray(rgb)
    if rgb.ndim == 1:
        rgb = np.tile(rgb, (len(xyz), 1))
    data = np.c_[xyz, rgb.astype(int)]
    header = ("ply\nformat ascii 1.0\n"
              f"element vertex {len(xyz)}\n"
              "property float x\nproperty float y\nproperty float z\n"
              "property uchar red\nproperty uchar green\nproperty uchar blue\n"
              "end_header")
    np.savetxt(path, data, fmt="%.6f %.6f %.6f %d %d %d", header=header, comments="")


def plane_xy_to_3d(xy: np.ndarray, up_val: float, up_idx: int, plane_idx: list[int]) -> np.ndarray:
    """Re-embed 2D plane points back into 3D at a constant up-axis coordinate, so
    the written PLY lines up with the original disc when loaded beside it."""
    out = np.zeros((len(xy), 3))
    out[:, plane_idx[0]] = xy[:, 0]
    out[:, plane_idx[1]] = xy[:, 1]
    out[:, up_idx] = up_val
    return out


def write_polygon_bundle(poly_dir: str, tree_id: str, poly_xy: np.ndarray,
                         hull_loop_xy: np.ndarray, up_val: float, up_idx: int,
                         plane_idx: list[int]) -> None:
    """Write <tree_id>_median_polygon_10mm_py.ply (cyan, the median-binned surface
    polygon) and <tree_id>_median_hull_10mm_py.ply (magenta, its convex hull) into
    poly_dir, for loading in CloudCompare beside the original disc/slice. `_10mm`
    keeps these from colliding with median_polygon_2deg.py's `_2deg`-suffixed
    output when both variants are pointed at the same folder."""
    os.makedirs(poly_dir, exist_ok=True)
    poly_closed = np.vstack([poly_xy, poly_xy[0]])
    write_ply_xyzrgb(os.path.join(poly_dir, f"{tree_id}_median_polygon_10mm_py.ply"),
                     plane_xy_to_3d(poly_closed, up_val, up_idx, plane_idx), (0, 200, 200))
    write_ply_xyzrgb(os.path.join(poly_dir, f"{tree_id}_median_hull_10mm_py.ply"),
                     plane_xy_to_3d(hull_loop_xy, up_val, up_idx, plane_idx), (200, 0, 200))


# Same guard as dendro_tape.py: a hull edge this long relative to the diameter
# means the hull is bridging a large unsampled gap, not tracing real surface.
MAX_EDGE_FRAC = 0.5


def analyze_slice(path: str, tree_id: str | None, up_axis: str = "y",
                  slice_height: float | None = None, slice_thickness: float = 0.06,
                  bin_width_mm: float = 10.0, min_coverage: float = 270.0,
                  poly_dir: str | None = None) -> dict:
    xyz = load_xyz(path)

    up_idx = {"x": 0, "y": 1, "z": 2}[up_axis]
    plane_idx = [i for i in (0, 1, 2) if i != up_idx]

    # Same band-cutting convention as fit_dab.py / dendro_tape.py / dab_itsme.R:
    # [h - t/2, h + t/2] along the up-axis. Omit --slice-height for a pre-cut slice.
    if slice_height is not None:
        coord = xyz[:, up_idx]
        keep = (coord > slice_height - slice_thickness / 2) & \
               (coord < slice_height + slice_thickness / 2)
        xyz = xyz[keep]

    n = len(xyz)
    if n < 8:
        detail = (f" in band {up_axis}={slice_height}±{slice_thickness/2}"
                  if slice_height is not None else "")
        raise ValueError(f"{path}: only {n} points{detail} — too few to fit.")

    xy = xyz[:, plane_idx]
    cov = angular_coverage_deg(xy)

    poly = median_surface_polygon(xy, bin_width_mm)
    poly_xy = poly["poly_xy"]
    median_poly_per_m = polygon_perimeter_m(poly_xy)
    hull = convex_hull_tape(poly_xy)

    valid = (cov >= min_coverage) and (hull["max_edge_frac"] <= MAX_EDGE_FRAC)

    if poly_dir:
        up_val = float(xyz[:, up_idx].mean())
        write_polygon_bundle(poly_dir, tree_id or os.path.splitext(os.path.basename(path))[0],
                             poly_xy, hull["loop"], up_val, up_idx, plane_idx)

    return {
        "tree_id": tree_id or os.path.splitext(os.path.basename(path))[0],
        "slice_file": os.path.basename(path),
        "up_axis": up_axis,
        "height_m": slice_height,
        "slice_thickness_m": slice_thickness if slice_height is not None else None,
        "n_points": n,
        "bin_width_mm": bin_width_mm,
        "ring_radius_mm": poly["ring_radius_mm"],
        "bin_width_deg_equiv": poly["bin_width_deg_equiv"],
        "n_bins": poly["n_bins"],
        "n_bins_populated": poly["n_bins_populated"],
        "max_gap_deg": poly["max_gap_deg"],
        "coverage_deg": round(cov, 1),
        "max_edge_frac": round(hull["max_edge_frac"], 3),
        "median_polygon_circumference_cm": round(100 * median_poly_per_m, 2),
        "median_polygon_diameter_cm": round(100 * median_poly_per_m / math.pi, 2),
        "median_hull_circumference_cm": round(hull["circumference_cm"], 2),
        "median_hull_equiv_diameter_cm": round(hull["equiv_diameter_cm"], 2),
        "median_hull_valid": bool(valid),
    }


def main():
    ap = argparse.ArgumentParser(
        description="Convex hull of a median-radius surface polygon on a trunk slice, "
                    "fixed arc-length angular bins (denoised alternative to dendro_tape.py's "
                    "raw-point hull; see median_polygon_2deg.py for the fixed-degree variant).")
    ap.add_argument("path", nargs="?", default=None,
                    help="A .ply slice/section, or a folder (with --batch). Not used with --from-sheet.")
    ap.add_argument("--batch", action="store_true", help="Treat path as a folder of *.ply.")
    ap.add_argument("--from-sheet", action="store_true",
                    help="Batch-run using the CONFIG block at the top of this file: read tree "
                         "ID/height/ply-path from SHEET_PATH and loop over every row instead of "
                         "the positional path/--tree-id/--slice-height arguments. Results are "
                         "both appended to --out (if given) and written back into SHEET_PATH's "
                         "OUTPUT_COL.")
    ap.add_argument("--tree-id", default=None)
    ap.add_argument("--up-axis", choices=["x", "y", "z"], default="y",
                    help="Trunk/up axis. ForestScanner (ARKit) clouds are Y-up -> 'y' "
                         "(default).")
    ap.add_argument("--slice-height", type=float, default=None,
                    help="Cut a band centred on this coordinate along --up-axis (m). "
                         "Match the thickness/height used by the other fitters. "
                         "Omit to measure a pre-cut slice/disc as-is.")
    ap.add_argument("--slice-thickness", type=float, default=0.06,
                    help="Band thickness for --slice-height (m, default 0.06).")
    ap.add_argument("--bin-width-mm", type=float, default=10.0,
                    help="Target arc-length bin width for the median surface polygon "
                         "(mm of ring circumference, default 10.0 -- approximates a "
                         "tape/dendrometer band's contact width; converted to an "
                         "angular bin count per-tree using that ring's mean radius, "
                         "so bin count scales with trunk size instead of a fixed "
                         "degree width covering wildly different arc lengths).")
    ap.add_argument("--min-coverage", type=float, default=270.0,
                    help="Min angular coverage (deg) for a trustworthy wrap "
                         "(default 270). Below this, median_hull_valid=False.")
    ap.add_argument("--out", default=None, help="CSV to write/append results to.")
    ap.add_argument("--poly-dir", default=None,
                    help="If set, write <tree_id>_median_polygon_10mm_py.ply (cyan) and "
                         "<tree_id>_median_hull_10mm_py.ply (magenta) per slice under this "
                         "folder, for loading in CloudCompare beside the original disc.")
    args = ap.parse_args()

    rows = []
    updates = []   # (sheet_row, value_mm) pairs -- only populated in --from-sheet mode

    if args.from_sheet:
        from sheet_batch import SheetConfig, load_manifest, write_back_all
        cfg = SheetConfig(sheet_path=SHEET_PATH, tree_id_col=TREE_ID_COL, ply_folder=PLY_FOLDER,
                          ply_filename_pattern=PLY_FILENAME_PATTERN, site_label=SITE_LABEL,
                          height_col=HEIGHT_COL, output_col=OUTPUT_COL, sheet_name=SHEET_NAME)
        manifest = load_manifest(cfg)
        if not manifest:
            sys.exit("No rows to process -- check the CONFIG block values at the top of this file.")
        for m in manifest:
            try:
                row = analyze_slice(m["path"], m["tree_id"], args.up_axis, m["height"],
                                    args.slice_thickness, args.bin_width_mm, args.min_coverage,
                                    args.poly_dir)
                rows.append(row)
                flag = "" if row["median_hull_valid"] else "  ** PARTIAL RING — hull invalid **"
                print(f"{row['tree_id']:<14} "
                      f"C_medhull={row['median_hull_circumference_cm']:.1f} cm  "
                      f"(C/pi diam={row['median_hull_equiv_diameter_cm']:.1f} cm)  "
                      f"C_medpoly={row['median_polygon_circumference_cm']:.1f} cm  "
                      f"cov={row['coverage_deg']:.0f}deg  "
                      f"bins={row['n_bins_populated']}/{row['n_bins']}{flag}")
                if row["median_hull_valid"]:
                    updates.append((m["row"], round(row["median_hull_equiv_diameter_cm"] * 10, 1)))
                else:
                    print(f"[skip write-back] {m['tree_id']}: hull invalid (partial ring), "
                          "no diameter to write", file=sys.stderr)
            except Exception as e:
                print(f"[skip] {m['tree_id']}: {e}", file=sys.stderr)
        write_back_all(cfg, updates)
    else:
        if not args.path:
            ap.error("path is required unless --from-sheet is given.")
        files = (sorted(glob.glob(os.path.join(args.path, "*.ply")))
                 if args.batch else [args.path])
        if not files:
            sys.exit(f"No PLY files found at: {args.path}")

        for f in files:
            try:
                row = analyze_slice(f, args.tree_id, args.up_axis, args.slice_height,
                                    args.slice_thickness, args.bin_width_mm, args.min_coverage,
                                    args.poly_dir)
                rows.append(row)
                flag = "" if row["median_hull_valid"] else "  ** PARTIAL RING — hull invalid **"
                print(f"{row['tree_id']:<14} "
                      f"C_medhull={row['median_hull_circumference_cm']:.1f} cm  "
                      f"(C/pi diam={row['median_hull_equiv_diameter_cm']:.1f} cm)  "
                      f"C_medpoly={row['median_polygon_circumference_cm']:.1f} cm  "
                      f"cov={row['coverage_deg']:.0f}deg  "
                      f"bins={row['n_bins_populated']}/{row['n_bins']}{flag}")
            except Exception as e:
                print(f"[skip] {f}: {e}", file=sys.stderr)

    if args.out and rows:
        import pandas as pd
        df = pd.DataFrame(rows)
        if os.path.exists(args.out):
            old = pd.read_csv(args.out)
            df = pd.concat([old, df], ignore_index=True)
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        df.to_csv(args.out, index=False)
        print(f"\nWrote {len(rows)} row(s) -> {args.out}")


if __name__ == "__main__":
    main()
