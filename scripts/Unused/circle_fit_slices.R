#!/usr/bin/env Rscript
# =============================================================================
# circle_fit_slices.R -- least-squares circle fit on every polished slice.
#
# SUPERSEDED 2026-09-30 by scripts/Step06_Measure/circle_fit.py / .R, which fit
# the same circle in Step 6 and write it to the sheet. Step 7 now reads the
# sheet, so nothing uses this script's CSV. Kept as the record.
#
# The fit is the algebraic (Kasa) least-squares circle, the same fit as
# scripts/fit_dab.R's fit_circle_kasa(), done in the plane across the trunk
# axis (X-Z for Y-up ForestScanner clouds). fit_dab.R rotates the up axis to Z
# first, a rigid rotation, which doesn't change the fitted diameter.
# Analysis only, so R only (see CLAUDE.md): it is not part of processing a
# tree and writes nothing to the sheet.
#
# Output (results/, or DAB_RESULTS):
#   circle_fit_slices.csv   one row per polished slice: tree, site, n_points,
#                           circle diameter (mm), circle RMS (mm), coverage (deg)
#
# Run:  Rscript scripts/Step07_Analysis/circle_fit_slices.R
# =============================================================================

suppressMessages(library(Rvcg))   # PLY reader, same as fit_dab.R

# =============================================================================
# CONFIG -- edit these for your own dataset. SLICE_FOLDER is step 5's output,
# the same folder the step 6 scripts read. `outdir` defaults to the
# repo-relative results/ folder, overridden by DAB_RESULTS.
# =============================================================================
SLICE_FOLDER  <- "C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"   # polished slices, <tag>__<Site>.ply
SLICE_PATTERN <- "^(.+)__(.+)\\.ply$"                                         # tree tag, then site label
UP_AXIS       <- "y"                                                          # ForestScanner (ARKit) clouds are Y-up
outdir <- Sys.getenv("DAB_RESULTS", "results")
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

# Algebraic (Kasa) least-squares circle fit on 2D points (as in fit_dab.R).
fit_circle_kasa <- function(xy) {
  x <- xy[, 1]; y <- xy[, 2]
  A <- cbind(x, y, 1)
  b <- x^2 + y^2
  coef <- qr.solve(A, b)
  cx <- coef[1] / 2; cy <- coef[2] / 2
  r <- sqrt(max(coef[3] + cx^2 + cy^2, 0))
  resid <- sqrt((x - cx)^2 + (y - cy)^2) - r
  list(cx = cx, cy = cy, r = r, rms = sqrt(mean(resid^2)))
}

# Largest covered arc (deg) about (cx, cy), as in fit_dab.R.
angular_coverage_deg <- function(xy, cx, cy) {
  ang <- sort(atan2(xy[, 2] - cy, xy[, 1] - cx))
  gaps <- diff(c(ang, ang[1] + 2 * pi))
  (2 * pi - max(gaps)) * 180 / pi
}

across_axes <- setdiff(c("x", "y", "z"), UP_AXIS)   # the two axes across the trunk
files <- list.files(SLICE_FOLDER, pattern = SLICE_PATTERN, full.names = TRUE)
if (length(files) == 0) stop(sprintf("No slices matching %s in %s", SLICE_PATTERN, SLICE_FOLDER))

rows <- lapply(files, function(f) {
  nm <- basename(f)
  xyz <- t(Rvcg::vcgImport(f, clean = FALSE, silent = TRUE)$vb[1:3, , drop = FALSE])
  if (nrow(xyz) < 8) { cat(sprintf("[skip] %s: only %d points\n", nm, nrow(xyz))); return(NULL) }
  xy <- xyz[, match(across_axes, c("x", "y", "z")), drop = FALSE]
  circ <- fit_circle_kasa(xy)
  data.frame(tree             = sub(SLICE_PATTERN, "\\1", nm),
             site             = sub(SLICE_PATTERN, "\\2", nm),
             n_points         = nrow(xyz),
             circle_diameter_mm = round(2000 * circ$r, 1),
             circle_rms_mm    = round(1000 * circ$rms, 2),
             coverage_deg     = round(angular_coverage_deg(xy, circ$cx, circ$cy), 1))
})
out <- do.call(rbind, rows)
write.csv(out, file.path(outdir, "circle_fit_slices.csv"), row.names = FALSE)
cat(sprintf("Circle fit on %d polished slices. Wrote %s\n", nrow(out), file.path(outdir, "circle_fit_slices.csv")))
