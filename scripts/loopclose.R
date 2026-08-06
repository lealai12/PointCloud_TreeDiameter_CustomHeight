#!/usr/bin/env Rscript
# loopclose.R -- Register drift-offset scan fragments into one closed cloud.
# R port of loopclose.py, for a Python-free RStudio workflow.
#
# WHAT THIS IS FOR (same problem as loopclose.py)
# ------------------------------------------------
# When a single mobile-LiDAR capture (e.g. an ARKit-based scanner) loses
# SLAM tracking partway through a circumferential pass around an object, the
# wrap doesn't close -- the start/end edges (or a mid-loop band) image the
# same surface but sit offset by accumulated drift. Cut the offending arcs
# into separate fragment PLYs (e.g. in CloudCompare), then use this script
# to register and merge them back into one cloud.
#
# HOW THIS DIFFERS FROM loopclose.py -- READ BEFORE RELYING ON THIS
# -------------------------------------------------------------------
# loopclose.py needs no initial guess: it coarse-aligns each fragment with
# RANSAC global registration on FPFH features, THEN refines with ICP. R has
# no equivalent to Open3D's FPFH/RANSAC global registration -- nothing in
# this project's R dependency chain (including Rvcg) provides feature-based,
# initial-guess-free registration. This script instead skips a coarse step
# entirely and refines directly with plain point-to-point rigid ICP
# (Kabsch/SVD) on the fragments' AS-EXPORTED coordinates, correspondences
# capped at --max-corr-dist exactly like the Python version's guard against
# a partial flap dragging onto the wrong surface.
#
# This relies on fragments cut from the SAME continuous ARKit capture
# already sharing a coordinate frame -- the drift this script fixes is a
# moderate accumulated offset, not an arbitrary unknown pose, so as-exported
# coordinates are already a reasonable ICP starting point. (An earlier
# version of this script added a centroid-matching "coarse" step before
# ICP; testing showed that actively HURTS here, since two different partial
# arcs of the same ring have different centroids even with zero drift
# between them -- centroid matching assumes near-total overlap, which is
# exactly the case this script does NOT have. Removed rather than kept as a
# false safety net.)
#
# Because there's no feature-based global search, this is NOT a general-
# purpose registration method: it can only recover a good alignment when the
# fragments are already close in the same frame. If a fragment pair starts
# far apart, mis-rotated, or mirrored, this script can converge to the wrong
# alignment without an obvious error (fitness/RMS can look plausible while
# being wrong) -- sanity-check the actual merged geometry (e.g. reopen
# stitched/<tag>.ply in CloudCompare) before trusting a join this script
# made, more so than you would for the Python version. If you have Python
# available, prefer loopclose.py; use this only when you don't.
#
# Usage
# -----
#   Rscript scripts/loopclose.R arcA.ply arcB.ply --tag mytree
#   Rscript scripts/loopclose.R "work/mytree_*.ply" --tag mytree --voxel 0.01 --max-corr-dist 0.02
#
# INPUT LOCATION NOTE: don't read arc pieces from a read-only "raw export"
# source folder -- cut the arcs and save them to a working folder first.
# Output always goes to --out-dir (default stitched/), never back over an input.
# =============================================================================
suppressMessages(library(Rvcg))

# --------------------------------------------------------------------- args
args <- commandArgs(trailingOnly = TRUE)
get_flag <- function(name, default = NULL) {
  i <- which(args == name)
  if (length(i) == 0) return(default)
  args[i + 1]
}
has_flag <- function(name) name %in% args

if (length(args) == 0 || has_flag("--help") || has_flag("-h")) {
  cat("Usage: Rscript loopclose.R <fragment.ply> [<fragment2.ply> ...] --tag <id>\n",
      "  --voxel FLOAT          working voxel size in metres (default 0.01)\n",
      "  --max-corr-dist FLOAT  ICP max correspondence distance in metres (default 0.02)\n",
      "  --min-overlap FLOAT    warn if fitness falls below this (default 0.15)\n",
      "  --max-overlap FLOAT    warn if fitness exceeds this on a partial arc (default 0.90)\n",
      "  --out-dir PATH         output folder (default stitched/)\n")
  quit(status = if (length(args) == 0) 1 else 0)
}

flag_positions <- which(args %in% c("--tag", "--voxel", "--max-corr-dist",
                                     "--min-overlap", "--max-overlap", "--out-dir"))
value_positions <- flag_positions + 1
pieces_raw <- args[setdiff(seq_along(args), c(flag_positions, value_positions))]

tag           <- get_flag("--tag")
voxel         <- as.numeric(get_flag("--voxel", "0.01"))
max_corr_dist <- as.numeric(get_flag("--max-corr-dist", "0.02"))
min_overlap   <- as.numeric(get_flag("--min-overlap", "0.15"))
max_overlap   <- as.numeric(get_flag("--max-overlap", "0.90"))
out_dir       <- get_flag("--out-dir", "stitched")

if (is.null(tag)) stop("--tag is required.")

# Expand any globs the shell (or Windows) didn't.
paths <- unlist(lapply(pieces_raw, function(p) {
  hits <- Sys.glob(p)
  if (length(hits)) hits else p
}))
missing <- paths[!file.exists(paths)]
if (length(missing)) stop("Fragment file(s) not found: ", paste(missing, collapse = ", "))
if (any(vapply(paths, function(p) {
  norm <- gsub("\\\\", "/", p)
  identical(strsplit(norm, "/")[[1]][1], "raw_ply")
}, logical(1)))) {
  stop("Refusing to read from raw_ply/ (read-only field exports). ",
       "Save your cut arcs to a working folder first.")
}
if (length(paths) < 2) stop("Need at least 2 fragment PLYs to register.")

# ----------------------------------------------------------------------- IO
read_ply_xyz <- function(path) {
  mesh <- vcgImport(path, clean = FALSE, silent = TRUE)
  xyz <- t(mesh$vb[1:3, , drop = FALSE])
  if (nrow(xyz) == 0) stop(sprintf("%s: no points read.", path))
  xyz
}

write_ply_xyz <- function(xyz, path) {
  mesh <- list(vb = rbind(t(xyz), 1), it = matrix(integer(0), nrow = 3, ncol = 0))
  class(mesh) <- "mesh3d"
  vcgPlyWrite(mesh, path, binary = TRUE)
}

# Mean-per-occupied-cell voxel downsample -- same role as Open3D's
# voxel_down_sample: caps point density for ICP speed and, at the end, dedupes
# overlap between merged fragments.
voxel_downsample <- function(xyz, voxel) {
  cell <- floor(xyz / voxel)
  key <- paste(cell[, 1], cell[, 2], cell[, 3], sep = "_")
  agg <- rowsum(xyz, key) / as.vector(table(key)[match(unique(key), names(table(key)))])
  # rowsum's row order follows sort(unique(key)); recompute cleanly via split to avoid
  # relying on rowsum's internal ordering guarantees.
  idx <- split(seq_len(nrow(xyz)), key)
  t(vapply(idx, function(ix) colMeans(xyz[ix, , drop = FALSE]), numeric(3)))
}

# --------------------------------------------------------- rigid ICP (Kabsch)
# Closed-form optimal rotation+translation between two matched Nx3 point
# sets (Kabsch/Umeyama SVD solution, reflection-corrected). Point-to-point,
# not point-to-plane -- the one further simplification versus loopclose.py's
# TransformationEstimationPointToPlane, kept for simplicity since this
# script's coarse step is already the bigger fidelity gap.
kabsch <- function(src, tgt) {
  src_c <- colMeans(src); tgt_c <- colMeans(tgt)
  H <- t(src - matrix(src_c, nrow(src), 3, byrow = TRUE)) %*%
       (tgt - matrix(tgt_c, nrow(tgt), 3, byrow = TRUE))
  sv <- svd(H)
  d <- sign(det(sv$v %*% t(sv$u)))
  R <- sv$v %*% diag(c(1, 1, d)) %*% t(sv$u)
  t <- tgt_c - as.vector(R %*% src_c)
  list(R = R, t = t)
}

apply_transform <- function(xyz, tf) {
  t(tf$R %*% t(xyz) + tf$t)
}

# Iterative closest point, correspondences capped at max_corr_dist (the same
# guard loopclose.py's docstring explains -- without it, a small partial
# fragment gets dragged onto non-overlapping surface to satisfy a false
# 100%-overlap assumption). Returns the cumulative transform plus final
# fitness (inlier fraction) / inlier RMS, computed the same way as Open3D
# reports them.
icp_align <- function(src, tgt, max_corr_dist, max_iter = 60, tol = 1e-7) {
  cur <- src
  R_tot <- diag(3); t_tot <- c(0, 0, 0)
  prev_rmse <- Inf
  fitness <- 0; inlier_rmse <- NA_real_

  for (it in seq_len(max_iter)) {
    nn <- vcgKDtree(tgt, cur, k = 1)
    d <- as.vector(nn$distance)
    inliers <- d < max_corr_dist
    fitness <- mean(inliers)
    if (!any(inliers)) break
    inlier_rmse <- sqrt(mean(d[inliers]^2))

    tf <- kabsch(cur[inliers, , drop = FALSE], tgt[nn$index[inliers], , drop = FALSE])
    cur <- apply_transform(cur, tf)
    R_tot <- tf$R %*% R_tot
    t_tot <- as.vector(tf$R %*% t_tot + tf$t)

    if (abs(prev_rmse - inlier_rmse) < tol) break
    prev_rmse <- inlier_rmse
  }
  list(R = R_tot, t = t_tot, fitness = fitness, inlier_rmse = inlier_rmse)
}

# --------------------------------------------------------------------- driver
cat(sprintf("Loop-closing %d fragments for tree %s (R port -- direct ICP, no RANSAC/FPFH coarse step):\n",
            length(paths), tag))
for (p in paths) cat("  -", p, "\n")
cat(sprintf("  voxel=%.0f mm   max_corr_dist=%.0f mm\n\n", voxel * 1000, max_corr_dist * 1000))

body <- read_ply_xyz(paths[1])
body_down <- voxel_downsample(body, voxel)
logs <- list()

for (p in paths[-1]) {
  src <- read_ply_xyz(p)
  src_down <- voxel_downsample(src, voxel)

  # no coarse step -- see module header: relies on fragments already
  # sharing a coordinate frame (same ARKit capture), refines directly.
  fit <- icp_align(src_down, body_down, max_corr_dist)
  rms_mm <- 1000 * fit$inlier_rmse

  flag <- ""
  if (fit$fitness < min_overlap) {
    flag <- sprintf("  ** LOW fitness (<%.2f) -- join may not have locked **", min_overlap)
  } else if (fit$fitness > max_overlap) {
    flag <- sprintf("  ** HIGH fitness (>%.2f) on a partial arc -- check it didn't collapse onto the wrong surface (and, given this script's weaker coarse step, double-check the join visually) **", max_overlap)
  }
  cat(sprintf("[%s]  fitness=%.3f  inlier_RMS=%.1f mm%s\n",
              basename(p), fit$fitness, rms_mm, flag))
  logs[[length(logs) + 1]] <- list(fragment = basename(p),
                                    fitness = round(fit$fitness, 3),
                                    inlier_rms_mm = round(rms_mm, 2))

  # bake the ICP transform into the full-resolution fragment
  src_aligned <- apply_transform(src, list(R = fit$R, t = fit$t))
  body <- rbind(body, src_aligned)
  body_down <- voxel_downsample(body, voxel)
}

before <- nrow(body)
merged <- voxel_downsample(body, voxel)
cat(sprintf("\nMerged %s -> %s points after voxel dedupe.\n",
            format(before, big.mark = ","), format(nrow(merged), big.mark = ",")))

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, sprintf("%s.ply", tag))
write_ply_xyz(merged, out_path)
cat(sprintf("Wrote %s\n", out_path))

if (length(logs)) {
  worst <- logs[[which.max(vapply(logs, function(l) l$inlier_rms_mm, numeric(1)))]]
  cat(sprintf("\nWorst join: %s (%.1f mm, fitness %.3f)\n",
              worst$fragment, worst$inlier_rms_mm, worst$fitness))
  cat("Next: measure the band with dab_itsme.R (or fit_dab.py/fit_dab.R) and compare the\n",
      "circle-fit RMS against the manually-cleaned baseline. If registration can't tighten\n",
      "it further, this scan is a re-capture candidate -- or re-run with loopclose.py if\n",
      "Python is available, since its RANSAC/FPFH coarse step is more robust than this\n",
      "script's centroid-only alignment.\n", sep = "")
}
