# Step 07 — Analysis

**Tool:** R only, by design. Four scripts.

| | |
|---|---|
| **Takes** | the working measurements sheet (`Working_Steps\field_measurements_Draft2_Working.xlsx`, real tree tags) — nothing else |
| **Makes** | `results/*.csv` and `results/plots/*.png` in the repo, or in the `DAB_RESULTS` folder if set |
| **Feeds** | the report |

## What is here

| Script | Question it answers | Output |
|---|---|---|
| `validate_field_accuracy.R` | How close is each cloud method to the field reading? Two scopes: the Dendrometer site only, and both sites with a reading (Dendrometer and PaintMarker). | `results/field_accuracy_{dendrometer_only,all_sites}_{pertree,summary}.csv` + scatter/error plots |
| `compare_hull_methods.R` | Does the denoised binned hull beat the raw-point hull — against the field reading, and against each other? Also prints the Python-vs-R cross-check. | `results/hull_comparison_*` CSVs, Bland–Altman and bin-width agreement plots |
| `plot_error_by_size.R` | Signed % error of every method, split by measurement type (DBH at the Dendrometer site, DAB at the PaintMarker site), not by a size threshold. | `results/error_by_size_pertree.csv`, `results/plots/error_by_size_boxplot.png` |
| `bin_fixed_angle_demo.R` | The fixed-angle binned-hull diameter at every processed site, not just the validated ones. | `results/bin_fixed_angle_demo_all_sites.{csv,png}` |

`scripts/plot_style.R` (at the `scripts/` root) holds the shared method names, colours and shapes so every figure uses one vocabulary. The first three scripts `source()` it.

## Why R-only

These scripts existed to decide which measurement path the workflow should use. They are not part of processing a tree, so a single-language lab doesn't need them to get from scan to diameter — the workflow layer (Steps 04 and 06) is what carries dual-language coverage.

## Commands

**Run from the repo root.** Every `source("scripts/...")` call and every `results/` output path is relative to the working directory.

```bash
Rscript scripts/Step07_Analysis/validate_field_accuracy.R
Rscript scripts/Step07_Analysis/compare_hull_methods.R
Rscript scripts/Step07_Analysis/plot_error_by_size.R
Rscript scripts/Step07_Analysis/bin_fixed_angle_demo.R
```

The sheet path is set in each script's CONFIG block and can be overridden without editing by setting the `DAB_SHEET` environment variable. The output folder defaults to `results/` and can be overridden the same way with `DAB_RESULTS`.

`results/` is git-tracked, so what the scripts write there becomes public when the repo is pushed.

## This project's run

The full set of outputs listed above was produced; the toolkit repo ships `results/` empty on purpose.
