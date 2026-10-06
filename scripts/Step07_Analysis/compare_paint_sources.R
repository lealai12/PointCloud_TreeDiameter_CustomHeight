#!/usr/bin/env Rscript
# =============================================================================
# compare_paint_sources.R -- the two paint-mark sources side by side.
#
# The trees carry two kinds of paint mark, set by two programs that measured
# differently (DJ, 2026-10-06):
#   ForestGeoPaint = red, the ForestGEO census mark,
#   DendroPaint    = blue, the dendrometer-program mark.
# Each has its own field diameter and date. The per-source analyses are the
# other step 7 scripts, run once per source. This script puts the two next to
# each other:
#   1. MAE (and bias, MAPE, n) per method, red against blue, over each source's
#      paint sites, overall and by group (DBH low marks, DAB above buttress).
#      The Dendrometer bands are the same in both, so they are left out here.
#      Extra "excl." sets leave out the EXCLUDE_SENSITIVITY pairs.
#   2. For trees with both sources: every scan estimate against both field
#      values, and the difference between the two field values. Where the two
#      marks share a Y the slice is the same, so only the reference differs.
#      Where the Y differs the marks are at different heights.
#
# The old PaintMarker site is not used: its values are split by source into
# these two sites.
#
# Outputs (results/, or DAB_RESULTS):
#   paint_sources_mae.csv          per method, source and group: n, bias, MAE, RMSE (mm), MAPE
#   paint_sources_both_trees.csv   per tree with both sources, per method: both estimates,
#                                  both field values, every error, the field difference
#   plots/paint_sources_mae.png    MAE per method, red next to blue, overall and by group
#
# Run:  Rscript scripts/Step07_Analysis/compare_paint_sources.R
# =============================================================================

suppressMessages({ library(readxl); library(dplyr); library(tidyr); library(ggplot2) })
source("scripts/plot_style.R")   # cwd-relative: run from the repo root

# =============================================================================
# CONFIG -- same sheet, output folder and site lists as the other step 7 scripts.
# =============================================================================
sheet   <- Sys.getenv("DAB_SHEET",
                      "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
PAINT_DBH_TREES <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height: DBH, not DAB (DJ, 2026-09-28)
EXCLUDE_SITES   <- character(0)   # tree + site pairs left out, e.g. "6647 DendroPaint". Empty: both 6647 marks stay in (DJ, 2026-10-06)
EXCLUDE_SENSITIVITY <- c("3853 ForestGeoPaint")   # tree + site pairs for extra "excl." sets, empty = none. 3853's red field value (967 mm) is probably a bad measurement, not a typo: every method and the blue value read about 1330 (DJ, 2026-10-06)
SOURCES    <- c(ForestGeoPaint = "Red (ForestGEO)", DendroPaint = "Blue (dendrometer program)")
Y_COL      <- c(ForestGeoPaint = "Y_value_ForestGeoPaint (Red)", DendroPaint = "Y_value_DendroPaint (Blue)")   # named this way in the sheet (DJ, 2026-10-06)
METHODS    <- c(ForestScanner = "ForestScanner", Python_true_hull = "DendroTape_pythonScript",
                bin_hull_FixedAngle = "BinFixedAngle_pythonScript",
                bin_hull_MeanDistanceRadius = "BinMeanDistanceRadius_pythonScript",
                R = "DabItsme_ConcaveHull_RScript", Circle = "CircleFit_pythonScript")

num <- function(x) suppressWarnings(as.numeric(x))
raw <- read_excel(sheet) %>% mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag), Tree_Tag != "XXXX")

# one row per tree x source x method, at that source's paint site
paint <- bind_rows(lapply(names(SOURCES), function(s) {
  bind_rows(lapply(names(METHODS), function(m) raw %>% transmute(
    tree = Tree_Tag, source = s, method = m,
    y = num(.data[[Y_COL[[s]]]]),
    field = num(.data[[sprintf("%s_FieldDiameter_mm", s)]]),
    field_date = as.character(.data[[sprintf("%s_Date", s)]]),
    est = num(.data[[sprintf("%s_%s_Diameter_mm", s, METHODS[[m]])]]),
    has_slice = !is.na(num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]])))))
})) %>%
  filter(!is.na(field), has_slice, !paste(tree, source) %in% EXCLUDE_SITES) %>%
  mutate(group = if_else(tree %in% PAINT_DBH_TREES, "DBH (low paint mark)", "DAB (above buttress)"),
         method_label = relabel_method(method))

# ---- 1. MAE per method, red against blue
stats <- function(d, label) d %>% filter(!is.na(est)) %>% group_by(source, method_label) %>%
  summarise(set = label, n = n(), bias = mean(est - field), MAE = mean(abs(est - field)),
            RMSE = sqrt(mean((est - field)^2)), MAPE = mean(100 * abs(est - field) / field), .groups = "drop")
# sensitivity sets without the EXCLUDE_SENSITIVITY pairs (the headline sets keep them)
sens     <- paint %>% filter(paste(tree, source) %in% EXCLUDE_SENSITIVITY)
excl_tag <- sprintf(", excl. %s", paste(unique(sprintf("%s %s", sens$tree,
                    c(ForestGeoPaint = "Red", DendroPaint = "Blue")[sens$source])), collapse = ", "))
paint_s  <- paint %>% filter(!paste(tree, source) %in% EXCLUDE_SENSITIVITY)
SETS <- c("all paint sites", if (nrow(sens) > 0) paste0("all paint sites", excl_tag),
          "DBH (low paint mark)", "DAB (above buttress)",
          if (nrow(sens) > 0) paste0("DAB (above buttress)", excl_tag))
mae <- bind_rows(stats(paint, SETS[1]),
                 if (nrow(sens) > 0) stats(paint_s, SETS[2]),
                 stats(paint %>% filter(group == "DBH (low paint mark)"), "DBH (low paint mark)"),
                 stats(paint %>% filter(group == "DAB (above buttress)"), "DAB (above buttress)"),
                 if (nrow(sens) > 0) stats(paint_s %>% filter(group == "DAB (above buttress)"), SETS[5])) %>%
  mutate(source = SOURCES[source]) %>% relocate(set) %>%
  arrange(factor(set, SETS), method_label, source)
write.csv(mae, file.path(outdir, "paint_sources_mae.csv"), row.names = FALSE)
cat("-- MAE per method, red against blue (paint sites only; the bands are the same in both) --\n")
print(as.data.frame(mae %>% mutate(across(c(bias, MAE, RMSE), round), MAPE = round(MAPE, 1)) %>%
  select(set, method_label, source, n, bias, MAE, MAPE) %>%
  pivot_wider(names_from = source, values_from = c(n, bias, MAE, MAPE))), row.names = FALSE)

# ---- 2. trees with both sources
both_trees <- paint %>% distinct(tree, source) %>% count(tree) %>% filter(n == 2) %>% pull(tree)
both <- paint %>% filter(tree %in% both_trees) %>%
  select(tree, source, method_label, y, field, field_date, est) %>%
  pivot_wider(names_from = source, values_from = c(y, field, field_date, est)) %>%
  transmute(tree, method = method_label,
            same_slice = !is.na(y_ForestGeoPaint) & y_ForestGeoPaint == y_DendroPaint,
            y_red = y_ForestGeoPaint, y_blue = y_DendroPaint,
            field_red = field_ForestGeoPaint, field_red_date = field_date_ForestGeoPaint,
            field_blue = field_DendroPaint, field_blue_date = field_date_DendroPaint,
            field_blue_minus_red = field_DendroPaint - field_ForestGeoPaint,
            est_red_slice = est_ForestGeoPaint, est_blue_slice = est_DendroPaint,
            red_slice_vs_red_field   = est_ForestGeoPaint - field_ForestGeoPaint,
            red_slice_vs_blue_field  = est_ForestGeoPaint - field_DendroPaint,
            blue_slice_vs_blue_field = est_DendroPaint - field_DendroPaint,
            blue_slice_vs_red_field  = est_DendroPaint - field_ForestGeoPaint) %>%
  arrange(tree, method)
write.csv(both, file.path(outdir, "paint_sources_both_trees.csv"), row.names = FALSE)
cat(sprintf("\n-- trees with both sources (%s): field values and the circle fit / convex hull --\n",
            paste(both_trees, collapse = ", ")))
print(as.data.frame(both %>% filter(method %in% c("Convex hull", "Circle fit (least squares)")) %>%
  select(tree, method, same_slice, y_red, y_blue, field_red, field_blue, field_blue_minus_red,
         red_slice_vs_red_field, blue_slice_vs_blue_field) %>%
  mutate(across(where(is.double), ~ round(.x, 2)))), row.names = FALSE)

# ---- figure: MAE per method, red next to blue
# Each panel's axis is set by the cloud methods (DJ, 2026-10-06). A ForestScanner
# bar taller than 1.3 x the tallest cloud-method bar in its panel is cut there
# and labelled with its full value.
pd <- mae %>% mutate(set = factor(set, SETS), source = factor(source, SOURCES)) %>%
  group_by(set) %>%
  mutate(cap      = 1.3 * max(MAE[method_label != "ForestScanner (in-app)"]),
         cut      = MAE > cap,
         MAE_plot = pmin(MAE, cap),
         bar_text = if_else(cut, sprintf("%.0f mm, n=%d", MAE, n), sprintf("n=%d", n))) %>%
  ungroup()
p <- ggplot(pd, aes(method_label, MAE_plot, fill = source)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_text(aes(label = bar_text), position = position_dodge(0.8), vjust = -0.3, size = 2.6) +
  facet_wrap(~ set, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = setNames(c("#CC3311", "#56B4E9"), SOURCES), name = "Paint source") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.18))) +
  labs(title = "Mean Absolute Error per Method, Red (ForestGEO) and Blue (Dendrometer Program) Paint Marks",
       subtitle = paste("Each source against its own field diameter, at its own paint sites. The y axis differs per panel.",
                        "Each axis is set by the cloud methods. A ForestScanner bar past it is cut and labelled with its full MAE.",
                        sep = "\n"),
       x = NULL, y = "MAE (mm)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 25, hjust = 1), legend.position = "bottom")
ggsave(file.path(plotdir, "paint_sources_mae.png"), p, width = 11, height = 3 + 2.6 * length(SETS), dpi = 130)
cat(sprintf("\nWrote %s/paint_sources_{mae,both_trees}.csv and %s/paint_sources_mae.png\n", outdir, plotdir))
