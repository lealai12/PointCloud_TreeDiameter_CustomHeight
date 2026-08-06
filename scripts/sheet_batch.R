# =============================================================================
# sheet_batch.R -- shared spreadsheet-driven batch-run helper for the
# per-.ply measurement scripts (dab_itsme.R, dendro_tape.R, median_polygon.R,
# median_polygon_2deg.R).
#
# WHY THIS EXISTS
# ----------------
# Each measurement script normally runs once per tree, with the tree's
# height (if any) typed by hand into --height/--height-z and its .ply path
# typed by hand as the positional argument -- fine for one-off work, but it
# doesn't batch (none of the four R measurement scripts have ever had a
# --batch flag at all, unlike their Python counterparts), and it ties every
# run to one specific file layout and column-naming scheme. This module lets
# a script instead read tree ID / height / output column straight from a
# spreadsheet (the CONFIG block at the top of each script) and loop over
# every row in one run -- someone with different column names and folders
# only has to edit that CONFIG block, not the measurement code.
#
# Shared ACROSS the four R measurement scripts -- this is plumbing, not
# measurement logic, so it does NOT fall under the "two independent
# implementations, deliberately kept separate" convention these scripts
# otherwise follow. That convention is about Python vs R each independently
# fitting the same tree as a correctness cross-check; sharing this file is
# plain DRY, same reasoning as plot_style.R. NOT shared with the Python
# side: scripts/sheet_batch.py is an independently written Python
# equivalent for the Python measurement scripts' own batch/read step --
# though see WRITE-BACK below, the actual write always goes through the
# Python path regardless of which language is doing the measuring.
#
# WRITE-BACK: WHY THIS PREFERS SHELLING OUT TO PYTHON OVER WRITING DIRECTLY
# ------------------------------------------------------------------------
# An earlier version of this file used the `openxlsx` package to load, edit,
# and save the workbook directly in R. Testing (2026-08-03) found that
# openxlsx's load-then-save round trip writes two kinds of corruption that
# openpyxl's stricter reader then refuses to re-open -- confirmed not just on
# cross-tool round trips but on a genuinely pristine, Excel-authored
# workbook: (1) empty bookViews window attributes, and (2) a dangling
# worksheet -> drawing relationship pointing at a file that never actually
# gets written into the archive (openpyxl raises KeyError hunting for it).
# Both are real, reproducible corruption risks against a hand-maintained,
# irreplaceable spreadsheet.
#
# The default write path therefore still routes every write -- from either
# language -- through the one path proven safe in both directions: openpyxl,
# via scripts/xlsx_write_back.py. This needs `python`/`python3` resolvable on
# PATH; see PYTHON_BIN below if that's not the case on your machine.
#
# For a machine with no Python at all (e.g. an RStudio-only install), a
# direct-R fallback exists in scripts/xlsx_repair.R: it writes with
# openxlsx as before, then patches both defects above directly in the saved
# .xlsx before handing control back, so the corrupt intermediate state never
# reaches disk as the final file. write_back_all() below tries Python first
# (matching the rest of the project's convention) and only falls back to
# this direct-R path -- with a printed warning -- when no Python interpreter
# is found on PATH. See xlsx_repair.R's header for how it was verified.
# =============================================================================
suppressMessages(library(readxl))

# Which Python interpreter to shell out to for the write-back step. Override
# if `python` isn't on PATH or resolves to the wrong install (e.g. set to a
# venv's python.exe, or "python3"). If neither resolves, write_back_all()
# falls back to the direct-R path in xlsx_repair.R.
PYTHON_BIN <- Sys.getenv("SHEET_BATCH_PYTHON", unset = "python")

.python_available <- function() {
  found <- Sys.which(PYTHON_BIN)
  if (nzchar(found)) return(TRUE)
  # PYTHON_BIN may have been left at its "python" default on a machine that
  # only has "python3" -- give that one shot before giving up.
  if (identical(PYTHON_BIN, "python")) return(nzchar(Sys.which("python3")))
  FALSE
}

# Read (tree_id, height, ply path, sheet row) for every row that has a tree
# ID and, if height_col is given, a non-empty height. Rows missing either
# are skipped with a printed reason -- normal mid-project state (not every
# tree has been picked/cut yet), not necessarily an error.
load_manifest <- function(sheet_path, sheet_name, tree_id_col, height_col,
                          ply_folder, ply_filename_pattern, site_label) {
  df <- readxl::read_excel(sheet_path, sheet = sheet_name)
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  if (!(tree_id_col %in% names(df))) {
    stop(sprintf("Column '%s' not found in %s", tree_id_col, sheet_path))
  }
  if (!is.null(height_col) && !(height_col %in% names(df))) {
    stop(sprintf("Column '%s' not found in %s", height_col, sheet_path))
  }

  manifest <- list()
  for (i in seq_len(nrow(df))) {
    tree_id <- df[[tree_id_col]][i]
    if (is.na(tree_id) || trimws(as.character(tree_id)) == "") next

    height <- NA_real_
    if (!is.null(height_col)) {
      height <- suppressWarnings(as.numeric(df[[height_col]][i]))
      if (is.na(height)) {
        cat(sprintf("[skip] %s: no value in '%s' yet\n", tree_id, height_col))
        next
      }
    }

    fname <- gsub("\\{tree_id\\}", as.character(tree_id), ply_filename_pattern, fixed = FALSE)
    fname <- gsub("\\{site\\}", if (is.null(site_label)) "" else site_label, fname, fixed = FALSE)
    path  <- file.path(ply_folder, fname)
    if (!file.exists(path)) {
      cat(sprintf("[skip] %s: %s not found\n", tree_id, path))
      next
    }

    # readxl data row i is workbook sheet row i+1 (row 1 is the header).
    manifest[[length(manifest) + 1]] <- list(
      tree_id = as.character(tree_id),
      height  = height,
      path    = path,
      row     = i + 1
    )
  }
  manifest
}

# Write every update (list(row=<sheet row>, value=<...>)) into output_col by
# shelling out to scripts/xlsx_write_back.py -- see the module header for
# why this doesn't write the xlsx directly. No-op if output_col is NULL or
# there's nothing to write -- callers can call this unconditionally. Run
# from the repo root (matching every other script's documented usage), so
# the relative path to xlsx_write_back.py resolves.
#
# `sheet_name` here uses R/readxl's convention (1-based when numeric, same
# value you'd pass to load_manifest above) -- xlsx_write_back.py's own
# --sheet-name is 0-based (openpyxl convention, matching Python's own
# CONFIG blocks), so a numeric sheet_name is converted here, once, rather
# than making every R script's CONFIG block reason about two different
# indexing conventions for the "same" number.
write_back_all <- function(sheet_path, sheet_name, output_col, updates) {
  if (is.null(output_col) || length(updates) == 0) return(invisible(NULL))

  if (!.python_available()) {
    cat("[write-back] No Python interpreter found on PATH -- falling back to\n",
        "  the direct-R write path (scripts/xlsx_repair.R). This works, but\n",
        "  the Python/openpyxl path is the one exercised most in testing;\n",
        "  install Python and put it on PATH (or set SHEET_BATCH_PYTHON) if\n",
        "  you'd rather use that path instead.\n", sep = "")
    source("scripts/xlsx_repair.R")
    return(write_back_all_direct_r(sheet_path, sheet_name, output_col, updates))
  }

  py_sheet_name <- if (is.numeric(sheet_name)) sheet_name - 1 else sheet_name

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp), add = TRUE)
  lines <- vapply(updates, function(u) sprintf("%d,%s", u$row, format(u$value, scientific = FALSE)),
                  character(1))
  writeLines(lines, tmp)

  script <- "scripts/xlsx_write_back.py"
  if (!file.exists(script)) {
    stop("scripts/xlsx_write_back.py not found -- run this from the repo root.")
  }
  args <- c(script, "--sheet", sheet_path, "--sheet-name", as.character(py_sheet_name),
            "--output-col", output_col, "--updates-csv", tmp)
  status <- system2(PYTHON_BIN, args)
  if (status != 0) {
    stop(sprintf("xlsx_write_back.py failed (exit %d) -- sheet NOT updated. ",
                 status),
        "Check that '", PYTHON_BIN, "' resolves to a working Python with openpyxl ",
        "installed (override via the SHEET_BATCH_PYTHON env var if needed).")
  }
}
