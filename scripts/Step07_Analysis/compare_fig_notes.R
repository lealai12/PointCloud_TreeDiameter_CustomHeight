#!/usr/bin/env Rscript
# =============================================================================
# compare_fig_notes.R -- error vs. field reading and the fig notes.
#
# On the second pass the four largest DAB over-reads were exactly the four
# DAB trees with a fig ("ficus pegado al tronco") noted by the census crews,
# including the two smallest DAB trees, so size alone doesn't explain it. A
# fig's roots on the bark would be wrapped by a cloud hull but possibly
# threaded under by a tape. This script reports the split. It does not say
# the fig is in the ring: that has to be checked in the RGB slices.
#
# Run once per paint source (first argument, see CONFIG).
#
# PART 1 -- fig noted vs. no fig noted, at the source's paint site on every tree
# NOT in PAINT_DBH_TREES (the above-buttress paint marks). All six methods.
#
# PART 2 -- the field_accuracy error chart without the fig paint sites:
# every Dendrometer site, plus the source's paint site on every tree not in
# FIG_TREES. Signed % bars per tree + site with the mm error printed on each,
# the five cloud methods. A Dendrometer site stays in even on a fig tree
# (3853), since the fig note there is about the band.
#
# Both parts drop EXCLUDE_SITES. No row is dropped for having a large error.
# Part 1's summary adds rows without the EXCLUDE_SENSITIVITY pairs, when one is
# in the run.
#
# Outputs (results/, or DAB_RESULTS):
# <src> = the paint source:
#   fig_notes_<src>_pertree.csv         Part 1, one row per tree + method: reading, estimate, error in mm and %
#   fig_notes_<src>_summary.csv         Part 1, per method and group: n, bias, MAE, RMSE (mm), mean % error, MAPE,
#                                       plus a "fig minus no fig" row with an exact one-sided permutation p
#   plots/fig_notes_<src>_error.png     Part 1, box + points, one panel per method, mm row and % row
#   plots/field_accuracy_no_fig_sites_<src>_error.png   Part 2, signed % bars, mm on each bar
#
# Run:  Rscript scripts/Step07_Analysis/compare_fig_notes.R ForestGeoPaint
#       Rscript scripts/Step07_Analysis/compare_fig_notes.R DendroPaint
# =============================================================================

suppressMessages({ library(readxl); library(dplyr); library(tidyr); library(ggplot2) })
source("scripts/plot_style.R")   # cwd-relative: run from the repo root

# =============================================================================
# CONFIG -- edit these for your own dataset. Same sheet, output folder and site
# lists as the other step 7 scripts. `sheet` is an absolute path to the LOCAL
# working root, overridden by DAB_SHEET. `outdir` defaults to the repo-relative
# results/ folder, overridden by DAB_RESULTS. results/ is tracked, so what this
# writes there goes public when the repo is pushed.
# =============================================================================
sheet   <- Sys.getenv("DAB_SHEET",
                      "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
FLAG_THRESHOLD  <- 0.5         # MaxEdgeFrac at or above this = flagged ring (sheet values are 3-decimal, so >=)
PAINT_DBH_TREES <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height, below any buttress: DBH, not DAB. Left out of Part 1, which compares DAB paint sites only (DJ, 2026-09-28)
EXCLUDE_SITES   <- character(0)   # tree + site pairs left out of every analysis, e.g. "6647 DendroPaint". Empty: both 6647 marks stay in (DJ, 2026-10-06)
EXCLUDE_SENSITIVITY <- c("3853 ForestGeoPaint")   # tree + site pairs for extra "excl." rows in the Part 1 summary, empty = none. 3853's red field value (967 mm) is probably a bad measurement, not a typo: every method and the blue value read about 1330 (DJ, 2026-10-06)
# Trees with a fig noted in the BCI 50ha dendrometer census Notes
# (BCI50ha_20tags_paintDiam_fullrecord.xlsx, sheet "Dendrometer Data"):
# 1993 "TIENE FICUS" (census 16-17, 2015-16), 3853 (census 27, 2023),
# 4524 (census 28, 2024), 5027 (census 27, 2023), 6883 (census 25 and 29,
# 2021 and 2025), 7163 (census 27-28, 2023-24). 6883 has no paint site with a
# reading, so it doesn't enter Part 1. (DJ, 2026-09-28)
FIG_TREES <- c("1993", "3853", "4524", "5027", "6883", "7163")

# Paint-mark source for this run, given as the first argument (DJ, 2026-10-06):
#   ForestGeoPaint = the red ForestGEO census mark, DendroPaint = the blue
#   dendrometer-program mark. Each has its own field diameter and date, and the
#   source goes into every output file name. The validation sites are the
#   Dendrometer bands plus this source's paint marks. The old PaintMarker site is
#   not used: its values are split by source into these two sites, so keeping it
#   would count the same marks twice, and on the red-only trees its field value
#   came from the blue program.
PAINT_SOURCES <- c(ForestGeoPaint = "red ForestGEO paint marks", DendroPaint = "blue dendrometer-program paint marks")
PAINT_SOURCE  <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(PAINT_SOURCE) || !PAINT_SOURCE %in% names(PAINT_SOURCES))
  stop("Give the paint source as the first argument: ", paste(names(PAINT_SOURCES), collapse = " or "))
SRC_LABEL <- PAINT_SOURCES[[PAINT_SOURCE]]

# three groups, by why the site is hard to measure, not by size
GROUPS      <- c("Band (dendrometer)", "DBH (low paint mark)", "DAB (above buttress)")
GROUP_FILLS <- setNames(c("#999999", "#56B4E9", "#D55E00"), GROUPS)
site_group  <- function(site, tree) case_when(site == "Dendrometer" ~ GROUPS[1],
                                              tree %in% PAINT_DBH_TREES ~ GROUPS[2],
                                              TRUE ~ GROUPS[3])

# field reading column for each validation site, and its short label
FIELD_COL  <- setNames(c("Dendrometer_FieldDiameter", sprintf("%s_FieldDiameter_mm", PAINT_SOURCE)),
                       c("Dendrometer", PAINT_SOURCE))
SITE_SHORT <- c(Dendrometer = "Band", ForestGeoPaint = "Red", DendroPaint = "Blue")

num <- function(x) suppressWarnings(as.numeric(x))

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

acc_all <- bind_rows(lapply(names(FIELD_COL), function(s) raw %>%
  transmute(
    tree                        = Tree_Tag,
    site                        = s,
    reading                     = num(.data[[FIELD_COL[[s]]]]),
    ForestScanner               = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
    Python_true_hull            = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
    Circle                      = num(.data[[sprintf("%s_CircleFit_pythonScript_Diameter_mm", s)]]),
    R                           = num(.data[[sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", s)]]),
    bin_hull_FixedAngle         = num(.data[[sprintf("%s_BinFixedAngle_pythonScript_Diameter_mm", s)]]),
    bin_hull_MeanDistanceRadius = num(.data[[sprintf("%s_BinMeanDistanceRadius_pythonScript_Diameter_mm", s)]]),
    # each method's own gap flag (ITSMe uses DendroTape's, same ring points)
    edge_dt = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", s)]]),
    edge_fa = num(.data[[sprintf("%s_BinFixedAngle_MaxEdgeFrac", s)]]),
    edge_md = num(.data[[sprintf("%s_BinMeanDistanceRadius_MaxEdgeFrac", s)]])
  ))) %>%
  # a site counts only if it has a field reading AND a cloud slice, same as
  # validate_field_accuracy.R (a sheet row with a reading but no slice is skipped)
  filter(!is.na(reading), !is.na(Python_true_hull)) %>%
  filter(!paste(tree, site) %in% EXCLUDE_SITES) %>%
  mutate(size = site_group(site, tree),
         fig  = factor(if_else(tree %in% FIG_TREES, "Fig noted", "No fig noted"), c("Fig noted", "No fig noted")))

if (nrow(acc_all) == 0) {
  cat("[fig-notes comparison skipped] no field readings in the sheet yet\n")
  quit(save = "no", status = 0)
}

to_long <- function(d, methods) {
  d %>%
    pivot_longer(all_of(methods), names_to = "method", values_to = "est") %>%
    filter(!is.na(est)) %>%
    mutate(err  = est - reading,
           pct  = 100 * err / reading,
           # ForestScanner doesn't use the ring, so it is never flagged
           edge = case_when(method %in% c("Python_true_hull", "R", "Circle") ~ edge_dt,
                            method == "bin_hull_FixedAngle"         ~ edge_fa,
                            method == "bin_hull_MeanDistanceRadius" ~ edge_md),
           flagged      = !is.na(edge) & edge >= FLAG_THRESHOLD,
           method_label = relabel_method(method))
}
group_stats <- function(d, ...) {
  d %>% group_by(method = method_label, ...) %>%
    summarise(n = n(), bias_mm = mean(err), MAE_mm = mean(abs(err)), RMSE_mm = sqrt(mean(err^2)),
              mean_pct = mean(pct), MAPE = mean(abs(pct)), .groups = "drop")
}
show <- function(tbl) {
  print(as.data.frame(tbl %>% mutate(across(any_of(c("bias_mm", "MAE_mm", "RMSE_mm")), ~ round(.x)),
                                     across(any_of(c("mean_pct", "MAPE")), ~ round(.x, 1)),
                                     across(any_of(c("p_mm", "p_pct")), ~ round(.x, 3)))),
        row.names = FALSE)
}
# mm row on top, % row below, one panel per method
two_row_plot <- function(d, group_col, fills, title, subtitle, label_col = "tree") {
  pd <- bind_rows(d %>% mutate(unit = "Error (mm)", value = err),
                  d %>% mutate(unit = "Error (%)",  value = pct)) %>%
    mutate(unit = factor(unit, c("Error (mm)", "Error (%)")))
  ggplot(pd, aes(.data[[group_col]], value, fill = .data[[group_col]])) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_boxplot(outlier.shape = NA, alpha = 0.6, width = 0.55) +
    geom_point(aes(shape = flagged), size = 2.2, position = position_nudge(x = 0.32)) +
    geom_text(aes(label = .data[[label_col]]), size = 2.6, colour = "grey30", hjust = 0,
              position = position_nudge(x = 0.38)) +
    facet_wrap(~ unit + method_label, nrow = 2, scales = "free_y",
               labeller = labeller(.multi_line = FALSE)) +
    scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
    scale_fill_manual(values = fills, name = NULL) +
    scale_x_discrete(expand = expansion(add = c(0.5, 0.9))) +
    labs(title = title, subtitle = subtitle, x = NULL, y = "Error  (est - reading)") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom", axis.text.x = element_blank())
}

# ===========================================================================
# PART 1 -- fig noted vs. no fig noted, DAB paint sites, all six methods
# ===========================================================================
acc <- acc_all %>% filter(site == PAINT_SOURCE, !tree %in% PAINT_DBH_TREES)

if (nrow(acc) == 0) {
  cat("[Part 1 skipped] no DAB paint-site field readings in the sheet yet\n")
} else {
  long <- to_long(acc, c("ForestScanner", "Python_true_hull", "R", "bin_hull_FixedAngle", "bin_hull_MeanDistanceRadius", "Circle"))
  cat(sprintf("Part 1, fig notes: %d DAB paint sites (%d with a fig noted), %d rows.\n",
              nrow(acc), sum(acc$fig == "Fig noted"), nrow(long)))

  pertree <- long %>%
    transmute(tree, site, fig, reading, method = method_label, est,
              err_mm = round(err, 1), err_pct = round(pct, 2), flagged) %>%
    arrange(method, fig, reading)
  write.csv(pertree, file.path(outdir, sprintf("fig_notes_%s_pertree.csv", PAINT_SOURCE)), row.names = FALSE)

  # exact one-sided permutation test on the difference in mean error (fig minus
  # no fig): every way of choosing which trees carry the "fig" label, not a sample
  perm_p <- function(v, is_fig) {
    k <- sum(is_fig)
    if (k == 0 || k == length(v)) return(NA_real_)
    obs  <- mean(v[is_fig]) - mean(v[!is_fig])
    null <- apply(combn(length(v), k), 2, function(i) mean(v[i]) - mean(v[-i]))
    mean(null >= obs - 1e-9)
  }
  fig_summary <- function(d, suffix = "") {
    by_group <- group_stats(d, group = fig) %>% mutate(group = paste0(as.character(group), suffix))
    diffs <- d %>% group_by(method = method_label) %>%
      summarise(group = paste0("fig minus no fig", suffix), n = n(),
                bias_mm  = mean(err[fig == "Fig noted"]) - mean(err[fig != "Fig noted"]),
                MAE_mm   = NA_real_, RMSE_mm = NA_real_,
                mean_pct = mean(pct[fig == "Fig noted"]) - mean(pct[fig != "Fig noted"]),
                MAPE     = NA_real_,
                p_mm     = perm_p(err, fig == "Fig noted"),
                p_pct    = perm_p(pct, fig == "Fig noted"), .groups = "drop")
    bind_rows(by_group, diffs)
  }
  # sensitivity rows without the EXCLUDE_SENSITIVITY pairs, when one is in this run
  sens <- long %>% filter(paste(tree, site) %in% EXCLUDE_SENSITIVITY)
  sens_suffix <- sprintf(", excl. %s", paste(unique(sprintf("%s %s", sens$tree, SITE_SHORT[sens$site])), collapse = ", "))
  GROUP_ORDER <- c("Fig noted", "No fig noted", "fig minus no fig")
  summary_tbl <- bind_rows(fig_summary(long),
                           if (nrow(sens) > 0) fig_summary(long %>% filter(!paste(tree, site) %in% EXCLUDE_SENSITIVITY), sens_suffix)) %>%
    arrange(method, factor(group, c(GROUP_ORDER, paste0(GROUP_ORDER, sens_suffix))))
  write.csv(summary_tbl, file.path(outdir, sprintf("fig_notes_%s_summary.csv", PAINT_SOURCE)), row.names = FALSE)
  cat("\n-- Part 1, per method and group (mm and %) --\n")
  show(summary_tbl)

  p1 <- two_row_plot(long, "fig", c("Fig noted" = "#009E73", "No fig noted" = "#999999"),
    sprintf("Error vs. Field Reading at Buttressed Paint Marks (%s): Fig Noted vs. No Fig Noted", SRC_LABEL),
    sprintf("n = %d DAB paint sites (%d with a fig in the BCI census notes). Top row mm, bottom row %%. Open markers = flagged ring (MaxEdgeFrac >= %.1f). The y axis differs per panel.",
            nrow(acc), sum(acc$fig == "Fig noted"), FLAG_THRESHOLD))
  ggsave(file.path(plotdir, sprintf("fig_notes_%s_error.png", PAINT_SOURCE)), p1, width = 17, height = 7.5, dpi = 130)
  cat(sprintf("\nWrote %s/fig_notes_%s_{pertree,summary}.csv and %s/fig_notes_%s_error.png\n", outdir, PAINT_SOURCE, plotdir, PAINT_SOURCE))
}

# ===========================================================================
# PART 2 -- the field_accuracy error chart without the fig paint sites:
# every Dendrometer site plus the paint sites on trees not in FIG_TREES. Same
# layout as validate_field_accuracy.R's error plot (signed % bars per tree +
# site, ordered by reading, plus a per-method average), for the four cloud
# methods, with each bar's error in mm printed above it. (DJ, 2026-09-28)
# ===========================================================================
acc2  <- acc_all %>% filter(site == "Dendrometer" | !tree %in% FIG_TREES)
long2 <- to_long(acc2, c("Python_true_hull", "bin_hull_FixedAngle", "bin_hull_MeanDistanceRadius", "R", "Circle")) %>%
  mutate(tree_label = sprintf("%s %s (%.0f)", tree, SITE_SHORT[site], reading))
cat(sprintf("\nPart 2, without the fig paint sites: %d tree-sites, %d rows.\n", nrow(acc2), nrow(long2)))

# Large finite `reading` sentinel (not Inf) so reorder() puts the average last,
# the same trick validate_field_accuracy.R uses.
avg2 <- long2 %>% group_by(method, method_label) %>%
  summarise(pct = mean(pct), err = mean(err), .groups = "drop") %>%
  mutate(tree_label = "Average", reading = 1e6)
p2_data <- bind_rows(long2 %>% select(tree_label, reading, method, method_label, pct, err), avg2) %>%
  mutate(mm_label = sprintf("%+.0f", err),
         label_hjust = if_else(pct >= 0, -0.15, 1.15))   # text reads away from zero

dodge <- position_dodge(0.8)
p2 <- ggplot(p2_data, aes(reorder(tree_label, reading), pct, fill = method_label)) +
  geom_col(position = dodge, width = 0.7) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_text(aes(label = mm_label, hjust = label_hjust), position = dodge,
            angle = 90, size = 2.3, colour = "grey25") +
  scale_y_continuous(expand = expansion(mult = c(0.12, 0.18))) +
  scale_fill_method() +
  labs(title = "Signed Percent Error vs. Field Reading, Without the Fig Paint Sites",
       subtitle = sprintf("Every dendrometer band plus the %s on trees without a fig note (n = %d tree-sites) -- trees ordered by reading, plus per-method averages.\nNumber on each bar = error in mm.",
                          SRC_LABEL, nrow(acc2)),
       x = "Tree and site (field reading, mm)", y = "Error  (est - reading) / reading  [%]") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(plotdir, sprintf("field_accuracy_no_fig_sites_%s_error.png", PAINT_SOURCE)), p2, width = 13, height = 6, dpi = 130)
cat(sprintf("\nWrote %s/field_accuracy_no_fig_sites_%s_error.png\n", plotdir, PAINT_SOURCE))
