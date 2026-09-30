#!/usr/bin/env Rscript
# =============================================================================
# circle_fit.R  --  least-squares circle fit on a trunk slice (R).
#
# WHAT THIS MEASURES
# ------------------
# The diameter of the circle that best fits the slice points: an algebraic
# (Kasa) least-squares fit in the plane across the trunk axis (X-Z for Y-up
# ForestScanner clouds). It is the classic point-cloud stem diameter.
#
# A circle passes through the middle of the bark's bumps rather than wrapping
# round them, so on a fluted or buttressed trunk it tends to read below a hull
# or a tape. On a round trunk the circle, the hull and a tape agree. The RMS of
# the radial residuals is reported too, as a measure of how round the ring is.
#
# Companion Python tool: scripts/Step06_Measure/circle_fit.py fits the same
# circle independently. The two share no code; where they disagree, it flags a bug.
#
# USAGE
# -----
# Cut a band at a picked height on a SECTION (clouds are Y-up -> --up-axis y):
#   Rscript scripts/Step06_Measure/circle_fit.R section.ply --tree-id 1234 --up-axis y \
#       --height 2.31 --thickness 0.06 --out results/circle_fit.csv
# Measure an already-cut, polished slice as-is: omit --height.
# Batch a folder of *.ply (one row each):
#   Rscript scripts/Step06_Measure/circle_fit.R slices/ --batch --up-axis y --out results/circle_fit_R.csv
# =============================================================================

suppressMessages(library(Rvcg))     # PLY reader

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
OUTPUT_COL <- "Dendrometer_CircleFit_RScript_Diameter_mm"  # this script's own column
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"  # step 5 output: polished slices, <tag>__<Site>.ply
PLY_FILENAME_PATTERN <- "{tree_id}__{site}.ply"  # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern
FLAG_COL <- NULL                         # no gap flag of its own: the circle is fit to the same ring
                                         # dendro_tape measures, so analysis uses the DendroTape flag

# ------------------------------------------------------------------ CLI parsing
# Base-R flag parser: a positional <path> plus --tree-id --up-axis --height
# --thickness --out, and the switches --batch --from-sheet.
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet

flag_names <- c("--tree-id", "--up-axis", "--height", "--thickness", "--out")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
batch      <- has_flag("--batch")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript circle_fit.R <slice.ply> [--up-axis y] [--height <m>] ",
       "[--thickness 0.06] [--tree-id id] [--out results/circle_fit.csv] ",
       "| <folder> --batch | --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id   <- get_flag("--tree-id",   if (is.na(path) || batch) NA else tools::file_path_sans_ext(basename(path)))
up_axis   <- get_flag("--up-axis",   "y")                   # ForestScanner clouds are Y-up
height    <- as.numeric(get_flag("--height", NA))          # picked coord along up-axis (m)
thickness <- as.numeric(get_flag("--thickness", 0.06))
out       <- get_flag("--out", NULL)

# ------------------------------------------------------------------ the fit
# Algebraic (Kasa) least-squares circle: solve x^2 + y^2 = D x + E y + F by QR;
# centre (D/2, E/2), r^2 = F + cx^2 + cy^2.
fit_circle_kasa <- function(xy) {
  x <- xy[, 1]; y <- xy[, 2]
  coef <- qr.solve(cbind(x, y, 1), x^2 + y^2)
  cx <- coef[1] / 2; cy <- coef[2] / 2
  r  <- sqrt(max(coef[3] + cx^2 + cy^2, 0))
  list(cx = cx, cy = cy, r = r, rms_m = sqrt(mean((sqrt((x - cx)^2 + (y - cy)^2) - r)^2)))
}

# Largest covered arc (deg) about the fitted centre. A circle fit on a one-sided
# arc is poorly constrained, so low coverage is worth a look.
angular_coverage_deg <- function(xy, cx, cy) {
  ang  <- sort(atan2(xy[, 2] - cy, xy[, 1] - cx))
  gaps <- diff(c(ang, ang[1] + 2 * pi))          # angular gaps between neighbours
  (2 * pi - max(gaps)) * 180 / pi                # 360 minus the biggest gap
}

# --------------------------------------------------------------------- measure
measure_one <- function(path, tree_id, up_axis, height, thickness) {
  # clean = FALSE is REQUIRED for point clouds: the default strips "unreferenced"
  # vertices, and in a point cloud (no faces) every vertex is unreferenced.
  mesh <- Rvcg::vcgImport(path, clean = FALSE, silent = TRUE)
  xyz  <- t(mesh$vb[1:3, , drop = FALSE])        # N x 3 matrix of X, Y, Z (metres)
  if (nrow(xyz) == 0) stop(sprintf("No points read from %s", path))

  up_idx    <- match(up_axis, c("x", "y", "z"))
  plane_idx <- setdiff(1:3, up_idx)

  # Height-slice mode: cut the band [height - t/2, height + t/2] along the up axis,
  # the same window as dendro_tape.R. Omit height to measure a pre-cut slice as-is.
  if (!is.na(height)) {
    coord <- xyz[, up_idx]
    keep  <- coord > (height - thickness / 2) & coord < (height + thickness / 2)
    xyz   <- xyz[keep, , drop = FALSE]
  }

  n <- nrow(xyz)
  if (n < 8) stop(sprintf("%s: only %d points in band -- too few for a circle fit.", path, n))

  xy   <- xyz[, plane_idx, drop = FALSE]         # project onto the cross-section plane
  circ <- fit_circle_kasa(xy)

  data.frame(
    tree_id                 = tree_id,
    slice_file              = basename(path),
    method                  = "least-squares circle (Kasa)",
    up_axis                 = up_axis,
    height_m                = if (is.na(height)) NA else round(height, 4),
    slice_thickness_m       = if (is.na(height)) NA else thickness,
    n_points                = n,
    coverage_deg            = round(angular_coverage_deg(xy, circ$cx, circ$cy), 1),
    circle_rms_mm           = round(1000 * circ$rms_m, 2),
    circle_circumference_cm = round(100 * 2 * pi * circ$r, 2),
    circle_diameter_cm      = round(100 * 2 * circ$r, 2),
    stringsAsFactors        = FALSE
  )
}

report_row <- function(row) {
  cat(sprintf("%-14s D_circle=%.1f cm  rms=%.1f mm  cov=%.0fdeg\n",
              row$tree_id, row$circle_diameter_cm, row$circle_rms_mm, row$coverage_deg))
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
  for (m in manifest) {
    h <- if (is.null(HEIGHT_COL)) NA_real_ else m$height
    result <- tryCatch(
      measure_one(m$path, m$tree_id, up_axis, h, thickness),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    # whole mm at the sheet only: the field readings are integer mm. CSV keeps full precision.
    updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$circle_diameter_cm * 10))
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else if (batch) {
  files <- sort(list.files(path, pattern = "\\.ply$", full.names = TRUE))
  if (!length(files)) stop(sprintf("No PLY files found at: %s", path))
  rows <- list()
  for (f in files) {
    result <- tryCatch(
      measure_one(f, tools::file_path_sans_ext(basename(f)), up_axis, height, thickness),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", f, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
  }
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, tree_id, up_axis, height, thickness)
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
