#!/usr/bin/env Rscript
# =============================================================================
# bin_fixed_angle_demo.R -- demonstration table + figure of the
# binned-hull, 2-degree-bin method (bin_fixed_angle.py) across every
# processed tree/site, not just the field-validated subset.
#
# WHY THIS EXISTS
# ----------------
# validate_field_accuracy.R answers "which method is most accurate" using
# only sites with a field reading to compare against. This script answers a
# different question: "what does the method identified as most effective
# actually produce, across every site processed so far" -- a demonstration/
# coverage view, not a new accuracy result.
#
# WORKING SHEET ONLY, same as validate_field_accuracy.R
# -------------------------------------------------------------------
# Reads only the real-tag working sheet. Output goes to results/ (or
# DAB_RESULTS), same as every other output in this repo.
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(ggplot2); library(readxl) })

# =============================================================================
# CONFIG -- edit these for your own dataset.
#
# Same role as the CONFIG block at the top of every measurement script
# (fit_dab.py/.R etc.): the one place a future researcher with a different
# sheet location has to edit. `sheet` is deliberately an absolute path to the
# LOCAL working root, not a repo-relative one. The working sheet holds real
# tree tags, lives outside version control and is never committed.
#
# Note the project's standing advice (CLAUDE.md): every script in this repo
# hardcodes this same path, so recreating that folder structure locally is
# usually simpler and less error-prone than editing the path in each script.
# Override without editing the file by setting the DAB_SHEET env var.
#
# SITE_COLUMN_PATTERN selects which binned-hull variant this demo plots.
# It currently points at the 2-degree-bin columns (hence this script's name),
# because on THIS project's validated subset the 2-degree and 10mm arc-length
# variants came out virtually identical with 2 degrees marginally ahead. That
# is a finding about this dataset, not a general result -- the two variants
# diverge as trunk size varies, so another project may well prefer the other
# one. To plot the 10mm variant instead, switch this to
# "%s_BinMeanDistanceRadius_pythonScript_Diameter_mm" and update this script's
# name, title and subtitle to match.
#
# `outdir` defaults to the repo-relative results/ folder, and the DAB_RESULTS
# env var overrides it. results/ is tracked, so what this writes there goes
# public when the repo is pushed. Run from the repo root.
# =============================================================================
sheet   <- Sys.getenv("DAB_SHEET",
                      "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
SITE_COLUMN_PATTERN <- "%s_BinFixedAngle_pythonScript_Diameter_mm"   # 2-degree bin
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
EXCLUDE_SENSITIVITY <- character(0)   # trees for an extra "excl." sensitivity row and average bar, empty = none (3853 back in everything, its second-pass ring is fine, DJ 2026-09-28)
FLAG_THRESHOLD      <- 0.5         # MaxEdgeFrac at or above this = flagged ring (sheet values are 3-decimal, so >=)

# field reading column for each site with ground truth (NA at the other sites).
# Both paint sources are shown (DJ, 2026-10-06). The old PaintMarker site is
# not: its values are split by source into ForestGeoPaint and DendroPaint.
FIELD_COL <- c(Dendrometer = "Dendrometer_FieldDiameter",
               ForestGeoPaint = "ForestGeoPaint_FieldDiameter_mm", DendroPaint = "DendroPaint_FieldDiameter_mm")
# picked-height column per site; two are named this way in the sheet (DJ, 2026-10-06)
HEIGHT_COL <- c(ForestGeoPaint = "Y_value_ForestGeoPaint (Red)", DendroPaint = "Y_value_DendroPaint (Blue)")

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

sites <- c("TopFlag", "LowerFlag", "ForestGeoPaint", "DendroPaint", "Dendrometer")

demo <- bind_rows(lapply(sites, function(s) {
  # looked up outside transmute(): NA at sites with no field column
  field <- if (s %in% names(FIELD_COL)) suppressWarnings(as.numeric(raw[[FIELD_COL[[s]]]])) else NA_real_
  raw %>%
    transmute(tree_id = Tree_Tag,
              site = s,
              height_m = .data[[if (s %in% names(HEIGHT_COL)) HEIGHT_COL[[s]] else sprintf("Y_value_%s", s)]],
              diameter_mm = .data[[sprintf(SITE_COLUMN_PATTERN, s)]],
              field_reading_mm = field,
              flagged = suppressWarnings(as.numeric(.data[[sprintf("%s_BinFixedAngle_MaxEdgeFrac", s)]])) >= FLAG_THRESHOLD)
})) %>%
  filter(!is.na(diameter_mm)) %>%
  arrange(diameter_mm) %>%
  mutate(tree_id = factor(tree_id, levels = unique(tree_id)))

write.csv(demo, file.path(outdir, "bin_fixed_angle_demo_all_sites.csv"), row.names = FALSE)
cat(sprintf("Wrote %d rows -> %s\n", nrow(demo), file.path(outdir, "bin_fixed_angle_demo_all_sites.csv")))
cat("\n")
print(as.data.frame(demo), row.names = FALSE)

# --------------------------------------------------------------------- figure
p <- ggplot(demo, aes(tree_id, diameter_mm, colour = site)) +
  geom_point(size = 3) +
  scale_colour_manual(values = c(LowerFlag = "#0072B2", Dendrometer = "#009E73", TopFlag = "#E69F00",
                                 ForestGeoPaint = "#CC3311", DendroPaint = "#56B4E9"),
                       name = "Site") +
  labs(title = "Binned hull, fixed angle -- diameter at every processed site",
       subtitle = "Applied to every processed tree/site, not just the field-validated subset used to check it\n(first pass: 2° and 10mm arc-length bins scored virtually identically here -- a result specific to this dataset)",
       x = "Tree tag", y = "Binned-hull equivalent diameter (mm)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 60, hjust = 1))

out_png <- file.path(plotdir, "bin_fixed_angle_demo_all_sites.png")
ggsave(out_png, p, width = 10, height = 6, dpi = 130)
cat(sprintf("\nWrote %s\n", out_png))
