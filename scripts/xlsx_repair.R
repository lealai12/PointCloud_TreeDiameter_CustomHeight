# =============================================================================
# xlsx_repair.R -- pure-R fallback write path for sheet_batch.R's --from-sheet
# write-back, for use when no Python interpreter is available.
#
# BACKGROUND (see sheet_batch.R's header for the full story): openxlsx's
# load-then-save round trip has been found, on genuine Excel-authored
# workbooks (not just cross-tool round trips), to write two kinds of
# corruption that stricter OOXML readers (openpyxl among them) reject:
#   1. An empty workbookView (xWindow="" yWindow="" windowWidth=""
#      windowHeight="") when the source lacked that metadata.
#   2. A dangling <Relationship> entry in a part's .rels file -- e.g. a
#      worksheet -> drawing relationship -- whose Target file was never
#      actually written into the archive.
# sheet_batch.R's default write path avoids this entirely by shelling out to
# Python's openpyxl (proven not to introduce either issue). This file exists
# so a machine with no Python still has a safe write path: repair_xlsx()
# runs a save through openxlsx and then patches both defects directly in the
# saved .xlsx (a zip archive) before handing control back, so the corrupt
# intermediate state never reaches disk as the final file.
#
# Tested against a real, pristine, Excel-authored workbook (not just a
# synthetic one) plus a synthetic empty-bookViews case: both defects
# reproduce and both are fixed, verified by re-opening the repaired file
# with openpyxl and diffing every cell against the pre-repair original.
# =============================================================================
suppressMessages({ library(xml2); library(zip); library(openxlsx) })

# Resolve an OOXML relative Target (e.g. "../drawings/drawing1.xml") against
# the directory containing the part that owns the .rels file (e.g.
# "xl/worksheets"), returning a normalized forward-slash archive path.
.resolve_ooxml_path <- function(base_dir, rel_target) {
  parts <- strsplit(base_dir, "/")[[1]]
  rel_parts <- strsplit(rel_target, "/")[[1]]
  for (p in rel_parts) {
    if (p == "..") parts <- parts[-length(parts)]
    else if (p != ".") parts <- c(parts, p)
  }
  paste(parts, collapse = "/")
}

# Post-save repair for openxlsx::saveWorkbook() output. Strips only
# relationship entries that are actually dangling (target file absent from
# the archive) and only workbookView attrs that are actually empty; every
# other part is left byte-identical. Safe to call on any .xlsx -- a no-op if
# neither defect is present. Returns TRUE if it changed anything.
repair_xlsx <- function(path) {
  tmpdir <- tempfile("xlsx_repair_")
  dir.create(tmpdir)
  on.exit(unlink(tmpdir, recursive = TRUE), add = TRUE)

  zip::unzip(path, exdir = tmpdir)

  all_files <- list.files(tmpdir, recursive = TRUE, full.names = FALSE)
  all_files_norm <- gsub("\\\\", "/", all_files)

  any_changed <- FALSE

  # defect 1: empty workbookView window attributes
  wb_xml_path <- file.path(tmpdir, "xl", "workbook.xml")
  if (file.exists(wb_xml_path)) {
    wb_txt <- paste(readLines(wb_xml_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    if (grepl('xWindow=""', wb_txt, fixed = TRUE)) {
      wb_txt <- sub(
        '<workbookView[^>]*/>',
        '<workbookView xWindow="0" yWindow="0" windowWidth="19200" windowHeight="12545" firstSheet="0" activeTab="0"/>',
        wb_txt
      )
      writeLines(wb_txt, wb_xml_path, useBytes = TRUE)
      any_changed <- TRUE
    }
  }

  # defect 2: dangling relationship entries (any *_rels/*.rels part)
  rels_files <- all_files[grepl("_rels/.*\\.rels$", all_files_norm)]
  for (relf in rels_files) {
    relf_norm <- gsub("\\\\", "/", relf)
    full_path <- file.path(tmpdir, relf)
    doc <- read_xml(full_path)
    ns <- xml_ns(doc)
    rel_nodes <- xml_find_all(doc, "//d1:Relationship", ns)

    base_dir <- dirname(dirname(relf_norm))  # part dir owning this .rels file
    removed_ids <- character(0)
    file_changed <- FALSE

    for (node in rel_nodes) {
      target <- xml_attr(node, "Target")
      mode   <- xml_attr(node, "TargetMode")
      if (!is.na(mode) && tolower(mode) == "external") next
      if (is.na(target)) next
      resolved <- .resolve_ooxml_path(base_dir, target)
      if (!(resolved %in% all_files_norm)) {
        removed_ids <- c(removed_ids, xml_attr(node, "Id"))
        xml_remove(node)
        file_changed <- TRUE
      }
    }

    if (file_changed) {
      write_xml(doc, full_path)
      any_changed <- TRUE

      # also drop any reference to the removed id in the owning part itself
      # (e.g. <drawing r:id="rId1"/> in sheet1.xml), so nothing points at a
      # relationship that no longer exists.
      owning_part <- file.path(tmpdir, base_dir, sub("\\.rels$", "", basename(relf)))
      if (length(removed_ids) && file.exists(owning_part)) {
        pdoc <- read_xml(owning_part)
        pns <- xml_ns(pdoc)
        for (rid in removed_ids) {
          refs <- xml_find_all(pdoc, sprintf("//*[@r:id='%s']", rid), pns)
          for (r in refs) xml_remove(r)
        }
        write_xml(pdoc, owning_part)
      }
    }
  }

  if (any_changed) {
    if (file.exists(path)) file.remove(path)
    old_wd <- setwd(tmpdir)
    on.exit(setwd(old_wd), add = TRUE)
    zip::zip(path, files = all_files, root = tmpdir)
  }

  invisible(any_changed)
}

# Direct-R write-back fallback for sheet_batch.R's write_back_all(), used
# only when no Python interpreter is available. Loads the workbook with
# openxlsx, writes each update into output_col by sheet row, saves, then
# repairs the two known defects above before returning.
write_back_all_direct_r <- function(sheet_path, sheet_name, output_col, updates) {
  if (length(updates) == 0) return(invisible(NULL))

  wb <- loadWorkbook(sheet_path)
  sheets <- names(wb)
  target_sheet <- if (is.numeric(sheet_name)) sheets[sheet_name] else sheet_name

  header <- readxl::read_excel(sheet_path, sheet = sheet_name, n_max = 0)
  col_idx <- match(output_col, names(header))
  if (is.na(col_idx)) {
    stop(sprintf("Column '%s' not found in %s", output_col, sheet_path))
  }

  for (u in updates) {
    writeData(wb, sheet = target_sheet, x = u$value,
              startRow = u$row, startCol = col_idx, colNames = FALSE)
  }
  saveWorkbook(wb, sheet_path, overwrite = TRUE)
  repair_xlsx(sheet_path)
  invisible(NULL)
}
