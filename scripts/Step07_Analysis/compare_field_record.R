#!/usr/bin/env Rscript
# =============================================================================
# compare_field_record.R -- how much do the census's own paint-mark diameters
# disagree with each other, next to how far the scan methods are from the
# field reference?
#
# The field reference is itself a tape reading, and on large buttressed trees
# the BCI census record shows its own paint-mark diameters moving around from
# visit to visit. This script puts the two side by side: the differences
# within the census record, and each scan method's error against the field
# reading on the 18 validation sites.
#
# Input: the BCI 50ha dendrometer census record for the project's trees
# (FIELD_RECORD, sheet "Dendrometer Data"), and the working sheet for the scan
# side, read the same way as validate_field_accuracy.R.
#
# Preparation
#   - duplicate rows (one per dendrometer) dropped on Tag, Census,
#     RAW_DBH_DAP_old_mm and RAW_DBH_DAP_new_mm, then sorted by Tag and Date,
#   - mark height = RAW_HOM_ALT_new_m, else PaintHt_processed_m, carried
#     forward within each tag.
#
# Values left out of the statistics (every one is listed, with its reason, in
# field_record_excluded.csv):
#   - entry errors: below ENTRY_ERROR_FRAC x the median of all that tag's old
#     and new values,
#   - pre-relocation references: on a tree whose mark moved, an old value equal
#     to the census-1 old value, paired with a new value taken at the new height,
#   - tree 2033's values at or above 2700 mm (2010-2016). From 2021 the same
#     6.7 m mark reads 2160-2261 mm, and the height was entered as 1.3 m in
#     2013, so it is not possible to tell which is right,
#   - pairs whose two values are at different mark heights.
#
# Three comparisons over the values that remain, raw differences, no growth
# correction (the decreases are counted, since growth cannot explain those):
#   A. same visit: new - old, on every row with both,
#   B. consecutive new measurements at the same height: later - earlier,
#   C. consecutive distinct reference (old) values at the same height:
#      later - earlier.
#
# Outputs (results/, or DAB_RESULTS):
#   field_record_pairs.csv       every pair, with a comparison column
#   field_record_excluded.csv    every value or pair left out, with the reason
#   field_record_summary.csv     per comparison and per scan method: pairs, trees,
#                                median years apart, mean / median / 90th pct / max
#                                absolute difference (mm), mean / median absolute
#                                difference (%), decreases, pairs >= 30 / 50 / 100 mm
#   plots/field_record_vs_scan.png
#
# Run:  Rscript scripts/Step07_Analysis/compare_field_record.R
# =============================================================================

suppressMessages({ library(readxl); library(dplyr); library(tidyr); library(ggplot2) })
source("scripts/plot_style.R")   # cwd-relative: run from the repo root

# =============================================================================
# CONFIG -- edit these for your own dataset. `sheet` and `outdir` as in the
# other step 7 scripts (DAB_SHEET / DAB_RESULTS override them). FIELD_RECORD is
# the census record, overridden by DAB_FIELD_RECORD. results/ is tracked, so
# what this writes there goes public when the repo is pushed.
# =============================================================================
sheet        <- Sys.getenv("DAB_SHEET",
                           "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx")
FIELD_RECORD <- Sys.getenv("DAB_FIELD_RECORD",
                           "C:/Projects/LiDAR_Project/Raw Data/BCI50ha_20tags_paintDiam_fullrecord.xlsx")
FIELD_RECORD_SHEET <- "Dendrometer Data"
outdir  <- Sys.getenv("DAB_RESULTS", "results")
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)
PAINT_DBH_TREES  <- c("2683", "3031", "180904", "180910", "5943")   # paint mark at breast height: DBH (DJ, 2026-09-28)
EXCLUDE_SITES    <- c("6647 PaintMarker")   # tree + site left out of every analysis: bad scan at the mark (DJ, 2026-09-28)
ENTRY_ERROR_FRAC <- 0.75                    # a value below this x the tag's median is an entry error
TREE_2033_MAX_MM <- 2700                    # 2033's values at or above this are left out (see header)
THRESHOLDS_MM    <- c(30, 50, 100)          # counted in the summary

num <- function(x) suppressWarnings(as.numeric(x))

# ------------------------------------------------------------------ census record
rec <- read_excel(FIELD_RECORD, sheet = FIELD_RECORD_SHEET) %>%
  transmute(tag = as.character(Tag), census = num(Census), date = as.Date(Date),
            old = num(RAW_DBH_DAP_old_mm), new = num(RAW_DBH_DAP_new_mm),
            hom_old = num(RAW_HOM_ALT_old_m), hom_new = num(RAW_HOM_ALT_new_m),
            paint_ht = num(PaintHt_processed_m)) %>%
  distinct(tag, census, old, new, .keep_all = TRUE) %>%
  arrange(tag, date) %>%
  mutate(height = coalesce(hom_new, paint_ht)) %>%
  group_by(tag) %>% fill(height, .direction = "down") %>% ungroup() %>%
  mutate(row_id = row_number())

excluded <- list()
drop_value <- function(df, mask, col, reason) {
  mask <- mask & !is.na(df[[col]])
  if (any(mask)) {
    excluded[[length(excluded) + 1]] <<- df[mask, ] %>%
      transmute(tag, census, date, column = col, value = .data[[col]], reason = reason)
    df[[col]][mask] <- NA
  }
  df
}

# entry errors, against each tag's median of all old and new values
tag_median <- rec %>% select(tag, old, new) %>% pivot_longer(c(old, new)) %>%
  group_by(tag) %>% summarise(med = median(value, na.rm = TRUE), .groups = "drop")
rec <- rec %>% left_join(tag_median, by = "tag")
for (col in c("old", "new")) {
  rec <- drop_value(rec, rec[[col]] < ENTRY_ERROR_FRAC * rec$med,
                    col, sprintf("entry error: below %.2f x the tag's median (%.0f mm)", ENTRY_ERROR_FRAC, NA))
}
excluded <- lapply(excluded, function(e) e %>% left_join(tag_median, by = "tag") %>%
  mutate(reason = sprintf("entry error: below %.2f x the tag's median (%.0f mm)", ENTRY_ERROR_FRAC, med)) %>%
  select(-med))

# pre-relocation references: the census-1 old value carried on after the mark moved
c1 <- rec %>% filter(census == 1) %>% group_by(tag) %>%
  summarise(c1_old = first(na.omit(old)), c1_height = first(height), .groups = "drop")
moved <- rec %>% group_by(tag) %>% summarise(moved = n_distinct(na.omit(height)) > 1, .groups = "drop")
rec <- rec %>% left_join(c1, by = "tag") %>% left_join(moved, by = "tag")
pre_reloc <- with(rec, moved & !is.na(c1_old) & !is.na(old) & old == c1_old &
                    !is.na(new) & !is.na(height) & !is.na(c1_height) & height != c1_height)
rec <- drop_value(rec, pre_reloc, "old", "pre-relocation reference: census-1 value paired with a new value at the new mark height")

# tree 2033: the two sets of values at the same mark can't both be right
for (col in c("old", "new")) {
  rec <- drop_value(rec, rec$tag == "2033" & rec[[col]] >= TREE_2033_MAX_MM, col,
                    sprintf("tree 2033: %s mm or more (2010-2016) conflicts with 2160-2261 mm at the same mark from 2021", TREE_2033_MAX_MM))
}

# ------------------------------------------------------------------ comparisons
# A. same visit: both values on the row, at that visit's mark height, unless
# the record gives the old value its own height (RAW_HOM_ALT_old_m, from
# census 26 on)
A_all <- rec %>% filter(!is.na(old), !is.na(new)) %>%
  transmute(comparison = "A. Same visit", tag, census_1 = census, census_2 = census,
            date_1 = date, date_2 = date, height_1 = coalesce(hom_old, height), height_2 = height,
            value_1 = old, value_2 = new)

# B. consecutive new measurements, C. consecutive distinct reference values
consecutive <- function(df, col, label, distinct_only) {
  v <- df %>% filter(!is.na(.data[[col]])) %>% select(tag, census, date, height, value = all_of(col))
  if (distinct_only) {
    v <- v %>% group_by(tag) %>% filter(is.na(lag(value)) | value != lag(value)) %>% ungroup()
  }
  v %>% group_by(tag) %>%
    mutate(census_1 = lag(census), date_1 = lag(date), height_1 = lag(height), value_1 = lag(value)) %>%
    ungroup() %>% filter(!is.na(value_1)) %>%
    transmute(comparison = label, tag, census_1, census_2 = census, date_1, date_2 = date,
              height_1, height_2 = height, value_1, value_2 = value)
}
B_all <- consecutive(rec, "new", "B. Consecutive new", distinct_only = FALSE)
C_all <- consecutive(rec, "old", "C. Consecutive reference", distinct_only = TRUE)

pairs_all <- bind_rows(A_all, B_all, C_all)
diff_height <- with(pairs_all, !is.na(height_1) & !is.na(height_2) & height_1 != height_2)
if (any(diff_height)) {
  excluded[[length(excluded) + 1]] <- pairs_all[diff_height, ] %>%
    transmute(tag, census = census_2, date = date_2, column = paste0("pair (", comparison, ")"),
              value = value_2 - value_1,
              reason = sprintf("pair at different mark heights (%.2f m and %.2f m)", height_1, height_2))
}
pairs <- pairs_all[!diff_height, ] %>%
  mutate(diff_mm = value_2 - value_1, abs_mm = abs(diff_mm), abs_pct = 100 * abs_mm / value_1,
         years = as.numeric(date_2 - date_1) / 365.25)

# ------------------------------------------------------------------ scan side
# same sheet, sites and filters as validate_field_accuracy.R, all six methods
FIELD_COL <- c(Dendrometer = "Dendrometer_FieldDiameter", PaintMarker = "PaintMarker_FieldDiameter_mm")
raw <- read_excel(sheet) %>% mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag), Tree_Tag != "XXXX")
scan <- bind_rows(lapply(names(FIELD_COL), function(s) raw %>% transmute(
    tag = Tree_Tag, site = s, reading = num(.data[[FIELD_COL[[s]]]]),
    ForestScanner               = num(.data[[sprintf("%s_ForestScanner_Diameter_mm", s)]]),
    Python_true_hull            = num(.data[[sprintf("%s_DendroTape_pythonScript_Diameter_mm", s)]]),
    bin_hull_FixedAngle         = num(.data[[sprintf("%s_BinFixedAngle_pythonScript_Diameter_mm", s)]]),
    bin_hull_MeanDistanceRadius = num(.data[[sprintf("%s_BinMeanDistanceRadius_pythonScript_Diameter_mm", s)]]),
    R                           = num(.data[[sprintf("%s_DabItsme_ConcaveHull_RScript_Diameter_mm", s)]]),
    Circle                      = num(.data[[sprintf("%s_CircleFit_pythonScript_Diameter_mm", s)]])))) %>%
  filter(!is.na(reading), !is.na(Python_true_hull)) %>%
  filter(!paste(tag, site) %in% EXCLUDE_SITES) %>%
  pivot_longer(c(ForestScanner, Python_true_hull, bin_hull_FixedAngle, bin_hull_MeanDistanceRadius, R, Circle),
               names_to = "method", values_to = "est") %>%
  filter(!is.na(est)) %>%
  mutate(comparison = as.character(relabel_method(method)), diff_mm = est - reading,
         abs_mm = abs(diff_mm), abs_pct = 100 * abs_mm / reading, years = NA_real_)

# ------------------------------------------------------------------ summary
summarise_diffs <- function(d) {
  d %>% group_by(comparison) %>% summarise(
    n_pairs          = n(),
    n_trees          = n_distinct(tag),
    median_years     = median(years),
    mean_abs_mm      = mean(abs_mm),
    median_abs_mm    = median(abs_mm),
    p90_abs_mm       = unname(quantile(abs_mm, 0.9, type = 7)),
    max_abs_mm       = max(abs_mm),
    mean_abs_pct     = mean(abs_pct),
    median_abs_pct   = median(abs_pct),
    n_decreases      = sum(diff_mm < 0),
    n_ge_30mm        = sum(abs_mm >= THRESHOLDS_MM[1]),
    n_ge_50mm        = sum(abs_mm >= THRESHOLDS_MM[2]),
    n_ge_100mm       = sum(abs_mm >= THRESHOLDS_MM[3]),
    .groups = "drop")
}
FIELD_ORDER <- c("A. Same visit", "B. Consecutive new", "C. Consecutive reference")
summary_tbl <- bind_rows(summarise_diffs(pairs), summarise_diffs(scan)) %>%
  mutate(source = if_else(comparison %in% FIELD_ORDER, "census record", "scan vs field reading"), .before = 1) %>%
  arrange(factor(comparison, c(FIELD_ORDER, METHOD_ORDER)))

write.csv(pairs %>% select(comparison, tag, census_1, census_2, date_1, date_2, height_1, height_2,
                           value_1, value_2, diff_mm, abs_mm, abs_pct, years),
          file.path(outdir, "field_record_pairs.csv"), row.names = FALSE)
excl <- bind_rows(excluded) %>% arrange(tag, date)
write.csv(excl, file.path(outdir, "field_record_excluded.csv"), row.names = FALSE)
write.csv(summary_tbl, file.path(outdir, "field_record_summary.csv"), row.names = FALSE)

cat(sprintf("Census record: %d rows after dropping duplicates, %d values or pairs left out.\n",
            nrow(rec), nrow(excl)))
cat("\n-- left out, by reason --\n")
print(as.data.frame(excl %>% mutate(reason = sub(":.*", "", reason)) %>% count(reason)), row.names = FALSE)
cat("\n-- summary --\n")
print(as.data.frame(summary_tbl %>% mutate(across(where(is.double), ~ round(.x, 1)))), row.names = FALSE)

# ------------------------------------------------------------------ figure
pd <- bind_rows(pairs %>% transmute(comparison, abs_mm),
                scan %>% transmute(comparison, abs_mm)) %>%
  mutate(comparison = factor(comparison, c(FIELD_ORDER, intersect(METHOD_ORDER, unique(scan$comparison)))))
fills <- c(setNames(rep("#BBBBBB", 3), FIELD_ORDER), METHOD_COLORS)
c_median <- median(pairs$abs_mm[pairs$comparison == "C. Consecutive reference"])
p <- ggplot(pd, aes(comparison, abs_mm, fill = comparison)) +
  geom_hline(yintercept = c_median, linetype = "dashed", colour = "grey40") +
  geom_boxplot(outlier.shape = NA, alpha = 0.6, width = 0.6) +
  geom_jitter(width = 0.15, height = 0, size = 1.3, alpha = 0.6, colour = "grey20") +
  scale_fill_manual(values = fills, guide = "none") +
  scale_y_continuous(trans = scales::pseudo_log_trans(sigma = 10, base = 10),
                     breaks = c(0, 10, 30, 100, 300, 1000)) +
  labs(title = "Differences Within the Census Record, and Scan Errors Against the Field Reading",
       subtitle = sprintf("Census record (grey): A = same visit (new - old), B = consecutive new measurements, C = consecutive reference values.\nScan methods: all %d validation sites. Dashed line = median of C (%.0f mm). Pseudo-log axis.",
                          n_distinct(paste(scan$tag, scan$site)), c_median),
       x = NULL, y = "Absolute difference (mm)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))
ggsave(file.path(plotdir, "field_record_vs_scan.png"), p, width = 12, height = 6.5, dpi = 130)

cat(sprintf("\nWrote %s/field_record_{pairs,excluded,summary}.csv and %s/field_record_vs_scan.png\n", outdir, plotdir))
