# Step 09 — Analysis

**Tool:** R only, by design. Four scripts.

| | |
|---|---|
| **Takes** | the anonymized measurements sheet (`field_measurements_Anon.xlsx`) — nothing else |
| **Makes** | `results/*.csv` and `results/plots/*.png` in the repo |
| **Feeds** | the report |

## What is here

| Script | Question it answers | Output |
|---|---|---|
| `validate_field_accuracy.R` | How close is each cloud method to the field reading? Two scopes: dendrometer-only trees, and every site with a reading. | `results/field_accuracy_{dendrometer_only,all_sites}_{pertree,summary}.csv` + scatter/error plots |
| `compare_hull_methods.R` | Does the denoised median-polygon hull beat the raw-point hull — against the field reading, and against each other? Also prints the Python-vs-R cross-check. | `results/hull_comparison_*` CSVs, Bland–Altman and bin-width agreement plots |
| `plot_error_by_size.R` | Signed % error of every method, split by measurement type (`has_dendrometer`), not by a size threshold. | `results/error_by_size_pertree.csv`, `results/plots/error_by_size_boxplot.png` |
| `build_median_hull_2deg_demo.R` | The median-hull diameter at every processed site, not just the validated ones. | `results/median_hull_2deg_demo_all_sites.{csv,png}` |

`scripts/plot_style.R` (at the `scripts/` root) holds the shared method names, colours and shapes so every figure uses one vocabulary. The first three scripts `source()` it.

## Why R-only

These scripts existed to decide which measurement path the workflow should use. They are not part of processing a tree, so a single-language lab doesn't need them to get from scan to diameter — the workflow layer (Steps 05 and 08) is what carries dual-language coverage.

## Commands

**Run from the repo root.** Every `source("scripts/...")` call and every `results/` output path is relative to the working directory.

```bash
Rscript scripts/Step09_Analysis/validate_field_accuracy.R
Rscript scripts/Step09_Analysis/compare_hull_methods.R
Rscript scripts/Step09_Analysis/plot_error_by_size.R
Rscript scripts/Step09_Analysis/build_median_hull_2deg_demo.R
```

The sheet path is set in each script's CONFIG block and can be overridden without editing by setting the `DAB_SHEET` environment variable.

## Real-tag output never goes in `results/`

All four scripts read only the anonymized sheet, so their output is safe to track in the repo. If you ever point one at real-tag CSVs, send its output to a folder **outside** the repo (this project uses `Working\Mean_Polygons\analysis2_local\`). `results/` is git-tracked.

## This project's run

The full set of outputs listed above was produced; the toolkit repo ships `results/` empty on purpose.
