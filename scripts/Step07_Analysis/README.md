# Step 07 — Analysis

Tools: R only, by design. Eight scripts in this folder.

Note: Input is the working sheet, Working_Steps\field_measurements_Draft2_Working.xlsx, with real tree tags, and for compare_field_record.R the BCI census record, Raw Data\BCI50ha_20tags_paintDiam_fullrecord.xlsx. Output CSVs go to results\ and pictures to results\plots\, or to the DAB_RESULTS folder if it is set.

Note: The validation sites are the Dendrometer bands and two paint-mark sources, each with its own field diameter and date: ForestGeoPaint (red, the ForestGEO census mark) and DendroPaint (blue, the dendrometer-program mark). Most scripts run once per source, with the source as the first argument, and put it in every output name (<src> below). The bands are in both runs. TopFlag and LowerFlag are estimate-only sites.

The scripts, and what each one answers:
- validate_field_accuracy.R <src>: how close each cloud method and ForestScanner come to the field reading. Two scopes, the bands only and the bands with that source's paint marks. results\field_accuracy_{dendrometer_only,<src>}_{pertree,summary}.csv, plus scatter and error plots
- compare_hull_methods.R <src>: whether the binned hull beats the raw-point convex hull, against the field reading and against each other. Also prints the Python vs R cross-check. results\hull_comparison_<src>_vs_field_reading_* CSVs, plus scatter, error, Bland-Altman and bin-width plots, and the method agreement over every site, the same for both sources: results\hull_comparison_method_agreement_*
- plot_error_by_size.R <src>: signed % error of every method, by group. results\error_by_size_<src>_pertree.csv, results\plots\error_by_size_<src>_boxplot.png
- plot_by_method.R <src>: the figures above split out, one panel per method, every method. results\plots\by_method_<src>_{scatter,error,error_mm,boxplot,boxplot_mm,bland_altman}.png
- compare_fig_notes.R <src>: at the source's buttressed (DAB) paint sites, error for trees with a fig noted in the BCI census notes vs. trees without, in mm and %. results\fig_notes_<src>_{pertree,summary}.csv, results\plots\fig_notes_<src>_error.png. Also the signed % error bar chart without the fig paint sites, the five cloud methods, with the mm error on each bar. results\plots\field_accuracy_no_fig_sites_<src>_error.png
- compare_field_record.R <src>: how much the census's own paint-mark diameters differ from each other (same visit, consecutive new measurements, consecutive reference values), next to each method's error against the field reading. Raw differences, no growth correction, all marks together. Values left out are listed with their reason. Also, per tree, the spread of every census value at the current paint mark next to the five cloud methods. results\field_record_{pairs,excluded}.csv, results\field_record_{summary,per_tree}_<src>.csv, results\plots\field_record_{vs_scan,per_tree}_<src>.png
- compare_paint_sources.R: the two sources side by side. MAE per method, red against blue, at each source's paint sites, and for trees with both marks every scan estimate against both field values and the difference between the two field values. results\paint_sources_{mae,both_trees}.csv, results\plots\paint_sources_mae.png
- bin_fixed_angle_demo.R: the fixed-angle binned-hull diameter at every processed site, not just the validated ones. results\bin_fixed_angle_demo_all_sites.{csv,png}

Steps:
1. Enter the field readings in the sheet, in mm (Dendrometer_FieldDiameter, ForestGeoPaint_FieldDiameter_mm, DendroPaint_FieldDiameter_mm), and close it in Excel.
2. In each script's CONFIG, set EXCLUDE_SITES, PAINT_DBH_TREES and EXCLUDE_SENSITIVITY (tree + site pairs, like "3853 ForestGeoPaint") for your trees, FIG_TREES in compare_fig_notes.R, and the census record path in compare_field_record.R (or set DAB_FIELD_RECORD).
3. Run every script from the repo root, the per-source ones once for each source:

    Rscript scripts/Step07_Analysis/validate_field_accuracy.R ForestGeoPaint
    Rscript scripts/Step07_Analysis/validate_field_accuracy.R DendroPaint
    Rscript scripts/Step07_Analysis/compare_hull_methods.R    ForestGeoPaint
    Rscript scripts/Step07_Analysis/compare_hull_methods.R    DendroPaint
    Rscript scripts/Step07_Analysis/plot_error_by_size.R      ForestGeoPaint
    Rscript scripts/Step07_Analysis/plot_error_by_size.R      DendroPaint
    Rscript scripts/Step07_Analysis/plot_by_method.R          ForestGeoPaint
    Rscript scripts/Step07_Analysis/plot_by_method.R          DendroPaint
    Rscript scripts/Step07_Analysis/compare_fig_notes.R       ForestGeoPaint
    Rscript scripts/Step07_Analysis/compare_fig_notes.R       DendroPaint
    Rscript scripts/Step07_Analysis/compare_field_record.R    ForestGeoPaint
    Rscript scripts/Step07_Analysis/compare_field_record.R    DendroPaint
    Rscript scripts/Step07_Analysis/compare_paint_sources.R
    Rscript scripts/Step07_Analysis/bin_fixed_angle_demo.R

4. Check that every output listed above is there. A missing file usually means a sheet column upstream is empty, not that a script failed.

Note: The groups are set by measurement type, not a diameter threshold. "Band (dendrometer)" is the Dendrometer site. "DBH (low paint mark)" is the paint site on the PAINT_DBH_TREES, whose mark sits at breast height below any buttress. "DAB (above buttress)" is every other paint site, measured above the buttress.

Note: No row is dropped for having a large error. The headline metrics use every tree-site, flagged rings included. Each summary adds sensitivity rows without flagged rings (MaxEdgeFrac >= 0.5), overall and by group, and one without the tree + site pairs in EXCLUDE_SENSITIVITY when one of them is in the run. Tree + site pairs in EXCLUDE_SITES are left out of everything.

Note: EXCLUDE_SENSITIVITY is "3853 ForestGeoPaint". 3853's red field value (967 mm) sits about 360 mm under every scan method and under its own blue value (1330 mm). It isn't a typo, but it may be a bad measurement. It stays in the headline numbers, and the summaries, average bars and fig-note table each have a version without it. The blue run has no such row, since 3853's blue value is fine.

Note: ForestScanner's errors are much larger than the cloud methods', and on a shared axis they squeeze the cloud methods flat. So where they share an axis, the axis is set by the cloud methods. A ForestScanner value past it is drawn at the edge and its real value is printed on the bar or in the caption. Figures where ForestScanner has its own panel or a log axis are unchanged.

Note: Where a tree's red and blue marks are at the same Y, both sources use the same polished slice, so only the field value differs. The method agreement in compare_hull_methods.R counts that slice once.

Note: Six methods are compared: the five cloud methods from Step 6 and ForestScanner's own reading. Which one to report depends on what the reference instrument measures and on the results. The circle fit is in every field comparison, but not in compare_hull_methods.R's method-agreement and bin-width figures, which pair the hull methods with each other.

Note: ForestScanner is left out of the hull_comparison error_mm figure completely. Its range, mean and count are printed in the figure caption.

Note: scripts/plot_style.R, at the scripts/ root, holds the shared method names, colours and shapes, so every figure uses one vocabulary.

Note: These scripts decided which measurement path the workflow uses. They are not part of processing a tree, so they are R only. The workflow layer, Steps 04 and 06, is what runs in both languages.

Note: results\ is git-tracked, so what the scripts write there becomes public when the repo is pushed.


This project's run:
- First pass: the full set of outputs was produced.
- Second pass: 6 dendrometer bands, 8 red and 11 blue paint sites with a field reading, and 45 tree-sites in the method agreement. Both 6647 marks are in.
