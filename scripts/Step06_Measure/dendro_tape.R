#!/usr/bin/env Rscript
# =============================================================================
# dendro_tape.R  --  mimic a physical dendrometer / girth tape on a trunk slice (R).
#
# WHAT THIS MEASURES (and why)
# ----------------------------
# A dendrometer band and a diameter/girth tape are both a *taut, inextensible
# band* wrapped around the stem under tension. A taut band around a cross-section
# traces exactly one shape -- the CONVEX HULL of the surface points -- because it
# physically cannot dip into a fissure; it bridges every concavity. (That is the
# literal definition of a convex hull: the outline a stretched rubber band takes
# around a set of points.) So the physically faithful mimic of a dendrometer is:
#
#     circumference  = convex-hull perimeter of the slice        (PRIMARY metric)
#     equiv diameter = circumference / pi                        (as a tape is pre-/pi'd)
#
# Grounded in the PHYSICS of the instrument, not in which method scores best on
# any particular dataset -- that keeps the tool unbiased.
#
# Deliberately NO circle fit in the MEASUREMENT and NO concave hull: a circle assumes
# a round trunk, a concave hull sinks into grooves -- neither is what a taut band does.
# (The optional --viz-dir picture draws a best-fit circle for visual reference only;
# it never feeds the diameter, the validity check or the sheet. This is a
# plain-geometry tool; it does NOT use ITSMe, unlike dab_itsme_concave_hull.R.)
#
# Companion Python tool: scripts/dendro_tape.py computes the same convex-hull taut
# wrap. Two independent implementations of one physical measurement -> an R lab
# and a Python lab each get a validated tool; where they disagree, it flags a bug.
#
# USAGE
# -----
# Cut a band at a picked height on a SECTION (clouds are Y-up -> --up-axis y):
#   Rscript scripts/dendro_tape.R section.ply --tree-id 1234 --up-axis y \
#       --height 2.31 --thickness 0.06 --out results/dendro_tape.csv
# Measure an already-cut thin slice/disc as-is: omit --height.
# Batch a folder of *.ply (one row each):
#   Rscript scripts/dendro_tape.R slices/ --batch --up-axis y --out results/dendro_tape_R.csv
# Also write a picture bundle per slice (add to any of the above):
#   --viz-dir <folder>  ->  <folder>/<tree_id>/  _slice_fit.png, _slice.ply,
#   _hull_<C>.ply (green), _ring_<C>.ply (red, reference only), _gapedge.ply
#   (magenta, rejected rings only), _measure.txt. On a ring rejected for a gap the
#   too-long hull edge is drawn thick in magenta and the picture is labelled
#   PARTIAL RING. This bundle replaces measure_slice.R's.
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
OUTPUT_COL <- "Dendrometer_DendroTape_RScript_Diameter_mm"  # R's convex-hull (tape) column (distinct
                                         # from "Dendrometer_DabItsme_ConcaveHull_RScript_Diameter_mm",
                                         # which is ITSMe's concave functional diameter -- a DIFFERENT method)
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"  # step 5 output: polished slices, <tag>__<Site>.ply
PLY_FILENAME_PATTERN <- "{tree_id}__{site}.ply"  # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern
FLAG_COL <- "Dendrometer_DendroTape_MaxEdgeFrac"  # the gap check, as a NUMBER, not a veto:
                                         # longest hull edge / equivalent diameter. > MAX_EDGE_FRAC
                                         # (0.5) is the flag, but the diameter is written either way
                                         # so the threshold can be revisited in analysis. NULL to skip.

# ------------------------------------------------------------------ CLI parsing
# Base-R flag parser: a positional <path> plus --tree-id --up-axis --height
# --thickness --min-coverage --out --viz-dir, and the switches --batch --from-sheet.
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet

flag_names <- c("--tree-id", "--up-axis", "--height", "--thickness",
                "--min-coverage", "--out", "--viz-dir")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
batch      <- has_flag("--batch")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript dendro_tape.R <section.ply> [--up-axis y] [--height <m>] ",
       "[--thickness 0.06] [--tree-id id] [--out results/dendro_tape.csv] [--viz-dir <dir>] ",
       "| <folder> --batch | --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id   <- get_flag("--tree-id",   if (is.na(path) || batch) NA else tools::file_path_sans_ext(basename(path)))
up_axis   <- get_flag("--up-axis",   "y")                   # ForestScanner clouds are Y-up
height    <- as.numeric(get_flag("--height", NA))          # picked coord along up-axis (m)
thickness <- as.numeric(get_flag("--thickness", 0.06))
min_cov   <- as.numeric(get_flag("--min-coverage", 270))
out       <- get_flag("--out", NULL)
viz_dir   <- get_flag("--viz-dir", NA)

MAX_EDGE_FRAC <- 0.5

# ------------------------------------------------------------------ visualization
# Picture bundle (--viz-dir). Ported from measure_slice.R's write_slice_bundle so the
# polished-slice pictures survive that script's retirement. Nothing here changes the
# measurement: the circle is fit ONLY to draw it, and the gap edge is the same edge
# measure_one() already found.
fit_circle_kasa <- function(xy) {          # algebraic LSQ circle -- picture only
  x <- xy[, 1]; y <- xy[, 2]
  coef <- qr.solve(cbind(x, y, 1), x^2 + y^2)
  cx <- coef[1] / 2; cy <- coef[2] / 2
  r  <- sqrt(max(coef[3] + cx^2 + cy^2, 0))
  list(cx = cx, cy = cy, r = r, circle_diameter_cm = 100 * 2 * r,
       circle_rms_mm = 1000 * sqrt(mean((sqrt((x - cx)^2 + (y - cy)^2) - r)^2)))
}

write_ply_xyzrgb <- function(path, xyz3, rgb) {   # ASCII PLY, one colour
  header <- c("ply", "format ascii 1.0", sprintf("element vertex %d", nrow(xyz3)),
              "property float x", "property float y", "property float z",
              "property uchar red", "property uchar green", "property uchar blue",
              "end_header")
  writeLines(c(header, sprintf("%.6f %.6f %.6f %d %d %d", xyz3[, 1], xyz3[, 2], xyz3[, 3],
                               rgb[1], rgb[2], rgb[3])), path)
}

to_3d <- function(pts2d, plane_idx, up_idx, up_value) {   # 2D section -> 3D at fixed height
  out <- matrix(0, nrow(pts2d), 3)
  out[, plane_idx[1]] <- pts2d[, 1]; out[, plane_idx[2]] <- pts2d[, 2]; out[, up_idx] <- up_value
  out
}

write_slice_bundle <- function(viz_dir, row, xyz, xy, loop, gap_i, plane_idx, up_idx) {
  tid <- row$tree_id
  d <- file.path(viz_dir, tid)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  tag  <- sprintf("C%.1fcm", row$tape_circumference_cm)
  circ <- fit_circle_kasa(xy)
  gap  <- loop[gap_i:(gap_i + 1), , drop = FALSE]
  invalid <- !isTRUE(row$tape_valid)
  ax <- c("x", "y", "z")[plane_idx]

  grDevices::png(file.path(d, sprintf("%s_slice_fit.png", tid)), width = 1200, height = 1200, res = 150)
  title <- sprintf("%s   C = %.1f cm   (C/pi diam = %.1f cm)\ncoverage %.0f deg | max edge %.2f x diam%s",
                   tid, row$tape_circumference_cm, row$tape_equiv_diameter_cm, row$coverage_deg,
                   row$max_edge_frac,
                   if (invalid) "\n** PARTIAL RING -- tape invalid, not written to sheet **" else "")
  plot(xy[, 1], xy[, 2], pch = 16, cex = 0.3, col = "grey60", asp = 1,
       xlab = sprintf("%s (m)", ax[1]), ylab = sprintf("%s (m)", ax[2]),
       main = title, cex.main = 0.8, col.main = if (invalid) "magenta" else "black")
  lines(loop[, 1], loop[, 2], col = "darkgreen", lwd = 1.2)
  t <- seq(0, 2 * pi, length.out = 400)
  lines(circ$cx + circ$r * cos(t), circ$cy + circ$r * sin(t), col = "red", lwd = 1)
  points(circ$cx, circ$cy, pch = 3, col = "red", cex = 1.5)
  leg <- c("slice points", "hull (tape)", "best-fit circle (reference only)")
  col <- c("grey60", "darkgreen", "red"); lwd <- c(NA, 1.2, 1); pch <- c(16, NA, NA)
  if (invalid) {
    lines(gap[, 1], gap[, 2], col = "magenta", lwd = 4)
    leg <- c(leg, sprintf("gap edge (%.2f x diam)", row$max_edge_frac))
    col <- c(col, "magenta"); lwd <- c(lwd, 4); pch <- c(pch, NA)
  }
  legend("topright", legend = leg, col = col, lwd = lwd, pch = pch, cex = 0.7, bty = "n")
  grDevices::dev.off()

  up_value <- mean(xyz[, up_idx])
  write_ply_xyzrgb(file.path(d, sprintf("%s_slice.ply", tid)), xyz, c(180, 180, 180))
  write_ply_xyzrgb(file.path(d, sprintf("%s_hull_%s.ply", tid, tag)),
                   to_3d(loop, plane_idx, up_idx, up_value), c(0, 200, 0))
  tt <- t[-length(t)]
  write_ply_xyzrgb(file.path(d, sprintf("%s_ring_%s.ply", tid, tag)),
                   to_3d(cbind(circ$cx + circ$r * cos(tt), circ$cy + circ$r * sin(tt)),
                         plane_idx, up_idx, up_value), c(255, 0, 0))
  if (invalid) {
    s <- seq(0, 1, length.out = 200)
    seg <- cbind(gap[1, 1] + s * (gap[2, 1] - gap[1, 1]), gap[1, 2] + s * (gap[2, 2] - gap[1, 2]))
    write_ply_xyzrgb(file.path(d, sprintf("%s_gapedge.ply", tid)),
                     to_3d(seg, plane_idx, up_idx, up_value), c(255, 0, 255))
  }
  keys <- c("height_m", "n_points", "coverage_deg", "max_edge_frac",
            "tape_circumference_cm", "tape_equiv_diameter_cm", "tape_valid")
  writeLines(c(sprintf("Tree %s", tid),
               sprintf("%s: %s", keys, vapply(keys, function(k) as.character(row[[k]]), character(1))),
               sprintf("reference_circle_diameter_cm: %.2f  (picture only)", circ$circle_diameter_cm),
               sprintf("reference_circle_rms_mm: %.2f  (picture only)", circ$circle_rms_mm)),
             file.path(d, sprintf("%s_measure.txt", tid)))
  d
}

# --------------------------------------------------------------------- measure
# Measures ONE tree/site and returns its result row. Pulled out into its own
# function so both the single-file CLI path and --from-sheet's loop over the
# manifest call the identical measurement logic.
measure_one <- function(path, tree_id, up_axis, height, thickness, min_cov, viz_dir = NA) {
  # vcgImport returns a mesh3d; $vb is 4 x N homogeneous coords -> take rows 1:3.
  # clean = FALSE is REQUIRED for point clouds: the default clean=TRUE strips
  # "unreferenced" vertices, and in a point cloud (no faces) every vertex is
  # unreferenced -- so the default can silently drop points. Duplicates left in are
  # harmless here (a convex hull is unchanged by repeated points).
  mesh <- Rvcg::vcgImport(path, clean = FALSE, silent = TRUE)
  xyz  <- t(mesh$vb[1:3, , drop = FALSE])        # N x 3 matrix of X, Y, Z (metres)
  if (nrow(xyz) == 0) stop(sprintf("No points read from %s", path))

  # Which column is the up axis, and which two form the cross-section plane.
  up_idx    <- match(up_axis, c("x", "y", "z"))
  plane_idx <- setdiff(1:3, up_idx)

  # Height-slice mode: cut the band [height - t/2, height + t/2] along the up axis --
  # the identical window fit_dab.py / dendro_tape.py use. Omit height to measure a
  # pre-cut slice/disc as-is.
  if (!is.na(height)) {
    coord <- xyz[, up_idx]
    keep  <- coord > (height - thickness / 2) & coord < (height + thickness / 2)
    xyz   <- xyz[keep, , drop = FALSE]
  }

  n <- nrow(xyz)
  if (n < 8) stop(sprintf("%s: only %d points in band -- too few for a tape wrap.", path, n))

  xy <- xyz[, plane_idx, drop = FALSE]           # project onto the cross-section plane

  # ----------------------------------------------------- taut tape = convex hull
  # chull() returns the indices of the hull vertices, ordered around the ring. Close
  # the loop (append the first index), take each edge's straight-line length, sum ->
  # perimeter (m). diff() on a matrix differences consecutive ROWS.
  h      <- grDevices::chull(xy)
  loop   <- xy[c(h, h[1]), , drop = FALSE]       # close the loop: last point == first
  edges  <- sqrt(rowSums(diff(loop)^2))          # each hull edge's length (m)
  per_m  <- sum(edges)
  circ_cm  <- 100 * per_m
  diam_cm  <- 100 * per_m / pi

  # Longest hull edge as a fraction of the equivalent diameter. On a full ring every
  # edge is tiny (~0); on a partial/broken ring the hull chords across the gap, making
  # one edge nearly a whole diameter. A center-free detector of "tape bridging a gap".
  # > 0.5 flags openings beyond ~65 deg while passing well-sampled full rings.
  equiv_diam_m  <- per_m / pi
  max_edge_frac <- if (equiv_diam_m > 0) max(edges) / equiv_diam_m else Inf

  # QC: angular coverage -- largest covered arc about the centroid. A taut tape
  # needs a (near-)closed loop; a partial ring chords across the gap and reads
  # too small.
  cx  <- mean(xy[, 1]); cy <- mean(xy[, 2])
  ang <- sort(atan2(xy[, 2] - cy, xy[, 1] - cx))
  gaps    <- diff(c(ang, ang[1] + 2 * pi))       # angular gaps between neighbours
  cov_deg <- (2 * pi - max(gaps)) * 180 / pi     # 360 minus the biggest gap
  # a trustworthy taut wrap needs a closed-enough loop: enough angular coverage AND
  # no single hull edge chording across a big gap.
  valid   <- cov_deg >= min_cov & max_edge_frac <= MAX_EDGE_FRAC

  row <- data.frame(
    tree_id                = tree_id,
    slice_file             = basename(path),
    method                 = "convex-hull taut tape",
    up_axis                = up_axis,
    height_m               = if (is.na(height)) NA else round(height, 4),
    slice_thickness_m      = if (is.na(height)) NA else thickness,
    n_points               = n,
    coverage_deg           = round(cov_deg, 1),
    max_edge_frac          = round(max_edge_frac, 3),
    tape_circumference_cm  = round(circ_cm, 2),
    tape_equiv_diameter_cm = round(diam_cm, 2),
    tape_valid             = valid,
    stringsAsFactors       = FALSE
  )
  if (!is.na(viz_dir)) {
    write_slice_bundle(viz_dir, row, xyz, xy, loop, which.max(edges), plane_idx, up_idx)
  }
  row
}

report_row <- function(row) {
  flag <- if (isTRUE(row$tape_valid)) "" else "  ** PARTIAL RING -- tape invalid **"
  cat(sprintf("%-14s C_tape=%.1f cm  (C/pi diam=%.1f cm)  cov=%.0fdeg  maxedge=%.2f%s\n",
              row$tree_id, row$tape_circumference_cm, row$tape_equiv_diameter_cm,
              row$coverage_deg, row$max_edge_frac, flag))
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
      measure_one(m$path, m$tree_id, up_axis, h, thickness, min_cov, viz_dir),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    # The gap check FLAGS, it does not block: write the diameter either way and
    # record max_edge_frac alongside it (see FLAG_COL).
    # whole mm at the sheet only: the field readings are integer mm. CSV keeps full precision.
    updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$tape_equiv_diameter_cm * 10))
    flag_updates[[length(flag_updates) + 1]] <- list(row = m$row, value = round(result$max_edge_frac, 3))
    if (!isTRUE(result$tape_valid)) {
      cat(sprintf("[flagged] %s: partial ring (max_edge_frac=%.3f) -- written, but check it\n",
                  m$tree_id, result$max_edge_frac))
    }
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  if (!is.null(FLAG_COL) && length(flag_updates)) {
    write_back_all(SHEET_PATH, SHEET_NAME, FLAG_COL, flag_updates)
  }
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else if (batch) {
  files <- sort(list.files(path, pattern = "\\.ply$", full.names = TRUE))
  if (!length(files)) stop(sprintf("No PLY files found at: %s", path))
  rows <- list()
  for (f in files) {
    result <- tryCatch(
      measure_one(f, tools::file_path_sans_ext(basename(f)), up_axis, height, thickness,
                  min_cov, viz_dir),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", f, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
  }
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, tree_id, up_axis, height, thickness, min_cov, viz_dir)
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
