#!/usr/bin/env Rscript
# =============================================================================
# plot_by_method.R -- the step 7 figures again, one panel per method.
#
# validate_field_accuracy.R, compare_hull_methods.R and plot_error_by_size.R
# draw every method together on one set of axes. This script draws the same
# comparisons split out, one facet per method, so each method's pattern can be
# read without the others on top of it. No new measurement, no new metric.
# The grouped figures are unchanged, this only adds six files.
#
# All five methods, at every validated site (Dendrometer and PaintMarker),
# one row per tree + site. DBH vs DAB and EXCLUDE_SITES follow the other step 7
# scripts. Open markers = flagged ring (MaxEdgeFrac >= FLAG_THRESHOLD), each
# method by its own flag (ITSMe uses DendroTape's, ForestScanner is never
# flagged). No row is dropped for having a large error.
#
# Outputs (results/plots/, or DAB_RESULTS/plots/):
#   by_method_scatter.png        estimate vs reading, 1:1 line, shared axes
#   by_method_error.png          signed % error per tree + site, plus averages
#   by_method_error_mm.png       signed error in mm, pseudo-log axis
#   by_method_boxplot.png        signed % error, DBH vs DAB
#   by_method_boxplot_mm.png     signed error in mm, DBH vs DAB
#   by_method_bland_altman.png   estimate - reading vs mean, per-method bias and limits
#
# Run:  Rscript scripts/Step07_Analysis/plot_by_method.R
# =============================================================================

suppressMessages({ library(readxl); library(dplyr); library(tidyr); library(ggplot2) })
source("scripts/plot_style.R")   # cwd-relative: run from the repo root

# =============================================================================
# CONFIG -- edit these for your own dataset. Same values as the other step 7
# scripts. `sheet` is an absolute path to the LOCAL working root, overridden by
# the DAB_SHEET env var. `outdir` defaults to the repo-relative results/
# folder, overridden by DAB_RESULTS. results/ is tracked, so what this writes
# there goes public when the repo is pushed.
# =============================================================================
sheet   <- Sys.getenv("DAB_SHEET",
                      "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
EXCLUDE_SENSITIVITY <- character(0)   # trees dropped from an extra average bar and the Bland-Altman limits, empty = none (3853 back in everything, its second-pass ring is fine, DJ 2026-09-28)
FLAG_THRESHOLD      <- 0.5         # MaxEdgeFrac at or above this = flagged ring (sheet values are 3-decimal, so >=)
PAINT_DBH_TREES     <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height, below any buttress: their PaintMarker site is DBH, not DAB (DJ, 2026-09-28)
EXCLUDE_SITES       <- c("6647 PaintMarker")   # tree + site left out of every analysis: bad scan at the mark (DJ, 2026-09-28)

# field reading column for each site with ground truth, and its short label
FIELD_COL  <- c(Dendrometer = "Dendrometer_FieldDiameter", PaintMarker = "PaintMarker_FieldDiameter_mm")
SITE_SHORT <- c(Dendrometer = "Dendro", PaintMarker = "Paint")
HAS_SENS   <- length(EXCLUDE_SENSITIVITY) > 0
EXCL_LABEL <- sprintf("excl. %s", paste(EXCLUDE_SENSITIVITY, collapse = ", "))

num <- function(x) suppressWarnings(as.numeric(x))

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

# same rows and method keys as plot_error_by_size.R (plot_style.R's
# relabel_method() maps the keys to the shared display labels)
acc <- bind_rows(lapply(names(FIELD_COL), function(s) raw %>%
  transmute(
    tree                        = Tree_Tag,
    site                        = s,
    reading                     = num(.data[[FIELD_COL[[s]]]]),
    ForestScanner               = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
    Python_true_hull            = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
    R                           = num(.data[[sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", s)]]),
    bin_hull_FixedAngle         = num(.data[[sprintf("%s_BinFixedAngle_pythonScript_Diameter_mm", s)]]),
    bin_hull_MeanDistanceRadius = num(.data[[sprintf("%s_BinMeanDistanceRadius_pythonScript_Diameter_mm", s)]]),
    # each method's own gap flag (ITSMe uses DendroTape's, same ring points)
    edge_dt = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", s)]]),
    edge_fa = num(.data[[sprintf("%s_BinFixedAngle_MaxEdgeFrac", s)]]),
    edge_md = num(.data[[sprintf("%s_BinMeanDistanceRadius_MaxEdgeFrac", s)]])
  ))) %>%
  filter(!is.na(reading)) %>%
  filter(!paste(tree, site) %in% EXCLUDE_SITES) %>%
  mutate(size = if_else(site == "Dendrometer" | tree %in% PAINT_DBH_TREES, "DBH", "DAB (above buttress)"))

if (nrow(acc) == 0) {
  cat("[by-method plots skipped] no field readings in the sheet yet\n")
  quit(save = "no", status = 0)
}

long <- acc %>%
  pivot_longer(c(ForestScanner, Python_true_hull, R, bin_hull_FixedAngle, bin_hull_MeanDistanceRadius),
               names_to = "method", values_to = "est") %>%
  filter(!is.na(est)) %>%
  mutate(err  = est - reading,
         pct  = 100 * err / reading,
         # ForestScanner doesn't use the ring, so it is never flagged
         edge = case_when(method %in% c("Python_true_hull", "R") ~ edge_dt,
                          method == "bin_hull_FixedAngle"         ~ edge_fa,
                          method == "bin_hull_MeanDistanceRadius" ~ edge_md),
         flagged      = !is.na(edge) & edge >= FLAG_THRESHOLD,
         method_label = relabel_method(method),
         # x-axis label for the per-tree plots, e.g. "3031 Dendro (724)"
         tree_label   = sprintf("%s %s (%.0f)", tree, SITE_SHORT[site], reading))

cat(sprintf("By-method plots: %d rows over %d tree-sites.\n",
            nrow(long), n_distinct(paste(long$tree, long$site))))
print(as.data.frame(long %>% count(method_label)), row.names = FALSE)

FLAG_SHAPE <- scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none")
flag_note  <- sprintf("open markers = flagged ring (MaxEdgeFrac >= %.1f)", FLAG_THRESHOLD)
save_plot  <- function(p, name, w, h) ggsave(file.path(plotdir, name), p, width = w, height = h, dpi = 130)

# ---- estimate vs reading: shared axes, so the panels compare directly
lim <- range(c(long$est, long$reading), na.rm = TRUE)
p_scatter <- ggplot(long, aes(reading, est, colour = method_label, shape = flagged)) +
  geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
  geom_point(size = 2.6, alpha = 0.9, stroke = 1) +
  facet_wrap(~ method_label, ncol = 3) +
  scale_colour_method(guide = "none") + FLAG_SHAPE +
  coord_equal(xlim = lim, ylim = lim) +
  labs(title = "Estimated Diameter vs. Field Reading, by Method",
       subtitle = paste0("All validated sites, dashed = 1:1, ", flag_note),
       x = "Field reading (mm)", y = "Estimated diameter (mm)") +
  theme_minimal(base_size = 11)
save_plot(p_scatter, "by_method_scatter.png", 11, 8)

# ---- per tree + site plots: shared tree order, two average entries per panel
tree_order  <- long %>% distinct(tree_label, reading) %>% arrange(reading) %>% pull(tree_label)
level_order <- c(tree_order, "Average", if (HAS_SENS) sprintf("Average (%s)", EXCL_LABEL))
averages <- function(col) {
  bind_rows(
    long %>% group_by(method, method_label) %>%
      summarise(value = mean(.data[[col]]), .groups = "drop") %>% mutate(tree_label = "Average"),
    if (HAS_SENS) long %>% filter(!tree %in% EXCLUDE_SENSITIVITY) %>% group_by(method, method_label) %>%
      summarise(value = mean(.data[[col]]), .groups = "drop") %>%
      mutate(tree_label = sprintf("Average (%s)", EXCL_LABEL))
  )
}
per_tree <- function(col) {
  bind_rows(long %>% transmute(method, method_label, tree_label, value = .data[[col]], flagged),
            averages(col) %>% mutate(flagged = FALSE)) %>%
    mutate(tree_label = factor(tree_label, levels = level_order))
}
boundary_avg <- length(tree_order) + 0.5   # rule between the last tree and the averages

# signed % error, bars. Each panel has its own y range so a method with small
# errors isn't flattened by one with large ones.
p_error <- ggplot(per_tree("pct"), aes(tree_label, value, fill = method_label)) +
  scale_x_discrete() +   # declared before the numeric vline, see compare_hull_methods.R FIG 3
  geom_vline(xintercept = boundary_avg, linetype = "dashed", colour = "grey70") +
  geom_col(width = 0.7) +
  geom_hline(yintercept = 0, colour = "grey40") +
  facet_wrap(~ method_label, ncol = 1, scales = "free_y") +
  scale_fill_method(guide = "none") +
  labs(title = "Signed Percent Error vs. Field Reading, by Method",
       subtitle = "Trees ordered by reading, plus per-method averages. The y axis differs per panel.",
       x = "Tree and site (field reading, mm)", y = "Error  (est - reading) / reading  [%]") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
save_plot(p_error, "by_method_error.png", 10, 13)

# signed error in mm, points on a pseudo-log axis (see compare_hull_methods.R
# FIG 3b for why points, not bars)
p_error_mm <- ggplot(per_tree("err"), aes(tree_label, value, colour = method_label, shape = flagged)) +
  scale_x_discrete() +
  geom_vline(xintercept = boundary_avg, linetype = "dashed", colour = "grey70") +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_point(size = 2.6, stroke = 1) +
  facet_wrap(~ method_label, ncol = 1) +
  scale_y_continuous(trans = scales::pseudo_log_trans(sigma = 10, base = 10),
                     breaks = c(-1000, -300, -100, -30, -10, 0, 10, 30, 100, 300, 1000)) +
  scale_colour_method(guide = "none") + FLAG_SHAPE +
  labs(title = "Signed Error vs. Field Reading (mm), by Method",
       subtitle = paste0("Trees ordered by reading, plus per-method averages, ", flag_note),
       x = "Tree and site (field reading, mm)", y = "Error  (est - reading)  [mm, pseudo-log]") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
save_plot(p_error_mm, "by_method_error_mm.png", 10, 13)

# ---- signed % error, DBH vs DAB
p_box <- ggplot(long, aes(size, pct, fill = size)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_boxplot(outlier.shape = NA, alpha = 0.7, width = 0.6) +
  geom_jitter(aes(shape = flagged), width = 0.12, height = 0, size = 1.8, alpha = 0.8) +
  facet_wrap(~ method_label, ncol = 3, scales = "free_y") +
  FLAG_SHAPE +
  scale_fill_manual(values = c("DBH" = "#56B4E9", "DAB (above buttress)" = "#D55E00"),
                    name = "Measurement type") +
  labs(title = "Signed Percent Error vs. Field Reading, by Method and Measurement Type",
       subtitle = paste0("All validated sites, ", flag_note, ". The y axis differs per panel."),
       x = NULL, y = "Error  (est - reading) / reading  [%]") +
  theme_minimal(base_size = 11)
save_plot(p_box, "by_method_boxplot.png", 11, 8)

# same box plot, signed error in mm (DJ, 2026-09-28)
p_box_mm <- p_box + aes(y = err) +
  labs(title = "Signed Error vs. Field Reading (mm), by Method and Measurement Type",
       y = "Error  (est - reading)  [mm]")
save_plot(p_box_mm, "by_method_boxplot_mm.png", 11, 8)

# ---- Bland-Altman: each panel gets its own bias and 95% limits, computed
# without the EXCLUDE_SENSITIVITY trees (every tree when it is empty), like the
# grouped figure in compare_hull_methods.R.
# Every point is still drawn.
ba_data  <- long %>% mutate(mean_est = (est + reading) / 2)
ba_lines <- ba_data %>% filter(!tree %in% EXCLUDE_SENSITIVITY) %>%
  group_by(method_label) %>%
  summarise(bias = mean(err), s = sd(err), .groups = "drop") %>%
  mutate(lo = bias - 1.96 * s, hi = bias + 1.96 * s)
p_ba <- ggplot(ba_data, aes(mean_est, err, colour = method_label, shape = flagged)) +
  geom_hline(yintercept = 0, colour = "grey30") +
  geom_hline(data = ba_lines, aes(yintercept = bias, colour = method_label), linetype = 2) +
  geom_hline(data = ba_lines, aes(yintercept = lo, colour = method_label), linetype = 3) +
  geom_hline(data = ba_lines, aes(yintercept = hi, colour = method_label), linetype = 3) +
  geom_point(size = 2.6, stroke = 1) +
  facet_wrap(~ method_label, ncol = 3, scales = "free_y") +
  scale_colour_method(guide = "none") + FLAG_SHAPE +
  labs(title = "Agreement with Field Reading (Bland-Altman), by Method",
       subtitle = paste0("dashed = mean bias, dotted = 95% limits of agreement",
                         if (HAS_SENS) paste0(" (", EXCL_LABEL, ")"), ", ", flag_note, ". The y axis differs per panel."),
       x = "Mean of estimate and reading (mm)", y = "Estimate - reading (mm)") +
  theme_minimal(base_size = 11)
save_plot(p_ba, "by_method_bland_altman.png", 11, 8)

cat(sprintf("\nWrote %s/by_method_{scatter,error,error_mm,boxplot,boxplot_mm,bland_altman}.png\n", plotdir))
