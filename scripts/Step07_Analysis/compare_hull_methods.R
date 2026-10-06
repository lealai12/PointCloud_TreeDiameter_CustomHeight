#!/usr/bin/env Rscript
# compare_hull_methods.R  --  HULL METHOD COMPARISON: true hull vs. binned-polygon hull
# ---------------------------------------------------------------------------
# Companion to validate_field_accuracy.R (the main field-accuracy comparison).
# That script is untouched by this one and this script does NOT feed back
# into it -- this is a separate, additive comparison, per project decision:
# the binned-hull method (scripts/bin_mean_distance_radius.py/.R +
# scripts/bin_fixed_angle.py/.R) exists to be compared against the
# existing true-convex-hull method (scripts/dendro_tape.py / .R), not to
# replace it.
#
# WHAT THIS COMPARES
#   - "true hull"     = convex hull of the RAW slice points   (dendro_tape.*)
#   - "binned hull"    = convex hull of a percentile-binned, denoised surface
#                         polygon, in TWO bin-width variants, both kept
#                         standalone rather than one replacing the other
#                         (see bin_mean_distance_radius.py's header for why):
#       2deg = fixed 2-degree angular bin      (bin_fixed_angle.py/.R)
#       10mm = fixed 10mm arc-length bin       (bin_mean_distance_radius.py/.R)
#   - "circle fit"    = least-squares circle on the same polished slice
#                         (circle_fit.py/.R), carried through Part 1 only:
#                         Part 2 pairs the hulls with each other.
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
#   Part 1 -- vs_field_reading: reads only the working sheet, same as
#   validate_field_accuracy.R, at the validation sites of one paint source
#   (the Dendrometer bands and that source's paint marks; first argument, see
#   CONFIG), one row per tree + site. The true-hull and
#   binned-hull diameters (Python AND R, for the cross-check) are all columns
#   in that sheet:
#     <Site>_DendroTape_pythonScript_Diameter_mm             = Python true hull (dendro_tape.py)
#     <Site>_DendroTape_RScript_Diameter_mm        = R true hull (dendro_tape.R)
#     <Site>_BinFixedAngle_pythonScript_Diameter_mm = Python binned hull (2 deg angular bin)
#     <Site>_BinFixedAngle_RScript_Diameter_mm      = R binned hull (2 deg angular bin)
#     <Site>_BinMeanDistanceRadius_pythonScript_Diameter_mm = Python binned hull (10mm arc-length bin)
#     <Site>_BinMeanDistanceRadius_RScript_Diameter_mm      = R binned hull (10mm arc-length bin)
#   The 2 deg and 10mm binned-hull columns are two separate bin_mean_distance_radius.py/.R
#   runs (fixed angular bin vs. fixed arc-length bin -- see that script's header
#   for why the arc-length version was added), transcribed into separate
#   columns rather than overwritten, so both remain comparable here.
#   NOTE: the sheet's `DabItsme_ConcaveHull_RScript` column (the first pass's plain
#   `RScript` column) is a DIFFERENT method -- ITSMe's concave "functional" diameter
#   (dab_itsme_concave_hull.R) -- not used here; don't confuse it with `DendroTape_RScript`.
#
#   Part 2 -- method_agreement: true hull vs. binned hull, paired per
#   tree+site, PER BIN VARIANT (2deg, 10mm), with NO field reading required --
#   the fuller processed batch (every measured site: TopFlag/LowerFlag/
#   ForestGeoPaint/DendroPaint/Dendrometer), not just the ones with field
#   ground truth, and the same whichever source is run. Where a tree's red and
#   blue marks share one slice (same Y), it is counted once. Working sheet
#   only, same as Part 1.
#
# Run:  Rscript scripts/Step07_Analysis/compare_hull_methods.R ForestGeoPaint
#       Rscript scripts/Step07_Analysis/compare_hull_methods.R DendroPaint
# ---------------------------------------------------------------------------

suppressMessages({
  library(readxl); library(dplyr); library(tidyr); library(ggplot2)
})
source("scripts/plot_style.R")   # cwd-relative (run from the repo root): shared method labels/colours/shapes across all plots/*.png

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
# BOTH parts below read only the real-tag working sheet. `outdir` defaults to
# the repo-relative results/ folder, and the DAB_RESULTS env var overrides it.
# results/ is tracked, so what this writes there goes public when the repo is
# pushed.
# Run from the repo root; the source() above is repo-relative.
# =============================================================================
sheet   <- Sys.getenv("DAB_SHEET",
                      "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
EXCLUDE_SENSITIVITY <- character(0)   # trees for an extra "excl." sensitivity row and average bar, empty = none (3853 back in everything, its second-pass ring is fine, DJ 2026-09-28)
FLAG_THRESHOLD      <- 0.5         # MaxEdgeFrac at or above this = flagged ring (sheet values are 3-decimal, so >=)
PAINT_DBH_TREES     <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height, below any buttress: on these trees the paint site (either source) is DBH, not DAB (DJ, 2026-09-28)
EXCLUDE_SITES       <- character(0)   # tree + site pairs left out of every analysis, e.g. "6647 DendroPaint". Empty: both 6647 marks stay in (DJ, 2026-10-06)

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
HAS_SENS   <- length(EXCLUDE_SENSITIVITY) > 0
EXCL_LABEL <- sprintf("excl. %s", paste(EXCLUDE_SENSITIVITY, collapse = ", "))

num   <- function(x) suppressWarnings(as.numeric(x))

# ===========================================================================
# PART 1 -- true hull & binned hull vs. field reading.
# Working sheet only, same as validate_field_accuracy.R, at the Dendrometer
# bands and this run's paint-mark source.
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
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

acc <- bind_rows(lapply(names(FIELD_COL), function(s) raw %>%
  transmute(
    tree               = Tree_Tag,
    site               = s,
    # Not part of the true-hull/binned-hull comparison this script exists for
    # (see header) -- kept only so the plotting section below can build the
    # combined ForestScanner + hull-methods figures (FIG 2a/3/3b) without a
    # second read of the sheet. Deliberately excluded from `long`/the
    # written CSVs, which stay scoped to the three hull methods.
    ForestScanner            = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
    Python_true_hull        = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
    Circle                  = num(.data[[sprintf("%s_CircleFit_pythonScript_Diameter_mm", s)]]),
    R_Circle                = num(.data[[sprintf("%s_CircleFit_RScript_Diameter_mm", s)]]),
    R_true_hull             = num(.data[[sprintf("%s_DendroTape_RScript_Diameter_mm", s)]]),
    Python_bin_hull_FixedAngle      = num(.data[[sprintf("%s_BinFixedAngle_pythonScript_Diameter_mm", s)]]),
    R_bin_hull_FixedAngle           = num(.data[[sprintf("%s_BinFixedAngle_RScript_Diameter_mm", s)]]),
    Python_bin_hull_MeanDistanceRadius = num(.data[[sprintf("%s_BinMeanDistanceRadius_pythonScript_Diameter_mm", s)]]),
    R_bin_hull_MeanDistanceRadius      = num(.data[[sprintf("%s_BinMeanDistanceRadius_RScript_Diameter_mm", s)]]),
    # each method's own gap flag, for the flagged-ring sensitivity row
    edge_true_hull                   = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", s)]]),
    edge_bin_hull_FixedAngle         = num(.data[[sprintf("%s_BinFixedAngle_MaxEdgeFrac", s)]]),
    edge_bin_hull_MeanDistanceRadius = num(.data[[sprintf("%s_BinMeanDistanceRadius_MaxEdgeFrac", s)]]),
    reading            = num(.data[[FIELD_COL[[s]]]])
  ))) %>%
  filter(!is.na(reading)) %>%
  filter(!paste(tree, site) %in% EXCLUDE_SITES) %>%
  # GROUPS: by measurement type, not a diameter threshold. See
  # validate_field_accuracy.R's header for why.
  mutate(size = site_group(site, tree))

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
py_r_check("Python_bin_hull_FixedAngle",      "R_bin_hull_FixedAngle",      "bin_hull_FixedAngle")
py_r_check("Python_bin_hull_MeanDistanceRadius", "R_bin_hull_MeanDistanceRadius", "bin_hull_MeanDistanceRadius")
py_r_check("Circle",                  "R_Circle",           "circle_fit")

long <- acc %>%
  pivot_longer(c(Python_true_hull, Python_bin_hull_FixedAngle, Python_bin_hull_MeanDistanceRadius, Circle),
               names_to = "method", values_to = "est") %>%
  # Display names for CSV columns/plots: drop "Python_" (results are
  # Python-only now, see the cross-check above -- the prefix no longer
  # disambiguates anything) and disambiguate the 2deg variant explicitly
  # instead of leaving it as the unqualified "bin_hull".
  mutate(method = recode(method,
                          Python_true_hull        = "true_hull",
                          Python_bin_hull_FixedAngle      = "bin_hull_FixedAngle",
                          Python_bin_hull_MeanDistanceRadius = "bin_hull_MeanDistanceRadius")) %>%
  filter(!is.na(est)) %>%
  mutate(err   = est - reading,
         pct   = 100 * err / reading,
         # each method is dropped from the flagged-ring row by its own flag
         flag_drop = case_when(
           method == "true_hull"                   ~ edge_true_hull >= FLAG_THRESHOLD,
           method == "bin_hull_FixedAngle"         ~ edge_bin_hull_FixedAngle >= FLAG_THRESHOLD,
           method == "bin_hull_MeanDistanceRadius" ~ edge_bin_hull_MeanDistanceRadius >= FLAG_THRESHOLD,
           method == "Circle"                      ~ edge_true_hull >= FLAG_THRESHOLD),   # same ring as the true hull
         flag_drop = !is.na(flag_drop) & flag_drop,
         # x-axis label for the bar plots: tree tag, short site, and the
         # field reading in parentheses, e.g. "3031 Dendro (724)"
         tree_label = sprintf("%s %s (%.0f)", tree, SITE_SHORT[site], reading))

if (nrow(long) == 0) {
  cat("\n[Part 1 skipped] no field readings in the sheet yet ",
      "(Dendrometer_FieldDiameter, ", FIELD_COL[[PAINT_SOURCE]], ").\n", sep = "")
} else {
  pertree <- long %>%
    mutate(tag = sprintf("%.0f", pct)) %>%
    select(tree, site, size, reading, method, est, tag) %>%
    pivot_wider(names_from = method, values_from = c(est, tag),
                names_glue = "{method}_{.value}") %>%
    arrange(size, reading)
  out_name <- function(stem) sub("^hull_comparison_", sprintf("hull_comparison_%s_", PAINT_SOURCE), stem)
  write.csv(pertree, file.path(outdir, out_name("hull_comparison_vs_field_reading_pertree.csv")), row.names = FALSE)

  summ <- function(df, label) {
    df %>% group_by(method) %>%
      summarise(set = label, n = n(),
                bias = mean(err), MAE = mean(abs(err)),
                RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)),
                .groups = "drop") %>% relocate(set)
  }
  by_group <- function(df, prefix) {
    df %>% group_by(size, method) %>%
      summarise(n = n(), bias = mean(err), MAE = mean(abs(err)),
                RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)), .groups = "drop") %>%
      mutate(set = paste0(prefix, size)) %>% relocate(set) %>% select(-size)
  }
  by_size <- bind_rows(by_group(long, "by group: "),
                       by_group(long %>% filter(!flag_drop), "by group, excl. flagged rings: "))

  summary_tbl <- bind_rows(
    summ(long, "all trees"),
    if (HAS_SENS) summ(long %>% filter(!tree %in% EXCLUDE_SENSITIVITY), EXCL_LABEL),
    summ(long %>% filter(!flag_drop), "excl. flagged rings"),
    if (n_distinct(long$size) > 1) by_size else NULL
  )
  write.csv(summary_tbl, file.path(outdir, out_name("hull_comparison_vs_field_reading_summary.csv")), row.names = FALSE)

  cat(sprintf("\n============ HULL METHOD COMPARISON -- VS. FIELD READING (%s) ============\n", PAINT_SOURCE))
  cat("signed % error per method:\n\n")
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
    transmute(tree, site, size, reading, est = ForestScanner, method = "ForestScanner") %>%
    filter(!is.na(est)) %>%
    mutate(err   = est - reading,
           pct   = 100 * err / reading,
           tree_label = sprintf("%s %s (%.0f)", tree, SITE_SHORT[site], reading))
  long_with_fs <- bind_rows(long, fs_long)

  # ---- FIG 2a: estimate vs. reading, four arms (ForestScanner + all three
  # hull methods) -- revises the previous 3-arm hull-only scatter in place.
  lim <- range(c(long_with_fs$est, long_with_fs$reading), na.rm = TRUE)
  fig2a_data <- long_with_fs %>% mutate(method_label = relabel_method(method))
  p_fig2a <- ggplot(fig2a_data, aes(reading, est, colour = method_label, shape = method_label)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    geom_point(size = 3, alpha = 0.85) +
    scale_colour_method() + scale_shape_method() +
    coord_equal(xlim = lim, ylim = lim) +
    labs(title = "Estimated Diameter vs. Field Reading",
         subtitle = sprintf("Dendrometer bands and %s -- dashed = 1:1", SRC_LABEL),
         x = "Field reading (mm)", y = "Estimated diameter (mm)",
         caption = "Binned hull, fixed angle and Binned hull, mean-distance radius overlap almost exactly at this scale --\nsee hull_comparison_binwidth_agreement.png for the difference on its own axis.") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, out_name("hull_comparison_vs_field_reading_scatter.png")), p_fig2a, width = 7.5, height = 6.8, dpi = 130)

  # ---- FIG 2b: Bland-Altman, the three hull arms only (no ForestScanner --
  # this figure is about agreement between the hull methods and the field
  # reading, not another vs.-reading scatter). Bias/limits of agreement
  # computed without the EXCLUDE_SENSITIVITY trees (every tree when it is empty), for Convex hull and Binned
  # hull 2deg only (the two arms with the biggest spread difference).
  ba_stats <- function(m) {
    d <- long %>% filter(method == m, !tree %in% EXCLUDE_SENSITIVITY)
    b <- mean(d$err); s <- sd(d$err)
    list(bias = b, lo = b - 1.96 * s, hi = b + 1.96 * s)
  }
  stat_true <- ba_stats("true_hull")
  stat_med2 <- ba_stats("bin_hull_FixedAngle")
  col_true  <- METHOD_COLORS[["Convex hull"]]
  col_med2  <- METHOD_COLORS[["Binned hull, fixed angle"]]

  ba_data <- long %>% mutate(method_label = relabel_method(method), mean_est = (est + reading) / 2)
  p_fig2b <- ggplot(ba_data, aes(mean_est, err, colour = method_label, shape = method_label)) +
    geom_hline(yintercept = 0, colour = "grey30") +
    geom_hline(yintercept = stat_true$bias, colour = col_true, linetype = 2) +
    geom_hline(yintercept = c(stat_true$lo, stat_true$hi), colour = col_true, linetype = 3) +
    geom_hline(yintercept = stat_med2$bias, colour = col_med2, linetype = 2) +
    geom_hline(yintercept = c(stat_med2$lo, stat_med2$hi), colour = col_med2, linetype = 3) +
    geom_point(size = 3, alpha = 0.85) +
    geom_text(data = ba_data %>% filter(tree %in% EXCLUDE_SENSITIVITY, method == "true_hull"),
              aes(label = tree), colour = "black", size = 3, vjust = -1, hjust = -0.15,
              show.legend = FALSE) +
    scale_colour_method() + scale_shape_method() +
    labs(title = "Agreement with Field Reading (Bland-Altman)",
         subtitle = paste0("dashed = mean bias, dotted = 95% limits of agreement (Convex hull & Binned hull, fixed angle",
                           if (HAS_SENS) paste0("; ", EXCL_LABEL), ")"),
         x = "Mean of estimate and reading (mm)", y = "Estimate − reading (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, out_name("hull_comparison_bland_altman.png")), p_fig2b, width = 8, height = 6, dpi = 130)

  # ---- shared tree order + summary boundary marker for FIG 3 / FIG 3b
  # No "size boundary" rule here (an earlier version drew one at a diameter
  # threshold): trees are ordered by reading, but the DBH/DAB measurement-type
  # grouping (see `size` above) doesn't split cleanly along that order -- two
  # DBH trees are interleaved among the larger DAB ones -- so a single
  # vertical line can't honestly mark it. by_size in the summary CSV is the
  # place to see the DBH-vs-DAB breakdown; this ordering is just by reading.
  tree_labels_ordered <- long_with_fs %>%
    distinct(tree, reading, tree_label) %>% arrange(reading)
  n_trees <- nrow(tree_labels_ordered)
  level_order  <- c(tree_labels_ordered$tree_label, "Average", if (HAS_SENS) sprintf("Average (%s)", EXCL_LABEL))
  boundary_avg <- n_trees + 0.5   # rule between the last tree and the Average bars

  # ---- FIG 3: signed % error, four arms, revises the hull-only error plot
  # in place -- this is now the one bar chart that covers Q1 (ForestScanner)
  # as well as Q2/Q3 (the hull methods), so a reader doesn't have to flip to
  # field_accuracy_*_error.png for a different colour scheme.
  avg_pct        <- long_with_fs %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>% mutate(tree_label = "Average")
  avg_pct_excl   <- long_with_fs %>% filter(!tree %in% EXCLUDE_SENSITIVITY) %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>% mutate(tree_label = sprintf("Average (%s)", EXCL_LABEL))
  p3_data <- bind_rows(long_with_fs %>% select(tree_label, method, pct),
                       avg_pct, if (HAS_SENS) avg_pct_excl) %>%
    mutate(method_label = relabel_method(method),
           tree_label    = factor(tree_label, levels = level_order))

  # the discrete scale is declared before the dashed rule: a numeric
  # xintercept as the first x layer makes ggplot2 < 3.5 train a continuous
  # x scale, which then rejects the tree labels
  p_fig3 <- ggplot(p3_data, aes(tree_label, pct, fill = method_label)) +
    scale_x_discrete() +
    geom_vline(xintercept = boundary_avg,  linetype = "dashed", colour = "grey70") +
    geom_col(position = position_dodge(0.8), width = 0.7) +
    geom_hline(yintercept = 0, colour = "grey40") +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    scale_fill_method() +
    labs(title = "Signed Percent Error vs. Field Reading",
         subtitle = "trees ordered by reading; dashed rule marks the summary block (see hull_comparison_..._summary.csv for the DBH-vs-DAB breakdown)",
         x = "Tree and site (field reading, mm)", y = "Error  (est - reading) / reading  [%]") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(plotdir, out_name("hull_comparison_vs_field_reading_error.png")), p_fig3, width = 9.5, height = 5.5, dpi = 130)

  # ---- FIG 3b: same data, absolute error in mm. POINTS instead of bars on
  # the pseudo-log axis -- a bar's LENGTH is read as magnitude, so on a log
  # scale a 100mm bar looks roughly 3x a 10mm bar instead of 10x, which is
  # misleading. A point's position on the same axis carries no such
  # implication, so the log-ish compression (needed so one large outlier
  # doesn't flatten every other bar to invisibility) stays honest.
  # The three hull methods only. ForestScanner's errors run to over a metre
  # and would stretch the axis, so they go in the caption instead (DJ, 2026-09-28).
  avg_err        <- long %>% group_by(method) %>%
    summarise(err = mean(err), .groups = "drop") %>% mutate(tree_label = "Average")
  avg_err_excl   <- long %>% filter(!tree %in% EXCLUDE_SENSITIVITY) %>% group_by(method) %>%
    summarise(err = mean(err), .groups = "drop") %>% mutate(tree_label = sprintf("Average (%s)", EXCL_LABEL))
  fs_caption <- if (nrow(fs_long) > 0)
    sprintf("ForestScanner (in-app) is left out of this figure. Its errors run from %.0f to %.0f mm (mean %.0f mm, n = %d tree-sites),\nsee field_accuracy_%s_pertree.csv for each value.",
            min(fs_long$err), max(fs_long$err), mean(fs_long$err), nrow(fs_long), PAINT_SOURCE) else NULL
  p3b_data <- bind_rows(long %>% select(tree_label, method, err),
                        avg_err, if (HAS_SENS) avg_err_excl) %>%
    mutate(method_label = relabel_method(method),
           tree_label    = factor(tree_label, levels = level_order))

  p_fig3b <- ggplot(p3b_data, aes(tree_label, err, colour = method_label, shape = method_label)) +
    scale_x_discrete() +   # see FIG 3
    geom_vline(xintercept = boundary_avg,  linetype = "dashed", colour = "grey70") +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_point(position = position_dodge(0.6), size = 3, alpha = 0.9) +
    scale_y_continuous(trans = scales::pseudo_log_trans(sigma = 10, base = 10),
                        breaks = c(-100, -30, -10, 0, 10, 30, 100, 300)) +
    scale_colour_method() + scale_shape_method() +
    labs(title = "Signed Error vs. Field Reading (mm)",
         subtitle = "points, not bars (bar length on a log axis is misleading); dashed rule marks the summary block",
         x = "Tree and site (field reading, mm)", y = "Error  (est - reading)  [mm, pseudo-log]",
         caption = fs_caption) +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(plotdir, out_name("hull_comparison_vs_field_reading_error_mm.png")), p_fig3b, width = 9.5, height = 5.5, dpi = 130)

  # ---- FIG Q3: bin-width agreement -- the two binned-hull variants overlap
  # almost exactly in FIG 2a (a legend entry with no visible points reads
  # like a rendering bug); this figure shows why, on its own axis.
  q3_data <- long %>% filter(method %in% c("bin_hull_FixedAngle", "bin_hull_MeanDistanceRadius")) %>%
    select(tree, site, reading, method, est) %>%
    pivot_wider(names_from = method, values_from = est) %>%
    mutate(diff_mm = bin_hull_FixedAngle - bin_hull_MeanDistanceRadius)

  p_q3 <- ggplot(q3_data, aes(reading, diff_mm)) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_point(size = 3, colour = col_med2) +
    labs(title = "Bin-Width Agreement: Binned Hull, Fixed Angle vs. Mean-Distance Radius",
         subtitle = "(2° estimate − 10mm estimate) per tree -- the two bin widths are\nindistinguishable at the scale of the measurement",
         x = "Field reading (mm)", y = "2° estimate − 10mm estimate (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, out_name("hull_comparison_binwidth_agreement.png")), p_q3, width = 7.5, height = 5.2, dpi = 130)

  cat(sprintf("\nWrote %s/hull_comparison_%s_vs_field_reading_{pertree,summary}.csv and %s/hull_comparison_%s_{vs_field_reading_{scatter,error,error_mm},bland_altman,binwidth_agreement}.png\n",
              outdir, PAINT_SOURCE, plotdir, PAINT_SOURCE))
}

# ===========================================================================
# PART 2 -- true hull vs. binned hull, PAIRED (same tree+site), no field
# reading required. Working sheet only, see header above.
#
# Python-only in the OUTPUT here too, same reasoning and same 2026-08-02
# decision as Part 1: R columns are still read and cross-checked against
# Python below, just not carried into `agreement`/the summary/the plot.
# ===========================================================================
site_pair <- function(site, stem) {
  raw %>%
    transmute(
      tree = Tree_Tag, site = site,
      true_py = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", site)]]),
      true_r  = num(.data[[sprintf("%s_DendroTape_RScript_Diameter_mm", site)]]),
      med_py  = num(.data[[sprintf("%s_%s_pythonScript_Diameter_mm", site, stem)]]),
      med_r   = num(.data[[sprintf("%s_%s_RScript_Diameter_mm", site, stem)]]),
      true_edge = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", site)]]),
      bin_edge  = num(.data[[sprintf("%s_%s_MaxEdgeFrac", site, stem)]])
    )
}
ALL_SITES <- c("TopFlag", "LowerFlag", "ForestGeoPaint", "DendroPaint", "Dendrometer")
# Trees whose red and blue marks are at the same Y share one polished slice, so
# their DendroPaint row repeats the ForestGeoPaint row. Count that slice once.
# (The Y headers are named this way in the sheet, DJ 2026-10-06.)
y_red  <- num(raw[["Y_value_ForestGeoPaint (Red)"]])
y_blue <- num(raw[["Y_value_DendroPaint (Blue)"]])
SHARED_SLICE_TREES <- raw$Tree_Tag[!is.na(y_red) & !is.na(y_blue) & y_red == y_blue]
drop_shared <- function(df) df %>% filter(!(site == "DendroPaint" & tree %in% SHARED_SLICE_TREES))
pairs_2deg <- bind_rows(lapply(ALL_SITES, site_pair, stem = "BinFixedAngle")) %>%
  filter(!is.na(true_py), !is.na(med_py)) %>% drop_shared()
pairs_10mm <- bind_rows(lapply(ALL_SITES, site_pair, stem = "BinMeanDistanceRadius")) %>%
  filter(!is.na(true_py), !is.na(med_py)) %>% drop_shared()

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
pair_check(pairs_2deg, "med_py",  "med_r",  "bin_hull_FixedAngle")
pair_check(pairs_10mm, "med_py",  "med_r",  "bin_hull_MeanDistanceRadius")

# ITSMe: the Python port (dab_itsme_concave_hull.py) against the R package run
# (dab_itsme_concave_hull.R). Both are written to the sheet in tenths of a mm,
# and the port rounds an occasional exact-tie coordinate the other way, so up
# to about 0.1 mm here is expected. Skipped if the Python columns aren't there.
itsme_pairs <- bind_rows(lapply(ALL_SITES, function(site) {
  py_col <- sprintf("%s_DabItsme_ConcaveHull_pythonScript_Diameter_mm", site)
  r_col  <- sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", site)
  if (!all(c(py_col, r_col) %in% names(raw))) return(NULL)
  data.frame(tree = raw$Tree_Tag, site = site, itsme_py = num(raw[[py_col]]), itsme_r = num(raw[[r_col]]))
})) %>% drop_shared()
if (nrow(itsme_pairs) > 0) pair_check(itsme_pairs, "itsme_py", "itsme_r", "itsme_concave")

# the circle fit, Python (circle_fit.py) against R (circle_fit.R), all sites
circle_pairs <- bind_rows(lapply(ALL_SITES, function(site) {
  py_col <- sprintf("%s_CircleFit_pythonScript_Diameter_mm", site)
  r_col  <- sprintf("%s_CircleFit_RScript_Diameter_mm", site)
  if (!all(c(py_col, r_col) %in% names(raw))) return(NULL)
  data.frame(tree = raw$Tree_Tag, site = site, circle_py = num(raw[[py_col]]), circle_r = num(raw[[r_col]]))
})) %>% drop_shared()
if (nrow(circle_pairs) > 0) pair_check(circle_pairs, "circle_py", "circle_r", "circle_fit")

to_agreement <- function(df, variant) {
  df %>% transmute(tree, site, variant = variant, true_est = true_py, bin_est = med_py,
                    diff_mm = bin_est - true_est, pct_diff = 100 * diff_mm / true_est,
                    true_flagged = !is.na(true_edge) & true_edge >= FLAG_THRESHOLD,
                    bin_flagged  = !is.na(bin_edge)  & bin_edge  >= FLAG_THRESHOLD)
}
agreement <- bind_rows(to_agreement(pairs_2deg, "FixedAngle"), to_agreement(pairs_10mm, "MeanDistanceRadius"))

if (nrow(agreement) == 0) {
  cat("\n[Part 2 skipped] need both a true-hull and a binned-hull value for at least one site/variant.\n")
} else {
  write.csv(agreement, file.path(outdir, "hull_comparison_method_agreement_pertree.csv"), row.names = FALSE)

  agree_summary <- agreement %>% group_by(variant) %>%
    summarise(n = n(),
              mean_diff_mm = mean(diff_mm), mean_abs_diff_mm = mean(abs(diff_mm)),
              mean_abs_pct_diff = mean(abs(pct_diff)),
              max_abs_diff_mm = max(abs(diff_mm)),
              cor = suppressWarnings(cor(true_est, bin_est)),
              .groups = "drop")
  write.csv(agree_summary, file.path(outdir, "hull_comparison_method_agreement_summary.csv"), row.names = FALSE)

  cat("\n============ HULL METHOD COMPARISON -- METHOD AGREEMENT (Python, paired per bin variant) ============\n")
  cat("negative diff_mm = binned hull read SMALLER than true hull (denoising pulled a stray-point-\n")
  cat("inflated hull in); large |pct_diff| flags a tree/site worth a manual look at the raw slice.\n\n")
  cat(sprintf("(%d per-tree-site rows written to hull_comparison_method_agreement_pertree.csv -- not printed here.)\n",
              nrow(agreement)))
  cat("\n-- agreement summary (mm) --\n")
  print(as.data.frame(agree_summary %>%
          mutate(across(c(mean_diff_mm, mean_abs_diff_mm, max_abs_diff_mm), round),
                 mean_abs_pct_diff = round(mean_abs_pct_diff, 1), cor = round(cor, 3))),
        row.names = FALSE)

  lim2 <- range(c(agreement$true_est, agreement$bin_est), na.rm = TRUE)
  p3 <- ggplot(agreement, aes(true_est, bin_est, colour = variant)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    geom_point(size = 3, alpha = 0.85) +
    coord_equal(xlim = lim2, ylim = lim2) +
    labs(title = "Hull Method Comparison -- True Hull vs. Binned-Polygon Hull (paired, per tree/site)",
         subtitle = "dashed = 1:1",
         x = "True hull equiv. diameter (mm)", y = "Binned hull equiv. diameter (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, "hull_comparison_method_agreement_scatter.png"), p3, width = 7, height = 6, dpi = 130)

  cat(sprintf("\nWrote %d rows -> %s/hull_comparison_method_agreement_{pertree,summary}.csv and\n  %s/hull_comparison_method_agreement_scatter.png\n",
              nrow(agreement), outdir, plotdir))
}
