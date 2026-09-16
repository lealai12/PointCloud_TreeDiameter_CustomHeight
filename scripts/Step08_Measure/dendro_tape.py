#!/usr/bin/env python3
"""
dendro_tape.py — mimic a physical dendrometer / girth tape on a trunk slice (Python).

WHAT THIS MEASURES (and why)
----------------------------
A dendrometer band and a diameter/girth tape are both a *taut, inextensible band*
wrapped around the stem under tension. A taut band around a cross-section traces
exactly one shape — the CONVEX HULL of the surface points — because a taut band
physically cannot dip into a fissure; it bridges every concavity. (That's the
literal definition of a convex hull: the outline a stretched rubber band takes
around a set of points.) So the physically faithful mimic of a dendrometer is:

    circumference  = convex-hull perimeter of the slice        (PRIMARY metric)
    equiv diameter = circumference / pi                        (as a tape is pre-/pi'd)

This is grounded in the PHYSICS of the instrument, not in which method happens
to score best on any particular dataset — that keeps the tool unbiased.

There is deliberately NO circle fit and NO concave hull here: a circle assumes a
round trunk, and a concave hull sinks into grooves — neither is what a taut band does.

Companion R tool: scripts/dendro_tape.R computes the same convex-hull taut wrap in
R. The two are independent implementations of one physical measurement, so a Python
lab and an R lab each get a validated tool; where they disagree, it flags a bug.

USAGE
-----
Cut a band at a picked height on a trunk SECTION (clouds are Y-up -> --up-axis y):
    python dendro_tape.py section.ply --tree-id 1234 --up-axis y \
        --slice-height 2.31 --slice-thickness 0.06 --out results/dendro_tape.csv

Measure an already-cut thin slice/disc as-is (omit --slice-height):
    python dendro_tape.py slice.ply --tree-id 1234 --up-axis y

Batch a folder of *.ply (one row each):
    python dendro_tape.py slices/ --batch --up-axis y --out results/dendro_tape.csv
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
OUTPUT_COL = "Dendrometer_pythonScript_Diameter_mm"  # SAME column fit_dab.py writes -- this
                                      # script's raw-point convex hull is numerically identical
                                      # to fit_dab.py's hull_equiv_diameter_cm on the same slice
                                      # (confirmed project-wide), so the sheet only carries one
                                      # Python true-hull column, not a separate one per script
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


def taut_band(xy: np.ndarray) -> dict:
    """Convex-hull perimeter of the 2D slice = the taut tape wrapped round the stem.

    `ConvexHull(xy).vertices` are the indices of the outermost points, already
    ordered around the hull. We close the loop (append the first point after the
    last), take the straight-line length of each edge, and sum them -> perimeter.

    We also return the LONGEST single hull edge as a fraction of the equivalent
    diameter. On a full ring every edge is tiny (adjacent points), so this is ~0;
    on a partial/broken ring the hull chords straight across the gap, making one
    edge nearly a whole diameter -> a big fraction. This is a center-free detector
    of the "tape bridging a gap" pathology (see max_edge_frac guard below).
    """
    h = ConvexHull(xy)
    loop = xy[h.vertices]                       # outer points, in order around the ring
    loop = np.vstack([loop, loop[0]])           # close the loop: last point == first
    # np.diff(..., axis=0) = edge vectors; norm(..., axis=1) = each edge's length (m)
    edges = np.linalg.norm(np.diff(loop, axis=0), axis=1)
    per_m = float(edges.sum())
    equiv_diam_m = per_m / math.pi
    return {
        "tape_circumference_cm": 100 * per_m,
        "tape_equiv_diameter_cm": 100 * equiv_diam_m,
        "max_edge_frac": float(edges.max() / equiv_diam_m) if equiv_diam_m > 0 else float("inf"),
    }


def angular_coverage_deg(xy: np.ndarray) -> float:
    """Largest covered arc (deg) about the slice centroid — a QC check.

    A taut tape needs a (near-)closed loop of points. If the cloud only captured
    part of the ring, the hull chords straight across the missing side and the
    circumference reads too small. Low coverage flags that.
    """
    cx, cy = xy[:, 0].mean(), xy[:, 1].mean()
    ang = np.sort(np.arctan2(xy[:, 1] - cy, xy[:, 0] - cx))
    gaps = np.diff(np.r_[ang, ang[0] + 2 * math.pi])   # angular gaps between neighbours
    return math.degrees(2 * math.pi - gaps.max())      # 360 minus the biggest gap


# A convex-hull edge longer than this fraction of the equivalent diameter means the
# tape is bridging a large gap (a partial/broken ring), so the circumference reads
# too small. ~0.5 flags openings beyond ~65 deg while passing well-sampled full rings
# (whose longest edge is a tiny fraction of the diameter). Self-scaling to tree size.
MAX_EDGE_FRAC = 0.5


def analyze_slice(path: str, tree_id: str | None, up_axis: str = "y",
                  slice_height: float | None = None, slice_thickness: float = 0.06,
                  min_coverage: float = 270.0) -> dict:
    xyz = load_xyz(path)

    # Which column is the trunk/up axis, and which two form the cross-section plane.
    # ForestScanner (ARKit) clouds are Y-up, so the ring is circular in X-Z (up-axis y).
    up_idx = {"x": 0, "y": 1, "z": 2}[up_axis]
    plane_idx = [i for i in (0, 1, 2) if i != up_idx]

    # Height-slice mode: `path` is a whole SECTION; cut the band [h - t/2, h + t/2]
    # along the up-axis — the identical window fit_dab.py and dendro_tape.R use.
    # Omit --slice-height and `path` is treated as an already-cut slice/disc.
    if slice_height is not None:
        coord = xyz[:, up_idx]
        keep = (coord > slice_height - slice_thickness / 2) & \
               (coord < slice_height + slice_thickness / 2)
        xyz = xyz[keep]

    n = len(xyz)
    if n < 8:
        detail = (f" in band {up_axis}={slice_height}±{slice_thickness/2}"
                  if slice_height is not None else "")
        raise ValueError(f"{path}: only {n} points{detail} — too few for a tape wrap.")

    xy = xyz[:, plane_idx]                       # project onto the cross-section plane
    cov = angular_coverage_deg(xy)
    tape = taut_band(xy)
    # a trustworthy taut wrap needs a closed-enough loop: enough angular coverage AND
    # no single hull edge chording across a big gap.
    valid = (cov >= min_coverage) and (tape["max_edge_frac"] <= MAX_EDGE_FRAC)

    return {
        "tree_id": tree_id or os.path.splitext(os.path.basename(path))[0],
        "slice_file": os.path.basename(path),
        "up_axis": up_axis,
        "height_m": slice_height,
        "slice_thickness_m": slice_thickness if slice_height is not None else None,
        "n_points": n,
        "coverage_deg": round(cov, 1),
        "max_edge_frac": round(tape["max_edge_frac"], 3),
        "tape_circumference_cm": round(tape["tape_circumference_cm"], 2),
        "tape_equiv_diameter_cm": round(tape["tape_equiv_diameter_cm"], 2),
        "tape_valid": bool(valid),
    }


def main():
    ap = argparse.ArgumentParser(
        description="Mimic a dendrometer/tape (convex-hull circumference) on a trunk slice.")
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
                         "(default). Slicing uses this axis; the tape wraps the other two.")
    ap.add_argument("--slice-height", type=float, default=None,
                    help="Cut a band centred on this coordinate along --up-axis (m). "
                         "Match the thickness/height used by fit_dab.py / dendro_tape.R. "
                         "Omit to measure a pre-cut slice/disc as-is.")
    ap.add_argument("--slice-thickness", type=float, default=0.06,
                    help="Band thickness for --slice-height (m, default 0.06).")
    ap.add_argument("--min-coverage", type=float, default=270.0,
                    help="Min angular coverage (deg) for a trustworthy tape wrap "
                         "(default 270). Below this, tape_valid=False.")
    ap.add_argument("--out", default=None, help="CSV to write/append results to.")
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
                                    args.slice_thickness, args.min_coverage)
                rows.append(row)
                flag = "" if row["tape_valid"] else "  ** PARTIAL RING — tape invalid **"
                print(f"{row['tree_id']:<14} "
                      f"C_tape={row['tape_circumference_cm']:.1f} cm  "
                      f"(C/pi diam={row['tape_equiv_diameter_cm']:.1f} cm)  "
                      f"cov={row['coverage_deg']:.0f}deg  "
                      f"maxedge={row['max_edge_frac']:.2f}{flag}")
                if row["tape_valid"]:
                    updates.append((m["row"], round(row["tape_equiv_diameter_cm"] * 10, 1)))
                else:
                    print(f"[skip write-back] {m['tree_id']}: tape invalid (partial ring), "
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
                                    args.slice_thickness, args.min_coverage)
                rows.append(row)
                flag = "" if row["tape_valid"] else "  ** PARTIAL RING — tape invalid **"
                print(f"{row['tree_id']:<14} "
                      f"C_tape={row['tape_circumference_cm']:.1f} cm  "
                      f"(C/pi diam={row['tape_equiv_diameter_cm']:.1f} cm)  "
                      f"cov={row['coverage_deg']:.0f}deg  "
                      f"maxedge={row['max_edge_frac']:.2f}{flag}")
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
