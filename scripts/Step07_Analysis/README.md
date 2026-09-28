# Step 07 — Analysis

Tools: R only, by design. Five scripts in this folder.

Note: Input is the working sheet, Working_Steps\field_measurements_Draft2_Working.xlsx, with real tree tags. Nothing else is read. Output CSVs go to results\ and pictures to results\plots\, or to the DAB_RESULTS folder if it is set.

The scripts, and what each one answers:
- validate_field_accuracy.R: how close each cloud method and ForestScanner come to the field reading. Two scopes, the Dendrometer site only and both sites with a reading. results\field_accuracy_{dendrometer_only,all_sites}_{pertree,summary}.csv, plus scatter and error plots
- compare_hull_methods.R: whether the binned hull beats the raw-point convex hull, against the field reading and against each other. Also prints the Python vs R cross-check. results\hull_comparison_* CSVs, plus scatter, error, Bland-Altman and bin-width plots
- plot_error_by_size.R: signed % error of every method, DBH vs DAB. results\error_by_size_pertree.csv, results\plots\error_by_size_boxplot.png
- bin_fixed_angle_demo.R: the fixed-angle binned-hull diameter at every processed site, not just the validated ones. results\bin_fixed_angle_demo_all_sites.{csv,png}
- plot_by_method.R: the figures above split out, one panel per method, all five methods. results\plots\by_method_{scatter,error,error_mm,boxplot,bland_altman}.png

Steps:
1. Enter the field readings in the sheet, in mm (Dendrometer_FieldDiameter, PaintMarker_FieldDiameter_mm), and close it in Excel.
2. In each script's CONFIG, set EXCLUDE_SITES, PAINT_DBH_TREES and EXCLUDE_SENSITIVITY for your trees.
3. Run every script from the repo root:

    Rscript scripts/Step07_Analysis/validate_field_accuracy.R
    Rscript scripts/Step07_Analysis/compare_hull_methods.R
    Rscript scripts/Step07_Analysis/plot_error_by_size.R
    Rscript scripts/Step07_Analysis/bin_fixed_angle_demo.R
    Rscript scripts/Step07_Analysis/plot_by_method.R

4. Check that every output listed above is there. A missing file usually means a sheet column upstream is empty, not that a script failed.

Note: DBH vs DAB is set by measurement type, not a diameter threshold. DBH is the Dendrometer site plus the PaintMarker site on the PAINT_DBH_TREES, whose paint mark sits at breast height below any buttress. DAB is every other PaintMarker site, measured above the buttress.

Note: No row is dropped for having a large error. The headline metrics use every tree-site, flagged rings included. Each summary adds two sensitivity rows, one without the trees in EXCLUDE_SENSITIVITY and one without flagged rings (MaxEdgeFrac >= 0.5). Tree + site pairs in EXCLUDE_SITES are left out of everything.

Note: ForestScanner is left out of hull_comparison_vs_field_reading_error_mm.png, since its errors run to over a metre and would stretch the axis. Its range, mean and count are printed in the figure caption.

Note: scripts/plot_style.R, at the scripts/ root, holds the shared method names, colours and shapes, so every figure uses one vocabulary.

Note: These scripts decided which measurement path the workflow uses. They are not part of processing a tree, so they are R only. The workflow layer, Steps 04 and 06, is what runs in both languages.

Note: results\ is git-tracked, so what the scripts write there becomes public when the repo is pushed.


This project's run:
- First pass: the full set of outputs was produced.
- Second pass: 18 tree-sites with a field reading (11 DBH, 7 DAB), and 41 tree-sites in the method agreement and demo. 6647 PaintMarker was left out, bad scan at the mark.
