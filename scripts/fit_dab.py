#!/usr/bin/env python3
"""
fit_dab.py — Fit Diameter (Above Buttress) / Circumference from a trunk-slice point cloud.

Given a thin trunk cross-section exported as a point cloud (e.g. from
CloudCompare), this:
  1. (optional) corrects for stem lean by rotating the slice so the stem axis = Z,
  2. fits a least-squares circle (Kåsa) -> best-fit diameter,
  3. computes the convex-hull perimeter -> tape-equivalent circumference & diameter,
  4. reports fit quality (RMS residual, angular coverage) so bad slices are flagged.

Intended for trunks where a normal tape/DBH reading isn't reliable at the
usual measurement height — buttressed, fluted, or otherwise irregular
cross-sections — where "diameter above buttress" (measured higher up, where
the trunk is closer to circular) is the standard field workaround.

Usage
-----
Single slice:
    python fit_dab.py slices/tree01_slice.ply --tree-id tree01 --dab-height 2.3

Batch a whole folder (one row per *.ply), append to results CSV:
    python fit_dab.py slices/ --batch --out results/dab_results.csv

Also emit the see-able output bundle (2D fit figure + 3D circle/hull overlays +
slice cloud + measure.txt) under a folder, one subfolder per tree:
    python fit_dab.py slices/tree01_slice.ply --tree-id tree01 \
        --viz-dir <output_folder>/viz

Notes
-----
- Report **circumference** as the primary metric and equivalent diameter = C/pi
  to match how a physical girth tape actually reads (it wraps the outside, it
  doesn't do a least-squares fit).
- Convex-hull perimeter mimics a tape wrapped around the stem. Only trust it on
  well-closed rings (angular coverage >= ~270 deg). Partial rings are flagged.
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
SHEET_NAME = 0                        # tab name (string) or 0-based index (openpyxl convention --
                                      # the R measurement scripts' SHEET_NAME is 1-based, readxl's
                                      # convention; the default 0/1 both mean "the first sheet")
TREE_ID_COL = "Tree_Tag"              # column holding each tree's ID
HEIGHT_COL = "Y_value_Dendrometer"    # column holding the picked cut height (m); swap to
                                      # Y_value_TopFlag / Y_value_LowerFlag for those sites
OUTPUT_COL = "Dendrometer_pythonScript_Diameter_mm"  # column the diameter (mm) is written into
PLY_FOLDER = "C:/Projects/LiDAR_Project/Working/Final_Disc_ply"  # whole trunk SECTIONS, not pre-cut discs
PLY_FILENAME_PATTERN = "{tree_id}.ply"   # {tree_id} required; {site} optional (see SITE_LABEL)
SITE_LABEL = "Dendrometer"            # substituted into {site} in the pattern, if used

try:
    from plyfile import PlyData
except ImportError:
    sys.exit("Missing dependency: pip install plyfile  (see requirements.txt)")

try:
    from scipy.spatial import ConvexHull
except ImportError:
    sys.exit("Missing dependency: pip install scipy  (see requirements.txt)")


# ----------------------------------------------------------------------------- IO
def load_xyz(path: str) -> np.ndarray:
    """Load an Nx3 array of XYZ from a PLY file."""
    ply = PlyData.read(path)
    v = ply["vertex"]
    return np.c_[np.asarray(v["x"]), np.asarray(v["y"]), np.asarray(v["z"])].astype(float)


# ------------------------------------------------------------------ lean correction
# IMPORTANT: do NOT PCA a thin slice to find the stem axis — a thin slab's
# largest-variance direction lies within the ring (the diameter), not along the
# stem, so it mangles the fit. To correct for lean, estimate the axis from a
# TALLER trunk segment (taller than the stem is wide) with `stem_axis_from_segment`,
# then apply it to the slice. For near-vertical stems, skip correction (default).
def stem_axis_from_segment(seg_xyz: np.ndarray) -> np.ndarray:
    """Estimate the stem axis (unit vector) from a tall trunk segment via PCA.
    The largest-variance direction of a tall bole segment is the stem axis.

    GOTCHA: this only holds when the segment is TALLER than the stem is wide. On a
    short segment the radial spread beats the axial spread and PCA returns a
    diameter direction instead — silently corrupting the fit. We check the top two
    singular values and warn if the axis is not clearly dominant; give it a segment
    at least ~2x the trunk diameter in height.
    """
    X = seg_xyz - seg_xyz.mean(axis=0)
    S, Vt = np.linalg.svd(X, full_matrices=False)[1:]
    if S[0] < 1.3 * S[1]:
        print(f"[warn] axis segment not clearly elongated (s0/s1={S[0]/S[1]:.2f}); "
              "it may be too short relative to trunk diameter. Use a taller "
              "segment or drop --axis-ply.", file=sys.stderr)
    axis = Vt[0]
    return axis / np.linalg.norm(axis)


def rotation_axis_to_z(axis: np.ndarray) -> np.ndarray:
    """Return the 3x3 rotation matrix R that sends `axis` onto +Z.

    Kept separate from the point-rotation below so callers can also use R to map
    fitted geometry (the overlay circle/hull) BACK into the original coordinate
    frame — otherwise a lean-corrected overlay wouldn't line up with the disc."""
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis)
    z = np.array([0.0, 0.0, 1.0])
    v = np.cross(axis, z)
    s = np.linalg.norm(v)
    c = float(np.dot(axis, z))
    if s < 1e-12:  # already aligned (or anti-aligned)
        return np.eye(3) if c > 0 else np.diag([1.0, 1.0, -1.0])
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * ((1 - c) / (s ** 2))


def rotate_axis_to_z(xyz: np.ndarray, axis: np.ndarray) -> np.ndarray:
    """Rotate points so `axis` aligns with +Z (uses `rotation_axis_to_z`)."""
    return xyz @ rotation_axis_to_z(axis).T


# --------------------------------------------------------------------- circle fit
def fit_circle_kasa(xy: np.ndarray) -> dict:
    """Algebraic (Kåsa) least-squares circle fit on 2D points."""
    x, y = xy[:, 0], xy[:, 1]
    A = np.c_[x, y, np.ones(len(x))]
    b = x ** 2 + y ** 2
    D, E, F = np.linalg.lstsq(A, b, rcond=None)[0]
    cx, cy = D / 2.0, E / 2.0
    r = math.sqrt(max(F + cx ** 2 + cy ** 2, 0.0))
    resid = np.hypot(x - cx, y - cy) - r
    return {
        "cx": cx, "cy": cy, "r": r,
        "circle_diameter_cm": 100 * 2 * r,
        "circle_circumference_cm": 100 * 2 * math.pi * r,
        "circle_rms_mm": 1000 * float(np.sqrt(np.mean(resid ** 2))),
    }


def angular_coverage_deg(xy: np.ndarray, cx: float, cy: float) -> float:
    """Largest covered arc (deg). Low coverage => one-sided/partial ring."""
    ang = np.sort(np.arctan2(xy[:, 1] - cy, xy[:, 0] - cx))
    gaps = np.diff(np.r_[ang, ang[0] + 2 * math.pi])
    return math.degrees(2 * math.pi - gaps.max())


def hull_perimeter(xy: np.ndarray) -> dict:
    """Convex-hull perimeter = tape-equivalent circumference."""
    h = ConvexHull(xy)
    loop = xy[h.vertices]
    loop = np.vstack([loop, loop[0]])
    per_m = float(np.sum(np.linalg.norm(np.diff(loop, axis=0), axis=1)))
    return {
        "hull_circumference_cm": 100 * per_m,
        "hull_equiv_diameter_cm": 100 * per_m / math.pi,
    }


# ------------------------------------------------------------------ visualization
# The measurement step emits, per slice, a small bundle the user can SEE:
#   <tree>_slice_fit.png   2D cross-section + fitted circle + hull, labeled
#   <tree>_slice.ply       the slice cloud (original coords)
#   <tree>_ring_<C>.ply    3D red circle overlay (loads beside the disc in CloudCompare)
#   <tree>_hull_<C>.ply    3D green hull outline (only when the ring is well-covered)
#   <tree>_measure.txt     the numbers in text (the "label" CloudCompare can't float)
# The overlay geometry is built in the fitted frame then mapped back to original
# coords with R, so it lines up with the disc even after lean-correction.
def hull_loop_xy(xy: np.ndarray) -> np.ndarray:
    """Ordered, closed convex-hull outline as an (M+1)x2 array (last point == first)."""
    h = ConvexHull(xy)
    loop = xy[h.vertices]
    return np.vstack([loop, loop[0]])


def ring_xyz(cx: float, cy: float, r: float, z: float, n: int = 500) -> np.ndarray:
    """n points evenly spaced on a circle radius r, centered (cx,cy), at height z."""
    t = np.linspace(0, 2 * math.pi, n, endpoint=False)
    return np.c_[cx + r * np.cos(t), cy + r * np.sin(t), np.full(n, z)]


def write_ply_xyzrgb(path: str, xyz: np.ndarray, rgb) -> None:
    """Write an ASCII PLY of colored points. `rgb` is one (r,g,b) 0-255 or an Nx3 array."""
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
    # savetxt writes the numeric block fast; comments="" keeps the header un-prefixed.
    np.savetxt(path, data, fmt="%.6f %.6f %.6f %d %d %d", header=header, comments="")


def plot_slice_fit(xy: np.ndarray, circ: dict, loop, row: dict, path: str) -> None:
    """Save a top-down PNG: slice points + best-fit circle + hull outline, labeled."""
    import matplotlib
    matplotlib.use("Agg")   # headless backend — just write the file, never open a window
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(6, 6))
    ax.scatter(xy[:, 0], xy[:, 1], s=2, c="0.6", label="slice points")
    t = np.linspace(0, 2 * math.pi, 400)
    ax.plot(circ["cx"] + circ["r"] * np.cos(t), circ["cy"] + circ["r"] * np.sin(t),
            "r-", lw=1.5, label="best-fit circle")
    if loop is not None:
        ax.plot(loop[:, 0], loop[:, 1], "g-", lw=1.2, label="hull (tape)")
    ax.plot(circ["cx"], circ["cy"], "r+", ms=10)
    ax.set_aspect("equal", "datalim")
    ax.set_xlabel("x (m)")
    ax.set_ylabel("y (m)")
    C = row.get("hull_circumference_cm") or row["circle_circumference_cm"]
    Dpi = row.get("hull_equiv_diameter_cm") or row["circle_diameter_cm"]
    title = (f"{row['tree_id']}   C = {C:.1f} cm   (C/pi diam = {Dpi:.1f} cm)\n"
             f"coverage {row['coverage_deg']:.0f} deg | circle RMS "
             f"{row['circle_rms_mm']:.1f} mm"
             + ("  ** LOW CONFIDENCE **" if row["low_confidence"] else ""))
    ax.set_title(title, fontsize=9)
    ax.legend(fontsize=7, loc="upper right")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)   # free the figure so a --batch run doesn't leak memory


def write_slice_bundle(viz_dir: str, tree_id: str, xyz_orig: np.ndarray,
                       xy_fit: np.ndarray, z_fit: float, circ: dict, row: dict,
                       R: np.ndarray) -> str:
    """Write the per-slice output bundle to viz_dir/<tree_id>/. Returns that folder.

    `R` is the lean-correction rotation applied to get `xy_fit` (identity if none);
    overlay geometry is mapped back to ORIGINAL coords via `@ R` so it aligns with
    the disc the user loads in CloudCompare."""
    d = os.path.join(viz_dir, tree_id)
    os.makedirs(d, exist_ok=True)
    C = row.get("hull_circumference_cm") or row["circle_circumference_cm"]
    tag = f"C{C:.1f}cm"

    # hull outline only when the ring is well-covered enough to trust the tape method
    loop = hull_loop_xy(xy_fit) if row["hull_valid"] else None

    # 2D figure — drawn in the fitted frame (the honest, lean-corrected cross-section)
    plot_slice_fit(xy_fit, circ, loop, row, os.path.join(d, f"{tree_id}_slice_fit.png"))

    # slice cloud in original coords, neutral gray
    write_ply_xyzrgb(os.path.join(d, f"{tree_id}_slice.ply"), xyz_orig, (180, 180, 180))

    # 3D circle overlay: build in fitted frame, map back to original with R
    ring = ring_xyz(circ["cx"], circ["cy"], circ["r"], z_fit) @ R
    write_ply_xyzrgb(os.path.join(d, f"{tree_id}_ring_{tag}.ply"), ring, (255, 0, 0))
    if loop is not None:
        hull3d = np.c_[loop, np.full(len(loop), z_fit)] @ R
        write_ply_xyzrgb(os.path.join(d, f"{tree_id}_hull_{tag}.ply"), hull3d, (0, 200, 0))

    # measure.txt — the numeric "label" CloudCompare can't float in the 3D view
    with open(os.path.join(d, f"{tree_id}_measure.txt"), "w") as f:
        f.write(f"Tree {tree_id}\n")
        for k in ("dab_height_m", "n_points", "coverage_deg",
                  "circle_diameter_cm", "circle_circumference_cm", "circle_rms_mm",
                  "hull_circumference_cm", "hull_equiv_diameter_cm",
                  "hull_valid", "low_confidence"):
            f.write(f"{k}: {row.get(k)}\n")
    return d


# --------------------------------------------------------------------- driver
def analyze_slice(path: str, tree_id: str | None, dab_height: float | None,
                  axis_ply: str | None = None, viz_dir: str | None = None,
                  slice_height: float | None = None,
                  slice_thickness: float = 0.06, up_axis: str = "z") -> dict:
    xyz_orig = load_xyz(path)

    # Which axis is the trunk/up axis. ForestScanner clouds are Y-up, so slicing
    # and the circle-fit plane must follow --up-axis, not a hard-coded Z.
    up_idx = {"x": 0, "y": 1, "z": 2}[up_axis]

    # Height-slice mode: `path` is a whole trunk SECTION, not a pre-cut ring.
    # Cut a band centred on the picked height (coord along the up-axis), matching
    # ITSMe's diameter_slice_pc window [h - t/2, h + t/2] so dab_itsme.R and
    # fit_dab.py measure the SAME band. Omit --slice-height and `path` is treated
    # as an already-cut slice (e.g. a thin disc that is itself the cross-section).
    if slice_height is not None:
        coord = xyz_orig[:, up_idx]
        keep = (coord > slice_height - slice_thickness / 2) & \
               (coord < slice_height + slice_thickness / 2)
        xyz_orig = xyz_orig[keep]
        if dab_height is None:
            dab_height = slice_height

    n = len(xyz_orig)
    if n < 8:
        detail = (f" in band {up_axis}={slice_height}±{slice_thickness/2}"
                  if slice_height is not None else "")
        raise ValueError(f"{path}: only {n} points{detail} — too few to fit.")

    # Rotate so the trunk axis -> +Z, then fit in the resulting XY plane. The axis
    # comes from --axis-ply (lean correction via PCA) if given, else from --up-axis
    # (a unit vector; 'z' yields identity = the original behaviour). Keep R so the
    # 3D overlay maps back onto the un-rotated disc for CloudCompare.
    axis = None
    if axis_ply:
        axis = stem_axis_from_segment(load_xyz(axis_ply))
    elif up_axis != "z":
        axis = {"x": np.array([1.0, 0, 0]), "y": np.array([0, 1.0, 0])}[up_axis]
    if axis is not None:
        R = rotation_axis_to_z(axis)
        xyz = xyz_orig @ R.T
    else:
        R = np.eye(3)
        xyz = xyz_orig
    xy = xyz[:, :2]

    circ = fit_circle_kasa(xy)
    cov = angular_coverage_deg(xy, circ["cx"], circ["cy"])
    row = {
        "tree_id": tree_id or os.path.splitext(os.path.basename(path))[0],
        "slice_file": os.path.basename(path),
        "dab_height_m": dab_height,
        "slice_thickness_m": slice_thickness if slice_height is not None else None,
        "n_points": n,
        "coverage_deg": round(cov, 1),
        "circle_diameter_cm": round(circ["circle_diameter_cm"], 2),
        "circle_circumference_cm": round(circ["circle_circumference_cm"], 2),
        "circle_rms_mm": round(circ["circle_rms_mm"], 2),
    }
    # hull only valid on well-closed rings
    if cov >= 270:
        row.update({k: round(v, 2) for k, v in hull_perimeter(xy).items()})
        row["hull_valid"] = True
    else:
        row["hull_circumference_cm"] = None
        row["hull_equiv_diameter_cm"] = None
        row["hull_valid"] = False
    row["low_confidence"] = bool(cov < 270 or circ["circle_rms_mm"] > 20)

    # Optional: write the see-able output bundle (2D fig + 3D overlays + txt).
    if viz_dir:
        write_slice_bundle(viz_dir, row["tree_id"], xyz_orig, xy,
                           float(xyz[:, 2].mean()), circ, row, R)
    return row


def main():
    ap = argparse.ArgumentParser(description="Fit DAB from trunk-slice point clouds.")
    ap.add_argument("path", nargs="?", default=None,
                    help="A .ply slice, or a folder (with --batch). Not used with --from-sheet.")
    ap.add_argument("--batch", action="store_true", help="Treat path as a folder of *.ply.")
    ap.add_argument("--from-sheet", action="store_true",
                    help="Batch-run using the CONFIG block at the top of this file: read tree "
                         "ID/height/ply-path from SHEET_PATH and loop over every row instead of "
                         "the positional path/--tree-id/--slice-height arguments. Results are "
                         "both appended to --out (if given) and written back into SHEET_PATH's "
                         "OUTPUT_COL.")
    ap.add_argument("--tree-id", default=None)
    ap.add_argument("--dab-height", type=float, default=None, help="Slice height above base (m).")
    ap.add_argument("--up-axis", choices=["x", "y", "z"], default="z",
                    help="Which axis is the trunk/up axis. ForestScanner (ARKit) clouds "
                         "are Y-up -> use 'y'. Slicing uses this axis; the circle is fit "
                         "in the other two. Default 'z' (standard Z-up).")
    ap.add_argument("--slice-height", type=float, default=None,
                    help="Height-slice mode: treat `path` as a whole trunk SECTION and cut "
                         "a band centred on this coordinate along --up-axis (m), matching "
                         "ITSMe/dab_itsme.R. Omit to fit a pre-cut slice/disc as-is.")
    ap.add_argument("--slice-height-z", type=float, default=None,
                    help="Back-compat alias for --slice-height (use with --up-axis z).")
    ap.add_argument("--slice-thickness", type=float, default=0.06,
                    help="Band thickness for --slice-height (m, default 0.06). Match the "
                         "--thickness passed to dab_itsme.R so both tools cut the same band.")
    ap.add_argument("--out", default=None, help="CSV to write/append results to.")
    ap.add_argument("--axis-ply", default=None,
                    help="Optional tall trunk-segment PLY used to estimate the stem "
                         "axis and correct for lean. Omit for near-vertical stems.")
    ap.add_argument("--viz-dir", default=None,
                    help="If set, write a per-slice output bundle (2D fit PNG, 3D "
                         "circle+hull overlay PLYs, slice cloud, measure.txt) under "
                        "<viz-dir>/<tree_id>/. Point this at whatever folder you keep visual QC output in.")
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
                row = analyze_slice(m["path"], m["tree_id"], args.dab_height, args.axis_ply,
                                    args.viz_dir, m["height"],
                                    args.slice_thickness, args.up_axis)
                rows.append(row)
                flag = "  ** LOW CONFIDENCE **" if row["low_confidence"] else ""
                print(f"{row['tree_id']:<14} "
                      f"D_circle={row['circle_diameter_cm']:.1f} cm  "
                      f"C_hull={row['hull_circumference_cm']}  "
                      f"cov={row['coverage_deg']:.0f}deg  "
                      f"rms={row['circle_rms_mm']:.1f}mm{flag}")
                if row["hull_equiv_diameter_cm"] is not None:
                    updates.append((m["row"], round(row["hull_equiv_diameter_cm"] * 10, 1)))
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
                slice_height = (args.slice_height if args.slice_height is not None
                                else args.slice_height_z)
                row = analyze_slice(f, args.tree_id, args.dab_height, args.axis_ply,
                                    args.viz_dir, slice_height,
                                    args.slice_thickness, args.up_axis)
                rows.append(row)
                flag = "  ** LOW CONFIDENCE **" if row["low_confidence"] else ""
                print(f"{row['tree_id']:<14} "
                      f"D_circle={row['circle_diameter_cm']:.1f} cm  "
                      f"C_hull={row['hull_circumference_cm']}  "
                      f"cov={row['coverage_deg']:.0f}deg  "
                      f"rms={row['circle_rms_mm']:.1f}mm{flag}")
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
