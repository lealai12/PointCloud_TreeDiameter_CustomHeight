#!/usr/bin/env python3
"""
circle_fit.py — least-squares circle fit on a trunk slice (Python).

WHAT THIS MEASURES
------------------
The diameter of the circle that best fits the slice points: an algebraic
(Kasa) least-squares fit in the plane across the trunk axis (X-Z for Y-up
ForestScanner clouds). It is the classic point-cloud stem diameter.

A circle passes through the middle of the bark's bumps rather than wrapping
round them, so on a fluted or buttressed trunk it tends to read below a hull
or a tape. On a round trunk the circle, the hull and a tape agree. The RMS of
the radial residuals is reported too, as a measure of how round the ring is.

Companion R tool: scripts/Step06_Measure/circle_fit.R fits the same circle
independently in R. The two share no code; where they disagree, it flags a bug.

USAGE
-----
Cut a band at a picked height on a trunk SECTION (clouds are Y-up -> --up-axis y):
    python circle_fit.py section.ply --tree-id 1234 --up-axis y \\
        --slice-height 2.31 --slice-thickness 0.06 --out results/circle_fit.csv

Measure an already-cut, polished slice as-is (omit --slice-height):
    python circle_fit.py slice.ply --tree-id 1234 --up-axis y

Batch a folder of *.ply (one row each):
    python circle_fit.py slices/ --batch --up-axis y --out results/circle_fit.csv
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
SHEET_PATH = "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx"  # the working sheet; Tree_Tag matches the .ply file names
SHEET_NAME = 0                        # tab name (string) or 0-based index
TREE_ID_COL = "Tree_Tag"              # column holding each tree's ID
HEIGHT_COL = None                     # None -> measure each .ply as an already-cut, already-
                                      # polished disc (the normal workflow for this script);
                                      # set to e.g. "Y_value_Dendrometer" to cut on the fly instead
OUTPUT_COL = "Dendrometer_CircleFit_pythonScript_Diameter_mm"  # this script's own column
PLY_FOLDER = "C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"  # step 5 output: polished slices, <tag>__<Site>.ply
PLY_FILENAME_PATTERN = "{tree_id}__{site}.ply"   # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL = "Dendrometer"            # substituted into {site} in the pattern
FLAG_COL = None                       # no gap flag of its own: the circle is fit to the same ring
                                      # dendro_tape measures, so analysis uses the DendroTape flag

try:
    from plyfile import PlyData
except ImportError:
    sys.exit("Missing dependency: pip install plyfile  (see requirements.txt)")


def load_xyz(path: str) -> np.ndarray:
    """Load an Nx3 array of XYZ from a PLY file."""
    ply = PlyData.read(path)
    v = ply["vertex"]
    return np.c_[np.asarray(v["x"]), np.asarray(v["y"]), np.asarray(v["z"])].astype(float)


def fit_circle_kasa(xy: np.ndarray) -> dict:
    """Algebraic (Kasa) least-squares circle on 2D points.

    Solves x^2 + y^2 = D x + E y + F in the least-squares sense; the centre is
    (D/2, E/2) and r^2 = F + cx^2 + cy^2."""
    x, y = xy[:, 0], xy[:, 1]
    A = np.c_[x, y, np.ones(len(x))]
    D, E, F = np.linalg.lstsq(A, x ** 2 + y ** 2, rcond=None)[0]
    cx, cy = D / 2.0, E / 2.0
    r = math.sqrt(max(F + cx ** 2 + cy ** 2, 0.0))
    resid = np.hypot(x - cx, y - cy) - r
    return {"cx": cx, "cy": cy, "r": r, "rms_m": float(np.sqrt(np.mean(resid ** 2)))}


def angular_coverage_deg(xy: np.ndarray, cx: float, cy: float) -> float:
    """Largest covered arc (deg) about the fitted centre. A circle fit on a
    one-sided arc is poorly constrained, so low coverage is worth a look."""
    ang = np.sort(np.arctan2(xy[:, 1] - cy, xy[:, 0] - cx))
    gaps = np.diff(np.r_[ang, ang[0] + 2 * math.pi])   # angular gaps between neighbours
    return math.degrees(2 * math.pi - gaps.max())      # 360 minus the biggest gap


def analyze_slice(path: str, tree_id: str | None, up_axis: str = "y",
                  slice_height: float | None = None, slice_thickness: float = 0.06) -> dict:
    xyz = load_xyz(path)

    # Which column is the trunk/up axis, and which two form the cross-section plane.
    # ForestScanner (ARKit) clouds are Y-up, so the ring is circular in X-Z (up-axis y).
    up_idx = {"x": 0, "y": 1, "z": 2}[up_axis]
    plane_idx = [i for i in (0, 1, 2) if i != up_idx]

    # Height-slice mode: `path` is a whole SECTION; cut the band [h - t/2, h + t/2]
    # along the up-axis, the same window as dendro_tape.py. Omit --slice-height and
    # `path` is treated as an already-cut slice/disc.
    if slice_height is not None:
        coord = xyz[:, up_idx]
        keep = (coord > slice_height - slice_thickness / 2) & \
               (coord < slice_height + slice_thickness / 2)
        xyz = xyz[keep]

    n = len(xyz)
    if n < 8:
        detail = (f" in band {up_axis}={slice_height}±{slice_thickness/2}"
                  if slice_height is not None else "")
        raise ValueError(f"{path}: only {n} points{detail} — too few for a circle fit.")

    xy = xyz[:, plane_idx]                       # project onto the cross-section plane
    circ = fit_circle_kasa(xy)
    return {
        "tree_id": tree_id or os.path.splitext(os.path.basename(path))[0],
        "slice_file": os.path.basename(path),
        "up_axis": up_axis,
        "height_m": slice_height,
        "slice_thickness_m": slice_thickness if slice_height is not None else None,
        "n_points": n,
        "coverage_deg": round(angular_coverage_deg(xy, circ["cx"], circ["cy"]), 1),
        "circle_rms_mm": round(1000 * circ["rms_m"], 2),
        "circle_circumference_cm": round(100 * 2 * math.pi * circ["r"], 2),
        "circle_diameter_cm": round(100 * 2 * circ["r"], 2),
    }


def report(row: dict) -> None:
    print(f"{row['tree_id']:<14} D_circle={row['circle_diameter_cm']:.1f} cm  "
          f"rms={row['circle_rms_mm']:.1f} mm  cov={row['coverage_deg']:.0f}deg")


def main():
    ap = argparse.ArgumentParser(description="Least-squares circle fit on a trunk slice.")
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
                         "(default). The circle is fit in the other two axes.")
    ap.add_argument("--slice-height", type=float, default=None,
                    help="Cut a band centred on this coordinate along --up-axis (m). "
                         "Omit to measure a pre-cut slice/disc as-is.")
    ap.add_argument("--slice-thickness", type=float, default=0.06,
                    help="Band thickness for --slice-height (m, default 0.06).")
    ap.add_argument("--out", default=None, help="CSV to write/append results to.")
    args = ap.parse_args()

    rows = []
    updates = []   # (sheet_row, value_mm) pairs -- only populated in --from-sheet mode

    if args.from_sheet:
        # sheet_batch.py lives at the scripts/ root, one level up from this
        # Step folder -- put it on the import path before importing it.
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
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
                                    args.slice_thickness)
                rows.append(row)
                report(row)
                # whole mm at the sheet only: the field readings are integer mm. CSV keeps full precision.
                updates.append((m["row"], int(round(row["circle_diameter_cm"] * 10))))
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
                row = analyze_slice(f, None if args.batch else args.tree_id, args.up_axis,
                                    args.slice_height, args.slice_thickness)
                rows.append(row)
                report(row)
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
