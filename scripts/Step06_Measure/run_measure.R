#!/usr/bin/env Rscript
# =============================================================================
# run_measure.R -- run any or all of the R step 6 measure scripts, at any or
# all sites, from one place.
#
# Pick the methods, sites and percentiles in the CONFIG block below, then run
# from the repo root:
#
#     Rscript scripts/Step06_Measure/run_measure.R
#
# Each method runs in --from-sheet mode, once per site (and, for the binned
# hulls, once per percentile). The site and the sheet columns are passed to the
# script on the command line (--site, --output-col, --flag-col, --height-col),
# so no script file is changed. Each script still reads everything else (the
# sheet path, the slice folder, the file name pattern) from its own CONFIG.
#
# This runs the R scripts only. run_measure.py is its twin for the Python
# scripts. They are written separately and share nothing, so a lab with only
# one language can use the one it has.
#
# Before anything runs, every sheet column the jobs will write into is checked.
# A job whose column is missing is skipped and listed, rather than measuring
# every slice and then failing at the write.
# =============================================================================

# =============================================================================
# CONFIG -- choose what to run.
# =============================================================================
METHODS <- c(                    # delete any you don't want
  "dendro_tape",
  "dab_itsme_concave_hull",
  "bin_fixed_angle",
  "bin_mean_distance_radius",
  "circle_fit"
)
SITES       <- c("Dendrometer", "TopFlag", "LowerFlag", "ForestGeoPaint", "DendroPaint")
PERCENTILES <- c(50, 90)         # binned hulls only. Every value needs an entry in PERCENTILE_TAG.

DRY_RUN <- FALSE                 # TRUE = print each command and the column check, run nothing
SHOW_SKIPS <- FALSE              # TRUE = list every tree a script skipped. A skip is usually a
                                 # tree with no slice or no picked height at that site.

# The sheet the measure scripts write into. Used here only to check the columns
# exist before running. It must match SHEET_PATH in the measure scripts' CONFIG.
SHEET_PATH <- "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx"
SHEET_NAME <- 1                  # tab name or 1-based index, as in the measure scripts

# Where each script's results CSV goes. The CSVs are appended to, not
# replaced, so a second run adds its rows below the first.
OUT_DIR <- "C:/Projects/LiDAR_Project/Working_Steps/6_Measure"
VIZ_DIR <- NA                    # dendro_tape only: a folder for the per-slice pictures, or NA

UP_AXIS <- "y"                   # ForestScanner clouds are Y-up

# ---- sheet column names ----
# How each column is named. {site} is the site, {lang} is "RScript". The
# binned hulls add a percentile tag after the method: the 90th has none (those
# columns came first) and the 50th has "P50".
PERCENTILE_TAG <- c("90" = "", "50" = "P50")
COLUMNS <- list(
  dendro_tape              = c(out = "{site}_DendroTape_{lang}_Diameter_mm",
                               flag = "{site}_DendroTape_MaxEdgeFrac"),
  dab_itsme_concave_hull   = c(out = "{site}_DabItsme_ConcaveHull_{lang}_Diameter_mm"),
  bin_fixed_angle          = c(out = "{site}_BinFixedAngle{tag}_{lang}_Diameter_mm",
                               flag = "{site}_BinFixedAngle{tag}_MaxEdgeFrac"),
  bin_mean_distance_radius = c(out = "{site}_BinMeanDistanceRadius{tag}_{lang}_Diameter_mm",
                               flag = "{site}_BinMeanDistanceRadius{tag}_MaxEdgeFrac"),
  circle_fit               = c(out = "{site}_CircleFit_{lang}_Diameter_mm")
)
LANG <- "RScript"
# ITSMe re-cuts its band from the picked height, so it also needs the height
# column. It is Y_value_<site>, except for the two paint sites, whose headers
# are named this way in this project's sheet.
HEIGHT_COLS <- c(ForestGeoPaint = "Y_value_ForestGeoPaint (Red)",
                 DendroPaint    = "Y_value_DendroPaint (Blue)")
BINNED <- c("bin_fixed_angle", "bin_mean_distance_radius")
# =============================================================================

suppressMessages(library(readxl))

# this script's own folder, so it finds the measure scripts beside it
script_dir <- local({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(f)) dirname(normalizePath(f[1])) else "scripts/Step06_Measure"
})
rscript <- file.path(R.home("bin"), "Rscript")

fill <- function(pattern, site, tag) {
  x <- gsub("{site}", site, pattern, fixed = TRUE)
  x <- gsub("{tag}", tag, x, fixed = TRUE)
  gsub("{lang}", LANG, x, fixed = TRUE)
}

# ---- build the job list
jobs <- list()
for (method in METHODS) {
  if (!method %in% names(COLUMNS))
    stop("Unknown method '", method, "'. Choose from: ", paste(names(COLUMNS), collapse = ", "))
  pcts <- if (method %in% BINNED) PERCENTILES else NA
  for (pct in pcts) {
    tag <- ""
    if (!is.na(pct)) {
      key <- as.character(pct)
      if (!key %in% names(PERCENTILE_TAG))
        stop("Percentile ", pct, " has no entry in PERCENTILE_TAG, so its columns have no name.")
      tag <- PERCENTILE_TAG[[key]]
    }
    for (site in SITES) {
      pats <- COLUMNS[[method]]
      cols <- c("--output-col" = fill(pats[["out"]], site, tag))
      if ("flag" %in% names(pats)) cols["--flag-col"] <- fill(pats[["flag"]], site, tag)
      if (method == "dab_itsme_concave_hull")
        cols["--height-col"] <- if (site %in% names(HEIGHT_COLS)) HEIGHT_COLS[[site]] else paste0("Y_value_", site)
      csv_name <- paste0(method, "_r", if (nzchar(tag)) paste0("_", tolower(tag)) else "", ".csv")
      args <- c(file.path(script_dir, paste0(method, ".R")),
                "--from-sheet", "--up-axis", UP_AXIS, "--site", site,
                "--out", file.path(OUT_DIR, csv_name))
      for (flag in names(cols)) args <- c(args, flag, cols[[flag]])
      if (!is.na(pct)) args <- c(args, "--percentile", as.character(pct))
      if (method == "dendro_tape" && !is.na(VIZ_DIR)) args <- c(args, "--viz-dir", VIZ_DIR)
      label <- paste0(method, if (!is.na(pct)) paste0(" P", pct) else "")
      jobs[[length(jobs) + 1]] <- list(label = label, site = site, args = args, cols = unname(cols))
    }
  }
}

# ---- check every column exists before running anything
headers <- names(read_excel(SHEET_PATH, sheet = SHEET_NAME, n_max = 0))
gone    <- lapply(jobs, function(j) setdiff(j$cols, headers))
ready   <- jobs[lengths(gone) == 0]
missing <- jobs[lengths(gone) > 0]
cat(sprintf("%d jobs: %d ready, %d with a missing sheet column.\n", length(jobs), length(ready), length(missing)))
for (i in which(lengths(gone) > 0))
  cat(sprintf("  [no column] %s at %s: %s\n", jobs[[i]]$label, jobs[[i]]$site, paste(gone[[i]], collapse = ", ")))

# ---- run
quote_arg <- function(a) ifelse(grepl(" ", a), shQuote(a, type = "cmd"), a)
results <- list()
for (j in ready) {
  cat(sprintf("\n===== %s  %s\n", j$label, j$site))
  if (DRY_RUN) {
    cat(paste(quote_arg(c(rscript, j$args)), collapse = " "), "\n")
    next
  }
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  out <- suppressWarnings(system2(rscript, quote_arg(j$args), stdout = TRUE, stderr = TRUE))
  rc  <- attr(out, "status"); if (is.null(rc)) rc <- 0
  wrote <- grep("^Wrote .*value\\(s\\)", out, value = TRUE)
  skips <- grep("^\\[skip\\]", out, value = TRUE)
  flags <- grep("^\\[flagged\\]", out, value = TRUE)
  # the first "Wrote N value(s)" line is the diameter column
  n_done <- if (length(wrote)) as.integer(strsplit(wrote[1], " ")[[1]][2]) else 0L
  cat(sprintf("  measured %d, skipped %d, flagged %d\n", n_done, length(skips), length(flags)))
  for (l in c(if (SHOW_SKIPS) skips, flags)) cat("  ", l, "\n", sep = "")
  if (rc != 0) {
    cat("  -- failed, last lines of output:\n")
    for (l in tail(out, 15)) cat("     ", l, "\n", sep = "")
  }
  results[[length(results) + 1]] <- list(job = j, rc = rc, n_done = n_done,
                                         n_skip = length(skips), n_flag = length(flags))
}

if (DRY_RUN) {
  cat("\nDRY_RUN is on: nothing was run.\n")
  quit(status = 0)
}
cat("\n===== summary\n")
cat(sprintf("%-30s %-15s %-8s %8s %7s %7s\n", "method", "site", "result", "measured", "skipped", "flagged"))
for (r in results)
  cat(sprintf("%-30s %-15s %-8s %8d %7d %7d\n", r$job$label, r$job$site,
              if (r$rc == 0) "ok" else "FAILED", r$n_done, r$n_skip, r$n_flag))
for (j in missing) cat(sprintf("%-30s %-15s %-8s\n", j$label, j$site, "no col"))
n_bad <- sum(vapply(results, function(r) r$rc != 0, logical(1))) + length(missing)
quit(status = if (n_bad > 0) 1 else 0)
