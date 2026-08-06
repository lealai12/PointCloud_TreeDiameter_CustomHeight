#!/usr/bin/env Rscript
# =============================================================================
# dab_itsme.R  --  second, independent trunk-diameter estimate via the ITSMe R package.
#
# Companion to scripts/fit_dab.py: every trunk cross-section is worth measuring
# BOTH ways, with independent code, so the two estimates can be compared
# against a field reading (tape, dendrometer, etc.) to see which tracks it
# best -- and so an unexplained disagreement between them flags a slice worth
# a second look, before you ever get to ground truth.
#
# Workflow this fits into:
#   1. Isolate a loop-closed TRUNK SECTION (a vertical chunk of the bole,
#      tall enough to pick a height on -- NOT a pre-cut thin ring).
#   2. Pick a point on the section; its Z is the measurement height.
#   3. Run BOTH tools on that section at that Z with the same slice thickness:
#        Rscript scripts/dab_itsme.R <section.ply> --tree-id 1234 \
#                --height-z 2.31 --thickness 0.06 --out results/dab_itsme_results.csv
#        python  scripts/fit_dab.py ... (matching height/thickness)
#
# Why this mirrors fit_dab.py exactly:
#   ITSMe's diameter_slice_pc() cuts a slice CENTRED at (lowest_point +
#   slice_height) with a window of +/- thickness/2. Without a DTM its
#   "lowest_point" is simply min(Z). So to slice the same ABSOLUTE band the
#   Python side cuts ([Z - t/2, Z + t/2]) we set  slice_height = Z - min(Z).
#
# What ITSMe gives us (and how it maps to fit_dab.py):
#   diameter   (circle fit, optim on radial spread, radius via MEDIAN radius)
#              -> compare with fit_dab.py circle_diameter_cm (Kasa least-squares)
#   fdiameter  (equivalent diameter of a CONCAVE hull, "functional" diameter)
#              -> compare with fit_dab.py hull (CONVEX) C/pi
#   R2         (mean squared radial residual, m^2) -> we also report it as an
#              RMS in mm (sqrt) so it lines up with fit_dab.py circle_rms_mm.
#
# Units: ITSMe works in metres; we report cm here, matching fit_dab.py.
# =============================================================================

suppressMessages(library(ITSMe))

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
HEIGHT_COL <- "Y_value_Dendrometer"      # column holding the picked cut height (m); swap to
                                         # Y_value_TopFlag / Y_value_LowerFlag for those sites
OUTPUT_COL <- "Dendrometer_RScript_Diameter_mm"  # column the diameter (mm) is written into
PLY_FOLDER <- "C:/Projects/LiDAR_Project/Working/Final_Disc_ply"  # whole trunk SECTIONS, not pre-cut discs
PLY_FILENAME_PATTERN <- "{tree_id}.ply"  # {tree_id} required; {site} optional (see SITE_LABEL)
SITE_LABEL <- "Dendrometer"              # substituted into {site} in the pattern, if used

# ------------------------------------------------------------------ CLI parsing
# Base-R flag parser (no extra package dependency). Recognises a positional
# <path> plus --tree-id --height-z --thickness --concavity --how --out
# --up-axis --from-sheet.
args <- commandArgs(trailingOnly = TRUE)

get_flag <- function(name, default = NULL) {   # value following --name, else default
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
has_flag <- function(name) name %in% args      # boolean flags, e.g. --from-sheet

# positional path = first non-flag token that isn't itself a flag's value
flag_names <- c("--tree-id", "--height-z", "--thickness", "--concavity",
                "--how", "--out", "--up-axis")
value_idx  <- match(flag_names, args) + 1                   # slots holding flag values
positional <- args[!startsWith(args, "--") & !(seq_along(args) %in% value_idx)]
path       <- if (length(positional)) positional[1] else NA

from_sheet <- has_flag("--from-sheet")
if (is.na(path) && !from_sheet) {
  stop("Usage: Rscript dab_itsme.R <section.ply> --height-z <Z_metres> ",
       "[--tree-id id] [--thickness 0.06] [--out results/dab_itsme_results.csv] ",
       "| --from-sheet (batch-run using the CONFIG block at the top of this file)")
}

tree_id   <- get_flag("--tree-id",   if (is.na(path)) NA else tools::file_path_sans_ext(basename(path)))
height_z  <- as.numeric(get_flag("--height-z", NA))         # ABSOLUTE picked Z (m)
thickness <- as.numeric(get_flag("--thickness", 0.06))
concavity <- as.numeric(get_flag("--concavity", 4))
how       <- get_flag("--how", "median")                    # ITSMe radius summary
out       <- get_flag("--out", NULL)
up_axis   <- get_flag("--up-axis", "z")                     # ForestScanner clouds are Y-up

if (!from_sheet && is.na(height_z)) {
  stop("--height-z <Z> is required (the picked point's Z, in metres) unless --from-sheet is given.")
}

# --------------------------------------------------------------------- measure
# Measures ONE tree/site and returns its result row. Pulled out into its own
# function so both the single-file CLI path and --from-sheet's loop over the
# manifest call the identical measurement logic -- --from-sheet changes WHERE
# path/tree_id/height_z come from, never how a slice gets measured.
measure_one <- function(path, tree_id, height_z, thickness, concavity, how, up_axis) {
  pc <- read_tree_pc(path)                       # data.frame X,Y,Z (PLY via Rvcg)
  if (is.null(pc) || nrow(pc) == 0) stop(sprintf("No points read from %s", path))

  # ForestScanner (ARKit) clouds are Y-up: the trunk axis is Y, not Z. ITSMe assumes
  # Z is the height axis (slices on Z, fits the circle in XY), so for --up-axis y we
  # swap Y<->Z. Then min(Z)=min(old Y), the slice runs along the trunk, and the circle
  # is fit in old X-Z -- matching fit_dab.py --up-axis y. height_z is then the old Y.
  if (up_axis == "y") pc <- data.frame(X = pc$X, Y = pc$Z, Z = pc$Y)

  lp <- min(pc$Z)                                # matches ITSMe tree_height_pc()$lp (no DTM)
  slice_height <- height_z - lp                  # height ABOVE lowest point

  # ITSMe slice + circle + concave-hull functional diameter, at our exact band.
  res <- diameter_slice_pc(
    pc,
    slice_height    = slice_height,
    slice_thickness = thickness,
    functional      = TRUE,        # we want the concave-hull ("tape-like") diameter too
    concavity       = concavity,
    how             = how
  )

  # Pull results, converting m -> cm. Guard the NaN / failure branches.
  diam_cm  <- res$diameter  * 100                 # circle-fit diameter
  fdiam_cm <- res$fdiameter * 100                 # concave-hull functional diameter
  r2       <- res$R2                              # mean squared radial residual (m^2)
  rms_mm   <- if (is.na(r2)) NA_real_ else sqrt(r2) * 1000   # -> RMS in mm (like fit_dab.py)

  # center = the optim() object; coords live in $par. NaN on failure.
  ctr <- res$center
  if (is.list(ctr) && !is.null(ctr$par)) {
    cx <- ctr$par[1]; cy <- ctr$par[2]
  } else { cx <- NA_real_; cy <- NA_real_ }

  arc_cov  <- res$arc_coverage                    # ITSMe's angular-coverage measure
  low_conf <- is.nan(res$diameter) ||
              isFALSE(res$inner_circle_empty) ||
              isFALSE(res$all_points_in_donut)

  data.frame(
    tree_id                       = tree_id,
    section_file                  = basename(path),
    method                        = "ITSMe::diameter_slice_pc",
    height_z_m                    = round(height_z, 4),
    slice_height_above_lp_m       = round(slice_height, 4),
    slice_thickness_m             = thickness,
    itsme_circle_diameter_cm      = round(diam_cm, 2),
    itsme_circle_circumference_cm = round(pi * diam_cm, 2),
    itsme_circle_rms_mm           = round(rms_mm, 2),
    itsme_func_diameter_cm        = round(fdiam_cm, 2),        # concave hull
    itsme_func_circumference_cm   = round(pi * fdiam_cm, 2),
    itsme_arc_coverage            = arc_cov,
    itsme_center_x                = round(cx, 4),
    itsme_center_y                = round(cy, 4),
    radius_how                    = how,
    low_confidence                = low_conf,
    stringsAsFactors              = FALSE
  )
}

report_row <- function(row) {
  flag <- if (isTRUE(row$low_confidence)) "  ** LOW CONFIDENCE **" else ""
  cat(sprintf("%-14s D_circle=%.1f cm  C_func=%.1f cm  rms=%.1f mm%s\n",
              row$tree_id, row$itsme_circle_diameter_cm,
              row$itsme_func_circumference_cm, row$itsme_circle_rms_mm, flag))
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
    result <- tryCatch(
      measure_one(m$path, m$tree_id, m$height, thickness, concavity, how, up_axis),
      error = function(e) { cat(sprintf("[skip] %s: %s\n", m$tree_id, conditionMessage(e))); NULL }
    )
    if (is.null(result)) next
    rows[[length(rows) + 1]] <- result
    report_row(result)
    if (!is.na(result$itsme_func_diameter_cm)) {
      updates[[length(updates) + 1]] <- list(row = m$row, value = round(result$itsme_func_diameter_cm * 10, 1))
    } else {
      cat(sprintf("[skip write-back] %s: functional diameter is NA, nothing to write\n", m$tree_id))
    }
  }
  write_back_all(SHEET_PATH, SHEET_NAME, OUTPUT_COL, updates)
  all_rows <- if (length(rows)) do.call(rbind, rows) else NULL
} else {
  row <- measure_one(path, tree_id, height_z, thickness, concavity, how, up_axis)
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
