#!/usr/bin/env Rscript
# =============================================================================
# bin_fixed_angle.R  --  convex hull of a PERCENTILE-RADIUS surface polygon
# (R), fixed 2-degree angular bins.
#
# FIXED-DEGREE vs. FIXED-ARC-LENGTH: TWO STANDALONE VARIANTS
# ------------------------------------------------------------
# This is the original fixed-angular-bin variant of bin_mean_distance_radius.R, kept as
# its own script rather than folded behind a flag: scripts/bin_mean_distance_radius.R
# (no "_2deg" suffix) is a SEPARATE, independent script that bins by a fixed
# ARC LENGTH (default 10mm) instead of a fixed angle -- see that script's
# header for the full reasoning. Both are kept available on purpose: the
# goal is to make the best method available, not to silently overwrite an
# earlier choice.
#
# This script's bin width scales with object size (a constant angular bin
# covers far more arc on a large object than a small one), where
# bin_mean_distance_radius.R's fixed arc-length bin stays predictable across a
# wide size range. That is a real difference in behaviour, not a ranking:
# neither variant is the default and neither supersedes the other. On this
# project's own validated subset the two scored virtually identically, with
# this fixed-degree variant marginally ahead -- a result specific to that
# dataset. Run both against your own data and choose on your own numbers.
#
# WHAT THIS MEASURES (and why)
# ----------------------------
# scripts/dendro_tape.R argues a taut tape/dendrometer band traces the CONVEX
# HULL of the raw slice points, and that is still true here. What this script
# targets is a known weakness of that raw-point hull: a convex hull is NOT
# outlier-robust -- a single stray point left in an imperfectly cleaned
# slice ring can itself become a hull vertex and inflate the tape reading.
#
# The fix: denoise the ring before taking the hull, by resampling it into a
# PERCENTILE SURFACE POLYGON --
#   1. bin the slice points by angle around the ring centroid (default 2 deg
#      bins),
#  2. take a high PERCENTILE of the radius within each bin (PERCENTILE in
#     CONFIG, default 90; 50 = the median used in the first pass). A high
#     percentile sits near the outer bark surface, where a tape rides; the
#     median sat part-way through the band of bark points and read small.
#     A bin with fewer than MIN_POINTS_PER_BIN points is treated as empty
#     (QC, counted in n_bins_sparse), so a sparse bin cannot set its own
#     radius from one or two stray points,
#   3. connect the per-bin (angle, percentile-radius) vertices in angular order
#      into a closed polygon -- this traces the real trunk surface, flutes
#      and all, so it is reported too (informational, NOT the primary metric;
#      conceptually adjacent to ITSMe's concave "functional" diameter, but
#      computed completely independently),
#   4. take the CONVEX HULL of THAT polygon (not of the raw points) -- the
#      primary metric this script exists to produce: a taut-tape-style wrap
#      that is robust to single-point noise because it wraps a denoised
#      surface, not the raw cloud.
#
# This is a comparison tool, not a replacement: it exists to check whether
# "convex hull of the raw points" (dendro_tape.R) and "convex hull of the
# percentile-radius polygon" (this script) agree. Where they diverge, that slice
# likely has exactly the outlier-hull-vertex problem this script routes
# around.
#
# Gaps: an angular bin with zero points (occlusion, or a bin narrower than
# the point spacing) has no value. Its radius is filled by circular linear
# interpolation between the nearest populated bins on either side, so the
# polygon stays closed; n_bins_populated / max_gap_deg say how much of the
# ring is real vs interpolated, and coverage_deg (identical definition to
# dendro_tape.R, computed on the RAW points, not the bins) plus max_edge_frac
# on the final hull gate bin_hull_valid exactly as in dendro_tape.R.
#
# Companion Python tool: scripts/bin_fixed_angle.py computes the same
# fixed-degree percentile-binned convex hull independently. Deliberately no
# shared code with dendro_tape.py/.R or fit_dab.py/dab_itsme_concave_hull.R (same project
# convention: two independent implementations, compared only at the results
# stage).
#
# No lean correction here (no --axis-ply), matching dendro_tape.R's
# minimalism -- scoped to the same near-vertical/dendrometer-site comparisons
# dendro_tape.R targets, not the general leaning-stem case.
#
# USAGE
# -----
# Cut a band at a picked height on a SECTION (clouds are Y-up -> --up-axis y):
#   Rscript scripts/bin_fixed_angle.R section.ply --tree-id 1234 --up-axis y \
#       --height 2.31 --thickness 0.06 --out results/bin_fixed_angle_r.csv
# Measure an already-cut thin slice/disc as-is: omit --height.
# =============================================================================

suppressMessages(library(Rvcg))     # PLY reader (independent of Python; no ITSMe needed)

# =============================================================================
# CONFIG -- edit these for your own dataset before running with --from-sheet.
# Ignored otherwise (single-file CLI usage below is unaffected).
#
# This is the "point at your own spreadsheet and column names" section: a
# future researcher with a differently-shaped manifest only has to edit the
# values below, not the measurement code (measure_one() etc.), to run this
# script's --from-sheet batch mode against their own project. See also
# scripts/sheet_batch.R, which this block's values get handed to.
# =============================================================================
SHEET_PATH <- "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx"  # the working sheet; Tree_Tag matches the .ply file names
SHEET_NAME <- 1                          # tab name (string) or 1-based index within SHEET_PATH
TREE_ID_COL <- "Tree_Tag"                # column holding each tree's ID
HEIGHT_COL <- NULL                       # NULL -> measure each .ply as an already-cut, already-
                                         # polished disc (the normal workflow for this script);
                                         # set to e.g. "Y_value_Dendrometer" to cut on the fly instead
OUTPUT_COL <- "Dendrometer_BinFixedAngle_RScript_Diameter_mm"  # the fixed-angle column
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"  # step 5 output: polished slices, <tag>__<Site>.ply
PLY_FILENAME_PATTERN <- "{tree_id}__{site}.ply"  # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern
FLAG_COL <- "Dendrometer_BinFixedAngle_MaxEdgeFrac"  # the gap check, as a NUMBER, not a veto: longest hull
                                         # edge / equivalent diameter. > MAX_EDGE_FRAC (0.5) is
                                         # the flag, but the diameter is written either way so the
                                         # threshold can be revisited in analysis. NULL to skip.

# ---- method settings (each is also overridable on the command line) ----
PERCENTILE <- 90                         # radius percentile taken inside each angular bin, measured
                                         # from the ring centroid. 50 = the median (the first-pass
                                         # method). Higher sits nearer the outer bark surface, where
                                         # a tape rides. Chosen in advance (2026-09-22), not tuned.
MIN_POINTS_PER_BIN <- 10                 # QC: a bin with fewer points than this is treated as EMPTY
                                         # and filled from its neighbours, like a bin with no points.
                                         # Counted in n_bins_sparse. 1 = use any bin with a point.

MAX_EDGE_FRAC <- 0.5                            # same guard as dendro_tape.R

# ------------------------------------------------------------------ CLI parsing
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet

flag_names <- c("--tree-id", "--up-axis", "--height", "--thickness",
                "--bin-width-deg", "--min-coverage", "--out", "--poly-dir",
                "--percentile", "--min-points")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript bin_fixed_angle.R <section.ply> [--up-axis y] [--height <m>] ",
       "[--thickness 0.06] [--bin-width-deg 2] [--tree-id id] ",
       "[--out results/bin_fixed_angle_r.csv] [--poly-dir <dir>] ",
       "| --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id    <- get_flag("--tree-id",       if (is.na(path)) NA else tools::file_path_sans_ext(basename(path)))
up_axis    <- get_flag("--up-axis",       "y")                # ForestScanner clouds are Y-up
height     <- as.numeric(get_flag("--height", NA))            # picked coord along up-axis (m)
thickness  <- as.numeric(get_flag("--thickness", 0.06))
bin_width  <- as.numeric(get_flag("--bin-width-deg", 2))
min_cov    <- as.numeric(get_flag("--min-coverage", 270))
percentile <- as.numeric(get_flag("--percentile", PERCENTILE))   # 50 = median
min_points <- as.integer(get_flag("--min-points", MIN_POINTS_PER_BIN))
out        <- get_flag("--out", NULL)
poly_dir   <- get_flag("--poly-dir", NULL)   # if set, write polygon/hull PLYs here (see below)

# ------------------------------------------------------------------ visualization
# If poly_dir is set, write <tree_id>_bin_polygon_fixed_angle_r.ply (cyan, the
# percentile-binned surface polygon) and <tree_id>_bin_hull_fixed_angle_r.ply
# (magenta, its convex hull) for loading in CloudCompare beside the original
# disc/slice. `_fixed_angle_r` suffix keeps these from colliding with
# bin_mean_distance_radius.py/.R's `_mean_distance_radius` output and with the Python `_py`
# variant when both are pointed at the same folder.
write_ply_xyzrgb <- function(path, xyz3, rgb) {
  # xyz3: N x 3 matrix; rgb: length-3 vector (0-255), applied to every row.
  # Ascii PLY, minimal writer -- duplicated rather than shared with the Python
  # side so the two scripts stay independent (see module docstring).
  n <- nrow(xyz3)
  header <- c("ply", "format ascii 1.0", sprintf("element vertex %d", n),
              "property float x", "property float y", "property float z",
              "property uchar red", "property uchar green", "property uchar blue",
              "end_header")
  body <- sprintf("%.6f %.6f %.6f %d %d %d",
                   xyz3[, 1], xyz3[, 2], xyz3[, 3], rgb[1], rgb[2], rgb[3])
  writeLines(c(header, body), path)
}

plane_xy_to_3d <- function(xy2, up_val, up_idx, plane_idx) {
  out <- matrix(0, nrow = nrow(xy2), ncol = 3)
  out[, plane_idx[1]] <- xy2[, 1]
  out[, plane_idx[2]] <- xy2[, 2]
  out[, up_idx] <- up_val
  out
}

# Longest run of consecutive empty bins, circular (wraps past the last bin
# back to the first) -- how much of the ring is interpolated, not measured.
max_empty_run <- function(pop) {
  n <- length(pop)
  if (all(pop)) return(0L)
  if (!any(pop)) return(n)
  start <- which(pop)[1]
  m <- pop[c(start:n, seq_len(start - 1))]      # rotate to start on a populated bin
  best <- cur <- 0L
  for (v in m) {
    if (v) cur <- 0L else { cur <- cur + 1L; best <- max(best, cur) }
  }
  best
}

# --------------------------------------------------------------------- measure
# Measures ONE tree/site and returns its result row. Pulled out into its own
# function so both the single-file CLI path and --from-sheet's loop over the
# manifest call the identical measurement logic.
measure_one <- function(path, tree_id, up_axis, height, thickness, bin_width, min_cov, poly_dir,
                        percentile = PERCENTILE, min_points = MIN_POINTS_PER_BIN) {
  # clean = FALSE is REQUIRED for point clouds -- see dendro_tape.R for why.
  mesh <- Rvcg::vcgImport(path, clean = FALSE, silent = TRUE)
  xyz  <- t(mesh$vb[1:3, , drop = FALSE])        # N x 3 matrix of X, Y, Z (metres)
  if (nrow(xyz) == 0) stop(sprintf("No points read from %s", path))

  up_idx    <- match(up_axis, c("x", "y", "z"))
  plane_idx <- setdiff(1:3, up_idx)

  # Same band-cutting convention as fit_dab.py / dendro_tape.py / dab_itsme_concave_hull.R.
  if (!is.na(height)) {
    coord <- xyz[, up_idx]
    keep  <- coord > (height - thickness / 2) & coord < (height + thickness / 2)
    xyz   <- xyz[keep, , drop = FALSE]
  }

  n <- nrow(xyz)
  if (n < 8) stop(sprintf("%s: only %d points in band -- too few to fit.", path, n))

  xy <- xyz[, plane_idx, drop = FALSE]           # project onto the cross-section plane

  # ------------------------------------------------------- percentile surface polygon
  cx <- mean(xy[, 1]); cy <- mean(xy[, 2])
  dx <- xy[, 1] - cx;  dy <- xy[, 2] - cy
  ang   <- atan2(dy, dx) %% (2 * pi)             # [0, 2*pi)
  radii <- sqrt(dx^2 + dy^2)

  n_bins    <- max(round(360 / bin_width), 3)
  bin_w_rad <- 2 * pi / n_bins
  bin_idx   <- pmin(floor(ang / bin_w_rad), n_bins - 1)          # 0-based bin index
  bin_centers <- (seq_len(n_bins) - 0.5) * bin_w_rad             # bin i (1-based) center

  bin_r    <- rep(NA_real_, n_bins)
  n_sparse <- 0                                 # bins with some points, but fewer than min_points
  for (i in seq_len(n_bins)) {
    sel <- radii[bin_idx == (i - 1)]
    if (length(sel) >= min_points) {
      bin_r[i] <- stats::quantile(sel, percentile / 100, type = 7, names = FALSE)  # type 7 = numpy default
    } else if (length(sel)) {
      n_sparse <- n_sparse + 1
    }
  }
  populated    <- !is.na(bin_r)
  n_populated  <- sum(populated)
  if (n_populated == 0) {
    stop(sprintf("%s: no populated angular bins -- too few/too clustered points.", path))
  }

  # Circular linear interpolation for empty bins: extend the populated
  # (angle, radius) samples by +/- 2*pi so approx() wraps correctly across the
  # 0/2*pi seam, then fill every bin center.
  pop_ang <- bin_centers[populated]
  pop_r   <- bin_r[populated]
  ord     <- order(pop_ang)
  pop_ang <- pop_ang[ord]; pop_r <- pop_r[ord]
  ext_ang <- c(pop_ang - 2 * pi, pop_ang, pop_ang + 2 * pi)
  ext_r   <- rep(pop_r, 3)
  filled_r <- approx(ext_ang, ext_r, xout = bin_centers, rule = 2)$y

  poly_xy <- cbind(cx + filled_r * cos(bin_centers), cy + filled_r * sin(bin_centers))
  max_gap_deg <- max_empty_run(populated) * bin_w_rad * 180 / pi

  # percentile polygon perimeter (informational -- NOT the primary metric)
  poly_loop <- rbind(poly_xy, poly_xy[1, ])
  poly_edges <- sqrt(rowSums(diff(poly_loop)^2))
  bin_poly_per_m <- sum(poly_edges)

  # -------------------------------------------- convex hull of the percentile polygon
  # (same taut-tape construction as dendro_tape.R, applied to poly_xy not raw xy)
  h         <- grDevices::chull(poly_xy)
  hull_loop <- poly_xy[c(h, h[1]), , drop = FALSE]
  hull_edges <- sqrt(rowSums(diff(hull_loop)^2))
  hull_per_m <- sum(hull_edges)
  equiv_diam_m <- hull_per_m / pi
  max_edge_frac <- if (equiv_diam_m > 0) max(hull_edges) / equiv_diam_m else Inf

  if (!is.null(poly_dir)) {
    dir.create(poly_dir, showWarnings = FALSE, recursive = TRUE)
    up_val <- mean(xyz[, up_idx])
    poly_closed_3d <- plane_xy_to_3d(rbind(poly_xy, poly_xy[1, ]), up_val, up_idx, plane_idx)
    hull_loop_3d   <- plane_xy_to_3d(hull_loop, up_val, up_idx, plane_idx)
    write_ply_xyzrgb(file.path(poly_dir, sprintf("%s_bin_polygon_fixed_angle_r.ply", tree_id)),
                     poly_closed_3d, c(0, 200, 200))
    write_ply_xyzrgb(file.path(poly_dir, sprintf("%s_bin_hull_fixed_angle_r.ply", tree_id)),
                     hull_loop_3d, c(200, 0, 200))
  }

  # QC: angular coverage -- identical definition to dendro_tape.R's, computed
  # on the RAW points so the two scripts' coverage_deg numbers are comparable.
  ang_sorted <- sort(atan2(dy, dx))
  gaps    <- diff(c(ang_sorted, ang_sorted[1] + 2 * pi))
  cov_deg <- (2 * pi - max(gaps)) * 180 / pi
  valid   <- cov_deg >= min_cov & max_edge_frac <= MAX_EDGE_FRAC

  data.frame(
    tree_id                         = tree_id,
    slice_file                      = basename(path),
    up_axis                         = up_axis,
    height_m                        = if (is.na(height)) NA else round(height, 4),
    slice_thickness_m               = if (is.na(height)) NA else thickness,
    n_points                        = n,
    bin_width_deg                   = bin_width,
    n_bins                          = n_bins,
    n_bins_populated                = n_populated,
    n_bins_sparse                   = n_sparse,
    percentile                      = percentile,
    min_points_per_bin              = min_points,
    max_gap_deg                     = round(max_gap_deg, 1),
    coverage_deg                    = round(cov_deg, 1),
    max_edge_frac                   = round(max_edge_frac, 3),
    bin_polygon_circumference_cm = round(100 * bin_poly_per_m, 2),
    bin_polygon_diameter_cm      = round(100 * bin_poly_per_m / pi, 2),
    bin_hull_circumference_cm    = round(100 * hull_per_m, 2),
    bin_hull_equiv_diameter_cm   = round(100 * equiv_diam_m, 2),
    bin_hull_valid               = valid,
    stringsAsFactors                = FALSE
  )
}

report_row <- function(row) {
  flag <- if (isTRUE(row$bin_hull_valid)) "" else "  ** PARTIAL RING -- hull invalid **"
  cat(sprintf("%-14s C_binhull=%.1f cm  (C/pi diam=%.1f cm)  C_binpoly=%.1f cm  cov=%.0fdeg  bins=%d/%d%s\n",
              row$tree_id, row$bin_hull_circumference_cm, row$bin_hull_equiv_diameter_cm,
              row$bin_polygon_circumference_cm, row$coverage_deg, row$n_bins_populated,
              row$n_bins, flag))
}

# ------------------------------------------------------------------------ run
if (from_sheet) {
  source("scripts/sheet_batch.R")   # cwd-relative: run from the repo root
  manifest <- load_manifest(
    sheet_path = SHEET_PATH, sheet_name = SHEET_NAME, tree_id_col = TREE_ID_COL,
    height_col = HEIGHT_COL, ply_folder = PLY_FOLDER,
    ply_filename_pattern = PLY_FILENAME_PATTERN, site_label = SITE_LABEL
  )
  if (length(manifest) == 0) {
    stop("No rows to process -- check the CONFIG block values at the top of this file.")
  }
  rows <- list()
  updates <- list()
  flag_updates <- list()   # (row, max_edge_frac) -> FLAG_COL
  for (m in manifest) {
    h <- if (is.null(HEIGHT_COL)) NA_real_ else m$height
    result <- tryCatch(
      measure_one(m$path, m$tree_id, up_axis, h, thickness, bin_width, min_cov, poly_dir,
                  percentile, min_points),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    # The gap check FLAGS, it does not block: write the diameter either way and
    # record max_edge_frac alongside it (see FLAG_COL).
    # whole mm at the sheet only: the field readings are integer mm.
    updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$bin_hull_equiv_diameter_cm * 10))
    flag_updates[[length(flag_updates) + 1]] <- list(row = m$row, value = round(result$max_edge_frac, 3))
    if (!isTRUE(result$bin_hull_valid)) {
      cat(sprintf("[flagged] %s: partial ring (max_edge_frac=%.3f) -- written, but check it\n",
                  m$tree_id, result$max_edge_frac))
    }
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  if (!is.null(FLAG_COL) && length(flag_updates)) {
    write_back_all(SHEET_PATH, SHEET_NAME, FLAG_COL, flag_updates)
  }
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, tree_id, up_axis, height, thickness, bin_width, min_cov, poly_dir,
                  percentile, min_points)
  report_row(row)
  all_rows <- row
}

# ------------------------------------------------------------ write / append CSV
if (!is.null(out) && !is.null(all_rows) && nrow(all_rows) > 0) {
  dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
  append <- file.exists(out)                       # write the header only the first time
  utils::write.table(all_rows, out, sep = ",", row.names = FALSE,
                     col.names = !append, append = append, qmethod = "double")
  cat(sprintf("Wrote %d row(s) -> %s\n", nrow(all_rows), out))
}
