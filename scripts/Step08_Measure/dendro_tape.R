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
# Deliberately NO circle fit and NO concave hull: a circle assumes a round trunk,
# a concave hull sinks into grooves -- neither is what a taut band does. (This is
# a plain-geometry tool; it does NOT use ITSMe, unlike dab_itsme.R.)
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
OUTPUT_COL <- "Dendrometer_DendroTape_RScript_Diameter_mm"  # R's true-hull column (distinct from
                                         # the plain "Dendrometer_RScript_Diameter_mm" column, which
                                         # is ITSMe's concave functional diameter -- a DIFFERENT method)
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working/Polished_Slices_ply"  # already-cut, polished discs
PLY_FILENAME_PATTERN <- "{tree_id}__{site}.ply"  # e.g. "1234__Dendrometer.ply" -- adjust to your own naming
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern

# ------------------------------------------------------------------ CLI parsing
# Base-R flag parser: a positional <path> plus --tree-id --up-axis --height
# --thickness --min-coverage --out --from-sheet.
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet

flag_names <- c("--tree-id", "--up-axis", "--height", "--thickness",
                "--min-coverage", "--out")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript dendro_tape.R <section.ply> [--up-axis y] [--height <m>] ",
       "[--thickness 0.06] [--tree-id id] [--out results/dendro_tape.csv] ",
       "| --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id   <- get_flag("--tree-id",   if (is.na(path)) NA else tools::file_path_sans_ext(basename(path)))
up_axis   <- get_flag("--up-axis",   "y")                   # ForestScanner clouds are Y-up
height    <- as.numeric(get_flag("--height", NA))          # picked coord along up-axis (m)
thickness <- as.numeric(get_flag("--thickness", 0.06))
min_cov   <- as.numeric(get_flag("--min-coverage", 270))
out       <- get_flag("--out", NULL)

MAX_EDGE_FRAC <- 0.5

# --------------------------------------------------------------------- measure
# Measures ONE tree/site and returns its result row. Pulled out into its own
# function so both the single-file CLI path and --from-sheet's loop over the
# manifest call the identical measurement logic.
measure_one <- function(path, tree_id, up_axis, height, thickness, min_cov) {
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

  data.frame(
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
}

report_row <- function(row) {
  flag <- if (isTRUE(row$tape_valid)) "" else "  ** PARTIAL RING -- tape invalid **"
  cat(sprintf("%-14s C_tape=%.1f cm  (C/pi diam=%.1f cm)  cov=%.0fdeg  maxedge=%.2f%s\n",
              row$tree_id, row$tape_circumference_cm, row$tape_equiv_diameter_cm,
              row$coverage_deg, row$max_edge_frac, flag))
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
      measure_one(m$path, m$tree_id, up_axis, h, thickness, min_cov),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    if (isTRUE(result$tape_valid)) {
      updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$tape_equiv_diameter_cm * 10, 1))
    } else {
      cat(sprintf("[skip write-back] %s: tape invalid (partial ring), nothing to write\n", m$tree_id))
    }
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, tree_id, up_axis, height, thickness, min_cov)
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
