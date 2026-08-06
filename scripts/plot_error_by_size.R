#!/usr/bin/env Rscript
# =============================================================================
# plot_error_by_size.R -- one box plot: signed % error vs. dendrometer
# reading, every method, split DBH-style dendrometer trees vs. DAB
# (above-buttress) trees.
#
# validate_field_accuracy.R and compare_hull_methods.R each report per-tree
# error and size-stratified summary stats, but neither puts every method
# side by side on one axis to compare the SHAPE of each method's error
# distribution across the split -- that's what this is for. No new
# measurement, no new metric: same errors those two scripts already compute,
# just all five methods in one plot.
#
# GROUPING: has_dendrometer, not a diameter threshold. The split that
# actually matters here is WHY a tree is hard to measure -- a real
# dendrometer band at breast height (has_dendrometer == "Yes", standard DBH,
# no buttress problem) vs. a buttressed trunk measured above the buttress
# instead (has_dendrometer %in% c("No", "Marked") -- DAB). In this sample
# that happens to line up closely with a ~1m diameter split too, but the
# measurement-type grouping is the real driver and the one that generalizes
# (an earlier version of this script used a raw <1000mm/>=1000mm threshold
# instead -- that's a proxy, not the actual reason these trees are hard).
#
# Anonymized sheet only, same rule as every other script in this repo.
# =============================================================================

suppressMessages({ library(readxl); library(dplyr); library(tidyr); library(ggplot2) })
source("scripts/plot_style.R")

sheet   <- "C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"
outdir  <- "results"
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)

num   <- function(x) suppressWarnings(as.numeric(x))
GROSS <- 0.5     # |error|/reading above this = likely data-entry/registration error, excluded

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag))

# pivot column names use plot_style.R's internal method keys (relabel_method()
# maps them to the shared display labels below) so this figure's colours and
# names match every other results/plots/*.png in this repo.
acc <- raw %>%
  transmute(
    tree                  = Tree_Tag,
    reading               = num(Dendrometer_Reading),
    has_dendrometer       = has_dendrometer,
    ForestScanner         = num(Dendrometer_ForestScanner_Diameter_mm),
    Python_true_hull      = num(Dendrometer_pythonScript_Diameter_mm),
    R                     = num(Dendrometer_RScript_Diameter_mm),
    median_hull_2Degrees  = num(Dendrometer_MedianPolygon_pythonScript_Diameter_mm),
    median_hull_10mm      = num(Dendrometer_MedianPolygon10mm_pythonScript_Diameter_mm)
  ) %>%
  filter(!is.na(reading)) %>%
  mutate(size = if_else(has_dendrometer == "Yes", "DBH (dendrometer)", "DAB (above buttress)"))

long <- acc %>%
  pivot_longer(c(ForestScanner, Python_true_hull, R, median_hull_2Degrees, median_hull_10mm),
               names_to = "method", values_to = "est") %>%
  filter(!is.na(est)) %>%
  mutate(err   = est - reading,
         pct   = 100 * err / reading,
         gross = abs(err) / reading > GROSS,
         method_label = relabel_method(method))

n_excluded <- sum(long$gross)
long_clean <- long %>% filter(!gross)

cat(sprintf("Error-by-size box plot: %d rows (%d gross outliers excluded).\n",
            nrow(long_clean), n_excluded))
cat("\n-- n per method x size --\n")
print(as.data.frame(long_clean %>% count(method_label, size)), row.names = FALSE)

write.csv(long_clean %>% select(tree, size, reading, method = method_label, est, err, pct),
          file.path(outdir, "error_by_size_pertree.csv"), row.names = FALSE)

p <- ggplot(long_clean, aes(method_label, pct, fill = size)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_boxplot(outlier.shape = NA, alpha = 0.7, width = 0.6,
               position = position_dodge(0.7)) +
  geom_point(position = position_jitterdodge(jitter.width = 0.12, dodge.width = 0.7),
             size = 1.8, alpha = 0.8, shape = 16) +
  scale_fill_manual(values = c("DBH (dendrometer)" = "#56B4E9", "DAB (above buttress)" = "#D55E00"),
                     name = "Measurement type") +
  labs(title = "Signed Percent Error vs. Dendrometer Reading, by Method and Measurement Type",
       subtitle = sprintf("Every method compared against field reading, dendrometer sites only (n=%d trees; %d gross data-entry outlier%s excluded)",
                           n_distinct(long_clean$tree), n_excluded, if (n_excluded == 1) "" else "s"),
       x = NULL, y = "Error  (est - reading) / reading  [%]") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

out_png <- file.path(plotdir, "error_by_size_boxplot.png")
ggsave(out_png, p, width = 9.5, height = 6.2, dpi = 130)
cat(sprintf("\nWrote %s and\n  %s\n", file.path(outdir, "error_by_size_pertree.csv"), out_png))
