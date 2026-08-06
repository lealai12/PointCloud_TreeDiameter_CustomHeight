#!/usr/bin/env Rscript
# =============================================================================
# build_median_hull_2deg_demo.R -- demonstration table + figure of the
# median-hull, 2-degree-bin method (median_polygon_2deg.py) across every
# processed tree/site, not just the field-validated subset.
#
# WHY THIS EXISTS
# ----------------
# validate_field_accuracy.R answers "which method is most accurate" using
# only sites with a field reading to compare against. This script answers a
# different question: "what does the method identified as most effective
# actually produce, across every site processed so far" -- a demonstration/
# coverage view, not a new accuracy result.
#
# ANONYMIZED SHEET ONLY -- same rule as validate_field_accuracy.R
# -------------------------------------------------------------------
# Reads ONLY field_measurements_Anon.xlsx. Output goes to results/, same as
# every other output in this repo.
# =============================================================================

suppressMessages({ library(dplyr); library(tidyr); library(ggplot2); library(readxl) })

sheet   <- "C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"
outdir  <- "results"
plotdir <- file.path(outdir, "plots")
dir.create(plotdir, recursive = TRUE, showWarnings = FALSE)

raw <- read_excel(sheet) %>%
  mutate(Tree_Tag = as.character(Tree_Tag)) %>%
  filter(!is.na(Tree_Tag))

sites <- c("TopFlag", "LowerFlag", "Dendrometer")

demo <- bind_rows(lapply(sites, function(s) {
  raw %>%
    transmute(tree_id = Tree_Tag,
              site = s,
              height_m = .data[[sprintf("Y_value_%s", s)]],
              diameter_mm = .data[[sprintf("%s_MedianPolygon_pythonScript_Diameter_mm", s)]],
              dendrometer_reading_mm = if (s == "Dendrometer") suppressWarnings(as.numeric(Dendrometer_Reading)) else NA_real_,
              has_dendrometer = has_dendrometer)
})) %>%
  filter(!is.na(diameter_mm)) %>%
  arrange(diameter_mm) %>%
  mutate(tree_id = factor(tree_id, levels = unique(tree_id)))

write.csv(demo, file.path(outdir, "median_hull_2deg_demo_all_sites.csv"), row.names = FALSE)
cat(sprintf("Wrote %d rows -> %s\n", nrow(demo), file.path(outdir, "median_hull_2deg_demo_all_sites.csv")))
cat("\n")
print(as.data.frame(demo), row.names = FALSE)

# --------------------------------------------------------------------- figure
p <- ggplot(demo, aes(tree_id, diameter_mm, colour = site)) +
  geom_point(size = 3) +
  scale_colour_manual(values = c(LowerFlag = "#0072B2", Dendrometer = "#009E73", TopFlag = "#E69F00"),
                       name = "Site") +
  labs(title = "Median hull, 2\u00b0 bins -- diameter at every processed site",
       subtitle = "The method identified as most effective, applied to every processed tree/site\n(not just the field-validated subset used to pick it)",
       x = "Tree (anonymized code)", y = "Median-hull equivalent diameter (mm)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 60, hjust = 1))

out_png <- file.path(plotdir, "median_hull_2deg_demo_all_sites.png")
ggsave(out_png, p, width = 10, height = 6, dpi = 130)
cat(sprintf("\nWrote %s\n", out_png))
