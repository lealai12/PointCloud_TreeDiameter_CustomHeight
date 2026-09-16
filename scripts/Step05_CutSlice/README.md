# Step 05 — Cut the slice

**Tool:** `cut_slice.py` (Python) or `cut_slice.R` (R) — independent twins, same method.

| | |
|---|---|
| **Takes** | `Working\Final_Disc_ply\<tag>.ply` from Step 04, plus the picked measurement height for each site |
| **Makes** | one raw band per tree-site: `Working\Claude_outputs\Cut_Slices_to_polish\<tag>__<Site>\` (slice cloud, fit PNG, circle/hull overlay PLYs, `measure.txt`) |
| **Feeds** | Step 06 — polish the ring |

## What happens here

This is where one tree becomes one or more **tree-sites**. Pick the height for each site by eye in CloudCompare — over a dendrometer band, or for a buttressed tree the lowest point where the trunk reads as roughly cylindrical — and read off its coordinate along the up-axis. **ForestScanner clouds are Y-up**, so that is a Y value; always pass `--up-axis y`. Record the same value in the sheet's `Y_value_<Site>` column.

The script cuts the band `[Y − t/2, Y + t/2]` (default `t = 0.06` m) out of the section and writes it to `--viz-dir` for polishing.

## The number it prints is a ceiling, not the estimate

The script keeps the full fit code so this step reports a diameter, but the band is **raw** — it still holds stray points outside the real bark. The convex-hull tape wraps around those too, so it reads high. Polishing deletes them, and a convex hull can only *shrink* when points are removed. So the hull reading here is an **upper bound** on the final answer; the polished value at Step 08 is always at or below it. (The circle-fit diameter has no such guarantee — it can move either way.) In this project polishing changed the hull reading on **28 of 32 sites**, median −38 mm, so treat this number as a sanity check only. By default nothing is written to the sheet from here (`OUTPUT_COL = None`).

## Commands

One section, one site (run from the repo root):

```bash
python  scripts/Step05_CutSlice/cut_slice.py <section.ply> --tree-id <tag>__<Site> --up-axis y \
        --slice-height <Y> --slice-thickness 0.06 --viz-dir <folder>
Rscript scripts/Step05_CutSlice/cut_slice.R  <section.ply> --tree-id <tag>__<Site> --up-axis y \
        --slice-height <Y> --slice-thickness 0.06 --viz-dir <folder>
```

Every tree in the sheet at once (heights read from `HEIGHT_COL` in the script's CONFIG block; set `SITE_LABEL`/`HEIGHT_COL` per site):

```bash
python  scripts/Step05_CutSlice/cut_slice.py --from-sheet --up-axis y --viz-dir <folder>
Rscript scripts/Step05_CutSlice/cut_slice.R  --from-sheet --up-axis y --viz-dir <folder>
```

`--slice-height` is required in single-file mode — cutting is this script's only job. A `.ply` you already cut belongs at Step 08, not here.

## This project's run

- **32 of 32** tree-sites cut. 19 trees → 32 sites: `Dendrometer`, `TopFlag`, `LowerFlag`, one to three per tree.
- Spot check that reproduces exactly: tree 3853, `--slice-height 3.181833` → `hull_circumference_cm: 445.97`, 189 510 points.
