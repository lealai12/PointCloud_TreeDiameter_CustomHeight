#!/usr/bin/env Rscript
# validate_field_accuracy.R  --  FIELD ACCURACY VALIDATION
# ---------------------------------------------------------------------------
# Feasibility study, core accuracy comparison. At each site with a field
# reading (the Dendrometer and PaintMarker sites), compare three diameter
# estimates
#   - ForestScanner  (iPhone app, <Site>_ForestScanner_Diameter_mm)
#   - Python hull    (dendro_tape.py convex-hull equiv diameter)
#   - R functional   (dab_itsme_concave_hull.R ITSMe concave-hull diameter)
# against the field reading (Dendrometer_FieldDiameter or
# PaintMarker_FieldDiameter_mm, mm). Rows are keyed by tree + site, since a
# tree can have a reading at both sites.
#
# Run in TWO scopes:
#   dendrometer_only  -> the Dendrometer site only.
#   all_sites         -> the Dendrometer and PaintMarker sites together.
#
# SIZE GROUPING: by measurement type, not a diameter threshold. "DBH" is the
# Dendrometer site (a band with no buttress problem) plus the PaintMarker site
# on the PAINT_DBH_TREES (CONFIG), whose paint mark sits at breast height below
# any buttress. "DAB (above buttress)" is every other PaintMarker site, a
# buttressed trunk measured above the buttress. Group by the reason the tree
# is hard to measure, not a size proxy for it.
#   - Tree + site pairs in EXCLUDE_SITES (CONFIG) are left out of everything.
#
# Notes:
#   - Trees in EXCLUDE_SENSITIVITY (CONFIG) stay in the headline metrics, and
#     a sensitivity row excluding them is also reported.
#   - Flagged rings (MaxEdgeFrac >= FLAG_THRESHOLD) stay in the headline
#     metrics, and a sensitivity row excluding them is also reported. The hull
#     and ITSMe both use the DendroTape flag, since they measure the same ring.
#     ForestScanner doesn't use the ring, so it is never dropped by the flag.
#   - No row is dropped for having a large error. Every tree + site counts.
#
# Outputs (results/, or DAB_RESULTS), per scope <s> in {dendrometer_only, all_sites}:
#   field_accuracy_<s>_pertree.csv    one row per tree + site, all methods + signed % error
#   field_accuracy_<s>_summary.csv    per-method metrics
#   plots/field_accuracy_<s>_scatter.png   estimate vs reading, 1:1 line
#   plots/field_accuracy_<s>_error.png     signed % error per tree
#
# Run:  Rscript scripts/Step07_Analysis/validate_field_accuracy.R
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
# `outdir` defaults to the repo-relative results/ folder, and the DAB_RESULTS
# env var overrides it. results/ is tracked, so what this writes there goes
# public when the repo is pushed. Run it from the repo root (source() below is
# repo-relative too).
# =============================================================================
sheet  <- Sys.getenv("DAB_SHEET",
                     "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
outdir <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
EXCLUDE_SENSITIVITY <- c("3853")   # trees dropped from the sensitivity row (3853 = first-pass code 17, scan hole over the site)
FLAG_THRESHOLD      <- 0.5         # MaxEdgeFrac at or above this = flagged ring (sheet values are 3-decimal, so >=)
PAINT_DBH_TREES     <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height, below any buttress: their PaintMarker site is DBH, not DAB (DJ, 2026-09-28)
EXCLUDE_SITES       <- c("6647 PaintMarker")   # tree + site left out of every analysis: bad scan at the mark (DJ, 2026-09-28)

# field reading column for each site with ground truth, and its short label
FIELD_COL  <- c(Dendrometer = "Dendrometer_FieldDiameter", PaintMarker = "PaintMarker_FieldDiameter_mm")
SITE_SHORT <- c(Dendrometer = "Dendro", PaintMarker = "Paint")
EXCL_LABEL <- sprintf("excl. %s", paste(EXCLUDE_SENSITIVITY, collapse = ", "))

num   <- function(x) suppressWarnings(as.numeric(x))

# The working sheet holds real tree tags in Tree_Tag. Read it as-is, with no
# translation logic here.
raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag)) %>%
  filter(Tree_Tag != "XXXX")   # tag unknown -- excluded from all analyses (DJ, 2026-09-21)

# every cloud-vs-reading pair, one row per tree + site (the "all_sites" scope)
acc_all <- bind_rows(lapply(names(FIELD_COL), function(s) {
  raw %>%
    transmute(
      tree          = Tree_Tag,
      site          = s,
      ForestScanner = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
      Python        = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
      R             = num(.data[[sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", s)]]),
      max_edge      = num(.data[[sprintf("%s_DendroTape_MaxEdgeFrac", s)]]),
      reading       = num(.data[[FIELD_COL[[s]]]])
    )
})) %>%
  filter(!is.na(reading), !is.na(Python)) %>%
  filter(!paste(tree, site) %in% EXCLUDE_SITES) %>%
  mutate(size         = if_else(site == "Dendrometer" | tree %in% PAINT_DBH_TREES, "DBH", "DAB (above buttress)"),
         ring_flagged = !is.na(max_edge) & max_edge >= FLAG_THRESHOLD)

# ---------------------------------------------------------------------------
# run one scope: long form, per-tree table, metrics, plots
# ---------------------------------------------------------------------------
run_scope <- function(acc, scope, title) {

  if (nrow(acc) == 0) {
    cat(sprintf("\n[%s skipped] no field readings in the sheet yet\n", scope))
    return(invisible(NULL))
  }

  long <- acc %>%
    pivot_longer(c(ForestScanner, Python, R), names_to = "method", values_to = "est") %>%
    filter(!is.na(est)) %>%
    mutate(err   = est - reading,
           pct   = 100 * err / reading,
           # the ring flag drops the hull and ITSMe rows in the flagged-ring
           # sensitivity row, never ForestScanner, which doesn't use the ring
           flag_drop = ring_flagged & method != "ForestScanner",
           # x-axis label for the bar plots: tree tag, short site, and the
           # field reading in parentheses, e.g. "3031 Dendro (724)"
           tree_label = sprintf("%s %s (%.0f)", tree, SITE_SHORT[site], reading))

  pertree <- long %>%
    mutate(tag = sprintf("%.0f", pct)) %>%
    select(tree, site, size, reading, flagged = ring_flagged, method, est, tag) %>%
    pivot_wider(names_from = method, values_from = c(est, tag),
                names_glue = "{method}_{.value}") %>%
    arrange(size, reading)

  summ <- function(df, label) {
    df %>% group_by(method) %>%
      summarise(set = label, n = n(),
                bias = mean(err), MAE = mean(abs(err)),
                RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)),
                .groups = "drop") %>% relocate(set)
  }
  by_size <- long %>% group_by(size, method) %>%
    summarise(n = n(),
              bias = mean(err), MAE = mean(abs(err)),
              RMSE = sqrt(mean(err^2)), MAPE = mean(abs(pct)),
              .groups = "drop") %>%
    mutate(set = paste0("by size: ", size)) %>%
    relocate(set) %>% select(-size)

  summary_tbl <- bind_rows(
    summ(long, "all trees"),
    summ(long %>% filter(!tree %in% EXCLUDE_SENSITIVITY), EXCL_LABEL),
    summ(long %>% filter(!flag_drop), "excl. flagged rings"),
    if (n_distinct(acc$size) > 1) by_size else NULL
  )

  write.csv(pertree,     file.path(outdir, sprintf("field_accuracy_%s_pertree.csv", scope)), row.names = FALSE)
  write.csv(summary_tbl, file.path(outdir, sprintf("field_accuracy_%s_summary.csv", scope)), row.names = FALSE)

  cat(sprintf("\n============ FIELD ACCURACY -- %s  (n=%d) ============\n",
              toupper(title), nrow(acc)))
  cat("signed % error per method:\n\n")
  print(as.data.frame(pertree %>% select(tree, site, size, reading, flagged,
          ForestScanner_tag, Python_tag, R_tag)), row.names = FALSE)
  cat("\n-- per-method metrics (mm; +bias = over-read) --\n")
  print(as.data.frame(summary_tbl %>%
          mutate(across(c(bias, MAE, RMSE), ~round(.x)), MAPE = round(MAPE, 1))),
        row.names = FALSE)

  long <- long %>% mutate(method_label = relabel_method(method))

  lim <- range(c(long$est, long$reading), na.rm = TRUE)
  p1 <- ggplot(long, aes(reading, est, colour = method_label, shape = method_label)) +
    geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey50") +
    geom_point(size = 3, alpha = 0.85)
  p1 <- p1 +
    scale_colour_method() + scale_shape_method() +
    coord_equal(xlim = lim, ylim = lim) +
    labs(title = "Estimated Diameter vs. Field Reading",
         subtitle = paste0(title, " -- dashed = 1:1"),
         x = "Field reading (mm)", y = "Estimated diameter (mm)") +
    theme_minimal(base_size = 12)
  ggsave(file.path(plotdir, sprintf("field_accuracy_%s_scatter.png", scope)),
         p1, width = 8.5, height = 6.8, dpi = 130)

  # append two summary bars per method at the far right of the x-axis: the
  # mean of exactly the bars plotted (every tree, EXCLUDE_SENSITIVITY
  # included), and a second mean excluding the EXCLUDE_SENSITIVITY trees too,
  # so the average can be seen with and without them.
  # Large finite `reading` sentinels (not Inf) so reorder() can still tell
  # the two summary bars apart and order them consistently after the trees.
  avg_pct <- long %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>%
    mutate(tree_label = "Average", reading = 1e6)
  avg_pct_excl <- long %>% filter(!tree %in% EXCLUDE_SENSITIVITY) %>% group_by(method) %>%
    summarise(pct = mean(pct), .groups = "drop") %>%
    mutate(tree_label = sprintf("Average (%s)", EXCL_LABEL), reading = 2e6)
  p2_data <- bind_rows(long %>% select(tree_label, reading, method, pct),
                       avg_pct, avg_pct_excl) %>%
    mutate(method_label = relabel_method(method))

  # Extra top headroom (12% instead of ggplot's 5% default): when one tree's
  # error dominates the range, the default expansion leaves its bar sitting
  # right against the panel edge, not clipped, but it reads that way.
  p2 <- ggplot(p2_data, aes(reorder(tree_label, reading), pct, fill = method_label)) +
    geom_col(position = position_dodge(0.8), width = 0.7) +
    geom_hline(yintercept = 0, colour = "grey40") +
    scale_y_continuous(expand = expansion(mult = c(0.05, 0.12))) +
    scale_fill_method() +
    labs(title = "Signed Percent Error vs. Field Reading",
         subtitle = paste0(title, " -- trees ordered by reading, plus per-method averages"),
         x = "Tree and site (field reading, mm)", y = "Error  (est - reading) / reading  [%]") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(plotdir, sprintf("field_accuracy_%s_error.png", scope)),
         p2, width = 8.5, height = 5.2, dpi = 130)

  invisible(summary_tbl)
}

# the Dendrometer site only
r1 <- run_scope(acc_all %>% filter(site == "Dendrometer"),
                "dendrometer_only", "Dendrometer Site Only")

# every site with a field reading (Dendrometer + PaintMarker)
r2 <- run_scope(acc_all,
                "all_sites", "All Validated Sites")

if (!is.null(r1) || !is.null(r2))
  cat(sprintf("\nWrote %s/field_accuracy_{dendrometer_only,all_sites}_{pertree,summary}.csv and %s/field_accuracy_*_{scatter,error}.png\n",
              outdir, plotdir))
