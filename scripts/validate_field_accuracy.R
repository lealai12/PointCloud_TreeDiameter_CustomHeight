#!/usr/bin/env Rscript
# validate_field_accuracy.R  --  FIELD ACCURACY VALIDATION
# ---------------------------------------------------------------------------
# Feasibility study, core accuracy comparison. At the dendrometer band,
# compare three diameter estimates
#   - ForestScanner  (iPhone app, Dendrometer_ForestScanner_Diameter_mm)
#   - Python hull    (fit_dab.py convex-hull equiv diameter)
#   - R functional   (dab_itsme.R ITSMe concave-hull diameter)
# against the field ground truth (Dendrometer_Reading, mm).
#
# Run in TWO scopes:
#   dendrometer_only  -> only trees with a real dendrometer (has_dendrometer
#                        == "Yes"; they carry Dendro_DateTime + 1.3 m).
#   all_sites         -> every tree with a dendrometer-site cloud estimate +
#                        reading (Yes + Marked + No).
#
# SIZE GROUPING: measurement type (has_dendrometer), not a diameter
# threshold. "small"/"large" below is really "DBH-style dendrometer tree" vs.
# "DAB (above-buttress) tree" -- has_dendrometer == "Yes" means a real
# dendrometer band at breast height (no buttress problem), regardless of
# that tree's actual diameter; "Marked"/"No" means a buttressed trunk
# measured above the buttress instead. These two groupings mostly overlap
# with a ~1m diameter split in this sample but NOT always -- two
# has_dendrometer == "Yes" trees are >1m diameter. Group by the reason the
# tree is hard to measure, not a size proxy for it.
#
# Notes:
#   - Tree 17 (code) is kept in (per operator) but over-reads badly on the cloud
#     methods; a sensitivity row excluding it is also reported.
#   - Gross data-entry outliers (|error|/reading > 0.5, e.g. ForestScanner
#     misreads on codes 14 and 6) are flagged and excluded from metrics.
#
# Outputs (repo results/), per scope <s> in {dendrometer_only, all_sites}:
#   field_accuracy_<s>_pertree.csv    one row per tree, all methods + signed % error
#   field_accuracy_<s>_summary.csv    per-method metrics
#   plots/field_accuracy_<s>_scatter.png   estimate vs reading, 1:1 line
#   plots/field_accuracy_<s>_error.png     signed % error per tree
#
# Run:  Rscript scripts/validate_field_accuracy.R
# ---------------------------------------------------------------------------

suppressMessages({
  library(readxl); library(dplyr); library(tidyr); library(ggplot2)
})
source("scripts/plot_style.R")   # shared method labels/colours/shapes across all plots/*.png

sheet  <- "C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"
outdir <- "results"
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)

num   <- function(x) suppressWarnings(as.numeric(x))
GROSS <- 0.5     # |error|/reading above this = likely data-entry error, excluded

# field_measurements_Anon.xlsx holds anonymized codes in Tree_Tag. Read only
# this anonymized file, as-is -- no translation logic here.
raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag))

# every dendrometer-site cloud-vs-reading pair (the "all_sites" scope) ------
acc_all <- raw %>%
  transmute(
    tree          = Tree_Tag,
    has_dendro    = has_dendrometer,
    ForestScanner = num(Dendrometer_ForestScanner_Diameter_mm),
    Python        = num(Dendrometer_pythonScript_Diameter_mm),
    R             = num(Dendrometer_RScript_Diameter_mm),
    reading       = num(Dendrometer_Reading)
  ) %>%
  filter(!is.na(reading), !is.na(Python)) %>%
  mutate(size = if_else(has_dendro == "Yes", "DBH (dendrometer)", "DAB (above buttress)"))

# ---------------------------------------------------------------------------
# run one scope: long form, per-tree table, metrics, plots
# ---------------------------------------------------------------------------
run_scope <- function(acc, scope, title) {

  long <- acc %>%
    pivot_longer(c(ForestScanner, Python, R), names_to = "method", values_to = "est") %>%
    filter(!is.na(est)) %>%
    mutate(err   = est - reading,
           pct   = 100 * err / reading,
           gross = abs(err) / reading > GROSS,
           # x-axis label for the bar plots: tree number + true dendrometer
           # reading in parentheses, e.g. "15 (448)"
           tree_label = sprintf("%s (%.0f)", tree, reading))

  pertree <- long %>%
    mutate(tag = ifelse(gross, sprintf("%.0f*", pct), sprintf("%.0f", pct))) %>%
    select(tree, size, reading, method, est, tag) %>%
    pivot_wider(names_from = method, values_from = c(est, tag),
                names_glue = "{method}_{.value}") %>%
    arrange(size, reading)

  summ <- function(df, label) {
    df %>% filter(!gross) %>% group_by(method) %>%
      summarise(set = label, n = n(),
                bias = mean(err), MAE = mean(abs(err)),
                RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)),
                .groups = "drop") %>% relocate(set)
  }
  by_size <- long %>% filter(!gross) %>% group_by(size, method) %>%
    summarise(n = n(),
              bias = mean(err), MAE = mean(abs(err)),
              RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)),
              .groups = "drop") %>%
    mutate(set = paste0("by size: ", size)) %>%
    relocate(set) %>% select(-size)

  summary_tbl <- bind_rows(
    summ(long, "all trees"),
    summ(long %>% filter(tree != "17"), "excl. tree 17"),
    if (n_distinct(acc$size) > 1) by_size else NULL
  )

  gross_rows <- long %>% filter(gross) %>% select(tree, method, est, reading, pct)

  write.csv(pertree,     file.path(outdir, sprintf("field_accuracy_%s_pertree.csv", scope)), row.names = FALSE)
  write.csv(summary_tbl, file.path(outdir, sprintf("field_accuracy_%s_summary.csv", scope)), row.names = FALSE)

  cat(sprintf("\n============ FIELD ACCURACY -- %s  (n=%d) ============\n",
              toupper(title), nrow(acc)))
  cat("signed % error per method (* = gross outlier, excluded from metrics):\n\n")
  print(as.data.frame(pertree %>% select(tree, size, reading,
          ForestScanner_tag, Python_tag, R_tag)), row.names = FALSE)
  if (nrow(gross_rows)) {
    cat("\n-- gross data-entry outliers (excluded) --\n")
    print(as.data.frame(gross_rows), row.names = FALSE)
  }
  cat("\n-- per-method metrics (mm; +bias = over-read) --\n")
  print(as.data.frame(summary_tbl %>%
          mutate(across(c(bias, MAE, RMSE), ~round(.x)), MAPE = round(MAPE, 1))),
        row.names = FALSE)

  long <- long %>% mutate(method_label = relabel_method(method))
  has_gross <- any(long$gross)

  lim <- range(c(long$est, long$reading), na.rm = TRUE)
  p1 <- ggplot(long, aes(reading, est, colour = method_label, shape = method_label)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    geom_point(size = 3, alpha = 0.85)
  if (has_gross) {
    p1 <- p1 +
      geom_point(data = long %>% filter(gross), aes(reading, est),
                 shape = 4, size = 5, stroke = 1.4, colour = "black",
                 inherit.aes = FALSE, show.legend = FALSE) +
      geom_text(data = long %>% filter(gross), aes(reading, est, label = tree),
                 colour = "black", size = 3, vjust = -1.1, inherit.aes = FALSE)
  }
  p1 <- p1 +
    scale_colour_method() + scale_shape_method() +
    coord_equal(xlim = lim, ylim = lim) +
    labs(title = "Estimated Diameter vs. Dendrometer Reading",
         subtitle = paste0(title, " -- dashed = 1:1",
                            if (has_gross) "; x = gross data-entry misread" else ""),
         x = "Dendrometer reading (mm)", y = "Estimated diameter (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, sprintf("field_accuracy_%s_scatter.png", scope)),
         p1, width = 8.5, height = 6.8, dpi = 130)

  # append two summary bars per method at the far right of the x-axis: the
  # mean of exactly the bars plotted (non-gross trees, tree 17 included), and
  # a second mean excluding tree 17 too (tree 17 is a known outlier in this
  # dataset -- see below -- so it's useful to see the average with and without it).
  # Large finite `reading` sentinels (not Inf) so reorder() can still tell
  # the two summary bars apart and order them consistently after the trees.
  avg_pct <- long %>% filter(!gross) %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>%
    mutate(tree_label = "Average", reading = 1e6)
  avg_pct_excl17 <- long %>% filter(!gross, tree != "17") %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>%
    mutate(tree_label = "Average (excl. 17)", reading = 2e6)
  p2_data <- bind_rows(long %>% filter(!gross) %>% select(tree_label, reading, method, pct),
                       avg_pct, avg_pct_excl17) %>%
    mutate(method_label = relabel_method(method))

  # Extra top headroom (12% instead of ggplot's 5% default): with tree 17's
  # error dominating the range, the default expansion leaves its bar sitting
  # right against the panel edge -- not clipped, but reads that way.
  p2 <- ggplot(p2_data, aes(reorder(tree_label, reading), pct, fill = method_label)) +
    geom_col(position = position_dodge(0.8), width = 0.7) +
    geom_hline(yintercept = 0, colour = "grey40") +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    scale_fill_method() +
    labs(title = "Signed Percent Error vs. Dendrometer Reading",
         subtitle = paste0(title, " -- trees ordered by reading, plus per-method averages"),
         x = "Tree (dendrometer reading, mm)", y = "Error  (est - reading) / reading  [%]") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(plotdir, sprintf("field_accuracy_%s_error.png", scope)),
         p2, width = 8.5, height = 5.2, dpi = 130)

  invisible(summary_tbl)
}

# dendrometer trees only
run_scope(acc_all %>% filter(has_dendro == "Yes"),
          "dendrometer_only", "Real Dendrometer Trees Only")

# every validated site (dendrometer + marked/matched sites on buttressed trees)
run_scope(acc_all,
          "all_sites", "All Validated Sites")

cat("\nWrote results/field_accuracy_{dendrometer_only,all_sites}_{pertree,summary}.csv and",
    "results/plots/field_accuracy_{dendrometer_only,all_sites}_{scatter,error}.png\n")
