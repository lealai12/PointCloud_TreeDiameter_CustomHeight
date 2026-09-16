# Step 08 — Measure

**Tool:** Python **and** R, both, independently. Nine scripts in this folder.

| | |
|---|---|
| **Takes** | `Working\Polished_Slices_ply\<tag>__<Site>.ply` from Step 07 |
| **Makes** | the diameter columns in the measurements sheet; per-slice viz bundles (`Working\Claude_outputs\Polished_Slices_viz\`); result CSVs (`Working\Mean_Polygons\`) |
| **Feeds** | Step 09 — analysis |

## This step is never skipped

Even when the raw band at Step 05 looked clean. Two reasons: Step 05's number is a ceiling, not the estimate (see [`../Step05_CutSlice/README.md`](../Step05_CutSlice/README.md)); and this step produces **five** estimate families where Step 05 gives one.

## The five estimates

| Estimate | Script(s) | Sheet column | Method |
|---|---|---|---|
| Python hull tape | `measure_slice.py` (R twin: `measure_slice.R`) | `<Site>_pythonScript_Diameter_mm` | Least-squares circle **plus** convex-hull perimeter ÷ π. The hull is the headline; the circle is a cross-check. |
| R functional (concave) | `dab_itsme.R` | `<Site>_RScript_Diameter_mm` | ITSMe's median-radius circle + **concave** hull "functional" diameter — dips into grooves, unlike a convex hull. A different method, not a port. R-only: ITSMe has no Python equivalent. |
| True hull baseline | `dendro_tape.R` / `.py` | `<Site>_DendroTape_RScript_Diameter_mm` | Raw-point convex-hull perimeter only, no circle fit — the plain taut-tape baseline the median-polygon methods are compared against. |
| Median polygon, 2° | `median_polygon_2deg.py` / `.R` | `<Site>_MedianPolygon_{pythonScript,RScript}_Diameter_mm` | Convex hull of a median-radius polygon binned every 2° — robust to a single stray point the way a raw hull isn't. Bin width scales with trunk size. |
| Median polygon, 10 mm | `median_polygon_10mm.py` / `.R` | `Dendrometer_MedianPolygon10mm_{pythonScript,RScript}_Diameter_mm` (Dendrometer site only in this project) | Same idea, fixed ~10 mm arc-length bins — bin width does not scale with trunk size. |

The sheet's `<Site>_ForestScanner_Diameter_mm` is a sixth column, the app's own in-field reading; no cloud step produces it.

Neither median-polygon variant supersedes the other. On this project's validated subset they scored virtually identically, 2° marginally ahead — a result specific to this dataset, not a general ranking. Run both on your own data.

## Commands

All run from the repo root (the R scripts `source("scripts/sheet_batch.R")` relative to the working directory). Clouds are Y-up → `--up-axis y`, always.

One slice, one script:

```bash
python  scripts/Step08_Measure/measure_slice.py <slice.ply> --tree-id <tag>__<Site> --up-axis y --out <csv>
Rscript scripts/Step08_Measure/measure_slice.R  <slice.ply> --tree-id <tag>__<Site> --up-axis y --out <csv>
```

Every slice in a folder, every script (how this project's numbers were produced):

```bash
python  scripts/Step08_Measure/measure_slice.py       <folder> --batch --up-axis y --out <csv>
Rscript scripts/Step08_Measure/measure_slice.R        <folder> --batch --up-axis y --out <csv>
Rscript scripts/Step08_Measure/dab_itsme.R            <folder> --batch --up-axis y --out <csv>
python  scripts/Step08_Measure/dendro_tape.py         <folder> --batch --up-axis y --out <csv>
Rscript scripts/Step08_Measure/dendro_tape.R          <folder> --batch --up-axis y --out <csv>
python  scripts/Step08_Measure/median_polygon_2deg.py <folder> --batch --up-axis y --out <csv>
Rscript scripts/Step08_Measure/median_polygon_2deg.R  <folder> --batch --up-axis y --out <csv>
python  scripts/Step08_Measure/median_polygon_10mm.py <folder> --batch --up-axis y --out <csv>
Rscript scripts/Step08_Measure/median_polygon_10mm.R  <folder> --batch --up-axis y --out <csv>
```

Every row of the sheet, written straight back into the sheet's output column (each script's CONFIG block names the sheet, the folder, the filename pattern and the column):

```bash
python  scripts/Step08_Measure/measure_slice.py --from-sheet --up-axis y
# ... and likewise for each of the others
```

`measure_slice.*` write the sheet in **whole millimetres**, matching the precision of the field readings the column is compared against; their CSV output keeps full precision. `measure_slice.*` and `dendro_tape.py` deliberately write the **same** sheet column (both are the convex-hull tape reading) — whichever ran last is what the sheet holds.

## Cross-checks worth knowing

- Python and R twins should agree **exactly** on the hull metrics — a convex hull is deterministic. Any difference is a bug, not a method difference. On this project's 32 sites every twin pair agreed to 0.000 mm.
- The `low_confidence` flag (coverage < 270° or circle RMS > 20 mm) fires routinely on big, rough, buttressed boles that are fine, and won't necessarily catch a real problem on a large tree. Read the numbers, don't trust the flag alone.
- A partial ring (< ~270° coverage) invalidates the hull entirely — a tape can't measure an open arc. The scripts refuse to write a hull diameter for those.

## Kept as the record

`scripts/fit_dab.py` and `scripts/fit_dab.R` at the `scripts/` root are the originals `measure_slice.*` and `cut_slice.*` were copied from. They are untouched, still run, and are what produced this project's published numbers.

## This project's run

- **32 of 32** tree-sites measured by every script.
