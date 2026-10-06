# Point-Cloud Tree Diameter at Custom Height

Example tree is 2033

A feasibility study: can **mobile-LiDAR point clouds** (iPhone / [ForestScanner](https://apps.apple.com/app/forestscanner/id1547643372)) be used to monitor tree diameter at an operator-chosen, non-standard height — e.g. **Diameter Above Buttress (DAB)** on heavily buttressed tropical trees — as a lower-effort alternative to manual tape sampling, which is extremely time- and labor-intensive when the trunk can't be tape-measured at the standard reference height?

Bring your own scanned trees. A subset carrying **dendrometers** and/or **tape DBH/DAB** readings lets you validate against ground truth. Each tree's cross-section is measured **several independent ways, in both Python and R**, and compared against the field data. The deliverable is an assessment of **when the point-cloud method agrees with tape, and when it fails**.

> **What's in this repo, and what isn't.** This repo carries the **method and the code**: a workflow for measuring large, buttressed trees that other people can pick up and run, plus every measurement and comparison script behind it. `results/` holds this project's own second-pass analysis tables and figures, from Step 7. **The point clouds and the working spreadsheet are not included.** The write-up of the results is reported separately.

**New here?** Jump to the [**Full walkthrough**](#full-walkthrough-one-tree-start-to-finish) — every step from a raw `.ply` off the scanner to a validated diameter, in order.

---

## What we're actually measuring (read this first)

We are **not** measuring diameter directly. From a point cloud you can only recover the **cross-sectional geometry of the trunk** at a chosen height. The pipeline is:

1. Extract a thin horizontal **slice** of trunk points at the chosen height.
2. Fit a shape to that ring of points to recover **circumference** and an **equivalent diameter**.
3. Report both — because on an irregular, fluted or buttressed tropical trunk, "diameter" is a **modeled quantity, not a physical one**.

**Two diameter conventions:**

- **Equivalent-circle diameter**, `D = C / π`, where `C` is a measured circumference. This mirrors what a DBH tape physically does: it wraps the outside of the bark, bridges flutes, and back-computes a diameter from the circumference.
- **Best-fit-circle diameter** — a least-squares circle returns a radius directly. Identical to the above on a perfectly round stem. On an irregular one the circle passes through the middle of the bark's bumps rather than wrapping them, so it tends to read lower. Its RMS residual is also a useful measure of how round the ring is.

**Six methods are compared** — five from the cloud, and ForestScanner's own reading. Which one to report depends on what the reference instrument measures and on the results.

**Site selection is per-tree and operator-chosen** — over a dendrometer band, over a painted census mark, or at the height where the buttress flares merge into a roughly cylindrical bole. **The height you pick is a real data column, not a nuisance parameter**: record it every time.

---

## How it works

From a trunk cross-section we recover geometry several independent ways per site. Every method below exists in **both Python and R**, written separately, so the two can be compared as a correctness cross-check.

- **`dendro_tape.py` / `.R`** — the raw-point **convex-hull "tape"**: the hull wraps the outside of the ring and bridges flutes, exactly as a physical girth tape does. No circle fit, nothing else. This is the most physically literal tape mimic, and the baseline the others are compared against.
- **`dab_itsme_concave_hull.R` / `.py`** — the [**ITSMe**](https://github.com/lmterryn/ITSMe) method: median-radius circle fit **+ concave-hull "functional" diameter** (the diameter of a circle with the same *area* as the concave hull), which dips *into* grooves where a convex hull bridges them. A genuinely different method. The `.R` calls the ITSMe R package. ITSMe has no Python package, so the `.py` is a port of its `diameter_slice_pc()`, including the `concaveman` concave hull it uses. On this project's 41 slices the port matches the R run exactly on the circle fit and to within 0.1 mm on the concave-hull diameter.
- **`bin_fixed_angle.*` / `bin_mean_distance_radius.*`** — the **binned** hulls. Instead of hulling the raw points, the ring is divided into angular wedges, one radius is taken per wedge, and the hull is computed on that denoised polygon. This is the scripted fix for the convex hull's single-stray-point problem.
- **`circle_fit.py` / `.R`** — the least-squares (Kåsa) **circle fit**, the classic point-cloud stem diameter. The circle passes through the middle of the bark's bumps rather than wrapping them, so on fluted and buttressed trunks it tends to read below the hulls.

`compare_hull_methods.R` checks the binned hulls against `dendro_tape.*` both vs. field reading and directly against each other, alongside — not instead of — the main field-accuracy comparison in `validate_field_accuracy.R`, which compares every method.

### The binned methods: two knobs, both yours

**The per-wedge statistic is a percentile, and it defaults to the 90th — not the median.** A median cuts noticeably *inside* the bark surface, which is not what a tape reads. `PERCENTILE` and `MIN_POINTS_PER_BIN` (default 10) are CONFIG values with `--percentile` / `--min-points` overrides. A wedge holding fewer points than the minimum is treated as empty and **skipped**: the polygon runs in a straight line from the last counted wedge before the gap to the first one after it, as a tape bridges a crevice. The empty count is reported per slice as a QC signal. (Until 2026-09-30 empty wedges were filled by interpolating the radius. The change moved 6 of 41 slices by at most 1.1 mm, always down.) Setting `50` / `1` reproduces a plain per-wedge median exactly.

**The wedge width ships as two variants of one method — a deliberate choice offered to you, not a default and a runner-up.** `bin_fixed_angle.*` uses a fixed **angle** (default 2°); `bin_mean_distance_radius.*` derives the wedge count from the ring's mean radius so each wedge spans a fixed **arc length** (default ~10 mm). The difference is what a wedge physically covers: a fixed angle spans very different amounts of bark on a small stem than on a giant (2° ≈ 8 mm on a small stem, ≈ 33 mm on a 2 m bole), while a fixed arc length stays constant across sizes.

Neither is universally better, and **the right choice depends on your stand**. Forestry practice varies enormously between sites, size distributions and species, so both are kept as first-class options. Run both against your own data and pick on your own numbers.

### Key conventions

- **⚠️ Clouds are Y-up.** ForestScanner (ARKit) exports have the **trunk axis along Y, not Z**. Cross-sections are circular only in the **X–Z plane** (slice at constant **Y**). **Always pass `--up-axis y`.** Slicing along Z cuts a vertical slab down the trunk and produces a two-band scatter, not a ring.
- **Everything is `.ply`, end to end.** The scanner exports `.ply`, CloudCompare saves `.ply`, every script reads `.ply`. **Nothing converts anything** — there is no `.bin` → `.ply` export step in this workflow.
- **Operator-chosen height.** The measurement height is a picked point on the section, recorded per site. A tree may be measured at several sites: **TopFlag**, **LowerFlag**, **ForestGeoPaint**, **DendroPaint** and **Dendrometer**. Each site has its own set of columns.
- **Units.** Point-cloud coordinates & heights are in **metres**; recorded **diameters are in millimetres** (`_mm` columns) to match the dendrometer data.
- **Only sites with a field reading enter the accuracy comparison.** In this project that means the Dendrometer bands and the two paint marks. The flag sites are cloud-only points for a height profile.
- **There are two kinds of paint mark.** ForestGeoPaint is the red ForestGEO census mark. DendroPaint is the blue mark from the dendrometer program. The two programs measured separately, so each mark has its own field diameter and date, and Step 7 runs once for each. On some trees both marks are at the same height, so both use the same slice and only the field value differs.
- **Earlier versions had one PaintMarker site.** It mixed the two kinds of mark, so it was split into ForestGeoPaint and DendroPaint and is no longer used. Its old results are kept in `results/archive_paintmarker_2026-10-06/` as the record.

---

## Repository layout

```
PointCloud_TreeDiameter_CustomHeight/
├── scripts/                      # one folder per processing step, in order; each has its own README
│   ├── Step01_PrepareTree/       # (CloudCompare, manual) organize captures by tree — README only
│   ├── Step02_CutSection/        # (CloudCompare, manual) segment the trunk section — README only
│   ├── Step03_CleanSection/      # (CloudCompare, manual) loop-close, merge, SOR — README only
│   ├── Step04_CutSlices/         # cut_slice.py / cut_slice.R — cut the band at the picked height
│   ├── Step05_PolishSlice/       # (CloudCompare, manual) polish the slice ring — README only
│   ├── Step06_Measure/           # dendro_tape.py / .R, dab_itsme_concave_hull.R / .py,
│   │                             #   bin_fixed_angle.py / .R, bin_mean_distance_radius.py / .R,
│   │                             #   circle_fit.py / .R
│   ├── Step07_Analysis/          # validate_field_accuracy.R,
│   │                             #   compare_hull_methods.R, plot_error_by_size.R,
│   │                             #   bin_fixed_angle_demo.R, plot_by_method.R,
│   │                             #   compare_fig_notes.R, compare_field_record.R,
│   │                             #   compare_paint_sources.R (R-only by design)
│   ├── Unused/                   # retired + never-run scripts, kept as the record
│   ├── fit_dab.py / fit_dab.R    # the originals cut_slice.* was copied from — untouched
│   ├── sheet_batch.py / .R       # --from-sheet plumbing (read manifest, write results back)
│   ├── xlsx_write_back.py / xlsx_repair.R   # .xlsx write-back + the openxlsx corruption workaround
│   ├── plot_style.R              # shared plot styling for Step 07
│   └── requirements.txt          # Python deps (+ requirements.lock.txt, requirements.R)
├── field_data/             # your measurements sheet (.xlsx); ships empty
├── results/                # this project's Step 7 CSVs + plots (point clouds are never committed)
├── raw_ply/ cleaned/ stitched/ slices/   # local cloud working dirs (contents gitignored)
├── Tree_notes.md           # per-tree issue → solution log (for the methods write-up)
└── Python_glossary.md      # Python constructs used by the scripts
```

**The point-cloud data is not in this repo.** Clouds are large and irreplaceable, so all cloud formats (`.ply`, `.las`, `.bin`, …) are gitignored and kept in your own working directory outside the repo. The working spreadsheet also lives outside version control. This project's sheet and `results/` use the trees' real tags. If your identifiers are sensitive, keep the analysis output out of any git-tracked folder (see `DAB_RESULTS` in Step 7).

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
Rscript scripts/requirements.R   # readxl, dplyr, tidyr, ggplot2, scales, Rvcg, lidR, ITSMe,
                                 # openxlsx, xml2, zip
```

### CloudCompare

Used for every manual step: segmenting, loop-closing, merging, SOR and polishing the slice ring. **It is not used for format conversion** — everything in this chain is already `.ply`. If you find a `-C_EXPORT_FMT PLY` command line in an older doc, it is residue from a superseded version of this workflow.

---

# Full walkthrough: one tree, start to finish

## How the steps map onto `scripts/`

Seven steps. Five are manual CloudCompare work by design; only steps 4 and 6 are scripted, and step 7 runs once at the end over everything.

| Step | `scripts/` folder | Tool | Unit of work |
|---|---|---|---|
| 1 Organize by tree | `Step01_PrepareTree/` | CloudCompare, manual | per tree |
| 2 Segment the trunk section | `Step02_CutSection/` | CloudCompare, manual | per capture |
| 3 Clean (loop-close, merge, SOR) | `Step03_CleanSection/` | CloudCompare, manual | per capture, then per tree |
| 4 Select site & cut the slice | `Step04_CutSlices/` — `cut_slice.py` / `.R` | Python / R | per tree-site |
| 5 Polish the slice ring | `Step05_PolishSlice/` | CloudCompare, manual | per tree-site |
| 6 Measure | `Step06_Measure/` — ten scripts | Python **and** R | per tree-site |
| 7 Validate & compare | `Step07_Analysis/` | R only | once, over everything |

Each folder has a README stating what it **takes**, what it **makes**, and what it **feeds**.

Work **one tree at a time** — that is the quality control. Steps marked **[conditional]** are skipped by most trees; the triage flags you record in Step 1 decide which ones you do.

**Keep your files wherever you like.** What this walkthrough tells you at every step is **what that step consumes and what it hands to the next one**. Follow the chain, not a folder layout.

**The chain, end to end:**

```
  raw scanner .ply
    │  [1] organize by tree, record triage flags     → one folder per tree
    │  [2] segment the trunk SECTION  (per capture)  → section .ply
    │  [3] clean:
    │        3a loop-close  ⟨if needed⟩
    │        3b merge captures  ⟨if needed⟩
    │        3c SOR  ⟨always⟩                        → cleaned segment .ply  (keep it)
    │  [4] cut the band at the picked height         → RAW band .ply
    │  [5] polish by hand                            → POLISHED ring .ply
    │  [6] measure, every method, Python AND R       → diameters (mm)
    │  [7] validate & compare                        → results/ CSVs + plots
    ▼
```

Two handoffs are easy to get wrong, so they're called out where they happen: the **cleaned segment** from Step 3 is what Step 4 cuts from, and is also the only cloud tall enough to measure a stem's lean, so don't discard it after cutting the band; and the **raw band** from Step 4 is *not* the thing you measure — Step 5's polished ring is.

> **Segmenting and cleaning now happen *before* merging.** A tree's captures arrive at the merge already trimmed to trunk. This is a change from an earlier version of this workflow, and it matters: ICP locks on far better when it isn't also being shown foliage and ground.

---

## Steps 1–5 — the manual chain

Each of these has its own README in its `scripts/` folder, written against the tools as they actually behave. Rather than duplicate them here, this section states the contract each step honours; open the step README for the click-by-click.

| | Takes | Makes | Feeds |
|---|---|---|---|
| **1 Organize by tree** | raw captures off the scanner | one folder per tree, original names kept, **read-only thereafter**; triage flags recorded in the sheet | Step 2 |
| **2 Cut the section** | a tree's capture(s) | the **trunk section** — a vertical chunk of bole containing every site you intend to measure | Step 3 |
| **3a Close loop** *[conditional]* | a single capture whose circumferential wrap didn't close (SLAM drift seam) | one closed cloud | 3b or 3c |
| **3b Merge captures** *[conditional]* | 2+ captures of one tree | one merged cloud | 3c |
| **3c SOR** *always* | the section | denoised section | Step 4 |
| **4 Cut the slice** | cleaned segment + the picked height | the **raw band** | Step 5 |
| **5 Polish** | the raw band | the **polished ring** | Step 6 |

**Things worth knowing before you start any of them:**

- **Accept the global shift on import** and reuse the same shift across every capture of one tree. It only recenters for numerical precision; relative geometry is untouched.
- **Make the section tall enough.** Beyond containing your sites, it is also the only cloud a stem's lean can be measured from, which needs a segment **taller than the trunk is wide** (≥ 2× diameter).
- **Keep the shared overlap intact** through steps 2 and 3a if the tree needs merging — ICP needs it to lock on.
- **Check every merge by eye.** Doubled or ghosted bark in the overlap zone means a bad merge, and a bad merge distorts geometry. Subsample afterwards to drop the duplicated overlap points.
- **SOR conservatively.** Over-aggressive Statistical Outlier Removal erodes the trunk surface and biases diameter **down** — it doesn't just remove noise.
- **Polishing is not optional in practice.** On this project's first pass it changed the answer on 28 of 32 sites, median shift −38 mm; only four bands were clean enough to skip, and no automatic flag identified which four in advance.

---

## Step 4 — (Python or R) Cut the slice

Pick the height by eye in CloudCompare — over the dendrometer band or painted mark, or the lowest point the trunk reads as roughly cylindrical — and record it in the sheet's `Y_value_<Site>` column. **On a Y-up cloud that is a Y coordinate.** Then cut every recorded height at once:

```bash
python  scripts/Step04_CutSlices/cut_slice.py --from-sheet --up-axis y
Rscript scripts/Step04_CutSlices/cut_slice.R  --from-sheet --up-axis y
```

Single-slice mode still works against one section:

```bash
python scripts/Step04_CutSlices/cut_slice.py <section.ply> --tree-id <tag>__<Site> --up-axis y \
    --slice-height <Y> --slice-thickness 0.06 --viz-dir <folder>
```

`--viz-dir` writes the bundle you load back into CloudCompare: the band itself, the fitted circle, the hull wrap, a fit PNG and a `measure.txt`. **The slice keeps the scan's own colours**, so you can see bark when you polish it.

> **⚠️ The diameter this step prints is a CEILING, not the result.** The band is raw — stray points outside the bark are still in it, and the convex hull wraps them too. Polishing removes them, and a convex hull can only *shrink* when points are removed, so the Step 6 number is always at or below this one. It lands in `<Site>_CutSlice_pythonScript_Diameter_mm` as a sanity check, not an estimate.

---

## Step 6 — (Python **and** R) Measure the polished ring

Run every method in `--from-sheet` mode. **One site per run** — each script's CONFIG names the sheet, the folder, the filename pattern, the site label and the output column, so the methods never overwrite each other.

```bash
python  scripts/Step06_Measure/dendro_tape.py                --from-sheet --up-axis y
Rscript scripts/Step06_Measure/dendro_tape.R                 --from-sheet --up-axis y
Rscript scripts/Step06_Measure/dab_itsme_concave_hull.R      --from-sheet --up-axis y
python  scripts/Step06_Measure/dab_itsme_concave_hull.py     --from-sheet --up-axis y
python  scripts/Step06_Measure/bin_fixed_angle.py            --from-sheet --up-axis y
Rscript scripts/Step06_Measure/bin_fixed_angle.R             --from-sheet --up-axis y
python  scripts/Step06_Measure/bin_mean_distance_radius.py   --from-sheet --up-axis y
Rscript scripts/Step06_Measure/bin_mean_distance_radius.R    --from-sheet --up-axis y
python  scripts/Step06_Measure/circle_fit.py                 --from-sheet --up-axis y
Rscript scripts/Step06_Measure/circle_fit.R                  --from-sheet --up-axis y
```

Single-file and folder modes also work; the ring is already cut, so **omit the height arguments** and the script measures the file as-is:

```bash
python  scripts/Step06_Measure/dendro_tape.py <polished_ring.ply> --tree-id <tag>__<Site> --up-axis y --out <csv>
python  scripts/Step06_Measure/dendro_tape.py <folder> --batch --up-axis y --out <csv>
```

> **The R binned scripts and both ITSMe scripts have no `--batch` mode.** Use `--from-sheet`, or loop over files one at a time. The Python ITSMe port is slow, about 30 seconds a slice.

### The gap check flags — it does not block

A convex hull on a ring with a hole in it chords straight across the hole, silently inflating the tape reading. `dendro_tape.*` and both binned scripts guard against this by measuring the **longest hull edge as a fraction of equivalent diameter** (`MAX_EDGE_FRAC`, default 0.5), because angular coverage alone doesn't catch it — coverage is measured from the centroid and over-reports on a broken ring.

**That number is recorded, not enforced.** Every site gets a diameter; the fraction is written to `<Site>_<Method>_MaxEdgeFrac` so you can apply your own threshold at analysis time without re-running anything. A flagged slice prints `[flagged] … written, but check it`.

> **⚠️ Look at a flagged slice before you decide what it means.** The guard cannot distinguish a genuine scan gap from a deep flute. On this project's second pass, one flagged ring had a whole arc missing (correctly caught — and its coverage still read 360°), while another chorded across a concavity that had points all along it — which is exactly what a girth tape bridges, and therefore a false alarm. Flagging concentrates on the lowest, most buttressed sites. `--viz-dir` draws the offending edge in magenta so you can tell the two apart in seconds.

### If the stem leans

Every Step 6 method measures a **level** cut: the band is cut across the cloud's up axis, which ForestScanner aligns with gravity. On a leaning stem that cut is slightly oval, and the 6 cm band is smeared sideways by the lean, so it reads a little **high**. Roughly, for the convex hull: +0.8% plus about 7 mm of diameter at 10°, and +1.7% plus about 10 mm at 15°.

**No Step 6 script corrects for lean.** `cut_slice.*` (and the original `fit_dab.*`) accept `--axis-ply <cleaned_segment.ply>`, which estimates the stem axis by PCA and rotates the cloud before *their own* fit, but the band they save is still a level cut, and that is what Step 5 polishes and Step 6 measures.

> **⚠️ If you use `--axis-ply`, the axis segment must be a TALL trunk segment — never a thin slice.** If it isn't taller than the trunk is wide, PCA latches onto a *diameter* direction instead of the stem axis. Rule of thumb: **≥ 2× the trunk diameter in height**. The script warns when `s0/s1` looks too low.

On this project's second pass the stems leaned 1–9°, measured from the cleaned segments, which is worth at most about 1–2 cm on the largest trunks, so no correction was applied.

### What your sheet actually needs

**Bring your own format — don't reshape your data to match ours.** `--from-sheet` needs exactly these, and you name them all yourself in the `CONFIG` block:

| CONFIG setting | What it points at | Required? |
|---|---|---|
| `TREE_ID_COL` | a column of **labels**, one row per tree — whatever you already call them | **Yes** |
| `HEIGHT_COL` | the picked cut height (m) for this site | Only if cutting on the fly; `None`/`NULL` measures already-cut discs as-is |
| `OUTPUT_COL` | the column the measured diameter (mm) gets written back into | **Yes** |
| `FLAG_COL` | the column `max_edge_frac` gets written into | No — `None`/`NULL` skips it |
| `SITE_LABEL` | which site this run measures | **Yes** |

Plus `SHEET_PATH`, `PLY_FOLDER` and `PLY_FILENAME_PATTERN` so the script can find the sheet and match each row to its `.ply`. That's the whole contract — everything else in the shipped CONFIG defaults is one project's column naming, kept as a worked example, not a required schema.

> **⚠️ The sheet must be an `.xlsx`. Convert before you run.** Both languages read Excel directly — `openpyxl` in Python, `readxl` in R — and there is deliberately no CSV reader: a previous attempt to accept CSVs broke the write-back path. Single-file and `--batch` usage don't touch a sheet at all, so they're unaffected.

**Diameters are written to the sheet as whole millimetres**, matching the precision of the field readings they're compared against, except the ITSMe columns, which are written in tenths of a millimetre. The `--out` CSVs keep full precision.

R's write-back prefers shelling out to `python`/`python3` (override via `SHEET_BATCH_PYTHON`) rather than writing the `.xlsx` directly — see `scripts/sheet_batch.R`'s header for why (a real corruption bug in `openxlsx` was found and worked around during testing). With no Python on PATH it falls back to a direct-R path (`scripts/xlsx_repair.R`) that patches the same corruption after saving — usable from a Python-free RStudio install, at the cost of being the less-exercised of the two paths.

---

## Checkpoint — is the sheet ready for analysis?

**This is the boundary between per-tree work and analysis.** Everything before this point happens per tree, in your own folders. Everything after reads one sheet and nothing else.

Stop here and check, because **Step 7 has two failure modes and only one of them is loud.**

- **A missing column errors out immediately.** The analysis scripts name their columns directly (`Dendrometer_FieldDiameter`, `ForestGeoPaint_FieldDiameter_mm`, `DendroPaint_FieldDiameter_mm`, `<Site>_DendroTape_pythonScript_Diameter_mm`, `Tree_Tag`, …). If one isn't in the sheet, R stops with "object not found." Annoying, but you'll know.
- **A missing *value* is dropped in silence.** Each script filters to rows that have both a reading and an estimate. Any row missing either just disappears — no warning — and the metrics are computed over whatever survived. Twelve trees measured but three readings not yet entered gives you a clean-looking summary of nine, and nothing on screen says so.

So the thing to verify is **completeness**, not correctness:

- [ ] **Every column the analysis names actually exists.**
- [ ] **Field readings** (`Dendrometer_FieldDiameter`, `ForestGeoPaint_FieldDiameter_mm`, `DendroPaint_FieldDiameter_mm`). No script writes these. They are your ground truth, and a row without one silently leaves the comparison.
- [ ] **Diameter columns** — `--from-sheet` wrote these, one column per script per site. Measured from the CLI instead? Transcribe from your `--out` CSVs now.
- [ ] **Check `n` in the summary output against the number of trees you expect.** Cheapest way to catch a silent drop.
- [ ] **Picked heights** and **triage flags** — should already be there.
- [ ] **Format is `.xlsx`**, not CSV.
- [ ] **The Step 7 site lists match your trees** (see below).

> **⚠️ The analysis scripts' `CONFIG` covers the sheet path and this project's site lists — not the column names.** Each Step 7 script's CONFIG holds `EXCLUDE_SITES` (tree + site pairs left out of everything), `PAINT_DBH_TREES` (trees whose paint mark sits at breast height, so it counts as DBH), `EXCLUDE_SENSITIVITY` (tree + site pairs for an extra "excluding" row), `FLAG_THRESHOLD` (0.5) and, in `compare_fig_notes.R`, `FIG_TREES`. **Set those for your own trees.** The column names are written into the code, so reusing the scripts on a differently-shaped sheet means editing them, not just CONFIG. They were written to settle this project's method question rather than as general tools.

> **⚠️ Mind where `--out` writes.** Paths resolve against your shell's current directory, which is easy to get wrong when running repo scripts against data held elsewhere. If your tree labels are sensitive, keep script output out of any git-tracked folder and check `git status` before committing.

---

## Step 7 — (R) Validate & compare

Most of these run once per paint source. Give the source as the first argument, ForestGeoPaint or DendroPaint. It goes into every output name (`<src>` below).

```bash
Rscript scripts/Step07_Analysis/validate_field_accuracy.R <src>   # -> results/field_accuracy_*
Rscript scripts/Step07_Analysis/compare_hull_methods.R    <src>   # -> results/hull_comparison_*
Rscript scripts/Step07_Analysis/plot_error_by_size.R      <src>   # -> results/error_by_size_<src>_*
Rscript scripts/Step07_Analysis/plot_by_method.R          <src>   # -> results/plots/by_method_<src>_*
Rscript scripts/Step07_Analysis/compare_fig_notes.R       <src>   # -> results/fig_notes_<src>_*
Rscript scripts/Step07_Analysis/compare_field_record.R    <src>   # -> results/field_record_*
Rscript scripts/Step07_Analysis/compare_paint_sources.R           # -> results/paint_sources_*
Rscript scripts/Step07_Analysis/bin_fixed_angle_demo.R            # -> results/bin_fixed_angle_demo_all_sites.*
```

Run these **from the repo root** — they `source()` `scripts/plot_style.R` with a repo-relative path. They read the working sheet and nothing else (`DAB_SHEET` overrides the path). Output goes to `results/`, or to the folder in `DAB_RESULTS`. **`results/` is git-tracked**, so anything written there goes public when the repo is pushed.

How the comparisons are set up:

- **Rows are tree + site.** Each run uses the Dendrometer bands and that source's paint marks. The bands are the same in both runs.
- **Groups are by measurement type, not a size threshold.** "Band" is the Dendrometer site. "DBH" is the paint mark on the trees in `PAINT_DBH_TREES`, which sits at breast height below any buttress. "DAB" is every other paint mark, measured above the buttress.
- **No row is dropped for having a large error.** The headline metrics use every tree-site, flagged rings included. Each summary adds sensitivity rows without flagged rings (`MaxEdgeFrac` ≥ 0.5), and without the tree + site pairs in `EXCLUDE_SENSITIVITY`.
- **One field value is in question.** Tree 3853's red value (967 mm) sits about 360 mm under every scan method and under its own blue value (1330 mm). It isn't a typo, but it may be a bad measurement. It stays in the headline numbers, and every summary has a row without it.
- **`compare_paint_sources.R`** puts the two sources side by side. It gives each method's error at the red marks and at the blue marks, and for the trees with both marks it compares every estimate against both field values.
- **`compare_fig_notes.R`** compares the buttressed paint sites on trees with a fig noted in the census notes against those without, and redraws the main error chart without the fig paint sites. It was added after the pattern was seen, so it is exploratory.
- **`compare_field_record.R`** shows how much the census's own paint-mark diameters differ from each other, next to each method's error.
- **ForestScanner's errors are much larger than the cloud methods'.** Where they share an axis, the axis is set by the cloud methods. A ForestScanner value past it is drawn at the edge, and its real value is printed on the bar or in the caption.

Watch the `[Python vs R cross-check]` lines `compare_hull_methods.R` prints — a convex hull is deterministic, so the hull and circle-fit twins should agree to **0.000 mm**. The ITSMe line can read up to about 0.1 mm, since both are stored in tenths of a mm and the port rounds an occasional point the other way. Anything larger is a bug, not a method difference.

Finally, log anything nonstandard in `Tree_notes.md` — the qualitative story that the sheet's structured columns can't hold.

---

## Per-tree checklist

```
- [ ]  1. (CloudCompare) Sort captures into the tree's folder; record triage flags:
          cloud_quality, Number_scans, needs_layers_merged, needs_loopclose, has_dendrometer
- [ ]  2. (CloudCompare) Cross-section tool -> trunk SECTION, per capture.
          Tall enough for every site AND >= 2x trunk diameter (lean reference).
- [ ] 3a. [if needs_loopclose] Find the seam, confirm overlap, cut the flap,
          point-pair align -> ICP on the overlap -> merge -> subsample
- [ ] 3b. [if needs_layers_merged] Point-pair align -> ICP (check RMS) -> merge -> subsample
- [ ] 3c. (always) Conservative SOR -> cleaned segment
- [ ]  4. (CloudCompare) Pick the site; read the height off the Y AXIS;
          record into Y_value_<Site> in the sheet. Then:
          python scripts/Step04_CutSlices/cut_slice.py --from-sheet --up-axis y
          Check from directly above: a full ~360 deg ring, not two side-bands.
- [ ]  5. (CloudCompare) Polish the ring by hand; don't over-trim real flutes.
          Save as <TreeID>__<Site>.ply -- Step 6 finds its input by exactly that pattern.
- [ ]  6. (Python + R) Measure, every method, height args OMITTED:
          python  scripts/Step06_Measure/dendro_tape.py           --from-sheet --up-axis y
          Rscript scripts/Step06_Measure/dab_itsme_concave_hull.R --from-sheet --up-axis y
          (+ their twins, bin_fixed_angle.* / bin_mean_distance_radius.* and circle_fit.* -- one run per site)
- [ ] 6b. Check <Site>_<Method>_MaxEdgeFrac. Over 0.5? Open the --viz-dir picture and
          decide: real scan gap, or a flute the tape would bridge anyway?
- [ ]  X. CHECKPOINT before analysis. Missing COLUMN = loud R error;
          missing VALUE = row silently dropped. Confirm the field readings and
          diameter columns are complete, set the Step 7 site lists, then
          sanity-check `n` in the summary.
- [ ]  7. (R) Rscript scripts/Step07_Analysis/validate_field_accuracy.R <src>
          (R) Rscript scripts/Step07_Analysis/compare_hull_methods.R <src>  <- watch the
              Python-vs-R cross-check lines. Hulls or circle nonzero = real bug
          (R) the other Step 7 scripts, for the figures
          <src> is ForestGeoPaint or DendroPaint. Run each script once for each.
- [ ]  8. (manual) Log anything nonstandard in Tree_notes.md
```

---

# Reference

## Script index

Every script in the repo, grouped by where it sits in the chain. Paths are relative to `scripts/`.

> **Why some steps are dual-language and some aren't.** The **workflow** scripts — everything a person reusing this pipeline actually has to run — exist in **both Python and R**, so a lab with only one of the two can still take a tree all the way through. The **analysis** scripts are **R-only on purpose**: they exist to work out which method this project should adopt, and they aren't part of the reusable workflow. ITSMe is an R package with no Python equivalent, so its Python twin, `dab_itsme_concave_hull.py`, is a port of the method rather than a call into the package.

### Environment — before you start

| File | Lang | Purpose |
|---|---|---|
| `requirements.txt` | Python | pip dependencies |
| `requirements.lock.txt` | Python | pinned versions, for reproducing an exact environment |
| `requirements.R` | R | installs R dependencies — handles the `lidR`-before-`ITSMe` ordering trap that otherwise fails the build |

### Steps 4 & 6 — measurement

| Script | Lang | Purpose | Notes |
|---|---|---|---|
| `Step04_CutSlices/cut_slice.py` / `.R` | both | Cut the band `[Y − t/2, Y + t/2]` out of a cleaned segment at the picked height; write the raw-band viz bundle | Copied from `fit_dab.*` with cutting as its only job (`--slice-height` required in single mode). Its diameter is a **ceiling** — see Step 4 |
| `Step06_Measure/dendro_tape.py` / `.R` | both | Raw-point convex-hull perimeter only, no circle fit — the plain taut-tape baseline | Carries the partial-ring and gap-edge guards, and writes the per-slice picture bundle with `--viz-dir`. The `true_hull` baseline `compare_hull_methods.R` compares the binned hulls against |
| `Step06_Measure/dab_itsme_concave_hull.R` / `.py` | both | ITSMe median-radius circle **+ concave "functional" diameter** (equal-area) | A genuinely different method. Concave hull traces *into* flutes where a convex hull bridges them, and underestimates where an arc is missing. The `.R` calls ITSMe; the `.py` ports it |
| `Step06_Measure/bin_mean_distance_radius.py` / `.R` | both | Convex hull of a percentile-binned polygon, wedge width set by a fixed **arc length** (default ~10 mm) | One of two offered variants |
| `Step06_Measure/bin_fixed_angle.py` / `.R` | both | Same method, wedge width set by a fixed **angle** (default 2°) | The other variant — **not** a superseded version |
| `Step06_Measure/circle_fit.py` / `.R` | both | Least-squares (Kåsa) circle fit | The circle passes through the middle of the bark's bumps, so on fluted trunks it tends to read below the hulls. RMS and coverage go to the CSV |

### Step 6 — batch plumbing

| Script | Lang | Purpose |
|---|---|---|
| `sheet_batch.py` / `sheet_batch.R` | both | Shared `--from-sheet` machinery: read the manifest, write results back into the sheet |
| `xlsx_write_back.py` | Python | Performs the actual `.xlsx` write. `sheet_batch.R` shells out to this whenever Python is on PATH (the preferred path) |
| `xlsx_repair.R` | R | Python-free fallback — patches `openxlsx`'s post-save corruption so write-back works on an R-only install |

### Step 7 — analysis *(R-only by design)*

| Script | Purpose |
|---|---|
| `Step07_Analysis/validate_field_accuracy.R` | The core feasibility result: every method vs. field reading, two scopes (the bands only, and the bands with one paint source), grouped by measurement type. Run once per source |
| `Step07_Analysis/compare_hull_methods.R` | Raw true hull vs. denoised binned hull, against field reading and against each other. Prints the Python-vs-R cross-check. Run once per source |
| `Step07_Analysis/plot_error_by_size.R` | Every method on one axis, by group, to compare the *shape* of each error distribution. Run once per source |
| `Step07_Analysis/bin_fixed_angle_demo.R` | Coverage view: the method applied to every processed site, not just the validated subset |
| `Step07_Analysis/plot_by_method.R` | The same comparisons split out, one panel per method: scatter, % and mm error, box plots, Bland-Altman. Run once per source |
| `Step07_Analysis/compare_fig_notes.R` | Buttressed paint sites, fig noted vs. not, and the main error chart without the fig paint sites. Exploratory. Run once per source |
| `Step07_Analysis/compare_field_record.R` | How much the census's own paint-mark diameters differ from each other, next to each method's error. Run once per source |
| `Step07_Analysis/compare_paint_sources.R` | The red and blue paint marks side by side: each method's error at each, and both field values on the trees that have both marks |
| `plot_style.R` *(root)* | Shared method labels/colours/shapes, sourced by the analysis scripts so every figure uses one vocabulary |

### `Unused/` — not part of the workflow

> **Nothing in this folder produced a result that was kept. A future user should not run any of it.** Reasons differ per file — see [`scripts/Unused/README.md`](scripts/Unused/README.md).

| Script | Verdict |
|---|---|
| `Unused/measure_slice.py` / `.R` | **Retired 2026-09-21.** Circle fit + convex-hull tape on a polished slice; produced this project's first-pass numbers. `dendro_tape.*` gives the identical hull diameter, adds the gap check, and now writes the same pictures. `OUTPUT_COL` is disabled, so it cannot write to the sheet |
| `Unused/circle_fit_slices.R` | **Superseded 2026-09-30** by `Step06_Measure/circle_fit.*`, which writes the circle fit to the sheet |
| `Unused/loopclose.py` | **Never run in this study.** FPFH/RANSAC coarse alignment + point-to-plane ICP, then merge. Cannot cut the flap — that's manual. Wrote nothing: `stitched/` holds only `.gitkeep` |
| `Unused/loopclose.R` | **Never run in this study.** Best-effort port of the above with **no coarse step**. Weaker; if ever tried, check the merge visually |
| `Unused/disc_dbh_template.R` | ⚠️ **Do not run this.** The earliest prototype — a minimal ITSMe example written before this project discovered its clouds are Y-up. **The code itself is not wrong**: `diameter_slice_pc` slices on Z because that is ITSMe's convention, correct for a Z-up cloud. What was wrong was feeding it Y-up data — a usage error that voided an entire first batch of measurements. Kept because that mistake is part of the documented method history |

### Notes on apparent duplication

- **`fit_dab.py` / `fit_dab.R` *(root)*** — the originals `cut_slice.*` and `measure_slice.*` were copied from. Untouched, still runnable, and kept as the record of what produced the published numbers. The copies carry their own copy of the fit code, so **a fix to one is not a fix to the others**.
- **`bin_fixed_angle.*` vs. `bin_mean_distance_radius.*`** — two variants of one method, both first-class. Which suits a stand depends on its size distribution. **Not redundant.**
- **`loopclose.R` vs. `loopclose.py`** — the R port is weaker (no coarse registration), but it's the difference between an R-only lab having the step and not having it. Neither was run in this study.

## Command reference

Cut one band at a picked height `Y` (metres), 6 cm thick, from a cleaned segment:

```bash
python  scripts/Step04_CutSlices/cut_slice.py <segment.ply> --tree-id <tag>__<Site> --up-axis y \
    --slice-height <Y> --slice-thickness 0.06 --viz-dir <out_dir>
```

Measure a polished ring (already a thin cross-section) whole:

```bash
python  scripts/Step06_Measure/dendro_tape.py <ring.ply> --tree-id <tag>__<Site> --up-axis y --out <csv>
Rscript scripts/Step06_Measure/dendro_tape.R  <ring.ply> --tree-id <tag>__<Site> --up-axis y --out <csv>
Rscript scripts/Step06_Measure/dab_itsme_concave_hull.R <segment.ply> --tree-id <id> --up-axis y \
    --height-z <Y> --thickness 0.06 --out <csv>
python  scripts/Step06_Measure/dab_itsme_concave_hull.py <segment.ply> --tree-id <id> --up-axis y \
    --height-z <Y> --thickness 0.06 --out <csv>
```

A whole folder of rings: `--batch` (path is a folder, one row per `*.ply`) — supported by `dendro_tape.py`/`.R`, `circle_fit.py`/`.R`, `bin_*.py`, `cut_slice.py`/`.R` and `fit_dab.py`/`.R`, but **not** the R binned scripts or either ITSMe script.

> **⚠️ The height/thickness flags are not named the same across scripts:**
>
> | Script | Height flag | Thickness flag |
> |---|---|---|
> | `cut_slice.py`/`.R`, `dendro_tape.py`, `circle_fit.py`, `bin_*.py`, `fit_dab.*` | `--slice-height` | `--slice-thickness` |
> | `dendro_tape.R`, `circle_fit.R`, `bin_*.R` | `--height` | `--thickness` |
> | `dab_itsme_concave_hull.R`/`.py` | `--height-z` | `--thickness` |
>
> Also: **`--up-axis` does not default the same way across scripts.** `fit_dab.*` and both ITSMe scripts default to **`z`** — the wrong axis for these clouds. Pass it explicitly, every time.

### Outputs

- **Your working workbook** (outside the repo) — per site: the `CutSlice` ceiling, `DendroTape`, `DabItsme_ConcaveHull`, `BinFixedAngle`, `BinMeanDistanceRadius` and `CircleFit` diameters in mm for Python and R, plus `MaxEdgeFrac`, alongside your field readings.
- **Per-slice viz bundle** (`--viz-dir` on `cut_slice.*` and `dendro_tape.*`): `*_slice.ply` (the measured band, in the scan's own colours), `*_ring_*.ply` (fitted circle), `*_hull_*.ply` (tape wrap), `*_gapedge.ply` on a flagged ring, `*_slice_fit.png`, `*_measure.txt`.
- **Binned geometry** (`--poly-dir` on the `bin_*` scripts): the binned surface polygon (cyan) and its hull (magenta) as `.ply`, to load in CloudCompare next to the original slice.
- **`results/*.csv` + `results/plots/*.png`** — where the analysis scripts write, or `DAB_RESULTS` if set. This repo's copy holds this project's second-pass results. Point clouds are never written here (and are gitignored by extension anyway).

## CloudCompare quick reference

Menu wording varies slightly by CloudCompare version; if a path differs on yours, the tool name is the thing to search for.

| Task | Menu path | Shortcut |
|---|---|---|
| Segment (manual crop) | `Edit > Segment` | `T` |
| Statistical Outlier Removal | `Tools > Clean > SOR` | — |
| Subsample | `Edit > Subsample` | — |
| Point-pair coarse align | `Tools > Registration > Align (point pairs picking)` | — |
| Fine ICP | `Tools > Registration > Fine registration (ICP)` | — |
| Merge clouds | `Edit > Merge` | — |
| Cross Section (slice) | `Tools > Segmentation > Cross Section` | — |
| Fit primitive | `Tools > Fit > Circle / Cylinder` | — |
| Toggle RGB on/off | `Properties > Colors` checkbox | — |
| Colour by height (find the buttress top) | `Edit > Scalar fields > Export coord to SF`, then a colour scale | — |

**Two rough in-CloudCompare sanity checks**, useful before you trust a scripted number — neither is an analysis result:
- Select the slice and read its **bounding box** dimensions in `Properties`, or point-pick a couple of diameters by hand.
- `Tools > Fit > Circle` on a slice returns a radius directly; `Tools > Fit > Cylinder` on a taller (~10–20 cm) section returns a radius *and* an axis, and is less sensitive to one bad slice. Then `C = 2πr`, `D = 2r`.

## Gotchas (don't repeat)

- **Y-up**: always `--up-axis y`. A correct slice is a full ~360° ring; two side-bands means the wrong axis. `fit_dab.*` and both ITSMe scripts still default to `z` — pass the flag explicitly, every time.
- **Convex hull is not outlier-robust** — a single stray point inflates the tape. Polish rings before fitting (Step 5); the `bin_*` scripts are a scripted fix for this specific problem.
- **SOR conservatively** — over-denoising erodes the trunk surface and biases diameter down.
- **Angular coverage over-reports on a broken ring**, because it's measured from the centroid. A ring can read 360° and still have a whole arc missing — that's what `MaxEdgeFrac` is for.
- **But `MaxEdgeFrac` can't tell a gap from a flute.** A deep concavity produces a long hull edge too, and a girth tape would bridge it legitimately. Look at the picture before discarding a flagged site.
- **`--axis-ply` needs a tall segment, never a thin slice** — see [If the stem leans](#if-the-stem-leans).
- **Roots or stems growing over the bark inflate every hull.** On this project the hulls read higher on buttressed trees with a fig noted in the census records than on trees without one, and the circle fit less so. The pattern was found after the data was seen, so treat it as a lead, not a result. Look at the ring in RGB before trusting a hull on a tree with a strangler fig or a heavy liana.
- **The `--from-sheet` manifest must be `.xlsx`.** There is no CSV reader, and adding one has broken the write-back path before. (Script `--out` files are still CSVs — that's output, not input.)
- **`Unused/loopclose.py` on a small flap should report LOW fitness (~0.2–0.3).** High fitness there means it collapsed onto the wrong surface.
- **The low-confidence RMS flag is miscalibrated for large, rough trunks** — it fires routinely on big buttressed boles that are fine, and doesn't catch every real outlier. Don't treat it as a reliable data-quality signal on large trees without also checking the numbers.
- **`scripts/Unused/disc_dbh_template.R` slices on Z and must not be used to measure anything here.** It's the pre-Y-up prototype, kept deliberately as a record of the mistake that cost a whole first batch. Use `dab_itsme_concave_hull.R` instead, which does the same thing correctly for Y-up clouds.
- **Don't conflate the sheet's ITSMe and hull columns.** The `DabItsme_ConcaveHull` columns are a **concave**, equal-area functional diameter; the `DendroTape` columns are a **convex** true hull. Different geometric constructs, different columns.
- **Three copies of the fit code exist** — `fit_dab.*`, `cut_slice.*` and `Unused/measure_slice.*`. That's deliberate (the originals are the record), but it means a fix to one is not a fix to the others.

## Open questions

Carried over from the project's design notes — unresolved, and worth stating plainly rather than leaving implied:

- **Fixed slice thickness, or adaptive by point density?** The pipeline uses a fixed 6 cm band throughout.
- **The gap threshold is one number doing two jobs.** `MAX_EDGE_FRAC = 0.5` flags both genuine scan gaps and deep flutes, and can't separate them. A check that asks whether points actually *exist* along the offending edge would distinguish the two; it hasn't been written.
- **The binning percentile was fixed at 90 in advance**, deliberately, so that no method got tuned against a field reading it had already seen. The second pass was run blind on that basis. Whether 90 is the right choice is still open. One method change was made after the field data was seen (empty wedges skipped instead of interpolated, Step 6), and it moved no result by more than 1.1 mm.
- **The measurement-height rule is not standardized.** "Above the buttress" is an operator judgment call. A written rule (e.g. "0.3 m above the visual buttress top") would make it reproducible across operators — at the cost of flexibility on trees that don't fit the rule.
- **Buttress-top detection could be automated** — e.g. from a cross-sectional area or roundness curve against height — removing the judgment call entirely.
- **There is no uncertainty budget.** Scan noise, slice thickness and fit residual all contribute; combining them into per-tree error bars has not been done.
- **Which method to report is open**, and depends on what the reference instrument measures and on the results (see [What we're actually measuring](#what-were-actually-measuring-read-this-first)). A hull measures what a tape measures, and a circle does not wrap the bark's bumps. On this project's field comparison the least-squares circle came closest overall, largely by not over-reading the buttressed and fig-covered trunks, and the binned hulls came closest at the dendrometer sites. The choice should be argued explicitly in the write-up.
- **Repeatability is untested.** For dendrometer trees the real prize is whether a re-scan recovers the same diameter within the dendrometer's detectable growth increment. That would establish point-cloud *monitoring*, not just one-off measurement — and it needs a second scanning campaign.
