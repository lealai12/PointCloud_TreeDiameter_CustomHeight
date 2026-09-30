#!/usr/bin/env Rscript
# =============================================================================
# plot_error_by_size.R -- one box plot: signed % error vs. field reading,
# every method, split by measurement type: DBH (the Dendrometer site and the
# breast-height paint marks) vs. DAB (above-buttress paint marks).
#
# validate_field_accuracy.R and compare_hull_methods.R each report per-tree
# error and size-stratified summary stats, but neither puts every method
# side by side on one axis to compare the SHAPE of each method's error
# distribution across the split -- that's what this is for. No new
# measurement, no new metric: same errors those two scripts already compute,
# just all six methods in one plot.
#
# GROUPING: by measurement type, not a diameter threshold. The split that
# actually matters here is WHY a tree is hard to measure. DBH is the
# Dendrometer site plus the PaintMarker site on the PAINT_DBH_TREES (CONFIG),
# whose paint mark sits at breast height below any buttress. DAB is every other
# PaintMarker site, a buttressed trunk measured above the buttress.
# Tree + site pairs in EXCLUDE_SITES (CONFIG) are left out.
# Rows are keyed by tree + site, since a tree can have a reading at both.
# (An earlier version of this script used a raw <1000mm/>=1000mm threshold,
# which is a proxy, not the actual reason these trees are hard.)
#
# Reads only the real-tag working sheet, same as the other step 7 scripts.
# =============================================================================

suppressMessages({ library(readxl); library(dplyr); library(tidyr); library(ggplot2) })
source("scripts/plot_style.R")   # cwd-relative: run from the repo root

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
# `outdir` defaults to the repo-relative results/ folder, and the DAB_RESULTS
# env var overrides it. results/ is tracked, so what this writes there goes
# public when the repo is pushed. Run from the repo root (source() above is
# repo-relative).
# =============================================================================
sheet   <- Sys.getenv("DAB_SHEET",
                      "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
EXCLUDE_SENSITIVITY <- character(0)   # trees for an extra "excl." sensitivity row and average bar, empty = none (3853 back in everything, its second-pass ring is fine, DJ 2026-09-28)
FLAG_THRESHOLD      <- 0.5         # MaxEdgeFrac at or above this = flagged ring (sheet values are 3-decimal, so >=)
PAINT_DBH_TREES     <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height, below any buttress: their PaintMarker site is DBH, not DAB (DJ, 2026-09-28)
EXCLUDE_SITES       <- c("6647 PaintMarker")   # tree + site left out of every analysis: bad scan at the mark (DJ, 2026-09-28)

# field reading column for each site with ground truth
FIELD_COL <- c(Dendrometer = "Dendrometer_FieldDiameter", PaintMarker = "PaintMarker_FieldDiameter_mm")

num   <- function(x) suppressWarnings(as.numeric(x))

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

# pivot column names use plot_style.R's internal method keys (relabel_method()
# maps them to the shared display labels below) so this figure's colours and
# names match every other results/plots/*.png in this repo.
acc <- bind_rows(lapply(names(FIELD_COL), function(s) raw %>%
  transmute(
    tree                  = Tree_Tag,
    site                  = s,
    reading               = num(.data[[FIELD_COL[[s]]]]),
    ForestScanner         = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
    Python_true_hull      = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
    Circle                = num(.data[[sprintf("%s_CircleFit_pythonScript_Diameter_mm", s)]]),
    R                     = num(.data[[sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", s)]]),
    bin_hull_FixedAngle  = num(.data[[sprintf("%s_BinFixedAngle_pythonScript_Diameter_mm", s)]]),
    bin_hull_MeanDistanceRadius      = num(.data[[sprintf("%s_BinMeanDistanceRadius_pythonScript_Diameter_mm", s)]]),
    # each method's own gap flag (ITSMe uses DendroTape's, same ring points)
    edge_dt = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", s)]]),
    edge_fa = num(.data[[sprintf("%s_BinFixedAngle_MaxEdgeFrac", s)]]),
    edge_md = num(.data[[sprintf("%s_BinMeanDistanceRadius_MaxEdgeFrac", s)]])
  ))) %>%
  filter(!is.na(reading)) %>%
  filter(!paste(tree, site) %in% EXCLUDE_SITES) %>%
  mutate(size = if_else(site == "Dendrometer" | tree %in% PAINT_DBH_TREES, "DBH", "DAB (above buttress)"))

if (nrow(acc) == 0) {
  cat("[error-by-size skipped] no field readings in the sheet yet\n")
  quit(save = "no", status = 0)
}

long <- acc %>%
  pivot_longer(c(ForestScanner, Python_true_hull, R, bin_hull_FixedAngle, bin_hull_MeanDistanceRadius, Circle),
               names_to = "method", values_to = "est") %>%
  filter(!is.na(est)) %>%
  mutate(err   = est - reading,
         pct   = 100 * err / reading,
         # ForestScanner doesn't use the ring, so it is never flagged
         edge  = case_when(method %in% c("Python_true_hull", "R", "Circle") ~ edge_dt,
                           method == "bin_hull_FixedAngle"         ~ edge_fa,
                           method == "bin_hull_MeanDistanceRadius" ~ edge_md),
         flagged = !is.na(edge) & edge >= FLAG_THRESHOLD,
         method_label = relabel_method(method))

long_clean <- long

cat(sprintf("Error-by-size box plot: %d rows.\n", nrow(long_clean)))
cat("\n-- n per method x size --\n")
print(as.data.frame(long_clean %>% count(method_label, size)), row.names = FALSE)

write.csv(long_clean %>% select(tree, site, size, reading, method = method_label, est, err, pct),
          file.path(outdir, "error_by_size_pertree.csv"), row.names = FALSE)

p <- ggplot(long_clean, aes(method_label, pct, fill = size)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_boxplot(outlier.shape = NA, alpha = 0.7, width = 0.6,
               position = position_dodge(0.7)) +
  # flagged rings get an open marker. group = size keeps the points dodged into
  # the same two slots as the boxes, rather than one slot per size x flag.
  geom_point(aes(shape = flagged, group = size),
             position = position_jitterdodge(jitter.width = 0.12, dodge.width = 0.7),
             size = 1.8, alpha = 0.8) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
  scale_fill_manual(values = c("DBH" = "#56B4E9", "DAB (above buttress)" = "#D55E00"),
                     name = "Measurement type") +
  labs(title = "Signed Percent Error vs. Field Reading, by Method and Measurement Type",
       subtitle = sprintf("Every method compared against field reading, dendrometer and paint-marker sites\n(n=%d tree-sites). Open markers = flagged ring (MaxEdgeFrac >= %.1f)",
                           n_distinct(paste(long_clean$tree, long_clean$site)), FLAG_THRESHOLD),
       x = NULL, y = "Error  (est - reading) / reading  [%]") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

out_png <- file.path(plotdir, "error_by_size_boxplot.png")
ggsave(out_png, p, width = 9.5, height = 6.2, dpi = 130)
cat(sprintf("\nWrote %s and\n  %s\n", file.path(outdir, "error_by_size_pertree.csv"), out_png))
