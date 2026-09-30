# Unused

**Nothing in this folder is part of the workflow. A future user should not run any of it.** The files are kept for three different reasons: two were superseded, two were never run, and one is the mistake the workflow was built to avoid.

## `measure_slice.py` / `measure_slice.R` — retired, superseded by `dendro_tape`

Retired **2026-09-21**. These measured a polished slice with a least-squares circle fit plus a convex-hull "tape" perimeter, and they produced this project's first-pass numbers.

`dendro_tape.py` / `dendro_tape.R` now do that job, and do it better:

- **Same number.** The convex-hull diameter is identical — 0.0000 mm apart on all 32 first-pass slices.
- **Plus a gap check.** `dendro_tape` measures the largest hull edge as a fraction of equivalent diameter, catching a ring that chords across a hole — something angular coverage misses, because coverage is measured from the centroid and over-reports on a broken ring. On the first-pass slices it flagged 6 of the 32 rings `measure_slice` accepted in silence: `2033__TopFlag`, `4524__LowerFlag`, `5213__LowerFlag`, `5926__LowerFlag`, `6647__LowerFlag`, `7163__LowerFlag`. Since 2026-09-24 the check **flags rather than blocks** — the diameter is written either way and the fraction goes to its own `MaxEdgeFrac` column, because the guard cannot tell a genuine scan gap from a deep flute that a girth tape would legitimately bridge.
- **Same pictures.** `dendro_tape` gained `--viz-dir`, writing the same bundle (fit PNG, slice cloud, hull/circle overlay PLYs, `measure.txt`), and draws a flagged ring's long edge in magenta labelled **PARTIAL RING**.

They are kept as the record of what produced the first-pass results. `OUTPUT_COL` is set to `None` / `NULL` in both, so neither can write to the sheet even if run. Their measurement code is a copy of `fit_dab.*`, which stays at the `scripts/` root for the same reason.

## `circle_fit_slices.R` — superseded by `Step06_Measure/circle_fit`

Fitted the least-squares circle on every polished slice for Step 7. Since 2026-09-30 `circle_fit.py` / `.R` do that in Step 6 and write the result to the sheet, which Step 7 now reads, so nothing uses this script's `results/circle_fit_slices.csv` any more.

## `loopclose.py` / `loopclose.R` — never run, produced nothing

Scripted loop-closing: register two hand-cut arc fragments (FPFH/RANSAC coarse alignment then point-to-plane ICP in the Python version; direct ICP with no coarse step in the R port) and merge them to `stitched/<tag>.ply`.

Three independent lines of evidence that they were not used in this study:

1. **No output, ever.** `loopclose.py` writes only to `stitched/`. The repo's `stitched/` holds nothing but `.gitkeep`, and no `stitched` folder exists anywhere in the project's working data.
2. **Never edited.** `loopclose.py`'s modification time is identical to the untouched originals from the same day (`.gitattributes`, `requirements.txt`, `xlsx_repair.R`, `dendro_tape.py`). `loopclose.R` was touched once, in a repo-wide header cleanup, not through use.
3. **The docs already say so.** The README's Step 4 provenance note: every loop-close in the study was done by hand in CloudCompare, and the scripts "have not been exercised as the production path on a full dataset."

Loop-closing as an *activity* was real. How it was actually done is in [`../Step01_PrepareTree/README.md`](../Step01_PrepareTree/README.md) and [`../Step03_CleanSection/README.md`](../Step03_CleanSection/README.md).

The scripts cannot cut the flap — that is manual — so at most they replace the register-and-merge part. If anyone ever does try them, sanity-check the merge visually in CloudCompare, and expect `loopclose.R` to be weaker than `loopclose.py`.

## `disc_dbh_template.R` — the example this workflow was built to replace

A 40-line ITSMe example — `read_tree_pc()` → `diameter_slice_pc(slice_height = 1.30, ...)` — that was the starting guide for this project. **The code is not wrong.** `diameter_slice_pc` slices on Z because that is ITSMe's convention, and that is correct for a Z-up cloud.

ForestScanner clouds are **Y-up**. Fed one, this script slices a vertical slab down the trunk instead of a horizontal ring — and returns a plausible-looking diameter rather than an error. A full first batch of measurements was made this way and had to be voided. Every other script in this repo defaults to or demands `--up-axis y` because of it, and `dab_itsme.R` exists to call the same ITSMe function with the axis swap done first.

It is kept because that mistake is part of the documented method history and the clearest demonstration of why the workflow is shaped the way it is. It still runs, has a hardcoded `z_value <- 1.30` and no axis handling, and will give someone with Y-up data a wrong number that looks right. Do not use it to measure anything.
