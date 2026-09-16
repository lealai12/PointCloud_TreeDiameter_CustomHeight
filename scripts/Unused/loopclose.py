#!/usr/bin/env python3
"""
loopclose.py — Register drift-offset scan fragments into one closed cloud.

When a single mobile-LiDAR capture (e.g. an ARKit-based scanner like
ForestScanner) loses SLAM tracking partway through a circumferential pass
around an object, the wrap doesn't close — the start/end edges (or a
mid-loop band) image the same surface but sit offset by accumulated drift.
The manual fix is to cut the offending arcs into separate clouds (e.g. in
CloudCompare) and align them by hand-picked point pairs. This script does
the same alignment in code, for a reproducible / batch-able cross-check.

Given N fragment PLYs (the arcs you cut out), this:
  1. voxel-downsamples + estimates normals + FPFH features on each,
  2. coarse-aligns each fragment to the growing body with **RANSAC global
     registration** on FPFH feature matches (no initial guess needed),
  3. refines with **point-to-plane ICP** using an explicit
     `--max-corr-dist` and a realistic overlap expectation,
  4. merges + voxel-dedupes into one cloud -> stitched/<tag>.ply,
  5. logs per-pair fitness + inlier RMS so a bad join is obvious.

Usage
-----
    python loopclose.py arcA.ply arcB.ply --tag mytree
    python loopclose.py work/mytree_*.ply --tag mytree --voxel 0.01 --max-corr-dist 0.02

WHY THIS EXISTS / THE GOTCHA IT ENCODES
---------------------------------------
A naive ICP registration on a small, partial fragment can make things WORSE
than not registering at all: if it assumes **100% overlap** between a small
edge flap and a near-complete body, it will drag the flap to "match"
non-overlapping surface, inflating the join error rather than closing it.
The fix is to never assume full overlap: ICP here only corresponds points
within `--max-corr-dist`, and we report `fitness` (the inlier fraction). For
a partial arc you should EXPECT a low fitness (~0.2-0.3), not 1.0 — a
suspiciously high fitness on a small flap means it collapsed onto the wrong
surface. `--min-overlap`/`--max-overlap` just warn when fitness falls
outside the band you expect; they don't force anything.

INPUT LOCATION NOTE
--------------------
Don't read arc pieces from a read-only "raw export" source folder — cut the
arcs and save them to a working folder first, then point this script at
those. Output always goes to `stitched/`, never back over an input.
"""

from __future__ import annotations
import argparse
import glob
import os
import sys

import numpy as np

try:
    import open3d as o3d
except ImportError:
    sys.exit("Missing dependency: pip install open3d  (see requirements.txt)")


# ----------------------------------------------------------------------------- IO
def load_cloud(path: str) -> o3d.geometry.PointCloud:
    pcd = o3d.io.read_point_cloud(path)
    if len(pcd.points) == 0:
        raise ValueError(f"{path}: no points read.")
    return pcd


def preprocess(pcd: o3d.geometry.PointCloud, voxel: float):
    """Downsample, estimate normals, and compute FPFH features at `voxel` scale.

    Returns (downsampled_cloud, fpfh). Normal + feature radii follow the open3d
    global-registration convention (2x and 5x the voxel size)."""
    down = pcd.voxel_down_sample(voxel)
    down.estimate_normals(
        o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 2, max_nn=30))
    fpfh = o3d.pipelines.registration.compute_fpfh_feature(
        down, o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 5, max_nn=100))
    return down, fpfh


# ------------------------------------------------------------ pairwise registration
def coarse_ransac(src_down, tgt_down, src_fpfh, tgt_fpfh, voxel: float):
    """RANSAC global registration on FPFH matches — no initial pose needed.

    `distance_threshold` at 1.5x voxel is the standard open3d recipe; correspondences
    farther than this are rejected, so a small arc can't falsely match the far wall."""
    dist = voxel * 1.5
    return o3d.pipelines.registration.registration_ransac_based_on_feature_matching(
        src_down, tgt_down, src_fpfh, tgt_fpfh, mutual_filter=True,
        max_correspondence_distance=dist,
        estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPoint(False),
        ransac_n=3,
        checkers=[
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnEdgeLength(0.9),
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnDistance(dist),
        ],
        criteria=o3d.pipelines.registration.RANSACConvergenceCriteria(100000, 0.999))


def refine_icp(src, tgt, init_T, max_corr_dist: float):
    """Point-to-plane ICP refine, correspondences capped at `max_corr_dist`.

    The cap is the whole point (see module docstring): it is what stops a partial
    flap from being dragged onto non-overlapping bark. `tgt` must have normals."""
    if not tgt.has_normals():
        tgt.estimate_normals(
            o3d.geometry.KDTreeSearchParamHybrid(radius=max_corr_dist * 2, max_nn=30))
    return o3d.pipelines.registration.registration_icp(
        src, tgt, max_corr_dist, init_T,
        o3d.pipelines.registration.TransformationEstimationPointToPlane(),
        o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=200))


# --------------------------------------------------------------------------- driver
def loopclose(paths, tag, voxel, max_corr_dist, min_overlap, max_overlap, out_dir):
    if len(paths) < 2:
        sys.exit("Need at least 2 fragment PLYs to register.")

    print(f"Loop-closing {len(paths)} fragments for tree {tag}:")
    for p in paths:
        print(f"  - {p}")
    print(f"  voxel={voxel*1000:.0f} mm   max_corr_dist={max_corr_dist*1000:.0f} mm\n")

    # First fragment is the reference body; register each subsequent arc onto the
    # accumulated cloud, transform it into place, and merge.
    body = load_cloud(paths[0])
    body_down, body_fpfh = preprocess(body, voxel)
    merged = body           # full-resolution accumulator
    logs = []

    for i, p in enumerate(paths[1:], start=1):
        src = load_cloud(p)
        src_down, src_fpfh = preprocess(src, voxel)

        coarse = coarse_ransac(src_down, body_down, src_fpfh, body_fpfh, voxel)
        fine = refine_icp(src_down, body_down, coarse.transformation, max_corr_dist)

        rms_mm = 1000 * fine.inlier_rmse
        fit = fine.fitness
        flag = ""
        if fit < min_overlap:
            flag = f"  ** LOW fitness (<{min_overlap:.2f}) — join may not have locked **"
        elif fit > max_overlap:
            flag = (f"  ** HIGH fitness (>{max_overlap:.2f}) on a partial arc - "
                    "check it didn't collapse onto the wrong surface **")
        print(f"[{os.path.basename(p)}]  fitness={fit:.3f}  "
              f"inlier_RMS={rms_mm:.1f} mm{flag}")
        logs.append({"fragment": os.path.basename(p), "fitness": round(fit, 3),
                     "inlier_rms_mm": round(rms_mm, 2)})

        # Bake the transform into the full-res fragment and grow the body.
        src.transform(fine.transformation)
        merged += src
        body_down, body_fpfh = preprocess(merged, voxel)

    # Dedupe overlap: voxel-downsample the merged cloud at the working scale.
    before = len(merged.points)
    merged = merged.voxel_down_sample(voxel)
    print(f"\nMerged {before:,} -> {len(merged.points):,} points after voxel dedupe.")

    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{tag}.ply")
    o3d.io.write_point_cloud(out_path, merged)
    print(f"Wrote {out_path}")

    worst = max(logs, key=lambda r: r["inlier_rms_mm"]) if logs else None
    if worst:
        print(f"\nWorst join: {worst['fragment']} "
              f"({worst['inlier_rms_mm']:.1f} mm, fitness {worst['fitness']:.3f})")
        print("Next: measure the band with fit_dab.py and compare the circle-fit RMS "
              "against the manually-cleaned baseline. If registration can't tighten "
              "it further, this scan is a re-capture candidate.")
    return out_path, logs


def main():
    ap = argparse.ArgumentParser(
        description="Register drift-offset scan fragments into one closed cloud.")
    ap.add_argument("pieces", nargs="+",
                    help="Fragment PLYs (the arcs you cut out). Glob-expanded. "
                         "Don't pass files straight from a read-only raw-export folder.")
    ap.add_argument("--tag", required=True, help="Object/tree tag, used for the output name.")
    ap.add_argument("--voxel", type=float, default=0.01,
                    help="Working voxel size in METERS (default 0.01 = 1 cm). "
                         "Sets downsample + FPFH scale + final dedupe.")
    ap.add_argument("--max-corr-dist", type=float, default=0.02,
                    help="ICP max correspondence distance in METERS (default 0.02 = 2 cm). "
                         "Keep it tight — this is the guard against the 100%%-overlap "
                         "failure described in the module docstring.")
    ap.add_argument("--min-overlap", type=float, default=0.15,
                    help="Warn if ICP fitness (inlier fraction) falls below this.")
    ap.add_argument("--max-overlap", type=float, default=0.90,
                    help="Warn if fitness exceeds this on a partial arc (likely collapse).")
    ap.add_argument("--out-dir", default="stitched",
                    help="Output folder (default: stitched/). Never writes to raw_ply/.")
    args = ap.parse_args()

    # Expand any globs the shell didn't (Windows / quoted args).
    paths = []
    for pat in args.pieces:
        hits = sorted(glob.glob(pat))
        paths.extend(hits if hits else [pat])
    missing = [p for p in paths if not os.path.exists(p)]
    if missing:
        sys.exit("Fragment file(s) not found: " + ", ".join(missing))
    if any(os.path.normpath(p).split(os.sep)[0] == "raw_ply" for p in paths):
        sys.exit("Refusing to read from raw_ply/ (read-only field exports). "
                 "Save your cut arcs to a working folder first.")

    loopclose(paths, args.tag, args.voxel, args.max_corr_dist,
              args.min_overlap, args.max_overlap, args.out_dir)


if __name__ == "__main__":
    main()
