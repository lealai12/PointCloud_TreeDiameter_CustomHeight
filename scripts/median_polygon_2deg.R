#!/usr/bin/env Rscript
# =============================================================================
# median_polygon_2deg.R  --  convex hull of a MEDIAN-RADIUS surface polygon
# (R), fixed 2-degree angular bins.
#
# FIXED-DEGREE vs. FIXED-ARC-LENGTH: TWO STANDALONE VARIANTS
# ------------------------------------------------------------
# This is the original fixed-angular-bin variant of median_polygon.R, kept as
# its own script rather than folded behind a flag: scripts/median_polygon.R
# (no "_2deg" suffix) is a SEPARATE, independent script that bins by a fixed
# ARC LENGTH (default 10mm) instead of a fixed angle -- see that script's
# header for the full reasoning. Both are kept available on purpose: the
# goal is to make the best method available, not to silently overwrite an
# earlier choice.
#
# The plain `median_polygon.R` name is deliberately kept on the arc-length
# variant rather than this one, even on datasets where this fixed-degree
# variant happens to score slightly better, because this script's bin width
# scales silently with object size (a constant angular bin covers far more
# arc on a large object than a small one) where the arc-length variant stays
# predictable across a wide size range. Use this script explicitly (by its
# full, suffixed name) when you specifically want fixed-degree behavior;
# reach for the plain name otherwise.
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
# MEDIAN SURFACE POLYGON --
#   1. bin the slice points by angle around the ring centroid (default 2 deg
#      bins),
#   2. take the MEDIAN radius within each bin (a median ignores a single
#      outlier the same way it always does; one stray point can pull a raw
#      convex hull outward, but it cannot pull a per-bin MEDIAN outward),
#   3. connect the per-bin (angle, median-radius) vertices in angular order
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
# median-radius polygon" (this script) agree. Where they diverge, that slice
# likely has exactly the outlier-hull-vertex problem this script routes
# around.
#
# Gaps: an angular bin with zero points (occlusion, or a bin narrower than
# the point spacing) has no median. Its radius is filled by circular linear
# interpolation between the nearest populated bins on either side, so the
# polygon stays closed; n_bins_populated / max_gap_deg say how much of the
# ring is real vs interpolated, and coverage_deg (identical definition to
# dendro_tape.R, computed on the RAW points, not the bins) plus max_edge_frac
# on the final hull gate median_hull_valid exactly as in dendro_tape.R.
#
# Companion Python tool: scripts/median_polygon_2deg.py computes the same
# fixed-degree median-binned convex hull independently. Deliberately no
# shared code with dendro_tape.py/.R or fit_dab.py/dab_itsme.R (same project
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
#   Rscript scripts/median_polygon_2deg.R section.ply --tree-id 1234 --up-axis y \
#       --height 2.31 --thickness 0.06 --out results/median_polygon_r_2deg.csv
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
SHEET_PATH <- "C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"  # anonymized sheet -- .ply files are named with the same anonymized codes
SHEET_NAME <- 1                          # tab name (string) or 1-based index within SHEET_PATH
TREE_ID_COL <- "Tree_Tag"                # column holding each tree's ID
HEIGHT_COL <- NULL                       # NULL -> measure each .ply as an already-cut, already-
                                         # polished disc (the normal workflow for this script);
                                         # set to e.g. "Y_value_Dendrometer" to cut on the fly instead
OUTPUT_COL <- "Dendrometer_MedianPolygon_RScript_Diameter_mm"  # the 2deg (original) column
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working/Polished_Slices_ply"  # already-cut, polished discs
PLY_FILENAME_PATTERN <- "{tree_id}__{site}.ply"  # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern

MAX_EDGE_FRAC <- 0.5                            # same guard as dendro_tape.R

# ------------------------------------------------------------------ CLI parsing
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet

flag_names <- c("--tree-id", "--up-axis", "--height", "--thickness",
                "--bin-width-deg", "--min-coverage", "--out", "--poly-dir")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript median_polygon_2deg.R <section.ply> [--up-axis y] [--height <m>] ",
       "[--thickness 0.06] [--bin-width-deg 2] [--tree-id id] ",
       "[--out results/median_polygon_r_2deg.csv] [--poly-dir <dir>] ",
       "| --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id    <- get_flag("--tree-id",       if (is.na(path)) NA else tools::file_path_sans_ext(basename(path)))
up_axis    <- get_flag("--up-axis",       "y")                # ForestScanner clouds are Y-up
height     <- as.numeric(get_flag("--height", NA))            # picked coord along up-axis (m)
thickness  <- as.numeric(get_flag("--thickness", 0.06))
bin_width  <- as.numeric(get_flag("--bin-width-deg", 2))
min_cov    <- as.numeric(get_flag("--min-coverage", 270))
out        <- get_flag("--out", NULL)
poly_dir   <- get_flag("--poly-dir", NULL)   # if set, write polygon/hull PLYs here (see below)

# ------------------------------------------------------------------ visualization
# If poly_dir is set, write <tree_id>_median_polygon_2deg_r.ply (cyan, the
# median-binned surface polygon) and <tree_id>_median_hull_2deg_r.ply
# (magenta, its convex hull) for loading in CloudCompare beside the original
# disc/slice. `_2deg_r` suffix keeps these from colliding with
# median_polygon.py/.R's `_10mm`-suffixed output and with the Python `_py`
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
measure_one <- function(path, tree_id, up_axis, height, thickness, bin_width, min_cov, poly_dir) {
  # clean = FALSE is REQUIRED for point clouds -- see dendro_tape.R for why.
  mesh <- Rvcg::vcgImport(path, clean = FALSE, silent = TRUE)
  xyz  <- t(mesh$vb[1:3, , drop = FALSE])        # N x 3 matrix of X, Y, Z (metres)
  if (nrow(xyz) == 0) stop(sprintf("No points read from %s", path))

  up_idx    <- match(up_axis, c("x", "y", "z"))
  plane_idx <- setdiff(1:3, up_idx)

  # Same band-cutting convention as fit_dab.py / dendro_tape.py / dab_itsme.R.
  if (!is.na(height)) {
    coord <- xyz[, up_idx]
    keep  <- coord > (height - thickness / 2) & coord < (height + thickness / 2)
    xyz   <- xyz[keep, , drop = FALSE]
  }

  n <- nrow(xyz)
  if (n < 8) stop(sprintf("%s: only %d points in band -- too few to fit.", path, n))

  xy <- xyz[, plane_idx, drop = FALSE]           # project onto the cross-section plane

  # ------------------------------------------------------- median surface polygon
  cx <- mean(xy[, 1]); cy <- mean(xy[, 2])
  dx <- xy[, 1] - cx;  dy <- xy[, 2] - cy
  ang   <- atan2(dy, dx) %% (2 * pi)             # [0, 2*pi)
  radii <- sqrt(dx^2 + dy^2)

  n_bins    <- max(round(360 / bin_width), 3)
  bin_w_rad <- 2 * pi / n_bins
  bin_idx   <- pmin(floor(ang / bin_w_rad), n_bins - 1)          # 0-based bin index
  bin_centers <- (seq_len(n_bins) - 0.5) * bin_w_rad             # bin i (1-based) center

  med_r <- rep(NA_real_, n_bins)
  for (i in seq_len(n_bins)) {
    sel <- radii[bin_idx == (i - 1)]
    if (length(sel)) med_r[i] <- median(sel)
  }
  populated    <- !is.na(med_r)
  n_populated  <- sum(populated)
  if (n_populated == 0) {
    stop(sprintf("%s: no populated angular bins -- too few/too clustered points.", path))
  }

  # Circular linear interpolation for empty bins: extend the populated
  # (angle, radius) samples by +/- 2*pi so approx() wraps correctly across the
  # 0/2*pi seam, then fill every bin center.
  pop_ang <- bin_centers[populated]
  pop_r   <- med_r[populated]
  ord     <- order(pop_ang)
  pop_ang <- pop_ang[ord]; pop_r <- pop_r[ord]
  ext_ang <- c(pop_ang - 2 * pi, pop_ang, pop_ang + 2 * pi)
  ext_r   <- rep(pop_r, 3)
  filled_r <- approx(ext_ang, ext_r, xout = bin_centers, rule = 2)$y

  poly_xy <- cbind(cx + filled_r * cos(bin_centers), cy + filled_r * sin(bin_centers))
  max_gap_deg <- max_empty_run(populated) * bin_w_rad * 180 / pi

  # median polygon perimeter (informational -- NOT the primary metric)
  poly_loop <- rbind(poly_xy, poly_xy[1, ])
  poly_edges <- sqrt(rowSums(diff(poly_loop)^2))
  median_poly_per_m <- sum(poly_edges)

  # -------------------------------------------- convex hull of the median polygon
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
    write_ply_xyzrgb(file.path(poly_dir, sprintf("%s_median_polygon_2deg_r.ply", tree_id)),
                     poly_closed_3d, c(0, 200, 200))
    write_ply_xyzrgb(file.path(poly_dir, sprintf("%s_median_hull_2deg_r.ply", tree_id)),
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
    max_gap_deg                     = round(max_gap_deg, 1),
    coverage_deg                    = round(cov_deg, 1),
    max_edge_frac                   = round(max_edge_frac, 3),
    median_polygon_circumference_cm = round(100 * median_poly_per_m, 2),
    median_polygon_diameter_cm      = round(100 * median_poly_per_m / pi, 2),
    median_hull_circumference_cm    = round(100 * hull_per_m, 2),
    median_hull_equiv_diameter_cm   = round(100 * equiv_diam_m, 2),
    median_hull_valid               = valid,
    stringsAsFactors                = FALSE
  )
}

report_row <- function(row) {
  flag <- if (isTRUE(row$median_hull_valid)) "" else "  ** PARTIAL RING -- hull invalid **"
  cat(sprintf("%-14s C_medhull=%.1f cm  (C/pi diam=%.1f cm)  C_medpoly=%.1f cm  cov=%.0fdeg  bins=%d/%d%s\n",
              row$tree_id, row$median_hull_circumference_cm, row$median_hull_equiv_diameter_cm,
              row$median_polygon_circumference_cm, row$coverage_deg, row$n_bins_populated,
              row$n_bins, flag))
}

# ------------------------------------------------------------------------ run
if (from_sheet) {
  source("scripts/sheet_batch.R")
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
  for (m in manifest) {
    h <- if (is.null(HEIGHT_COL)) NA_real_ else m$height
    result <- tryCatch(
      measure_one(m$path, m$tree_id, up_axis, h, thickness, bin_width, min_cov, poly_dir),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    if (isTRUE(result$median_hull_valid)) {
      updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$median_hull_equiv_diameter_cm * 10, 1))
    } else {
      cat(sprintf("[skip write-back] %s: hull invalid (partial ring), nothing to write\n", m$tree_id))
    }
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, tree_id, up_axis, height, thickness, bin_width, min_cov, poly_dir)
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
