# Handoff for Claude Code: pre-step-7 cleanup

Written 2026-09-24 (Panama time) for DJ to hand to Claude Code.
Repo: `C:\Users\leala\OneDrive\Documents\GitHub\PointCloud_TreeDiameter_CustomHeight`
Working data: `C:\Projects\LiDAR_Project\Working_Steps\`

**Scope.** This job covers steps 1 to 6 only. The step 7 problems are known and are a separate job, so don't touch `scripts/Step07_Analysis/` or its README.

## State when this was written

- HEAD is `ec98738` ("Make missing bins flag instead of stop processing in analyses", 2026-09-24 13:06).
- Three tracked files have edits that DJ hasn't committed: `README.md` (13:30), `Python_glossary.md` (13:31) and `scripts/Unused/README.md` (13:31). The repo `CLAUDE.md` was also edited at 13:31, but it is gitignored. **Don't touch these edits, and don't stage them.**
- On the working sheet, every site with a height has its step 4 value, all six step 6 diameters and the `MaxEdgeFrac` flags. The one exception is `XXXX`, which is excluded on purpose. The Python and R twins agree on all 123 pairs.
- `DabItsme_ConcaveHull_RScript_Diameter_mm` is empty at all four sites, which is what task 1 is for.

Before starting, run `git status` and `git log --oneline -3` and confirm the repo matches the state above. If it doesn't, stop and ask DJ.

## Rules for this job

- **Ask, don't decide.** If anything here is unclear or doesn't match the repo, stop and ask DJ.
- **Check each file before you edit it.** Before touching a file, report:
  - its modified time;
  - its word count;
  - a quoted line or two that confirm it is the current version.
- **Report every edit.** After each edit, show the diff against the original and list every difference.
- **Make surgical edits only.** Replace the stale text and nothing else, and don't rephrase anything around it. Don't add semicolons or em-dashes; DJ deliberately removes them.
- **Don't touch the measurement code.** That means any function that computes a diameter, a hull, a coverage value or a validity flag. Don't edit `fit_dab.py` or `fit_dab.R` at all.
- **Don't edit the working sheet,** and don't run anything with `--from-sheet`. DJ runs the sheet write-back himself.
- **Don't read the field-diameter columns.** The run is blind. That means `Dendrometer_FieldDiameter` and `PaintMarker_FieldDiameter_mm`.
- **Don't write to `C:\Projects\LiDAR_Project\Working\`.** It is the frozen first pass.
- **Don't commit and don't push.** DJ does both. End by reporting `git status` and a suggested commit message.

---

## TASK 1: Point `dab_itsme_concave_hull.R` at the second-pass data

**What it means:** ITSMe is the only step 6 script still set up for the first pass. It should read the same polished slices and the same working sheet as the other step 6 scripts.

**Why this works without touching the measurement code:** the script always cuts its own band at the sheet height, with a default thickness of 0.06 m. The polished slices were cut by `cut_slice` at that same height with the same 0.06 m band, so ITSMe's band contains the whole polished slice. All the methods then measure the same points.

Edit only the CONFIG block of `scripts/Step06_Measure/dab_itsme_concave_hull.R`:

| Key | Now | Change to |
|---|---|---|
| `SHEET_PATH` | `"C:/Projects/LiDAR_Project/field_measurements_Anon.xlsx"` | `"C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx"` |
| `PLY_FOLDER` | `"C:/Projects/LiDAR_Project/Working/Final_Disc_ply"` | `"C:/Projects/LiDAR_Project/Working_Steps/5_PolishedSlices"` |
| `PLY_FILENAME_PATTERN` | `"{tree_id}.ply"` | `"{tree_id}__{site}.ply"` |

- Leave `HEIGHT_COL`, `OUTPUT_COL` and `SITE_LABEL` as they are (Dendrometer). They are changed per site at run time, like the other step 6 scripts.
- Update the comments on those three lines so they describe the new values. Match the wording the other step 6 scripts use for the same keys.
- Update the header comment block (lines ~11–21) only where it says the input must be a tall trunk section and not a pre-cut ring. That is no longer true in sheet mode. Show DJ the proposed wording before writing it.

**Verify on the command line, not with `--from-sheet`.** Write output to `C:\Projects\LiDAR_Project\scratch_verify_2026-09-24\itsme\`.

1. Read `Y_value_<Site>` from the sheet for these slices. Read that column only.
   - `3031__Dendrometer`
   - `5926__LowerFlag`
   - `2033__TopFlag`
   - `1993__PaintMarker`
2. **Coordinate check (do this first).** For each slice, confirm that the sheet height lies inside the slice file's Y range, and that the range is about 0.06 m wide.
   - If any file fails this, stop and report. It would mean CloudCompare shifted the coordinates when the polished slice was saved.
3. Run the script on each slice:
   ```
   Rscript scripts/Step06_Measure/dab_itsme_concave_hull.R <5_PolishedSlices\tag__Site.ply> --tree-id <tag>__<Site> --up-axis y --height-z <Y_value> --thickness 0.06 --out <scratch>\itsme_check.csv
   ```
4. Check two things.
   - The script's point count should equal the slice file's point count. If it doesn't, ITSMe's band is dropping points: report it and don't adjust anything.
   - Compare `itsme_func_diameter_cm` with `bin_*`/`dendro_tape` for the same slice. A concave hull should come out at or below the convex-hull (`dendro_tape`) number. Report the numbers side by side, and don't compare any of them with field data.
5. `Rscript -e 'invisible(parse("scripts/Step06_Measure/dab_itsme_concave_hull.R"))'` passes.

**Flag it for DJ, don't change it:** ITSMe writes to the sheet rounded to 0.1 mm (`round(x * 10, 1)`), but every other step 6 script writes whole millimetres.

**Done when:** CONFIG points at `5_PolishedSlices` and the working sheet, all four slices pass the checks above, and DJ has seen the numbers. DJ then runs `--from-sheet` for each of the four sites himself.

## TASK 2: Document the three-decimal `MaxEdgeFrac` (no code change)

**What it means:** step 6 writes `MaxEdgeFrac` to the sheet rounded to 3 decimals, and DJ is keeping it that way. The scripts decide validity on the unrounded value. So a ring that failed the gap check can read exactly `0.500` in the sheet.
- Two rings do this on the current sheet: `TopFlag BinFixedAngle` and `LowerFlag DendroTape`.
- In the step 6 output files these are `4524__TopFlag` and `6647__LowerFlag`.

DJ will choose the threshold rule at step 7. For now, write it down so nobody assumes `> 0.5` is safe.

Add one sentence to each of these:

1. The repo `CLAUDE.md`, at the end of the Gotchas bullet that starts `**The gap check FLAGS, it does not block (since 2026-09-24).**`. Suggested sentence:
   > The sheet value is rounded to 3 decimals, and the scripts decide on the unrounded value, so a flagged ring can read exactly 0.500 in the sheet (two do on the second pass). A `> 0.5` filter would keep them.
2. `scripts/Step06_Measure/README.md`, in the corrected flag wording from task 3. Use the same sentence.

Don't edit the project `README.md` for this; it is DJ's rewrite from today. Instead, point out the matching place in it (the section "The gap check flags — it does not block") so he can add the sentence himself.

## TASK 3: Correct the stale step READMEs (steps 1 to 6)

**What it means:** fix only what the seven-step reorganization and today's flag change made wrong. That means step numbers, folder paths, file names, script names, sheet column names and the flag behaviour. Keep DJ's structure and wording everywhere else. Keep the "This project's run" first-pass numbers, since they are the record.

Use the repo `CLAUDE.md` as the source of truth. Show DJ each file's diff before moving to the next one.

- **`Step01_PrepareTree/README.md`, `Step02_CutSection/README.md`, `Step03_CleanSection/README.md`:** these already match the new chain as far as checked, so expect no changes. Confirm, and report anything you find instead of editing it.

- **`Step04_CutSlices/README.md`:** the whole file still describes the deleted `.bin` → `.ply` export step. It has to describe step 4, cutting the slice. Draft a replacement in the same style as the other step READMEs (H1, Takes/Makes/Feeds table, short "what happens", commands), using:
  - **Takes:** `Working_Steps\3_CleanedSegments_Final\<tag>_CleanedSegment.ply`, plus the `Y_value_<Site>` heights in the sheet.
  - **Makes:** `Working_Steps\4_CutSlices\<tag>__<Site>\`, holding `<tag>__<Site>_slice.ply`, `_slice_fit.png`, `_ring_*.ply`, `_hull_*.ply` and `_measure.txt`. It also makes `cut_slices_python.csv` and the `<Site>_CutSlice_pythonScript_Diameter_mm` column.
  - **Feeds:** Step 05, polishing the slice.
  - **Commands:** the two `--from-sheet` lines and the single-slice line from `CLAUDE.md` step 4.
  - **The key point:** the diameter step 4 writes is a **ceiling** (raw band with stray points still in), not the result.
  - Keep the CloudCompare CLI command and the `-AUTO_SAVE OFF` warning as a short note at the bottom, labelled as only needed for converting a legacy `.bin`. The 2026-09-18 spec asked for that command to be kept somewhere.
  - Keep the first-pass line ("19 of 19 sections exported") under "This project's run", marked as first pass.
  - **Show DJ the full draft before writing it,** since this one is a replacement and not a line fix.

- **`Step05_PolishSlice/README.md`:**
  - Change the H1 `# Step 06 — Polish the slice ring` to `# Step 05 — Polish the slice ring`.
  - **Takes:** change `the raw band from Step 05 (\`Cut_Slices_to_polish\<tag>__<Site>\<tag>__<Site>_slice.ply\`)` to the raw band from Step 04 (`Working_Steps\4_CutSlices\<tag>__<Site>\<tag>__<Site>_slice.ply`).
  - **Makes:** change `Working\Polished_Slices\<tag>_<Site>_slice.bin` to `Working_Steps\5_PolishedSlices\<tag>__<Site>.ply`.
  - **Feeds:** change `Step 07 — export to .ply` to Step 06, measure.
  - Change `(along Z axis for most clouds, y axis if scanned by CloudCompare)` to `(along Z axis for most clouds, y axis if collected from ForestScanner)`, which is the Step03 wording.
  - Change `Save as \`.bin\`.` to say: save as `.ply`, named `<tag>__<Site>.ply` (double underscore, no CloudCompare suffix), because step 6 finds its input by exactly that name.

- **`Step06_Measure/README.md`:** almost every reference in this file is first-pass. Correct each of these in place, keeping the section order.
  - **H1:** `Step 08` becomes `Step 06`.
  - **Script count:** "Nine scripts" becomes the actual count of script files in the folder.
  - **Table:**
    - Takes becomes `Working_Steps\5_PolishedSlices\<tag>__<Site>.ply` from Step 05.
    - Makes becomes the sheet diameter and `MaxEdgeFrac` columns plus the output CSVs and viz folders in `Working_Steps\6_Measure\`.
    - Feeds becomes Step 07.
  - **Estimates table:** remove the `measure_slice` row (retired, now in `Unused/`), and use the current names and columns:
    - `dab_itsme_concave_hull.R` writes `<Site>_DabItsme_ConcaveHull_RScript_Diameter_mm`;
    - `dendro_tape` writes `<Site>_DendroTape_{pythonScript,RScript}_Diameter_mm`;
    - `bin_fixed_angle` writes `<Site>_BinFixedAngle_{pythonScript,RScript}_Diameter_mm`;
    - `bin_mean_distance_radius` writes `<Site>_BinMeanDistanceRadius_{pythonScript,RScript}_Diameter_mm`, at every site and not just Dendrometer.
  - **Wedge statistic:** it is the 90th percentile (`PERCENTILE`), not the median.
  - **Cross-reference link:** `../Step05_CutSlice/README.md` becomes `../Step04_CutSlices/README.md`. "Step 05's number is a ceiling" becomes Step 04.
  - **Commands:** `Step08_Measure` becomes `Step06_Measure`, with the current script names. Drop `measure_slice`. Take them from `CLAUDE.md` step 6.
  - **Last write wins:** delete the sentence saying `measure_slice.*` and `dendro_tape.py` write the same column. Each script now has its own column.
  - **Partial rings:** "The scripts refuse to write a hull diameter for those" becomes the current behaviour. The diameter is always written, `max_edge_frac` goes to `<Site>_<Method>_MaxEdgeFrac`, and a flagged ring is checked by looking at its picture. Add the task 2 sentence here.
  - **"Kept as the record":** keep this section, and change "`measure_slice.*` and `cut_slice.*` were copied from" to say that `measure_slice.*` now lives in `Unused/`.

List the Step07 README's stale lines for DJ, but don't edit them. That is the step 7 job.

## TASK 4: Outer `CLAUDE.md` (`C:\Projects\LiDAR_Project\CLAUDE.md`)

This file is outside the repo. DJ has approved editing these two lines only.

- **Line 74:** in the `dendro_tape` table row, replace
  > Refuses to write a ring whose longest hull edge spans more than half the diameter (a gap the tape would chord across).

  with wording that says the diameter is always written and the longest-edge fraction goes to `<Site>_DendroTape_MaxEdgeFrac` as a flag, with more than 0.5 (the tape chording across a gap) marked in the picture as PARTIAL RING.
- **Line 92:** replace
  > A ring failing either is **not written to the sheet**.

  with: since 2026-09-24 a failing ring is still written, and `MaxEdgeFrac` records the gap check. Also add that both `bin_*` scripts carry the same guard, since the line currently says "both in `dendro_tape`".

Take the modified time and word count before editing (see Rules) and show the diff after.

## TASK 5: Repo `CLAUDE.md`, line 144

The line says the working spreadsheet is ignored by the pattern `field_measurements_*working*.xlsx`. `.gitignore` actually lists only `field_measurements_working.xlsx`. The current sheet, `field_measurements_Draft2_Working.xlsx`, is safe only because it lives outside the repo, in `Working_Steps\`.

Replace
> `field_measurements_*working*.xlsx`

with the actual pattern `field_measurements_working.xlsx`, and add a few words saying the working sheet is kept outside the repo. **Don't edit `.gitignore`.** Ask DJ if you think it should change.

## TASK 6: Hand back

- Report `git status` in full. The expected changes are:
  - `dab_itsme_concave_hull.R`;
  - the Step04, Step05 and Step06 READMEs;
  - DJ's own three uncommitted docs from before, untouched.
  - The two `CLAUDE.md` files won't show up, because one is gitignored and the other is outside the repo.
- Suggested commit message for DJ:
  ```
  Point ITSMe at second-pass slices; correct step 4-6 READMEs

  - dab_itsme_concave_hull.R CONFIG: working sheet, 5_PolishedSlices,
    {tree_id}__{site}.ply
  - Step04 README now describes cutting the slice (export step is gone)
  - Step05/06 READMEs: seven-step numbers and paths, current script and
    column names, gap check flags instead of blocking, 3-decimal MaxEdgeFrac note
  ```
  No attribution line. Don't commit it.

## Not in this job (step 7, for later)

- The analysis scripts don't read `MaxEdgeFrac` yet, and the 0.500 threshold rule needs deciding.
- The analysis scripts default to `field_measurements_Anon.xlsx`. The second-pass sheet uses real tags, and there is no anonymized copy yet.
- "excl. tree 17" is hardcoded in `validate_field_accuracy.R`.
- The Step07 README is stale.
- PaintMarker isn't in the analysis loops.
