#!/usr/bin/env Rscript
# =============================================================================
# fit_dab.R  --  independent R port of fit_dab.py, for a Python-free RStudio
# workflow. Same method, same metrics, ported line-for-line where the two
# languages allow: least-squares (Kasa) circle fit + convex-hull "tape"
# perimeter, optional PCA-based lean correction, coverage/RMS confidence
# flag, and the same --viz-dir output bundle (2D fit PNG, 3D circle/hull
# overlay PLYs, slice cloud, measure.txt).
#
# This is fit_dab.py's TRUE twin, in the same "two independent
# implementations, deliberately kept separate" sense as dendro_tape.py/.R and
# median_polygon.py/.R -- same measurement method, written independently in
# each language, so the two can be compared as a correctness cross-check.
# dab_itsme.R is a SEPARATE thing: it was always meant to be a different
# METHOD (ITSMe's own circle + concave-hull fit), not a port of fit_dab.py's
# method -- this file doesn't replace or change that, it fills the gap that
# fit_dab.py's own approach previously had no R equivalent at all.
#
# Two known, deliberate simplifications vs. fit_dab.py -- both because R's
# least-squares/eigen routines are numerically different implementations of
# the same math, not because the method itself changed:
#   - fit_circle_kasa() solves via qr.solve() (QR-based least squares)
#     instead of numpy's SVD-based lstsq -- both solve the identical Kasa
#     normal equations; expect numerical agreement to several decimal places,
#     not bit-for-bit identity.
#   - stem_axis_from_segment() uses base R's svd() instead of numpy's SVD --
#     same algorithm family, same elongation-ratio warning ported as-is.
#
# USAGE
# -----
# Cut a band at a picked height on a SECTION (clouds are Y-up -> --up-axis y):
#   Rscript scripts/fit_dab.R section.ply --tree-id 1234 --up-axis y \
#       --slice-height 2.31 --slice-thickness 0.06 --out results/fit_dab_r_results.csv
# Measure an already-cut thin slice/disc as-is: omit --slice-height.
# Whole folder of slices: --batch (path is a folder, one row per *.ply).
# Lean correction on a leaning stem: --axis-ply <tall_segment.ply> (a TALL
# trunk segment, at least ~2x the trunk diameter -- never a thin slice, see
# stem_axis_from_segment() below for why).
# Visual QC bundle: --viz-dir <folder>.
# =============================================================================

suppressMessages(library(Rvcg))     # PLY reader (independent of Python; no ITSMe needed)

# =============================================================================
# CONFIG -- edit these for your own dataset before running with --from-sheet.
# Ignored otherwise (single-file/--batch CLI usage below is unaffected).
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
HEIGHT_COL <- "Y_value_Dendrometer"      # column holding the picked cut height (m); swap to
                                         # Y_value_TopFlag / Y_value_LowerFlag for those sites
OUTPUT_COL <- "Dendrometer_FitDab_RScript_Diameter_mm"  # column the diameter (mm) is written into
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working/Final_Disc_ply"  # whole trunk SECTIONS, not pre-cut discs
PLY_FILENAME_PATTERN <- "{tree_id}.ply"  # {tree_id} required; {site} optional (see SITE_LABEL)
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern, if used

# ------------------------------------------------------------------ CLI parsing
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet, --batch

flag_names <- c("--tree-id", "--up-axis", "--dab-height", "--slice-height",
                "--slice-thickness", "--axis-ply", "--viz-dir", "--out")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
batch      <- has_flag("--batch")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript fit_dab.R <slice.ply> [--up-axis y] [--tree-id id] ",
       "[--slice-height <m>] [--slice-thickness 0.06] [--axis-ply <segment.ply>] ",
       "[--viz-dir <dir>] [--out results/fit_dab_r_results.csv] | --batch (path is a folder) ",
       "| --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id_arg      <- get_flag("--tree-id", NA)
up_axis          <- get_flag("--up-axis", "z")
dab_height_arg   <- as.numeric(get_flag("--dab-height", NA))
slice_height_arg <- as.numeric(get_flag("--slice-height", NA))
slice_thickness  <- as.numeric(get_flag("--slice-thickness", 0.06))
axis_ply         <- get_flag("--axis-ply", NA)
viz_dir          <- get_flag("--viz-dir", NA)
out              <- get_flag("--out", NULL)

# --------------------------------------------------------------- geometry helpers
cross3 <- function(a, b) c(a[2]*b[3] - a[3]*b[2], a[3]*b[1] - a[1]*b[3], a[1]*b[2] - a[2]*b[1])

# IMPORTANT: do NOT PCA a thin slice to find the stem axis -- a thin slab's
# largest-variance direction lies within the ring (the diameter), not along
# the stem, so it mangles the fit. Give this a TALL trunk segment (at least
# ~2x the trunk diameter in height) via --axis-ply; for near-vertical stems,
# skip lean correction entirely (the default).
stem_axis_from_segment <- function(seg_xyz) {
  Xc <- scale(seg_xyz, center = TRUE, scale = FALSE)
  sv <- svd(Xc)
  S <- sv$d
  if (S[1] < 1.3 * S[2]) {
    warning(sprintf(
      "axis segment not clearly elongated (s0/s1=%.2f); it may be too short relative to trunk diameter. Use a taller segment or drop --axis-ply.",
      S[1] / S[2]))
  }
  axis <- sv$v[, 1]
  axis / sqrt(sum(axis^2))
}

# 3x3 rotation matrix R sending `axis` onto +Z (Rodrigues' formula). Kept
# separate from the point-rotation below so it can also map fitted overlay
# geometry (ring/hull) BACK into the original coordinate frame -- otherwise
# a lean-corrected overlay wouldn't line up with the disc in CloudCompare.
rotation_axis_to_z <- function(axis) {
  axis <- axis / sqrt(sum(axis^2))
  z <- c(0, 0, 1)
  v <- cross3(axis, z)
  s <- sqrt(sum(v^2))
  cs <- sum(axis * z)
  if (s < 1e-12) return(if (cs > 0) diag(3) else diag(c(1, 1, -1)))
  vx <- matrix(c(0, v[3], -v[2], -v[3], 0, v[1], v[2], -v[1], 0), nrow = 3)
  diag(3) + vx + (vx %*% vx) * ((1 - cs) / (s^2))
}

# Algebraic (Kasa) least-squares circle fit on 2D points.
fit_circle_kasa <- function(xy) {
  x <- xy[, 1]; y <- xy[, 2]
  A <- cbind(x, y, 1)
  b <- x^2 + y^2
  coef <- qr.solve(A, b)
  cx <- coef[1] / 2; cy <- coef[2] / 2
  r <- sqrt(max(coef[3] + cx^2 + cy^2, 0))
  resid <- sqrt((x - cx)^2 + (y - cy)^2) - r
  list(cx = cx, cy = cy, r = r,
       circle_diameter_cm = 100 * 2 * r,
       circle_circumference_cm = 100 * 2 * pi * r,
       circle_rms_mm = 1000 * sqrt(mean(resid^2)))
}

# Largest covered arc (deg) about (cx, cy). Low coverage => one-sided/partial ring.
angular_coverage_deg <- function(xy, cx, cy) {
  ang <- sort(atan2(xy[, 2] - cy, xy[, 1] - cx))
  gaps <- diff(c(ang, ang[1] + 2 * pi))
  (2 * pi - max(gaps)) * 180 / pi
}

# Convex-hull perimeter = tape-equivalent circumference.
hull_perimeter <- function(xy) {
  h <- grDevices::chull(xy)
  loop <- xy[c(h, h[1]), , drop = FALSE]
  per_m <- sum(sqrt(rowSums(diff(loop)^2)))
  list(hull_circumference_cm = 100 * per_m, hull_equiv_diameter_cm = 100 * per_m / pi)
}

# ------------------------------------------------------------------ visualization
# Same per-slice bundle as fit_dab.py's write_slice_bundle:
#   <tree>_slice_fit.png   2D cross-section + fitted circle + hull, labeled
#   <tree>_slice.ply       the slice cloud (original coords)
#   <tree>_ring_<C>.ply    3D red circle overlay
#   <tree>_hull_<C>.ply    3D green hull outline (only when the ring is well-covered)
#   <tree>_measure.txt     the numbers in text
write_ply_xyzrgb <- function(path, xyz3, rgb) {
  n <- nrow(xyz3)
  header <- c("ply", "format ascii 1.0", sprintf("element vertex %d", n),
              "property float x", "property float y", "property float z",
              "property uchar red", "property uchar green", "property uchar blue",
              "end_header")
  body <- sprintf("%.6f %.6f %.6f %d %d %d",
                   xyz3[, 1], xyz3[, 2], xyz3[, 3], rgb[1], rgb[2], rgb[3])
  writeLines(c(header, body), path)
}

ring_xyz <- function(cx, cy, r, z, n = 500) {
  t <- seq(0, 2 * pi, length.out = n + 1)[1:n]
  cbind(cx + r * cos(t), cy + r * sin(t), z)
}

plot_slice_fit <- function(xy, circ, loop, row, path) {
  grDevices::png(path, width = 1200, height = 1200, res = 150)
  on.exit(grDevices::dev.off())
  C <- if (!is.na(row$hull_circumference_cm)) row$hull_circumference_cm else row$circle_circumference_cm
  Dpi <- if (!is.na(row$hull_equiv_diameter_cm)) row$hull_equiv_diameter_cm else row$circle_diameter_cm
  title <- sprintf("%s   C = %.1f cm   (C/pi diam = %.1f cm)\ncoverage %.0f deg | circle RMS %.1f mm%s",
                    row$tree_id, C, Dpi, row$coverage_deg, row$circle_rms_mm,
                    if (isTRUE(row$low_confidence)) "  ** LOW CONFIDENCE **" else "")
  plot(xy[, 1], xy[, 2], pch = 16, cex = 0.3, col = "grey60", asp = 1,
       xlab = "x (m)", ylab = "y (m)", main = title, cex.main = 0.85)
  t <- seq(0, 2 * pi, length.out = 400)
  lines(circ$cx + circ$r * cos(t), circ$cy + circ$r * sin(t), col = "red", lwd = 1.5)
  if (!is.null(loop)) lines(loop[, 1], loop[, 2], col = "darkgreen", lwd = 1.2)
  points(circ$cx, circ$cy, pch = 3, col = "red", cex = 1.5)
  legend("topright", legend = c("slice points", "best-fit circle", "hull (tape)"),
         col = c("grey60", "red", "darkgreen"), pch = c(16, NA, NA), lty = c(NA, 1, 1),
         cex = 0.7, bty = "n")
}

# `R` is the lean-correction rotation applied to get `xy_fit` (identity if
# none); overlay geometry is mapped back to ORIGINAL coords via `%*% R` (R is
# orthogonal, so this is R's inverse) so it aligns with the disc in CloudCompare.
write_slice_bundle <- function(viz_dir, tree_id, xyz_orig, xy_fit, z_fit, circ, row, R) {
  d <- file.path(viz_dir, tree_id)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  C <- if (!is.na(row$hull_circumference_cm)) row$hull_circumference_cm else row$circle_circumference_cm
  tag <- sprintf("C%.1fcm", C)

  loop <- NULL
  if (isTRUE(row$hull_valid)) {
    h <- grDevices::chull(xy_fit)
    loop <- xy_fit[c(h, h[1]), , drop = FALSE]
  }

  plot_slice_fit(xy_fit, circ, loop, row, file.path(d, sprintf("%s_slice_fit.png", tree_id)))
  write_ply_xyzrgb(file.path(d, sprintf("%s_slice.ply", tree_id)), xyz_orig, c(180, 180, 180))

  ring <- ring_xyz(circ$cx, circ$cy, circ$r, z_fit) %*% R
  write_ply_xyzrgb(file.path(d, sprintf("%s_ring_%s.ply", tree_id, tag)), ring, c(255, 0, 0))
  if (!is.null(loop)) {
    hull3d <- cbind(loop, z_fit) %*% R
    write_ply_xyzrgb(file.path(d, sprintf("%s_hull_%s.ply", tree_id, tag)), hull3d, c(0, 200, 0))
  }

  keys <- c("dab_height_m", "n_points", "coverage_deg", "circle_diameter_cm",
            "circle_circumference_cm", "circle_rms_mm", "hull_circumference_cm",
            "hull_equiv_diameter_cm", "hull_valid", "low_confidence")
  writeLines(c(sprintf("Tree %s", tree_id),
               sprintf("%s: %s", keys, vapply(keys, function(k) as.character(row[[k]]), character(1)))),
             file.path(d, sprintf("%s_measure.txt", tree_id)))
  d
}

# --------------------------------------------------------------------- measure
# Measures ONE tree/site and returns its result row. Pulled out into its own
# function so both the single-file CLI path and --from-sheet's loop over the
# manifest call the identical measurement logic.
measure_one <- function(path, tree_id, up_axis, dab_height, slice_height,
                        slice_thickness, axis_ply, viz_dir) {
  mesh <- Rvcg::vcgImport(path, clean = FALSE, silent = TRUE)
  xyz_orig <- t(mesh$vb[1:3, , drop = FALSE])
  if (nrow(xyz_orig) == 0) stop(sprintf("No points read from %s", path))

  up_idx <- match(up_axis, c("x", "y", "z"))

  # Height-slice mode: `path` is a whole trunk SECTION, not a pre-cut ring.
  # Cut a band centred on the picked height, matching dab_itsme.R/dendro_tape.R's
  # window [h - t/2, h + t/2]. Omit --slice-height and `path` is treated as an
  # already-cut slice (e.g. a thin disc that is itself the cross-section).
  if (!is.na(slice_height)) {
    coord <- xyz_orig[, up_idx]
    keep  <- coord > (slice_height - slice_thickness / 2) & coord < (slice_height + slice_thickness / 2)
    xyz_orig <- xyz_orig[keep, , drop = FALSE]
    if (is.na(dab_height)) dab_height <- slice_height
  }

  n <- nrow(xyz_orig)
  if (n < 8) {
    detail <- if (!is.na(slice_height)) sprintf(" in band %s=%.3f+/-%.3f", up_axis, slice_height, slice_thickness / 2) else ""
    stop(sprintf("%s: only %d points%s -- too few to fit.", path, n, detail))
  }

  # Rotate so the trunk axis -> +Z, then fit in the resulting XY plane. The
  # axis comes from --axis-ply (lean correction) if given, else from
  # --up-axis (identity when up_axis == "z" = the original behaviour). Keep
  # R so the 3D overlay maps back onto the un-rotated disc for CloudCompare.
  axis <- NULL
  if (!is.na(axis_ply)) {
    seg_mesh <- Rvcg::vcgImport(axis_ply, clean = FALSE, silent = TRUE)
    axis <- stem_axis_from_segment(t(seg_mesh$vb[1:3, , drop = FALSE]))
  } else if (up_axis != "z") {
    axis <- switch(up_axis, x = c(1, 0, 0), y = c(0, 1, 0))
  }

  if (!is.null(axis)) {
    R <- rotation_axis_to_z(axis)
    xyz <- xyz_orig %*% t(R)
  } else {
    R <- diag(3)
    xyz <- xyz_orig
  }
  xy <- xyz[, 1:2, drop = FALSE]

  circ <- fit_circle_kasa(xy)
  cov <- angular_coverage_deg(xy, circ$cx, circ$cy)

  row <- data.frame(
    tree_id                  = tree_id,
    slice_file                = basename(path),
    dab_height_m               = dab_height,
    slice_thickness_m          = if (!is.na(slice_height)) slice_thickness else NA_real_,
    n_points                   = n,
    coverage_deg                = round(cov, 1),
    circle_diameter_cm          = round(circ$circle_diameter_cm, 2),
    circle_circumference_cm     = round(circ$circle_circumference_cm, 2),
    circle_rms_mm                = round(circ$circle_rms_mm, 2),
    stringsAsFactors = FALSE
  )

  # hull only valid on well-closed rings -- coverage-only gate, matching
  # fit_dab.py exactly (the newer tape scripts additionally gate on
  # max_edge_frac; fit_dab.py never had that, so this port doesn't add it).
  if (cov >= 270) {
    hp <- hull_perimeter(xy)
    row$hull_circumference_cm  <- round(hp$hull_circumference_cm, 2)
    row$hull_equiv_diameter_cm <- round(hp$hull_equiv_diameter_cm, 2)
    row$hull_valid <- TRUE
  } else {
    row$hull_circumference_cm  <- NA_real_
    row$hull_equiv_diameter_cm <- NA_real_
    row$hull_valid <- FALSE
  }
  row$low_confidence <- (cov < 270) || (circ$circle_rms_mm > 20)

  if (!is.na(viz_dir)) {
    write_slice_bundle(viz_dir, tree_id, xyz_orig, xy, mean(xyz[, 3]), circ, row, R)
  }
  row
}

report_row <- function(row) {
  flag <- if (isTRUE(row$low_confidence)) "  ** LOW CONFIDENCE **" else ""
  hull_txt <- if (is.na(row$hull_circumference_cm)) "NA" else sprintf("%.1f", row$hull_circumference_cm)
  cat(sprintf("%-14s D_circle=%.1f cm  C_hull=%s  cov=%.0fdeg  rms=%.1fmm%s\n",
              row$tree_id, row$circle_diameter_cm, hull_txt, row$coverage_deg,
              row$circle_rms_mm, flag))
}

# ------------------------------------------------------------------------ run
resolve_tree_id <- function(path, override) {
  if (!is.na(override)) override else tools::file_path_sans_ext(basename(path))
}

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
    result <- tryCatch(
      measure_one(m$path, m$tree_id, up_axis, dab_height_arg, m$height,
                  slice_thickness, axis_ply, viz_dir),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    if (isTRUE(result$hull_valid)) {
      updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$hull_equiv_diameter_cm * 10, 1))
    } else {
      cat(sprintf("[skip write-back] %s: hull invalid (partial ring), nothing to write\n", m$tree_id))
    }
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else if (batch) {
  files <- sort(list.files(path, pattern = "\\.ply$", full.names = TRUE))
  if (!length(files)) stop(sprintf("No PLY files found at: %s", path))
  rows <- list()
  for (f in files) {
    result <- tryCatch(
      measure_one(f, resolve_tree_id(f, tree_id_arg), up_axis, dab_height_arg,
                  slice_height_arg, slice_thickness, axis_ply, viz_dir),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", f, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
  }
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, resolve_tree_id(path, tree_id_arg), up_axis, dab_height_arg,
                      slice_height_arg, slice_thickness, axis_ply, viz_dir)
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
