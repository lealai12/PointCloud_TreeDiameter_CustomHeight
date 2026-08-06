# DAB per-tree processing checklist

The reusable walkthrough we run **one tree at a time** in CloudCompare. Each session, this gets instantiated as the task list; conditional steps are skipped when they don't apply. Record data into `field_data/field_measurements.csv` as you go (relevant columns in brackets). Full detail for any step is in `DAB_Workflow_Protocol_v0.1.md`.

## 0. Triage & import
- Open the tree's PLY(s) in CloudCompare; accept the global shift (reuse the same shift across a tree's multiple scans).
- Assess and record flags: `cloud_quality` (clean/messy), `Number_scans`, `needs_fuse` (multiple clouds to merge?), `needs_loopclose` (circumferential wrap didn't close?), `has_dendrometer` (also implies site type: over dendrometer vs above buttress).
- **Scale check:** measure the distance between the **two pole flags** (known = **1.000 m**, independent of the ground); record `scale_check_m`; flag if off by more than ~1–2%. If ground isn't identifiable, use the **lower flag** as the height datum for `Measure_Height`.

## 1. Clean — *always*
- Segment out non-trunk points (ground, understory, neighboring stems); a few passes from different angles.
- Conservative SOR (start k=6, σ=1.0; loosen if it erodes the trunk surface — that biases diameter low).
- Save → `cleaned/<Tree_Tag>.ply`.  [`status = cleaned`]

## 2. Fuse — *only if `needs_fuse`*
- Light-clean each piece → **Align (point pairs)** → **ICP** (check RMS) → `Edit > Merge` → re-SOR.
- Re-check pole scale. Save → `stitched/<Tree_Tag>.ply`.  [`status = fused`]

## 3. Close loop — *only if `needs_loopclose`*
- Top view; locate the seam and confirm overlap → cut the overlap flap → register (point pairs + ICP) → merge → subsample to dedupe.
- Re-check pole scale.  [`status = looped`]
- If the seam won't close without a kink, drift is distributed → flag the tree / consider re-scan.

## 4. Select site & cut slice — *always*
- Pick the site: **over the dendrometer** (color by RGB, find the band, cut just above/below the hardware) **or above the buttress** (judgment call on a round-bole height).
- Record `Measure_Height` (and `has_dendrometer` captures which site type).
- **Manually cut a ~2–5 cm band** (Segment tool or Cross Section box). Orient perpendicular to the stem axis if the stem leans.
- Inspect from directly above: want a closed ring. Note occlusion gaps (one-sided rings are low-confidence).
- Export → `slices/<Tree_Tag>_slice.ply`.

## 5. Clean slice ring — *always*
- Re-open/inspect `slices/<Tree_Tag>_slice.ply` and manually remove non-trunk or obvious outlier points left in the band.
- Re-check top view for a clean, closed ring and preserve real stem geometry (avoid over-trimming concavities).
- Save (overwrite) → `slices/<Tree_Tag>_slice.ply`.

## 6. Fit circumference — *always*
- `python scripts/fit_dab.py slices/<Tree_Tag>_slice.ply --tree-id <Tree_Tag> --dab-height <h>`  (add `--axis-ply <tall_segment.ply>` if leaning).
- Record circumference, equivalent diameter (C/π), hull circumference, circle RMS, coverage, low_confidence → `results/dab_results.csv`.  [`status = measured`]

## 7. Validate — *only if field data exists*
- Compare point-cloud circumference/diameter to `field_dab_cm` / `field_dbh_cm` at the same height, or to the dendrometer girth. Record the residual.  [`status = validated`]

## 8. Close out
- Update `field_measurements.csv`: `status`, done-flags, and `notes` on any issues or low-confidence results.
- Log any noteworthy issue + the solution used in `Tree_notes.md` (qualitative log for the methods / limitations write-up).

---
*One tree at a time, for quality control. The CSV is the durable per-tree record; a new chat session re-orients from `CLAUDE.md` + this checklist + the CSV.*
