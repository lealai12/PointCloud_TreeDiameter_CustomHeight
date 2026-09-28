#!/usr/bin/env Rscript
# =============================================================================
# compare_fig_notes.R -- error vs. field reading at the buttressed paint-mark
# sites, trees with a fig noted in the BCI census notes vs. trees without.
#
# On the second pass the four largest DAB over-reads were exactly the four
# DAB trees with a fig ("ficus pegado al tronco") noted by the census crews,
# including the two smallest DAB trees, so size alone doesn't explain it. A
# fig's roots on the bark would be wrapped by a cloud hull but possibly
# threaded under by a tape. This script reports the split. It does not say
# the fig is in the ring: that has to be checked in the RGB slices.
#
# Sites: the PaintMarker site on every tree NOT in PAINT_DBH_TREES (the
# above-buttress paint marks), minus EXCLUDE_SITES. All five methods. No row
# is dropped for having a large error.
#
# Outputs (results/, or DAB_RESULTS):
#   fig_notes_pertree.csv     one row per tree + method: reading, estimate, error in mm and %
#   fig_notes_summary.csv     per method and group: n, bias, MAE, RMSE (mm), mean % error, MAPE,
#                             plus a "fig minus no fig" row with an exact one-sided permutation p
#   plots/fig_notes_error.png box + points, fig vs no fig, one panel per method, mm row and % row
#
# Run:  Rscript scripts/Step07_Analysis/compare_fig_notes.R
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
PAINT_DBH_TREES <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height: left out here, only DAB paint sites are compared (DJ, 2026-09-28)
EXCLUDE_SITES   <- c("6647 PaintMarker")   # tree + site left out of every analysis: bad scan at the mark (DJ, 2026-09-28)
# Trees with a fig noted in the BCI 50ha dendrometer census Notes
# (BCI50ha_20tags_paintDiam_fullrecord.xlsx, sheet "Dendrometer Data"):
# 1993 "TIENE FICUS" (census 16-17, 2015-16), 3853 (census 27, 2023),
# 4524 (census 28, 2024), 5027 (census 27, 2023), 6883 (census 25 and 29,
# 2021 and 2025), 7163 (census 27-28, 2023-24). 3853 and 6883 have no DAB
# paint site with a reading, so they don't enter this comparison. (DJ, 2026-09-28)
FIG_TREES <- c("1993", "3853", "4524", "5027", "6883", "7163")

num <- function(x) suppressWarnings(as.numeric(x))

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

s <- "PaintMarker"
acc <- raw %>%
  transmute(
    tree                        = Tree_Tag,
    site                        = s,
    reading                     = num(PaintMarker_FieldDiameter_mm),
    ForestScanner               = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
    Python_true_hull            = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
    R                           = num(.data[[sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", s)]]),
    bin_hull_FixedAngle         = num(.data[[sprintf("%s_BinFixedAngle_pythonScript_Diameter_mm", s)]]),
    bin_hull_MeanDistanceRadius = num(.data[[sprintf("%s_BinMeanDistanceRadius_pythonScript_Diameter_mm", s)]]),
    # each method's own gap flag (ITSMe uses DendroTape's, same ring points)
    edge_dt = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", s)]]),
    edge_fa = num(.data[[sprintf("%s_BinFixedAngle_MaxEdgeFrac", s)]]),
    edge_md = num(.data[[sprintf("%s_BinMeanDistanceRadius_MaxEdgeFrac", s)]])
  ) %>%
  # a site counts only if it has a field reading AND a cloud slice, same as
  # validate_field_accuracy.R (a sheet row with a reading but no slice is skipped)
  filter(!is.na(reading), !is.na(Python_true_hull)) %>%
  filter(!paste(tree, site) %in% EXCLUDE_SITES) %>%
  filter(!tree %in% PAINT_DBH_TREES) %>%
  mutate(fig = if_else(tree %in% FIG_TREES, "Fig noted", "No fig noted"),
         fig = factor(fig, c("Fig noted", "No fig noted")))

if (nrow(acc) == 0) {
  cat("[fig-notes comparison skipped] no DAB paint-site field readings in the sheet yet\n")
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
         method_label = relabel_method(method))

cat(sprintf("Fig-notes comparison: %d DAB paint sites (%d with a fig noted), %d rows.\n",
            nrow(acc), sum(acc$fig == "Fig noted"), nrow(long)))

pertree <- long %>%
  transmute(tree, site, fig, reading, method = method_label, est,
            err_mm = round(err, 1), err_pct = round(pct, 2), flagged) %>%
  arrange(method, fig, reading)
write.csv(pertree, file.path(outdir, "fig_notes_pertree.csv"), row.names = FALSE)

# exact one-sided permutation test on the difference in mean error (fig minus
# no fig): every way of choosing which trees carry the "fig" label, not a sample
perm_p <- function(v, is_fig) {
  k <- sum(is_fig)
  if (k == 0 || k == length(v)) return(NA_real_)
  obs  <- mean(v[is_fig]) - mean(v[!is_fig])
  null <- apply(combn(length(v), k), 2, function(i) mean(v[i]) - mean(v[-i]))
  mean(null >= obs - 1e-9)
}
by_group <- long %>% group_by(method = method_label, group = fig) %>%
  summarise(n = n(), bias_mm = mean(err), MAE_mm = mean(abs(err)), RMSE_mm = sqrt(mean(err^2)),
            mean_pct = mean(pct), MAPE = mean(abs(pct)), .groups = "drop") %>%
  mutate(group = as.character(group))
diffs <- long %>% group_by(method = method_label) %>%
  summarise(group = "fig minus no fig", n = n(),
            bias_mm  = mean(err[fig == "Fig noted"]) - mean(err[fig != "Fig noted"]),
            MAE_mm   = NA_real_, RMSE_mm = NA_real_,
            mean_pct = mean(pct[fig == "Fig noted"]) - mean(pct[fig != "Fig noted"]),
            MAPE     = NA_real_,
            p_mm     = perm_p(err, fig == "Fig noted"),
            p_pct    = perm_p(pct, fig == "Fig noted"), .groups = "drop")
summary_tbl <- bind_rows(by_group, diffs) %>% arrange(method, factor(group, c("Fig noted", "No fig noted", "fig minus no fig")))
write.csv(summary_tbl, file.path(outdir, "fig_notes_summary.csv"), row.names = FALSE)

cat("\n-- per method and group (mm and %) --\n")
print(as.data.frame(summary_tbl %>% mutate(across(c(bias_mm, MAE_mm, RMSE_mm), ~ round(.x)),
                                           across(c(mean_pct, MAPE), ~ round(.x, 1)),
                                           across(any_of(c("p_mm", "p_pct")), ~ round(.x, 3)))),
      row.names = FALSE)

# ---- figure: mm row on top, % row below, one panel per method
pd <- bind_rows(long %>% mutate(unit = "Error (mm)",  value = err),
                long %>% mutate(unit = "Error (%)",   value = pct)) %>%
  mutate(unit = factor(unit, c("Error (mm)", "Error (%)")))
p <- ggplot(pd, aes(fig, value, fill = fig)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_boxplot(outlier.shape = NA, alpha = 0.6, width = 0.55) +
  geom_point(aes(shape = flagged), size = 2.2, position = position_nudge(x = 0.32)) +
  geom_text(aes(label = tree), size = 2.6, colour = "grey30", hjust = 0, position = position_nudge(x = 0.38)) +
  facet_wrap(~ unit + method_label, nrow = 2, scales = "free_y",
             labeller = labeller(.multi_line = FALSE)) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 1), guide = "none") +
  scale_fill_manual(values = c("Fig noted" = "#009E73", "No fig noted" = "#999999"), name = NULL) +
  scale_x_discrete(expand = expansion(add = c(0.5, 0.9))) +
  labs(title = "Error vs. Field Reading at Buttressed Paint Marks: Fig Noted vs. No Fig Noted",
       subtitle = sprintf("n = %d DAB paint sites (%d with a fig in the BCI census notes). Top row mm, bottom row %%. Open markers = flagged ring (MaxEdgeFrac >= %.1f). The y axis differs per panel.",
                          nrow(acc), sum(acc$fig == "Fig noted"), FLAG_THRESHOLD),
       x = NULL, y = "Error  (est - reading)") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", axis.text.x = element_blank())
ggsave(file.path(plotdir, "fig_notes_error.png"), p, width = 14, height = 7.5, dpi = 130)

cat(sprintf("\nWrote %s/fig_notes_{pertree,summary}.csv and %s/fig_notes_error.png\n", outdir, plotdir))
