# Point-Cloud Tree Diameter at Custom Height

A feasibility study: can **mobile-LiDAR point clouds** (iPhone / [ForestScanner](https://apps.apple.com/app/forestscanner/id1547643372)) be used to monitor tree diameter at an operator-chosen, non-standard height — e.g. **Diameter Above Buttress (DAB)** on heavily buttressed tropical trees — as a lower-effort alternative to manual tape sampling, which is extremely time- and labor-intensive when the trunk can't be tape-measured at the standard reference height?

Bring your own scanned trees. A subset carrying **dendrometers** and/or **tape DBH/DAB** readings lets you validate against ground truth. Each tree's cross-section is measured **two independent ways** (Python and R) and compared against the field data. The deliverable is an assessment of **when the point-cloud method agrees with tape, and when it fails**.

---

## How it works

From a trunk cross-section we recover geometry a few independent ways per site:

- **`fit_dab.py` / `fit_dab.R`** — least-squares circle **+ convex-hull "tape"** (the hull wraps the outside and bridges flutes, like a physical tape). Independent Python/R implementations of the same method, cross-checked against each other.
- **R (`dab_itsme.R`)** — the [**ITSMe**](https://github.com/lmterryn/ITSMe) package: circle fit **+ concave-hull "functional" diameter**. A different method, R-only (no Python equivalent — it's specifically an ITSMe-package feature).

The recorded metric is the **tape-equivalent diameter**; the pipelines are kept independent and compared against tape/dendrometer to see which tracks the field data best.

A purpose-built pair, `dendro_tape.py`/`dendro_tape.R`, computes *only* the raw-point convex-hull tape (no circle, no concave hull) as the most physically literal tape mimic. A third pair, `median_polygon.py`/`median_polygon.R`, computes the convex hull of a **median-radius-binned** surface polygon instead — a denoised alternative meant to be robust to the single-stray-point problem a raw convex hull has; it roughly halves the field-accuracy error of the raw-point hull. It's a comparison tool, not a replacement: `compare_hull_methods.R` checks it against `dendro_tape.*` both vs. field reading and directly against each other, alongside (not instead of) the main field-accuracy comparison in `validate_field_accuracy.R`.

`median_polygon.*` bins the slice ring before taking the median radius per bin, and comes in **two standalone variants** that are both kept in the repo rather than one replacing the other: `median_polygon.py`/`.R` (no suffix) bins by a fixed **10mm arc length**, `median_polygon_2deg.py`/`.R` bins by the original fixed **2° angle**. Which one performs better can depend on the size range of what you're measuring (a fixed-degree bin covers a very different amount of surface on a small object vs. a large one) — the plain name deliberately stays on the arc-length variant because its bin width stays predictable across a wide size range, but both are kept available to test against your own data.

### Key conventions

- **⚠️ Clouds are Y-up.** ForestScanner (ARKit) exports have the **trunk axis along Y, not Z**. Cross-sections are circular only in the **X–Z plane** (slice at constant **Y**). **Always pass `--up-axis y`.** Slicing along Z cuts a vertical slab down the trunk and produces a two-band scatter, not a ring.
- **Operator-chosen height.** The measurement height is a picked point on the section, recorded per location. A tree may be measured at multiple sites — **TopFlag**, **LowerFlag**, and/or **Dendrometer** — each in its own column.
- **Units.** Point-cloud coordinates & heights are in **metres**; recorded **diameters are in millimetres** (`_mm` columns) to match the dendrometer data.
- **Only the dendrometer site has field ground truth** (the `Dendrometer_Reading`, in mm). Flag sites are cloud-only points for a height profile.

---

## Repository layout

```
PointCloud_TreeDiameter_CustomHeight/
├── scripts/
│   ├── fit_dab.py / fit_dab.R   # circle + convex-hull tape, flags, --up-axis, --viz-dir (independent Python/R twins, same method)
│   ├── dab_itsme.R         # R/ITSMe second estimate: circle + concave functional diameter
│   ├── dendro_tape.py / dendro_tape.R       # raw-point convex-hull tape mimic, no circle/concave hull
│   ├── median_polygon.py / median_polygon.R # convex hull of a median-binned surface polygon, fixed ~10mm arc-length bin (denoised alternative to dendro_tape)
│   ├── median_polygon_2deg.py / median_polygon_2deg.R # same method, fixed 2-degree angular bin — the original variant, kept standalone alongside the arc-length one
│   ├── loopclose.py / loopclose.R   # loop-close / merge for fragmented scans (R port is a documented best-effort fallback — no RANSAC/FPFH coarse step, see its header)
│   ├── validate_field_accuracy.R  # field accuracy: methods vs. field reading
│   ├── compare_hull_methods.R     # hull method comparison: true hull vs. median hull (both bin variants), vs. reading and vs. each other; Python-only output (R is still computed and cross-checked, not duplicated in results)
│   └── requirements.txt    # Python deps (+ requirements.lock.txt)
├── field_data/             # field_measurements.csv (picks/field record); private .xlsx lives outside the repo
├── results/                # result CSVs + plots (point clouds are never committed)
├── raw_ply/ cleaned/ stitched/ slices/   # local cloud working dirs (contents gitignored)
├── DAB_Workflow_Protocol_v0.1.md         # full protocol
├── DAB_per_tree_checklist.md             # per-tree walkthrough
├── Tree_notes.md           # per-tree issue → solution log (for the methods write-up)
└── Python_glossary.md      # Python constructs used by the scripts
```

**The point-cloud data is not in this repo.** Clouds are large and irreplaceable, so all cloud formats (`.ply`, `.las`, `.bin`, …) are gitignored and kept in your own working directory outside the repo. The private working workbook lives outside version control and uses internal code numbers rather than any original identifiers; a separate tag-mapping workbook (real identifier <-> code) stays local only, never committed. The pipeline is: raw scanner PLY → cleaned & segmented discs in CloudCompare (saved as `.bin`) → exported to `.ply` for the fitters.

---

## Setup

### Python
```bash
python -m venv TreeDiameter_Environment
# Windows: TreeDiameter_Environment\Scripts\activate
pip install -r scripts/requirements.txt      # numpy scipy pandas matplotlib plyfile open3d openpyxl
```

### R (4.6.x)
```bash
Rscript scripts/requirements.R   # readxl, dplyr, tidyr, ggplot2, scales, Rvcg, lidR, ITSMe
```
Gotcha `requirements.R` handles for you: `lidR` is currently archived on CRAN, so it has to come from the maintainer's R-universe binary *before* `ITSMe` installs, or the `ITSMe` build fails.

### CloudCompare
Used for interactive cleaning/segmentation and for `.bin → .ply` export. The fitters cannot read CloudCompare `.bin`; convert first (headless):
```bash
CloudCompare -SILENT -AUTO_SAVE OFF -O <disc.bin> -C_EXPORT_FMT PLY -SAVE_CLOUDS FILE <disc.ply>
```

---

## Usage

Measure one disc at a picked height `Y` (metres), 6 cm band, both tools:

```bash
# Python — convex-hull tape + circle, plus a CloudCompare-viewable viz bundle
python scripts/fit_dab.py <disc.ply> --tree-id <id> --up-axis y \
    --slice-height <Y> --slice-thickness 0.06 --viz-dir <out_dir>

# R — ITSMe circle + concave functional diameter, same band
Rscript scripts/dab_itsme.R <disc.ply> --tree-id <id> --up-axis y \
    --height-z <Y> --thickness 0.06 --out results/dab_itsme_results.csv
```

If the disc is already a thin cross-section, omit `--slice-height` / `--height-z` band args and fit it whole. For leaning stems, `fit_dab.py --axis-ply <tall_segment.ply>` estimates and corrects the stem axis (never PCA a thin slice for this).

### Batch mode: `--from-sheet` (reusing this for your own dataset)

All seven measurement scripts (`fit_dab.py`/`.R`, `dab_itsme.R`, `dendro_tape.py`/`.R`, `median_polygon.py`/`.R`, `median_polygon_2deg.py`/`.R`) can loop over every tree in a spreadsheet instead of one manual invocation per tree:

```bash
python scripts/fit_dab.py --from-sheet --up-axis y
Rscript scripts/dab_itsme.R --from-sheet --up-axis y
```

Each script has a `CONFIG` block at the very top (sheet path, tree-ID/height/output-column names, `.ply` folder + filename pattern) — **that's the one place a future researcher with different column names or folder layout needs to edit**, not the measurement code. `--from-sheet` reads tree ID (and, where configured, a picked height) per row, measures each tree with the exact same code the manual CLI path uses, and writes each result both to `--out` (as usual) and back into the sheet's configured output column. Single-file/`--batch` usage above is unaffected — this is a separate, additive mode.

R's write-back prefers shelling out to `python`/`python3` (override via the `SHEET_BATCH_PYTHON` env var) rather than writing the `.xlsx` directly — see `scripts/sheet_batch.R`'s header comment for why (a real corruption bug in the `openxlsx` package was found and worked around during testing). If no Python interpreter is on PATH, it automatically falls back to a direct-R write path (`scripts/xlsx_repair.R`) that patches the same corruption after saving — this keeps the whole workflow usable from a Python-free RStudio install, at the cost of being the less-exercised of the two paths.

Once every tree is measured and results are anonymized into `field_data/field_measurements_Anon.xlsx`, run the repo-side analysis:

```bash
Rscript scripts/validate_field_accuracy.R    # core feasibility result -> results/field_accuracy_*
Rscript scripts/compare_hull_methods.R       # true hull vs. median hull, both bin widths -> results/hull_comparison_*
```

### Outputs
- **Your working workbook** (e.g. `field_measurements_Anon.xlsx`, outside the repo) — Python & R tape diameters (mm) per location, low-confidence `Flags`, alongside the field `Dendrometer_Reading`. Uses internal code numbers rather than original identifiers.
- **Per-disc viz bundle** (`--viz-dir`): `*_slice.ply` (the measured band), `*_ring_*.ply` (fitted circle), `*_hull_*.ply` (tape wrap), `*_slice_fit.png`, `*_measure.txt`.
- **`results/*.csv` + `results/plots/*.png`** — the committed, anonymization-safe analysis output: field accuracy vs. dendrometer reading, and the hull-method comparison, both size-stratified.

---

## What the analysis scripts tell you

- `validate_field_accuracy.R` — per-method accuracy (MAPE, bias, RMSE) against field tape/dendrometer readings, stratified by whether the site had a real dendrometer band (standard-height stem) or was measured above a buttress (non-standard height). Writes `results/field_accuracy_*`.
- `compare_hull_methods.R` — compares the raw convex-hull "tape" against the denoised median-polygon hull (`median_polygon.*`), both against each other and against field reading. In our own testing this denoising step roughly halved field-accuracy error on most validated trees, with one unresolved outlier — expect your own dataset's numbers to differ. Writes `results/hull_comparison_*`.

Both are anonymized-sheet-only and expect the `--from-sheet` workflow above to have populated the manifest first.

## Gotchas (don't repeat)

- **Y-up**: always `--up-axis y`. A correct slice is a full ~360° ring; two side-bands means the wrong axis.
- **Convex hull is not outlier-robust** — a single stray point inflates the tape. Clean slices before fitting; `median_polygon.*` is a scripted fix for this specific problem.
- **SOR conservatively** — over-denoising erodes the trunk surface and biases diameter down.
- **Partial rings** (< ~270° coverage) give unreliable fits and are flagged.
- **The low-confidence RMS flag is miscalibrated for large, rough trunks** — it fires routinely on big buttressed boles that are fine, and doesn't catch every real outlier. Don't treat it as a reliable data-quality signal on large trees without also checking the numbers.
