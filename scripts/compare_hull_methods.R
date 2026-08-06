#!/usr/bin/env Rscript
# compare_hull_methods.R  --  HULL METHOD COMPARISON: true hull vs. median-polygon hull
# ---------------------------------------------------------------------------
# Companion to validate_field_accuracy.R (the main field-accuracy comparison).
# That script is untouched by this one and this script does NOT feed back
# into it -- this is a separate, additive comparison, per project decision:
# the median-hull method (scripts/median_polygon.py/.R +
# scripts/median_polygon_2deg.py/.R) exists to be compared against the
# existing true-convex-hull method (scripts/dendro_tape.py / .R), not to
# replace it.
#
# WHAT THIS COMPARES
#   - "true hull"     = convex hull of the RAW slice points   (dendro_tape.*)
#   - "median hull"    = convex hull of a median-binned, denoised surface
#                         polygon, in TWO bin-width variants, both kept
#                         standalone rather than one replacing the other
#                         (see median_polygon.py's header for why):
#       2deg = fixed 2-degree angular bin      (median_polygon_2deg.py/.R)
#       10mm = fixed 10mm arc-length bin       (median_polygon.py/.R)
#
# PYTHON-ONLY OUTPUT (deliberate choice): every method here has an
# independent R implementation too, and both parts below load and cross-check
# it against Python (see the printed "[Python vs R cross-check]" lines) --
# but R is not carried into the results CSVs/plots. R and Python agree
# exactly everywhere checked (0.000 mm diff), which is the *point* of keeping
# two independent implementations -- a displayed R column would just repeat
# the Python one, not add information. If a cross-check ever prints a
# nonzero diff, that's a real bug and worth investigating before trusting
# either output.
#
# TWO parts, with DELIBERATELY DIFFERENT data sources (read this before
# changing paths):
#
#   Part 1 -- vs_field_reading: reads ONLY the anonymized sheet
#   (field_measurements_Anon.xlsx), same rule as validate_field_accuracy.R.
#   The true-hull and median-hull diameters (Python AND R, for the
#   cross-check) are all columns in that sheet once anonymize-and-transcribed
#   in -- this part needs NOTHING from outside the anonymized sheet:
#     Dendrometer_pythonScript_Diameter_mm             = Python true hull (dendro_tape.py)
#     Dendrometer_DendroTape_RScript_Diameter_mm        = R true hull (dendro_tape.R)
#     Dendrometer_MedianPolygon_pythonScript_Diameter_mm = Python median hull (2 deg angular bin)
#     Dendrometer_MedianPolygon_RScript_Diameter_mm      = R median hull (2 deg angular bin)
#     Dendrometer_MedianPolygon10mm_pythonScript_Diameter_mm = Python median hull (10mm arc-length bin)
#     Dendrometer_MedianPolygon10mm_RScript_Diameter_mm      = R median hull (10mm arc-length bin)
#   The 2 deg and 10mm median-hull columns are two separate median_polygon.py/.R
#   runs (fixed angular bin vs. fixed arc-length bin -- see that script's header
#   for why the arc-length version was added), transcribed into separate
#   columns rather than overwritten, so both remain comparable here.
#   NOTE: the sheet's older `RScript` column (no DendroTape/MedianPolygon tag)
#   is a DIFFERENT method -- ITSMe's concave "functional" diameter
#   (dab_itsme.R) -- not used here; don't confuse it with `DendroTape_RScript`.
#
#   Part 2 -- method_agreement: true hull vs. median hull, paired per
#   tree+site, PER BIN VARIANT (2deg, 10mm), with NO field reading required --
#   the fuller processed batch (every measured site: TopFlag/LowerFlag/
#   Dendrometer), not just the ones with field ground truth. ANONYMIZED
#   SHEET ONLY, same rule as Part 1 and validate_field_accuracy.R -- reads
#   TopFlag/LowerFlag/Dendrometer true-hull and median-hull columns straight
#   from field_measurements_Anon.xlsx, nothing else. The 10mm-bin variant
#   stays Dendrometer-only: the anonymized sheet only has
#   *_MedianPolygon10mm_* columns for that site.
#
# Run:  Rscript scripts/compare_hull_methods.R
# ---------------------------------------------------------------------------

suppressMessages({
  library(readxl); library(dplyr); library(tidyr); library(ggplot2)
})
source("scripts/plot_style.R")   # shared method labels/colours/shapes across all plots/*.png

sheet   <- "C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"
outdir  <- "results"
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)

num   <- function(x) suppressWarnings(as.numeric(x))
GROSS <- 0.5     # |error|/reading above this = likely data-entry/registration error, excluded

# ===========================================================================
# PART 1 -- true hull & median hull vs. field reading.
# Anonymized sheet ONLY -- same rule as validate_field_accuracy.R.
#
# Python-only in the OUTPUT (results CSVs/plots): R is still read in here and
# cross-checked against Python below, but not shown as its own column/bar --
# the two implementations agree exactly (see the printed cross-check), so a
# displayed R column would just be a duplicate of the Python one, not new
# information. R stays in the pipeline as the correctness check the
# two-independent-implementations convention exists for; it's just not
# repeated in the results, a deliberate display-only decision.
# ===========================================================================
raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag))

acc <- raw %>%
  transmute(
    tree               = Tree_Tag,
    has_dendro         = has_dendrometer,
    # Not part of the true-hull/median-hull comparison this script exists for
    # (see header) -- kept only so the plotting section below can build the
    # combined ForestScanner + hull-methods figures (FIG 2a/3/3b) without a
    # second read of the sheet. Deliberately excluded from `long`/the
    # written CSVs, which stay scoped to the three hull methods.
    ForestScanner            = num(Dendrometer_ForestScanner_Diameter_mm),
    Python_true_hull        = num(Dendrometer_pythonScript_Diameter_mm),
    R_true_hull             = num(Dendrometer_DendroTape_RScript_Diameter_mm),
    Python_median_hull      = num(Dendrometer_MedianPolygon_pythonScript_Diameter_mm),
    R_median_hull           = num(Dendrometer_MedianPolygon_RScript_Diameter_mm),
    Python_median_hull_10mm = num(Dendrometer_MedianPolygon10mm_pythonScript_Diameter_mm),
    R_median_hull_10mm      = num(Dendrometer_MedianPolygon10mm_RScript_Diameter_mm),
    reading            = num(Dendrometer_Reading)
  ) %>%
  filter(!is.na(reading)) %>%
  # SIZE GROUPING: measurement type, not a diameter threshold -- see
  # validate_field_accuracy.R's header for why (two has_dendrometer == "Yes"
  # trees are >1m diameter, so a raw threshold misclassifies them).
  mutate(size = if_else(has_dendro == "Yes", "DBH (dendrometer)", "DAB (above buttress)"))

# Python vs R cross-check (console only -- not written anywhere): confirms
# the two independent implementations still agree before we drop R from the
# displayed output below.
py_r_check <- function(py_col, r_col, label) {
  d <- acc %>% filter(!is.na(.data[[py_col]]), !is.na(.data[[r_col]]))
  if (nrow(d) == 0) return(invisible(NULL))
  maxdiff <- max(abs(d[[py_col]] - d[[r_col]]))
  cat(sprintf("[Python vs R cross-check] %-18s max |diff| across %d trees: %.3f mm\n",
              label, nrow(d), maxdiff))
}
py_r_check("Python_true_hull",        "R_true_hull",        "true_hull")
py_r_check("Python_median_hull",      "R_median_hull",      "median_hull_2deg")
py_r_check("Python_median_hull_10mm", "R_median_hull_10mm", "median_hull_10mm")

long <- acc %>%
  pivot_longer(c(Python_true_hull, Python_median_hull, Python_median_hull_10mm),
               names_to = "method", values_to = "est") %>%
  # Display names for CSV columns/plots: drop "Python_" (results are
  # Python-only now, see the cross-check above -- the prefix no longer
  # disambiguates anything) and disambiguate the 2deg variant explicitly
  # instead of leaving it as the unqualified "median_hull".
  mutate(method = recode(method,
                          Python_true_hull        = "true_hull",
                          Python_median_hull      = "median_hull_2Degrees",
                          Python_median_hull_10mm = "median_hull_10mm")) %>%
  filter(!is.na(est)) %>%
  mutate(err   = est - reading,
         pct   = 100 * err / reading,
         gross = abs(err) / reading > GROSS,
         # x-axis label for the bar plots: tree number + true dendrometer
         # reading in parentheses, e.g. "15 (448)"
         tree_label = sprintf("%s (%.0f)", tree, reading))

if (nrow(long) == 0) {
  cat("\n[Part 1 skipped] the sheet has no Dendrometer_MedianPolygon_*_Diameter_mm ",
      "values yet -- anonymize-and-transcribe the median-hull results in first.\n", sep = "")
} else {
  pertree <- long %>%
    mutate(tag = ifelse(gross, sprintf("%.0f*", pct), sprintf("%.0f", pct))) %>%
    select(tree, size, reading, method, est, tag) %>%
    pivot_wider(names_from = method, values_from = c(est, tag),
                names_glue = "{method}_{.value}") %>%
    arrange(size, reading)
  write.csv(pertree, file.path(outdir, "hull_comparison_vs_field_reading_pertree.csv"), row.names = FALSE)

  summ <- function(df, label) {
    df %>% filter(!gross) %>% group_by(method) %>%
      summarise(set = label, n = n(),
                bias = mean(err), MAE = mean(abs(err)),
                RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)),
                .groups = "drop") %>% relocate(set)
  }
  by_size <- long %>% filter(!gross) %>% group_by(size, method) %>%
    summarise(n = n(), bias = mean(err), MAE = mean(abs(err)),
              RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)), .groups = "drop") %>%
    mutate(set = paste0("by size: ", size)) %>% relocate(set) %>% select(-size)

  summary_tbl <- bind_rows(
    summ(long, "all trees"),
    summ(long %>% filter(tree != "17"), "excl. tree 17"),
    if (n_distinct(long$size) > 1) by_size else NULL
  )
  write.csv(summary_tbl, file.path(outdir, "hull_comparison_vs_field_reading_summary.csv"), row.names = FALSE)

  cat("\n============ HULL METHOD COMPARISON -- VS. FIELD READING ============\n")
  cat("signed % error per method (* = gross outlier, excluded from metrics):\n\n")
  print(as.data.frame(pertree), row.names = FALSE)
  cat("\n-- per-method metrics (mm; +bias = over-read) --\n")
  print(as.data.frame(summary_tbl %>%
          mutate(across(c(bias, MAE, RMSE), ~round(.x)), MAPE = round(MAPE, 1))),
        row.names = FALSE)

  # ForestScanner joins the plots below (FIG 2a/3/3b) but deliberately stays
  # out of `long`/pertree/summary_tbl above -- this script's CSVs stay scoped
  # to the three hull methods; ForestScanner's own metrics already live in
  # field_accuracy_*.csv. See the plot-cleanup spec, 2026-08-02.
  fs_long <- acc %>%
    transmute(tree, size, reading, est = ForestScanner, method = "ForestScanner") %>%
    filter(!is.na(est)) %>%
    mutate(err   = est - reading,
           pct   = 100 * err / reading,
           gross = abs(err) / reading > GROSS,
           tree_label = sprintf("%s (%.0f)", tree, reading))
  long_with_fs <- bind_rows(long, fs_long)

  # ---- FIG 2a: estimate vs. reading, four arms (ForestScanner + all three
  # hull methods) -- revises the previous 3-arm hull-only scatter in place.
  lim <- range(c(long_with_fs$est, long_with_fs$reading), na.rm = TRUE)
  fig2a_data <- long_with_fs %>% mutate(method_label = relabel_method(method))
  p_fig2a <- ggplot(fig2a_data, aes(reading, est, colour = method_label, shape = method_label)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    geom_point(size = 3, alpha = 0.85) +
    geom_point(data = fig2a_data %>% filter(gross), aes(reading, est),
               shape = 4, size = 5, stroke = 1.4, colour = "black",
               inherit.aes = FALSE, show.legend = FALSE) +
    geom_text(data = fig2a_data %>% filter(gross), aes(reading, est, label = tree),
              colour = "black", size = 3, vjust = -1.1, inherit.aes = FALSE) +
    scale_colour_method() + scale_shape_method() +
    coord_equal(xlim = lim, ylim = lim) +
    labs(title = "Estimated Diameter vs. Dendrometer Reading",
         subtitle = "dashed = 1:1;  x = ForestScanner gross data-entry misread (tree labeled)",
         x = "Dendrometer reading (mm)", y = "Estimated diameter (mm)",
         caption = "Median hull, 2° and Median hull, 10 mm overlap almost exactly at this scale --\nsee hull_comparison_binwidth_agreement.png for the difference on its own axis.") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, "hull_comparison_vs_field_reading_scatter.png"), p_fig2a, width = 7.5, height = 6.8, dpi = 130)

  # ---- FIG 2b: Bland-Altman, the three hull arms only (no ForestScanner --
  # this figure is about agreement between the hull methods and the field
  # reading, not another vs.-reading scatter). Bias/limits of agreement
  # computed excl. tree 17, for Convex hull and Median hull 2deg only (the
  # two arms with the biggest spread difference).
  ba_stats <- function(m) {
    d <- long %>% filter(method == m, tree != "17")
    b <- mean(d$err); s <- sd(d$err)
    list(bias = b, lo = b - 1.96 * s, hi = b + 1.96 * s)
  }
  stat_true <- ba_stats("true_hull")
  stat_med2 <- ba_stats("median_hull_2Degrees")
  col_true  <- METHOD_COLORS[["Convex hull"]]
  col_med2  <- METHOD_COLORS[["Median hull, 2°"]]

  ba_data <- long %>% mutate(method_label = relabel_method(method), mean_est = (est + reading) / 2)
  p_fig2b <- ggplot(ba_data, aes(mean_est, err, colour = method_label, shape = method_label)) +
    geom_hline(yintercept = 0, colour = "grey30") +
    geom_hline(yintercept = stat_true$bias, colour = col_true, linetype = 2) +
    geom_hline(yintercept = c(stat_true$lo, stat_true$hi), colour = col_true, linetype = 3) +
    geom_hline(yintercept = stat_med2$bias, colour = col_med2, linetype = 2) +
    geom_hline(yintercept = c(stat_med2$lo, stat_med2$hi), colour = col_med2, linetype = 3) +
    geom_point(size = 3, alpha = 0.85) +
    geom_text(data = ba_data %>% filter(tree == "17", method == "true_hull"),
              aes(label = "tree 17"), colour = "black", size = 3, vjust = -1, hjust = -0.15,
              show.legend = FALSE) +
    scale_colour_method() + scale_shape_method() +
    labs(title = "Agreement with Dendrometer Reading (Bland-Altman)",
         subtitle = "dashed = mean bias, dotted = 95% limits of agreement (Convex hull & Median hull, 2°; excl. tree 17)",
         x = "Mean of estimate and reading (mm)", y = "Estimate − reading (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, "hull_comparison_bland_altman.png"), p_fig2b, width = 8, height = 6, dpi = 130)

  # ---- shared tree order + summary boundary marker for FIG 3 / FIG 3b
  # No "size boundary" rule here (an earlier version drew one at a diameter
  # threshold): trees are ordered by reading, but the DBH/DAB measurement-type
  # grouping (see `size` above) doesn't split cleanly along that order -- two
  # DBH trees are interleaved among the larger DAB ones -- so a single
  # vertical line can't honestly mark it. by_size in the summary CSV is the
  # place to see the DBH-vs-DAB breakdown; this ordering is just by reading.
  tree_labels_ordered <- long_with_fs %>% filter(!gross) %>%
    distinct(tree, reading, tree_label) %>% arrange(reading)
  n_trees <- nrow(tree_labels_ordered)
  level_order  <- c(tree_labels_ordered$tree_label, "Average", "Average (excl. 17)")
  boundary_avg <- n_trees + 0.5   # rule between the last tree and the Average bars

  # ---- FIG 3: signed % error, four arms, revises the hull-only error plot
  # in place -- this is now the one bar chart that covers Q1 (ForestScanner)
  # as well as Q2/Q3 (the hull methods), so a reader doesn't have to flip to
  # field_accuracy_*_error.png for a different colour scheme.
  avg_pct        <- long_with_fs %>% filter(!gross) %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>% mutate(tree_label = "Average")
  avg_pct_excl17 <- long_with_fs %>% filter(!gross, tree != "17") %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>% mutate(tree_label = "Average (excl. 17)")
  p3_data <- bind_rows(long_with_fs %>% filter(!gross) %>% select(tree_label, method, pct),
                       avg_pct, avg_pct_excl17) %>%
    mutate(method_label = relabel_method(method),
           tree_label    = factor(tree_label, levels = level_order))

  p_fig3 <- ggplot(p3_data, aes(tree_label, pct, fill = method_label)) +
    geom_vline(xintercept = boundary_avg,  linetype = "dashed", colour = "grey70") +
    geom_col(position = position_dodge(0.8), width = 0.7) +
    geom_hline(yintercept = 0, colour = "grey40") +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    scale_fill_method() +
    labs(title = "Signed Percent Error vs. Dendrometer Reading",
         subtitle = "trees ordered by reading; dashed rule marks the summary block (see hull_comparison_..._summary.csv for the DBH-vs-DAB breakdown)",
         x = "Tree (dendrometer reading, mm)", y = "Error  (est - reading) / reading  [%]") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(plotdir, "hull_comparison_vs_field_reading_error.png"), p_fig3, width = 9.5, height = 5.5, dpi = 130)

  # ---- FIG 3b: same data, absolute error in mm. POINTS instead of bars on
  # the pseudo-log axis -- a bar's LENGTH is read as magnitude, so on a log
  # scale a 100mm bar looks roughly 3x a 10mm bar instead of 10x, which is
  # misleading. A point's position on the same axis carries no such
  # implication, so the log-ish compression (needed so tree 17's ~430mm
  # outlier doesn't flatten every other bar to invisibility) stays honest.
  avg_err        <- long_with_fs %>% filter(!gross) %>% group_by(method) %>%
    summarise(err = mean(err), .groups = "drop") %>% mutate(tree_label = "Average")
  avg_err_excl17 <- long_with_fs %>% filter(!gross, tree != "17") %>% group_by(method) %>%
    summarise(err = mean(err), .groups = "drop") %>% mutate(tree_label = "Average (excl. 17)")
  p3b_data <- bind_rows(long_with_fs %>% filter(!gross) %>% select(tree_label, method, err),
                        avg_err, avg_err_excl17) %>%
    mutate(method_label = relabel_method(method),
           tree_label    = factor(tree_label, levels = level_order))

  p_fig3b <- ggplot(p3b_data, aes(tree_label, err, colour = method_label, shape = method_label)) +
    geom_vline(xintercept = boundary_avg,  linetype = "dashed", colour = "grey70") +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_point(position = position_dodge(0.6), size = 3, alpha = 0.9) +
    scale_y_continuous(trans = scales::pseudo_log_trans(sigma = 10, base = 10),
                        breaks = c(-100, -30, -10, 0, 10, 30, 100, 300)) +
    scale_colour_method() + scale_shape_method() +
    labs(title = "Signed Error vs. Dendrometer Reading (mm)",
         subtitle = "points, not bars (bar length on a log axis is misleading); dashed rule marks the summary block",
         x = "Tree (dendrometer reading, mm)", y = "Error  (est - reading)  [mm, pseudo-log]") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(plotdir, "hull_comparison_vs_field_reading_error_mm.png"), p_fig3b, width = 9.5, height = 5.5, dpi = 130)

  # ---- FIG Q3: bin-width agreement -- the two median-hull variants overlap
  # almost exactly in FIG 2a (a legend entry with no visible points reads
  # like a rendering bug); this figure shows why, on its own axis.
  q3_data <- long %>% filter(method %in% c("median_hull_2Degrees", "median_hull_10mm")) %>%
    select(tree, reading, method, est) %>%
    pivot_wider(names_from = method, values_from = est) %>%
    mutate(diff_mm = median_hull_2Degrees - median_hull_10mm)

  p_q3 <- ggplot(q3_data, aes(reading, diff_mm)) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_point(size = 3, colour = col_med2) +
    labs(title = "Bin-Width Agreement: Median Hull, 2° vs. 10 mm",
         subtitle = "(2° estimate − 10mm estimate) per tree -- the two bin widths are\nindistinguishable at the scale of the measurement",
         x = "Dendrometer reading (mm)", y = "2° estimate − 10mm estimate (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, "hull_comparison_binwidth_agreement.png"), p_q3, width = 7.5, height = 5.2, dpi = 130)

  cat("\nWrote results/hull_comparison_vs_field_reading_{pertree,summary}.csv and",
      "results/plots/hull_comparison_vs_field_reading_{scatter,error,error_mm}.png,",
      "results/plots/hull_comparison_bland_altman.png,",
      "results/plots/hull_comparison_binwidth_agreement.png\n")
}

# ===========================================================================
# PART 2 -- true hull vs. median hull, PAIRED (same tree+site), no field
# reading required. Anonymized sheet ONLY -- see header above.
#
# Python-only in the OUTPUT here too, same reasoning and same 2026-08-02
# decision as Part 1: R columns are still read and cross-checked against
# Python below, just not carried into `agreement`/the summary/the plot.
# ===========================================================================
site_pair <- function(site) {
  raw %>%
    transmute(
      tree = Tree_Tag, site = site,
      true_py = num(.data[[sprintf("%s_pythonScript_Diameter_mm", site)]]),
      true_r  = num(.data[[sprintf("%s_DendroTape_RScript_Diameter_mm", site)]]),
      med_py  = num(.data[[sprintf("%s_MedianPolygon_pythonScript_Diameter_mm", site)]]),
      med_r   = num(.data[[sprintf("%s_MedianPolygon_RScript_Diameter_mm", site)]])
    )
}
pairs_2deg <- bind_rows(lapply(c("TopFlag", "LowerFlag", "Dendrometer"), site_pair)) %>%
  filter(!is.na(true_py), !is.na(med_py))

# 10mm variant -- Dendrometer-site columns only exist in the anonymized
# sheet for this bin width (see header).
pairs_10mm <- raw %>%
  transmute(
    tree = Tree_Tag, site = "Dendrometer",
    true_py = num(Dendrometer_pythonScript_Diameter_mm),
    true_r  = num(Dendrometer_DendroTape_RScript_Diameter_mm),
    med_py  = num(Dendrometer_MedianPolygon10mm_pythonScript_Diameter_mm),
    med_r   = num(Dendrometer_MedianPolygon10mm_RScript_Diameter_mm)
  ) %>%
  filter(!is.na(true_py), !is.na(med_py))

# Python vs R cross-check (console only -- not written anywhere): confirms
# the two independent implementations still agree before we drop R from the
# displayed agreement/summary/plot below.
pair_check <- function(df, py_col, r_col, label) {
  d <- df %>% filter(!is.na(.data[[py_col]]), !is.na(.data[[r_col]]))
  if (nrow(d) == 0) return(invisible(NULL))
  cat(sprintf("[Python vs R cross-check] %-18s max |diff| across %d site-rows: %.3f mm\n",
              label, nrow(d), max(abs(d[[py_col]] - d[[r_col]]))))
}
pair_check(pairs_2deg, "true_py", "true_r", "true_hull")
pair_check(pairs_2deg, "med_py",  "med_r",  "median_hull_2deg")
pair_check(pairs_10mm, "med_py",  "med_r",  "median_hull_10mm")

to_agreement <- function(df, variant) {
  df %>% transmute(tree, site, variant = variant, true_est = true_py, median_est = med_py,
                    diff_mm = median_est - true_est, pct_diff = 100 * diff_mm / true_est)
}
agreement <- bind_rows(to_agreement(pairs_2deg, "2Degrees"), to_agreement(pairs_10mm, "10mm"))

if (nrow(agreement) == 0) {
  cat("\n[Part 2 skipped] need both a true-hull and a median-hull value (anonymized sheet) for at least one site/variant.\n")
} else {
  write.csv(agreement, file.path(outdir, "hull_comparison_method_agreement_pertree.csv"), row.names = FALSE)

  agree_summary <- agreement %>% group_by(variant) %>%
    summarise(n = n(),
              mean_diff_mm = mean(diff_mm), mean_abs_diff_mm = mean(abs(diff_mm)),
              mean_abs_pct_diff = mean(abs(pct_diff)),
              max_abs_diff_mm = max(abs(diff_mm)),
              cor = suppressWarnings(cor(true_est, median_est)),
              .groups = "drop")
  write.csv(agree_summary, file.path(outdir, "hull_comparison_method_agreement_summary.csv"), row.names = FALSE)

  cat("\n============ HULL METHOD COMPARISON -- METHOD AGREEMENT (Python, paired per bin variant) ============\n")
  cat("negative diff_mm = median hull read SMALLER than true hull (denoising pulled a stray-point-\n")
  cat("inflated hull in); large |pct_diff| flags a tree/site worth a manual look at the raw slice.\n\n")
  cat(sprintf("(%d per-tree-site rows written to hull_comparison_method_agreement_pertree.csv -- not printed here.)\n",
              nrow(agreement)))
  cat("\n-- agreement summary (mm) --\n")
  print(as.data.frame(agree_summary %>%
          mutate(across(c(mean_diff_mm, mean_abs_diff_mm, max_abs_diff_mm), round),
                 mean_abs_pct_diff = round(mean_abs_pct_diff, 1), cor = round(cor, 3))),
        row.names = FALSE)

  lim2 <- range(c(agreement$true_est, agreement$median_est), na.rm = TRUE)
  p3 <- ggplot(agreement, aes(true_est, median_est, colour = variant)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    geom_point(size = 3, alpha = 0.85) +
    coord_equal(xlim = lim2, ylim = lim2) +
    labs(title = "Hull Method Comparison -- True Hull vs. Median-Polygon Hull (paired, per tree/site)",
         subtitle = "dashed = 1:1",
         x = "True hull equiv. diameter (mm)", y = "Median hull equiv. diameter (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, "hull_comparison_method_agreement_scatter.png"), p3, width = 7, height = 6, dpi = 130)

  cat(sprintf("\nWrote %d rows -> results/hull_comparison_method_agreement_{pertree,summary}.csv and\n  results/plots/hull_comparison_method_agreement_scatter.png\n",
              nrow(agreement)))
}
