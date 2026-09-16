# Point-Cloud Tree Diameter at Custom Height

A feasibility study: can **mobile-LiDAR point clouds** (iPhone / [ForestScanner](https://apps.apple.com/app/forestscanner/id1547643372)) be used to monitor tree diameter at an operator-chosen, non-standard height — e.g. **Diameter Above Buttress (DAB)** on heavily buttressed tropical trees — as a lower-effort alternative to manual tape sampling, which is extremely time- and labor-intensive when the trunk can't be tape-measured at the standard reference height?

Bring your own scanned trees. A subset carrying **dendrometers** and/or **tape DBH/DAB** readings lets you validate against ground truth. Each tree's cross-section is measured **two independent ways** (Python and R) and compared against the field data. The deliverable is an assessment of **when the point-cloud method agrees with tape, and when it fails**.

> **What's in this repo, and what isn't.** This repo carries the **method and the code**: a workflow for measuring large, buttressed trees that other people can pick up and run, plus every measurement and comparison script behind it. **The study's own results are reported separately** — `results/` ships empty by design, not because anything is unfinished.

**New here?** Jump to the [**Full walkthrough**](#full-walkthrough-one-tree-start-to-finish) — every step from a raw `.ply` off the scanner to a validated diameter, in order.

---

## What we're actually measuring (read this first)

We are **not** measuring diameter directly. From a point cloud you can only recover the **cross-sectional geometry of the trunk** at a chosen height. The pipeline is:

1. Extract a thin horizontal **slice** of trunk points at the chosen height.
2. Fit a shape to that ring of points to recover **circumference** and an **equivalent diameter**.
3. Report both — because on an irregular, fluted or buttressed tropical trunk, "diameter" is a **modeled quantity, not a physical one**.

**Two diameter conventions — pick one and stay consistent:**

- **Equivalent-circle diameter**, `D = C / π`, where `C` is the fitted circumference. This mirrors what a DBH tape physically does: it measures circumference and back-computes a diameter. **This is the convention to use when comparing against tape-measured DBH/DAB.**
- **Best-fit-circle diameter** — a least-squares circle returns a radius directly. Identical to the above on a perfectly round stem; different on an irregular one. Useful as a cross-check, not as the headline number.

**This project reports circumference as primary and equivalent-circle diameter as derived**, because that is what matches field tape practice. The circle fit is kept as a secondary signal (and its RMS residual is a useful data-quality metric).

**Site selection is per-tree and operator-chosen** — either over a dendrometer band, or at the height where the buttress flares merge into a roughly cylindrical bole. **The height you pick is a real data column, not a nuisance parameter**: record it every time.

---

## How it works

From a trunk cross-section we recover geometry a few independent ways per site:

- **`fit_dab.py` / `fit_dab.R`** — least-squares circle **+ convex-hull "tape"** (the hull wraps the outside and bridges flutes, like a physical tape). Independent Python/R implementations of the same method, cross-checked against each other.
- **R (`dab_itsme.R`)** — the [**ITSMe**](https://github.com/lmterryn/ITSMe) package: circle fit **+ concave-hull "functional" diameter**. A different method, R-only (no Python equivalent — it's specifically an ITSMe-package feature).

The recorded metric is the **tape-equivalent diameter**; the pipelines are kept independent and compared against tape/dendrometer to see which tracks the field data best.

A purpose-built pair, `dendro_tape.py`/`dendro_tape.R`, computes *only* the raw-point convex-hull tape (no circle, no concave hull) as the most physically literal tape mimic. A third pair, `median_polygon_10mm.py`/`median_polygon_10mm.R`, computes the convex hull of a **median-radius-binned** surface polygon instead — a denoised alternative meant to be robust to the single-stray-point problem a raw convex hull has; it roughly halves the field-accuracy error of the raw-point hull. It's a comparison tool, not a replacement: `compare_hull_methods.R` checks it against `dendro_tape.*` both vs. field reading and directly against each other, alongside (not instead of) the main field-accuracy comparison in `validate_field_accuracy.R`.

`median_polygon_*` bins the slice ring before taking the median radius per bin, and ships as **two variants of the same method — a deliberate choice offered to you, not a default and a runner-up.** `median_polygon_10mm.py`/`.R` bins by a fixed **10 mm arc length**; `median_polygon_2deg.py`/`.R` bins by a fixed **2° angle**. The difference is what a bin physically covers: a fixed angle spans a very different amount of bark on a small stem than on a giant, while a fixed arc length stays constant across sizes.

Neither is universally better, and **the right choice depends on your stand**. Forestry practice varies enormously between sites, size distributions, and species, so both are kept as first-class options rather than one being retired. **On this project's validated subset the two came out virtually identical, with the 2° variant marginally ahead — that is a finding about this dataset, not a general result, and it should not be assumed to transfer to another project.** Run both against your own data and pick on your own numbers.

### Key conventions

- **⚠️ Clouds are Y-up.** ForestScanner (ARKit) exports have the **trunk axis along Y, not Z**. Cross-sections are circular only in the **X–Z plane** (slice at constant **Y**). **Always pass `--up-axis y`.** Slicing along Z cuts a vertical slab down the trunk and produces a two-band scatter, not a ring.
- **Operator-chosen height.** The measurement height is a picked point on the section, recorded per location. A tree may be measured at multiple sites — **TopFlag**, **LowerFlag**, and/or **Dendrometer** — each in its own column.
- **Units.** Point-cloud coordinates & heights are in **metres**; recorded **diameters are in millimetres** (`_mm` columns) to match the dendrometer data.
- **Only the dendrometer site has field ground truth** (the `Dendrometer_Reading`, in mm). Flag sites are cloud-only points for a height profile.

---

## Repository layout

```
PointCloud_TreeDiameter_CustomHeight/
├── scripts/                # one folder per processing step, in order; each has its own README
│   ├── Step01_PrepareTree/       # (CloudCompare, manual) import, fuse, loop-close, clean — README only
│   ├── Step02_CutSection/        # (CloudCompare, manual) cut down to the trunk section — README only
│   ├── Step03_CleanSection/      # (CloudCompare, manual) clean the section — README only
│   ├── Step04_ExportSectionPly/  # (CloudCompare CLI) .bin -> .ply — README with the one command
│   ├── Step05_CutSlice/          # cut_slice.py / cut_slice.R — cut a thin band at the picked height
│   ├── Step06_PolishSlice/       # (CloudCompare, manual) polish the ring — README only
│   ├── Step07_ExportSlicePly/    # (CloudCompare CLI) .bin -> .ply — README with the one command
│   ├── Step08_Measure/           # measure_slice.py / .R, dab_itsme.R, dendro_tape.py / .R,
│   │                             #   median_polygon_10mm.py / .R, median_polygon_2deg.py / .R
│   ├── Step09_Analysis/          # validate_field_accuracy.R, compare_hull_methods.R,
│   │                             #   plot_error_by_size.R, build_median_hull_2deg_demo.R (R-only by design)
│   ├── Unused/                   # loopclose.py / .R (never run), disc_dbh_template.R (the pre-Y-up prototype)
│   ├── fit_dab.py / fit_dab.R    # the originals cut_slice.* and measure_slice.* were copied from — untouched, kept as the record
│   ├── sheet_batch.py / sheet_batch.R  # --from-sheet plumbing (read manifest, write results back)
│   ├── xlsx_write_back.py / xlsx_repair.R  # .xlsx write-back + the openxlsx corruption workaround
│   ├── plot_style.R              # shared plot styling for Step09
│   └── requirements.txt          # Python deps (+ requirements.lock.txt, requirements.R)
├── field_data/             # your measurements sheet (.xlsx — see "What your sheet actually needs"); ships empty
├── results/                # result CSVs + plots (point clouds are never committed)
├── raw_ply/ cleaned/ stitched/ slices/   # local cloud working dirs (contents gitignored)
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
Rscript scripts/requirements.R   # readxl, dplyr, tidyr, ggplot2, scales, Rvcg, lidR, ITSMe,
                                 # openxlsx, xml2, zip (the Python-free write-back fallback)
```
Gotcha `requirements.R` handles for you: `lidR` is currently archived on CRAN, so it has to come from the maintainer's R-universe binary *before* `ITSMe` installs, or the `ITSMe` build fails.

### CloudCompare
Used for interactive cleaning/segmentation and for `.bin → .ply` export. The fitters cannot read CloudCompare `.bin`; convert first (headless):
```bash
CloudCompare -SILENT -AUTO_SAVE OFF -O <disc.bin> -C_EXPORT_FMT PLY -SAVE_CLOUDS FILE <disc.ply>
```

---

# Full walkthrough: one tree, start to finish

## How the 14 steps map onto `scripts/`

The walkthrough below is written as 14 steps. The `scripts/` folders are numbered by the **nine-stage folder chain** the data actually moves through — a stage counts as its own folder only if every tree has a file for it. The two numberings are both kept; this table joins them.

| Walkthrough step | `scripts/` folder | Tool |
|---|---|---|
| 1 Import · 3 Fuse · 4 Close loop · 5 Clean | `Step01_PrepareTree/` | CloudCompare, manual |
| 2 Triage | *(recorded in the sheet, no folder)* | manual |
| 6 Cut down to the trunk section | `Step02_CutSection/` | CloudCompare, manual |
| *(second clean on the section)* | `Step03_CleanSection/` | CloudCompare, manual |
| 7 Export `.bin` → `.ply` | `Step04_ExportSectionPly/` | CloudCompare CLI |
| 8 Pick the site · 9 Pre-cut the raw band | `Step05_CutSlice/` — `cut_slice.py` / `.R` | Python / R |
| 10 Polish the ring | `Step06_PolishSlice/` | CloudCompare, manual |
| *(export the polished ring)* | `Step07_ExportSlicePly/` | CloudCompare CLI |
| 11 Measure, both languages | `Step08_Measure/` — `measure_slice.py` / `.R` + the other seven | Python **and** R |
| 12 Checkpoint | *(manual, no folder)* | manual |
| 13 Analysis | `Step09_Analysis/` | R only |
| 14 Log | `Tree_notes.md` | manual |

Each folder has a README stating what it **takes**, what it **makes**, and what it **feeds**.

This is the complete process, in order, for taking **one scanned tree** from a raw ForestScanner export to a validated diameter. Work **one tree at a time** — that is the quality control. Each step is labelled with the tool you're in: **(CloudCompare)** = interactive, mouse-driven; **(Python)** / **(R)** = run a script; **(manual)** = you, a spreadsheet, and a text editor.

Steps marked **[conditional]** are skipped by most trees — the triage flags in [Step 2](#step-2--cloudcompare-triage-the-tree) decide which ones you do.

**Keep your files wherever you like.** This walkthrough never tells you which folder to use — that's your business, and half these stages are CloudCompare-native `.bin` files that only ever live on your own machine. What it *does* tell you, at every step, is **what that step consumes and what it hands to the next one**. Follow the chain, not a folder layout.

Every step below ends with the same three lines:

- **Takes** — the artifact it needs, and which step produced it
- **Makes** — the artifact it produces
- **Feeds** — the step that consumes it next

**The chain, end to end:**

```
  raw scanner .ply
    │  [1] import                      → working cloud
    │  [2] triage                        (no artifact — sets the flags for 3/4)
    │  [3] fuse  ⟨if needed⟩            → one merged cloud
    │  [4] loop-close  ⟨if needed⟩      → one closed cloud
    │  [5] clean + SOR                  → cleaned trunk
    │  [6] cut to trunk SECTION         → tall section  ──────────┐
    │  [7] export .bin → .ply           → section .ply  ──────────┤ (keep it:
    │  [8] pick site, read Y height       (no artifact — a number  │  step 11b
    │                                      into your sheet)        │  needs it)
    │  [9] cut raw band at that height  → RAW band .ply            │
    │ [10] polish by hand  ⟨recommended⟩ → POLISHED ring .ply      │
    │ [11] measure, Python AND R        → diameters (mm)  ◄────────┘
    │ [12] CHECKPOINT: sheet ready?       (gate — no new artifact)
    │ [13] run the analysis             → results/ CSVs + plots
    │ [14] log anything odd             → your notes
    ▼
```

Two handoffs are easy to get wrong, so they're called out where they happen: the **section** from Step 7 is still needed at Step 11b (lean correction), so don't discard it after cutting the band; and the **raw band** from Step 9 is *not* the thing you measure — Step 10's polished ring is.

---

## Step 1 — (CloudCompare) Import the raw scan

> **Use `.ply`.** Every script in this repo reads PLY (`plyfile` in Python, `Rvcg` in R). **Other point-cloud formats — LAS, LAZ, E57, PCD — haven't been tested here.** If your scanner writes one of those, convert to PLY in CloudCompare before starting; whether the rest of the workflow behaves identically on a converted cloud is untested.

1. `File > Open` → pick the tree's raw `.ply` (keep your scans wherever suits you).
2. If prompted about large coordinates, **accept the global shift** ("Yes to all"). It only recenters the cloud for numerical precision; relative geometry is untouched. **Reuse the same shift across every scan of the same tree** — CloudCompare offers to.
3. Rename the cloud in the DB tree to match the tree's tag, so you don't lose track of it later.
4. Save as CloudCompare `.bin` — this is your working copy. **Treat the raw scans as read-only.** Never edit, move or overwrite one; every later stage writes a new file. They're irreplaceable field captures.

> **Tip:** colour by RGB (`Properties > Colors`) to find the dendrometer band later, or by height to make the buttress zone obvious.

**Takes:** the raw `.ply`, straight off the scanner (ForestScanner in this project's case).
**Makes:** a working CloudCompare `.bin` — your editable copy.
**Feeds:** Step 2 (triage), then Step 3, 4 or 5 depending on the flags.

---

## Step 2 — (CloudCompare) Triage the tree

Record these four flags for the tree before you touch it — they decide which of steps 3–4 you run:

| flag | values | decides |
|---|---|---|
| `cloud_quality` | clean / messy | how much cleaning Step 5 needs |
| `Number_scans` | 1, 2, 3… | 2+ means this tree was captured in multiple passes → Step 3 |
| `needs_fuse` | yes / no | do **Step 3** (multiple clouds to merge) |
| `needs_loopclose` | yes / no | do **Step 4** (one cloud, wrap didn't close) |
| `has_dendrometer` | yes / no | site type in Step 8, and whether it enters validation |

**Fuse ≠ loop-close.** Fuse merges *separate* clouds (a giant scanned in two passes, or track-loss fragments) into one. Loop-close repairs a drift seam *within a single continuous* cloud. Most trees need neither; a few need one; occasionally a tree needs both.

**Scale.** ForestScanner (ARKit) exports are already metrically scaled — no rescaling step is needed or applied anywhere in this pipeline.

**Height datum.** The ground is often not identifiable in these clouds, and heights here are picked coordinates on the cloud's own Y axis rather than true heights above ground. Whatever datum you use, use the same one across every site on a tree and note it.

**Takes:** the working cloud from Step 1 — you're looking at it, not changing it.
**Makes:** the four flags, recorded against this tree. No file.
**Feeds:** the routing decision — Step 3 and/or 4 if flagged, otherwise straight to Step 5.

---

## Step 3 — [conditional] (CloudCompare) Fuse multi-scan trees

*Only if `needs_fuse = yes`* — the tree was too big for one ForestScanner pass, or the scan broke into fragments.

1. Lightly clean each piece first (coarse segment only — keep the **overlap region**; ICP needs shared surface to lock onto).
2. Load all of the tree's scans. Select two: one reference, one "to align".
3. `Tools > Registration > Align (point pairs picking)` — pick **≥ 4 clearly corresponding features** (branch fork, buttress edge, bark scar), well spread out, not clustered. Apply.
4. `Tools > Registration > Fine registration (ICP)`. Set **final overlap** to a realistic % (30–50), random sampling limit ~50k. Run.
5. Check the reported **RMS** — a few mm to ~1–2 cm is good. High RMS means bad correspondences: redo the point pairs.
6. Repeat for scanC, etc., aligning each new scan to the growing merged model.
7. `Edit > Merge`, then `Edit > Subsample` to even out the doubled density in the overlap, then re-run SOR.
8. **Sanity-check the merge before moving on.** A bad merge distorts geometry — look for doubled/ghosted bark surface in the overlap zone, and check the ICP RMS was in the mm–cm range, not worse.

**Takes:** every scan of this tree, from Step 1.
**Makes:** one merged cloud.
**Feeds:** Step 5 (clean). A tree needing both fuse and loop-close goes on to Step 4 first.

---

## Step 4 — [conditional] (CloudCompare) Close the loop on a drift seam

*Only if `needs_loopclose = yes`* — a **single** scan whose circumferential wrap didn't close. Symptom: the trunk looks like a sheet of paper rolled into a cylinder where the two edges don't meet, or the scanner logged "Lost track".

This is **registration, not smoothing** — you're aligning regions that image the same physical bark, so it doesn't bias the measured shape.

**This step is done by hand in CloudCompare.** Like cleaning and fusing, it's a visual judgment call — you have to see the seam to know where it is and whether the two edges genuinely overlap.

1. Top-down view. Locate the seam and **confirm there is real overlap** — two edges imaging the same bark, not just a gap.
2. Segment the overlapping edge flap into its own cloud, leaving the main body.
3. `Tools > Registration > Align (point pairs picking)` on shared bark features to coarse-align the flap to the body.
4. `Tools > Registration > Fine registration (ICP)`, restricted to the overlap.
5. `Edit > Merge`, then subsample to remove the duplicated points in the overlap.

If the seam won't close without a kink, the drift is distributed around the whole loop rather than rigid — flag the tree or re-scan; rigid registration can't recover it.

### Optional scripted assist

`scripts/Unused/loopclose.py` performs steps 3–5 in code, for a reproducible or batchable alternative to hand-picking point pairs. **It does not replace this step** — you still have to find the seam and cut the arc fragments in CloudCompare first, and it must never be pointed at your raw scans (it writes, and they're read-only):

```bash
python scripts/Unused/loopclose.py arcA.ply arcB.ply --tag <tag> \
    --voxel 0.01 --max-corr-dist 0.02 --out-dir stitched
```

It does FPFH-feature RANSAC coarse alignment (so no manual point picking) then point-to-plane ICP with an explicit max correspondence distance. `loopclose.R` is a documented best-effort fallback for a Python-free install — no RANSAC/FPFH coarse step; see its header.

> **Provenance:** every loop-close in the study this repo came out of was done **by hand in CloudCompare**. These scripts are offered as a reproducible alternative and encode a real design lesson (never assume full overlap between a small flap and a near-complete body), but they were **never run** in that study and have not been exercised as the production path on a full dataset — which is why they live in `scripts/Unused/`. Treat them accordingly and check their output.

> **If you use it, read the fitness number rather than accepting the merge.** For a small partial arc you should **expect a low fitness (~0.2–0.3)**, not 1.0. A suspiciously *high* fitness on a small flap means it collapsed onto the wrong surface. Either way, check the merge visually in CloudCompare before continuing.

**Takes:** the single drift-affected cloud from Step 1 (or the merged cloud from Step 3), plus the arc fragments you cut from it by hand.
**Makes:** one closed cloud.
**Feeds:** Step 5 (clean).

---

## Step 5 — (CloudCompare) Clean the trunk — *always*

Coarse manual segmentation first, statistical denoising second. That order matters.

1. Select the cloud → **Segment** tool (scissors icon, `Edit > Segment`, shortcut `T`).
2. Rotate so you're looking side-on at a vertical trunk. Draw a polygon around trunk + buttress, `Enter` to keep the inside, green check to split. You get `.segmented` and `.remaining` — keep the trunk.
3. Rotate 90° and repeat. **A few passes from different angles** cleanly isolates the bole from ground, understory and neighbouring stems.
4. `Tools > Clean > Statistical Outlier Removal (SOR)` — start at **k = 6 neighbours, n_sigma = 1.0**. Loosen (raise sigma) if it eats real trunk points.

> **⚠️ Be conservative with SOR.** Over-denoising erodes the trunk surface and biases every diameter downward. iPhone LiDAR is fairly clean — you rarely need to push it.

5. Only if the cloud is huge and sluggish: `Edit > Subsample > Space` at ~2–5 mm minimum spacing. Never below the detail the circle fit needs. Keep the full-resolution version.

**Takes:** the working cloud from Step 1, or the merged/closed cloud from Step 3 or 4.
**Makes:** the isolated, denoised trunk.
**Feeds:** Step 6 (cut to section).

---

## Step 6 — (CloudCompare) Cut down to the trunk section

Cut the cleaned tree down to just the vertical chunk of bole you'll measure on — a **trunk section**, tall enough to pick a height on, **not** a thin pre-cut ring. (The thin ring comes later, in Step 9.)

Use the Segment tool (`T`) or `Tools > Segmentation > Cross Section`. Save the finished section.

> **The section earns its keep twice.** On a messy cloud it's what makes the height pick possible at all — an isolated, cleaned length of bole with the understory and neighbouring stems already gone. And if the stem leans, this section is exactly what `--axis-ply` needs for lean correction: a **tall** segment, ideally ≥ 2× the trunk diameter in height. Never a thin slice — see [Leaning stems](#leaning-stems).

**Takes:** the cleaned trunk from Step 5.
**Makes:** the **trunk section** — a tall vertical chunk of bole, as CloudCompare `.bin`.
**Feeds:** Step 7 (export to `.ply`). **Keep this file** — Step 11b needs it again for lean correction.

---

## Step 7 — (CloudCompare CLI) Export `.bin` → `.ply`

The fitters cannot read CloudCompare `.bin`. Convert headlessly:

```bash
CloudCompare -SILENT -AUTO_SAVE OFF -O <disc.bin> -C_EXPORT_FMT PLY -SAVE_CLOUDS FILE <disc.ply>
```

**Takes:** the trunk section `.bin` from Step 6.
**Makes:** the same section as `.ply` — the first file the scripts can actually read.
**Feeds:** Step 8 (pick the height on it) and Step 9 (cut the band from it). **Keep it** — Step 11b uses it as the `--axis-ply` reference.

---

## Step 8 — (CloudCompare) Pick the measurement site and read its height

This is the operator judgment call the whole study is built around — and the number you record here drives every script after it.

**Two site modes** (which one you're in is implied by `has_dendrometer`):

- **Over the dendrometer** — colour by RGB, find the band visually, and measure at that exact height so the cloud circumference is directly comparable to the dendrometer's own girth reading. **Cut just above or below the hardware** so the device itself doesn't inflate the circumference.
- **Above the buttress** — for buttressed trees without a dendrometer, rotate the cloud and pick the **lowest height where the buttress flares have merged into a roughly cylindrical bole**. Somewhat arbitrary is fine; just keep your rule consistent across trees and record it.

> **⚠️ Read the height off the Y axis, not Z.** These clouds are Y-up. This is the single most expensive mistake in this project's history — a whole first batch of measurements was made Z-up and had to be discarded.

Record the height (metres) into your sheet's height column for **this** site. (In this project's sheet that's `Y_value_TopFlag` / `Y_value_LowerFlag` / `Y_value_Dendrometer`, one per site — but the column is yours to name; see [What your sheet actually needs](#what-your-sheet-actually-needs).) A tree can have several sites.

**Takes:** the section `.ply` from Step 7.
**Makes:** a **number** — the picked height, written into your sheet. No new file.
**Feeds:** Step 9, which cuts at that height. Repeat Steps 8–11 per site if a tree has more than one.

---

## Step 9 — (Python) Pre-cut a raw band at that height

> **Steps 9, 10 and 11 in one line:** *the machine cuts the band (9), you clean it by hand (10, recommended), then the machine measures it (11).* Nine and ten are not two slicing steps — nine produces a raw band, ten produces a cleaner one. They're separate because **a convex hull is not outlier-robust**: one stray point left in the band becomes a hull vertex and inflates the tape reading. If a band comes out already clean you can measure it as-is, but check it before you trust it.

Cut a thin (~6 cm) band at the height you just picked, so you have something concrete to clean by hand in Step 10. This is `cut_slice.py` (or `cut_slice.R`) — a cutter, not the final number: the diameter it prints is a **ceiling** (a raw band still carries stray points outside the bark, and a convex hull can only shrink once they're removed), so the polished value in Step 11 is always at or below it.

```bash
python  scripts/Step05_CutSlice/cut_slice.py <section.ply> --tree-id <id> --up-axis y \
    --slice-height <Y> --slice-thickness 0.06 --viz-dir <out_dir>
Rscript scripts/Step05_CutSlice/cut_slice.R  <section.ply> --tree-id <id> --up-axis y \
    --slice-height <Y> --slice-thickness 0.06 --viz-dir <out_dir>
```

`--viz-dir` writes the bundle you'll load back into CloudCompare: `*_slice.ply` (the band), `*_ring_*.ply` (fitted circle), `*_hull_*.ply` (tape wrap), `*_slice_fit.png`, `*_measure.txt`.

**Sanity check before moving on:** open `*_slice.ply` and look at it **from directly above**. A correct slice is a **full ~360° ring**. Two side-bands means you sliced the wrong axis — go back and add `--up-axis y`.

Band thickness: thin enough that taper is negligible, thick enough for a stable fit. 2–6 cm is the working range. If the stem **leans**, orient the cut perpendicular to the stem axis rather than horizontal, or you'll cut an ellipse and overestimate — see [leaning stems](#leaning-stems) below.

**Takes:** the section `.ply` from Step 7, plus the height from Step 8.
**Makes:** the **raw band** `.ply` (plus the viz bundle). Machine-cut and still dirty.
**Feeds:** Step 10, which cleans it. Measure this raw band directly only if it's already clean (see Step 10).

---

## Step 10 — [conditional] (CloudCompare) Polish the slice ring — *recommended*

**Strongly recommended, but skippable.** Look at the raw band from directly above. If the ring is already clean — no strays, no vine or neighbouring-stem fragments, no floaters — you can measure it as-is and go straight to Step 11. If anything doesn't belong, polish it:

Open the raw band and **manually remove the stray and non-trunk points**. Re-check the plan view for a clean, closed ring. **Don't over-trim** — concavities and flutes are real stem geometry, not noise.

Save, then export back to `.ply` (Step 7's command).

> **Why this is worth doing even when the band looks passable.** A convex hull is not outlier-robust: one stray point can *be* a hull vertex and inflate the tape reading on its own. `median_polygon_*` exists specifically to route around this, and it does help — but a hand-cleaned ring is the first line of defence, and it's the only one that helps `fit_dab.*` and `dendro_tape.*`, which hull the raw points directly.

**Takes:** the raw band `.ply` from Step 9.
**Makes:** the **polished ring** `.ply` — the file every measurement should see.
**Feeds:** Step 11 (measure), every script, both languages. *(Skipped this step? Step 11 measures the raw band instead — check its `low_confidence` and coverage flags with extra suspicion.)*

---

## Step 11 — (Python **and** R) Measure the polished slice, twice, independently

The core design of this project: **every slice is measured by two implementations that share no code.** They're compared only at the results stage; where they disagree, that's a bug worth finding.

Because the ring is already cut, **omit the height/thickness arguments** — the scripts measure the file as-is.

**Python:**
```bash
python scripts/Step08_Measure/measure_slice.py       <polished_ring.ply> --tree-id <id> --up-axis y --out results/measure_slice_python.csv
python scripts/Step08_Measure/dendro_tape.py         <polished_ring.ply> --tree-id <id> --up-axis y --out results/dendro_tape_python.csv
python scripts/Step08_Measure/median_polygon_10mm.py <polished_ring.ply> --tree-id <id> --up-axis y --out results/median_polygon_python_10mm.csv
python scripts/Step08_Measure/median_polygon_2deg.py <polished_ring.ply> --tree-id <id> --up-axis y --out results/median_polygon_python_2deg.csv
```

**R:**
```bash
Rscript scripts/Step08_Measure/measure_slice.R       <polished_ring.ply> --tree-id <id> --up-axis y --out results/measure_slice_r.csv
Rscript scripts/Step08_Measure/dab_itsme.R           <polished_ring.ply> --tree-id <id> --up-axis y --out results/dab_itsme_results.csv
Rscript scripts/Step08_Measure/dendro_tape.R         <polished_ring.ply> --tree-id <id> --up-axis y --out results/dendro_tape_r.csv
Rscript scripts/Step08_Measure/median_polygon_10mm.R <polished_ring.ply> --tree-id <id> --up-axis y --out results/median_polygon_r_10mm.csv
Rscript scripts/Step08_Measure/median_polygon_2deg.R <polished_ring.ply> --tree-id <id> --up-axis y --out results/median_polygon_r_2deg.csv
```

At minimum you need **`fit_dab.py` + `dab_itsme.R`** — that's the project's core Python/R pair. The `dendro_tape.*` and `median_polygon_*` runs feed the additive hull-method comparison in Step 13.

### [conditional] If the stem leans

*Skip this for a near-vertical stem — a plain horizontal slice is accurate to ~1–2% even at 15° of lean.*

A horizontal slice through a leaning stem cuts an **ellipse**, and an ellipse over-reads. `fit_dab.py` corrects for it by deriving the stem axis and rotating the slice before fitting — but it needs a tall reference to derive that axis from, and **that reference is the trunk section you kept from Step 6**:

```bash
python scripts/Step08_Measure/measure_slice.py <polished_ring.ply> --tree-id <id> --up-axis y \
    --axis-ply <section.ply>
```

> **⚠️ The axis reference must be the tall section, never the thin slice.** If it isn't taller than the trunk is wide, PCA latches onto a *diameter* direction instead of the stem axis and silently corrupts the fit. Rule of thumb: **≥ 2× the trunk diameter in height**. The script warns when `s0/s1` looks too low.

The alternative, decided back at Step 9, is to cut the band **perpendicular to the stem axis** rather than horizontally. Either works; don't do both.

> **⚠️ The height/thickness flags are NOT named the same across languages.** If you *are* cutting on the fly rather than measuring a pre-cut ring:
>
> | script | height flag | thickness flag |
> |---|---|---|
> | `fit_dab.py`, `fit_dab.R`, `dendro_tape.py`, `median_polygon_*.py` | `--slice-height` | `--slice-thickness` |
> | `dendro_tape.R`, `median_polygon_*.R` | `--height` | `--thickness` |
> | `dab_itsme.R` | `--height-z` | `--thickness` |
>
> Also: **`--up-axis` does not default the same way across scripts.** `fit_dab.py`, `fit_dab.R` and `dab_itsme.R` default to **`z`** — the wrong axis for these clouds. `dendro_tape.*` and `median_polygon_*` default to `y`. Pass `--up-axis y` explicitly on every call and the difference can't bite you.

### Batch mode: measure every tree at once

Once heights are recorded for a whole set of trees, all nine measurement scripts can loop over the sheet instead of one invocation per tree:

```bash
python  scripts/Step08_Measure/measure_slice.py --from-sheet --up-axis y
Rscript scripts/Step08_Measure/dab_itsme.R      --from-sheet --up-axis y
```

### What your sheet actually needs

**Bring your own format — don't reshape your data to match ours.** `--from-sheet` needs exactly three things, and you name all three yourself in the `CONFIG` block:

| CONFIG setting | What it points at | Required? |
|---|---|---|
| `TREE_ID_COL` | a column of **labels**, one row per tree — whatever you already call them | **Yes** |
| `HEIGHT_COL` | the picked cut height (m) for this site | Only if cutting on the fly; set it to `None`/`NULL` to measure already-cut, already-polished discs as-is |
| `OUTPUT_COL` | the column the measured diameter (mm) gets written back into | **Yes** |

Plus `SHEET_PATH`, `PLY_FOLDER` and `PLY_FILENAME_PATTERN` so the script can find the sheet and match each row to its `.ply`. That's the whole contract — everything else in the shipped CONFIG defaults is one project's column naming, kept as a worked example, not a required schema.

> **⚠️ The sheet must be an `.xlsx`. Convert before you run.** Both languages read Excel directly — `openpyxl` in Python, `readxl` in R — and there is deliberately no CSV reader: a previous attempt to accept CSVs broke the write-back path. If your records live in a CSV, open it and **Save As `.xlsx`** first. Single-file and `--batch` usage don't touch a sheet at all, so they're unaffected.

Each script has that **`CONFIG` block at the very top** — **that's the one place a researcher with different column names or a different folder layout needs to edit**, never the measurement code. `--from-sheet` reads the tree ID (and, where configured, a picked height) per row, measures each tree with the exact same code the manual CLI path uses, and writes each result both to `--out` and back into the sheet's configured output column.

R's write-back prefers shelling out to `python`/`python3` (override via `SHEET_BATCH_PYTHON`) rather than writing the `.xlsx` directly — see `scripts/sheet_batch.R`'s header for why (a real corruption bug in `openxlsx` was found and worked around during testing). With no Python on PATH it falls back to a direct-R path (`scripts/xlsx_repair.R`) that patches the same corruption after saving — usable from a Python-free RStudio install, at the cost of being the less-exercised of the two paths.

**Takes:** the polished ring `.ply` from Step 10 — and, for lean correction only, the section `.ply` from Step 7.
**Makes:** diameters in mm, written to `--out` CSVs and (in `--from-sheet` mode) back into your sheet.
**Feeds:** Step 12 (record) and Step 13 (analyse).

---

## Step 12 — (manual) Checkpoint: is the sheet ready for analysis?

**This is the boundary between per-tree work and analysis.** Everything before this point happens per tree, in your own folders. Everything after reads one sheet and nothing else.

Stop here and check it, because **Step 13 has two failure modes and only one of them is loud.**

- **A missing column errors out immediately.** The analysis scripts name their columns directly (`Dendrometer_Reading`, `Dendrometer_pythonScript_Diameter_mm`, `has_dendrometer`, `Tree_Tag`, …). If one isn't in the sheet, R stops with "object not found." Annoying, but you'll know.
- **A missing *value* is dropped in silence.** Each script filters to rows that have both a reading and an estimate (`filter(!is.na(reading), !is.na(Python))`). Any row missing either just disappears — no warning — and the metrics are computed over whatever survived. Twelve trees measured but three readings not yet entered gives you a clean-looking summary of nine, and nothing on screen says so.

So the thing to verify is **completeness**, not correctness. Most of it is already filled in; confirm rather than re-enter:

- [ ] **Every column the analysis names actually exists** — see the note below on where those names live.
- [ ] **Field/tape readings** — never written by any script; they're your ground truth, and a row without one silently leaves the comparison.
- [ ] **Diameter columns** — `--from-sheet` wrote these for you, one column per script run. Measured from the CLI instead? Transcribe from your `--out` CSVs now.
- [ ] **Check `n` in the summary output against the number of trees you expect.** This is the cheapest way to catch silent drops.
- [ ] **Picked heights** (Step 8) and **triage flags** (Step 2) — should already be there.
- [ ] **Format is `.xlsx`**, not CSV.
- [ ] *If your project anonymizes* — as the original one did, to keep real identifiers out of a public repo — transcribe into the code-numbered sheet now and point the analysis at that one.

> **⚠️ The analysis scripts' `CONFIG` covers the sheet *path* only — not the column names.** Unlike the measurement scripts, which take `TREE_ID_COL` / `HEIGHT_COL` / `OUTPUT_COL` from CONFIG, the four analysis scripts have their column names, the `has_dendrometer == "Yes"` grouping, the gross-outlier threshold and one specific tree ID written into the code. Reusing them on a differently-shaped sheet means editing the scripts, not just CONFIG. They were written to settle this project's method question rather than as general tools — see the [Script index](#script-index).

> **⚠️ Mind where `--out` writes.** Paths resolve against your shell's current directory, which is easy to get wrong when running repo scripts against data held elsewhere. If your tree labels are sensitive, keep script output out of any git-tracked folder and check `git status` before committing.

**Takes:** the sheet, as Step 11 left it.
**Makes:** nothing new — this is a gate, not a transformation.
**Feeds:** Step 13, which reads this sheet and only this sheet.

---

## Step 13 — (R) Run the analysis

Once every tree is measured and anonymized in:

```bash
Rscript scripts/Step09_Analysis/validate_field_accuracy.R      # core feasibility result -> results/field_accuracy_*
Rscript scripts/Step09_Analysis/compare_hull_methods.R         # true hull vs. median hull -> results/hull_comparison_*
Rscript scripts/Step09_Analysis/plot_error_by_size.R           # all methods on one axis  -> results/error_by_size_* + plots/
Rscript scripts/Step09_Analysis/build_median_hull_2deg_demo.R  # coverage view            -> results/median_hull_2deg_demo_*
```

Run these **from the repo root** — the first three `source()` `scripts/plot_style.R` with a repo-relative path (`build_median_hull_2deg_demo.R` doesn't: it colours by site, not by method, and carries its own scale). All four read **only** the anonymized sheet, so everything they write is anonymization-safe and belongs in the tracked `results/`. Each has a `CONFIG` block at the top for the sheet path (or set `DAB_SHEET` to override without editing).

- `validate_field_accuracy.R` — the core feasibility result. Per-method accuracy (MAPE, bias, RMSE) against field tape/dendrometer readings, in two scopes (`dendrometer_only`, `all_sites`), stratified by whether the site had a real dendrometer band (standard-height stem) or was measured above a buttress.
- `compare_hull_methods.R` — raw convex-hull "tape" vs. the denoised median-polygon hull, against each other and against field reading. Watch the printed **`[Python vs R cross-check]`** lines: they should read 0.000 mm. **A nonzero diff is a real bug** — investigate before trusting either output.
- `plot_error_by_size.R` — the only figure that puts every method on one axis, so you can compare the *shape* of each method's error distribution across the dendrometer-vs-buttress split.
- `build_median_hull_2deg_demo.R` — a coverage view rather than a new accuracy result: the best-scoring method on this dataset applied to *every* processed tree/site, not just the field-validated subset used to pick it.

**Takes:** the populated sheet from Step 12. Nothing else — no `.ply`, no per-tree CSVs.
**Makes:** `results/*.csv` + `results/plots/*.png`.
**Feeds:** Step 14, and your write-up.

> **On the 2° vs. 10 mm result — read it as project-specific.** The two variants came out **virtually identical** on this project's validated subset, with 2° marginally ahead; that's why `build_median_hull_2deg_demo.R` plots the 2° columns. This is a finding about *this* dataset. Because a fixed angular bin and a fixed arc-length bin diverge as trunk size varies, a stand with a different size distribution can easily separate them further, or reverse the order. Treat the choice as one to make on your own data, not one this repo has settled for you.

---

## Step 14 — (manual) Log anything nonstandard

Write any issue → diagnosis → fix into `Tree_notes.md`. That file is the raw material for the methods and limitations sections of the write-up, and it's where the hard-won gotchas below came from. It ships as an empty template — the entries are yours to add.

**Takes:** whatever went sideways on this tree.
**Makes:** one entry in `Tree_notes.md`.
**Feeds:** your methods and limitations write-up. Nothing downstream in the pipeline.

---

## Per-tree checklist

The same 14 steps in tickable form — copy this block per tree. **[conditional]** steps are skipped unless the Step 2 flags say otherwise.

```markdown
Tree: ________   Site(s): TopFlag / LowerFlag / Dendrometer

- [ ]  1. (CloudCompare) Import raw .ply, accept global shift (reuse across scans), save .bin
- [ ]  2. (CloudCompare) Record flags: cloud_quality, Number_scans, needs_fuse,
          needs_loopclose, has_dendrometer
- [ ]  3. [if needs_fuse]      (CloudCompare) Point-pair align -> ICP (check RMS) -> merge -> re-SOR
- [ ]  4. [if needs_loopclose] (CloudCompare) Find the seam, confirm overlap, cut the flap,
          point-pair align -> ICP on the overlap -> merge -> subsample
          (scripts/Unused/loopclose.py can do the register/merge part but was
           never run in this study -- if tried, expect LOW fitness ~0.2-0.3 on a
           small flap, and check the merge visually)
- [ ]  5. (CloudCompare) Segment trunk from several angles + conservative SOR (k=6, sigma=1.0)
- [ ]  6. (CloudCompare) Cut down to the trunk SECTION (tall chunk, not a thin ring)
- [ ]  7. (CloudCompare CLI) Export .bin -> .ply
- [ ]  8. (CloudCompare) Pick the site; read the height off the Y AXIS;
          record into Y_value_<Site> in the sheet
- [ ]  9. (Python or R) Pre-cut the raw band (its diameter is a CEILING, not the result):
          python scripts/Step05_CutSlice/cut_slice.py <section.ply> --tree-id <id> --up-axis y \
              --slice-height <Y> --slice-thickness 0.06 --viz-dir <out_dir>
          Check from directly above: full ~360 deg ring, not two side-bands.
- [ ] 10. [recommended] (CloudCompare) Polish the ring by hand; don't over-trim real
          flutes; export .ply. Skip only if the raw band is already clean.
- [ ] 11. (Python + R) Measure the polished slice, both languages, height args OMITTED:
          python  scripts/Step08_Measure/measure_slice.py <slice.ply> --tree-id <id> --up-axis y --out <csv>
          Rscript scripts/Step08_Measure/dab_itsme.R      <slice.ply> --tree-id <id> --up-axis y --out <csv>
          (+ dendro_tape.* / median_polygon_* if feeding the hull comparison)
- [ ] 11b. [if the stem leans] Add --axis-ply <section.ply> -- the TALL Step 6 section,
           never the thin slice (>= 2x trunk diameter). Skip for near-vertical stems.
- [ ] 12. (manual) CHECKPOINT before analysis. Missing COLUMN = loud R error;
          missing VALUE = row silently dropped from the metrics. Confirm the
          field readings and diameter columns are complete, then sanity-check
          `n` in the summary against the tree count you expect.
          Anonymizing? Transcribe into the code-numbered sheet now.
- [ ] 13. (R) Rscript scripts/Step09_Analysis/validate_field_accuracy.R
          (R) Rscript scripts/Step09_Analysis/compare_hull_methods.R   <- watch the Python-vs-R
              cross-check lines; nonzero = real bug
- [ ] 14. (manual) Log anything nonstandard in Tree_notes.md
```

---

# Reference

## Script index

Every script in the repo, grouped by where it sits in the walkthrough. Paths are relative to `scripts/`; the `Step##_` folder is the processing stage (see the [mapping table](#how-the-14-steps-map-onto-scripts)).

> **Why some steps are dual-language and some aren't.** The **workflow** scripts — everything a person reusing this pipeline actually has to run — exist in **both Python and R**, so a lab with only one of the two can still take a tree all the way through. The **analysis** scripts are **R-only on purpose**: they exist to work out which method this project should adopt, and they aren't part of the reusable workflow. `dab_itsme.R` is R-only for a different reason again — ITSMe is an R package and there is no Python equivalent to port.

### Environment — before you start

| File | Lang | Purpose |
|---|---|---|
| `requirements.txt` | Python | pip dependencies |
| `requirements.lock.txt` | Python | pinned versions, for reproducing an exact environment |
| `requirements.R` | R | installs R dependencies — handles the `lidR`-before-`ITSMe` ordering trap that otherwise fails the build |

### Steps 9 & 11 — measurement (`Step05_CutSlice/`, `Step08_Measure/`)

| Script | Lang | Purpose | Notes |
|---|---|---|---|
| `Step05_CutSlice/cut_slice.py` / `.R` | both | Cut the band `[Y − t/2, Y + t/2]` out of a trunk section at the picked height; write the raw-band viz bundle | Copied from `fit_dab.*` with cutting as its only job (`--slice-height` required). Keeps the fit code so Step 9 prints a number, but that number is a **ceiling** — see its header. `--from-sheet` cuts every tree from the sheet's heights and writes nothing back by default |
| `Step08_Measure/measure_slice.py` / `.R` | both | Least-squares circle **+ convex-hull tape** on an already-polished slice, with coverage/RMS confidence flags | Copied from `fit_dab.*` with the cutting arguments removed — it never cuts. Writes the sheet in **whole mm** to match the field readings; CSV keeps full precision |
| `fit_dab.py` / `fit_dab.R` *(root)* | both | Least-squares circle **+ convex-hull tape**, with coverage/RMS confidence flags | The all-purpose fitter, and the **only** pair that also cuts the band (`--slice-height`) and writes the QC viz bundle (`--viz-dir`) — so it's used twice, at step 9 and step 11 |
| `Step08_Measure/dab_itsme.R` | **R only** | ITSMe median-radius circle **+ concave "functional" diameter** | A genuinely different method, not a port. Concave hull traces *into* flutes where a convex hull bridges them |
| `Step08_Measure/dendro_tape.py` / `.R` | both | Convex hull of the raw slice points — nothing else | Produces the **same number** `fit_dab.*` already reports. Kept deliberately; see below |
| `Step08_Measure/median_polygon_10mm.py` / `.R` | both | Convex hull of a median-radius polygon, fixed **10 mm arc-length** bin | One of two offered variants |
| `Step08_Measure/median_polygon_2deg.py` / `.R` | both | Same method, fixed **2° angular** bin | The other variant — **not** a superseded version |

### Step 11 — batch plumbing

| Script | Lang | Purpose |
|---|---|---|
| `sheet_batch.py` / `sheet_batch.R` | both | Shared `--from-sheet` machinery: read the manifest, write results back into the sheet |
| `xlsx_write_back.py` | Python | Performs the actual `.xlsx` write. `sheet_batch.R` shells out to this whenever Python is on PATH (the preferred path) |
| `xlsx_repair.R` | R | Python-free fallback — patches `openxlsx`'s post-save corruption so write-back works on an R-only install |

### Step 13 — analysis (`Step09_Analysis/`, R-only by design)

| Script | Purpose |
|---|---|
| `Step09_Analysis/validate_field_accuracy.R` | The core feasibility result: every method vs. field reading, two scopes, stratified by measurement type |
| `Step09_Analysis/compare_hull_methods.R` | Raw true hull vs. denoised median hull — against field reading and against each other |
| `Step09_Analysis/plot_error_by_size.R` | The only figure putting all methods on one axis, to compare the *shape* of each error distribution |
| `Step09_Analysis/build_median_hull_2deg_demo.R` | Coverage view: the method applied to every processed site, not just the validated subset |
| `plot_style.R` *(root)* | Shared method labels/colours/shapes, sourced by the first three above so every figure uses one vocabulary |

### `Unused/` — not part of the workflow

> **Nothing in this folder produced a result that was kept. A future user should not run any of it.** Two different reasons, spelled out in [`scripts/Unused/README.md`](scripts/Unused/README.md).

| Script | Verdict |
|---|---|
| `Unused/loopclose.py` | **Never run in this study.** FPFH/RANSAC coarse alignment + point-to-plane ICP, then merge — a scripted alternative to hand-picking point pairs for the loop-close registration sub-step. Cannot cut the flap (that is manual). Wrote nothing: the repo's `stitched/` has only `.gitkeep`, and no `stitched` folder exists in the project's working data |
| `Unused/loopclose.R` | **Never run in this study.** Best-effort port of the above with **no coarse step** (R has no FPFH/RANSAC equivalent) — direct ICP on as-exported coordinates. Weaker; if ever tried, check the merge visually |
| `Unused/disc_dbh_template.R` | ⚠️ **Do not run this. Kept deliberately, as a record.** The earliest prototype — a minimal ITSMe example (`read_tree_pc` → `diameter_slice_pc`) written before this project discovered its clouds are Y-up. **The code itself is not wrong**: `diameter_slice_pc` slices on Z because that is ITSMe's convention, and it is correct for a Z-up cloud. What was wrong was feeding it Y-up data — a usage error that voided an entire first batch of measurements and is the reason every other script here defaults to or demands `--up-axis y`. It is superseded for all real work by `dab_itsme.R`, which calls the same package function and adds the axis swap, the concave functional diameter, batch mode and sheet write-back. Nothing in the repo references it. It is kept because that mistake is part of this project's documented method history — but it is a runnable file with a hardcoded `z_value <- 1.30` and no axis handling, so **someone with Y-up data who runs it gets a plausible-looking wrong number** |

### Redundancy notes

Three things look like duplication and only one of them is:

- **`dendro_tape.*` vs. `fit_dab.*`** — genuinely produces an identical number (confirmed project-wide) and writes to the same sheet column. It is kept on purpose: it's the clean, single-purpose `true_hull` baseline that `compare_hull_methods.R` compares the median-polygon hull against, uncomplicated by a circle fit. **A decision, not an oversight.**
- **`median_polygon_10mm.*` vs. `median_polygon_2deg.*`** — two variants of one method, both first-class. Which one suits a stand depends on its size distribution, and forestry practice varies too much between sites for this repo to pick for you. **Not redundant.**
- **`loopclose.R` vs. `loopclose.py`** — the R port is weaker (no coarse registration), but it's the difference between an R-only lab having the step and not having it. **Not redundant** — though neither was run in this study; both are in `Unused/`.
- **`cut_slice.*` / `measure_slice.*` vs. `fit_dab.*`** — the two new pairs are copies of `fit_dab.*` with different argument surfaces (one cuts, one never cuts); the fit code is identical. `fit_dab.*` stays untouched as the record of what produced the published numbers. Three copies of the fit code is a maintenance cost taken on purpose: a fix to one is not a fix to the others.

## Command reference

Cut one band at a picked height `Y` (metres), 6 cm, from a trunk section:

```bash
# Python or R — convex-hull tape + circle (a CEILING on the raw band), plus a CloudCompare-viewable viz bundle
python  scripts/Step05_CutSlice/cut_slice.py <section.ply> --tree-id <id> --up-axis y \
    --slice-height <Y> --slice-thickness 0.06 --viz-dir <out_dir>

# R — ITSMe circle + concave functional diameter, same band, cut from the same section
Rscript scripts/Step08_Measure/dab_itsme.R <section.ply> --tree-id <id> --up-axis y \
    --height-z <Y> --thickness 0.06 --out results/dab_itsme_results.csv
```

Measure a polished slice (already a thin cross-section) whole:

```bash
python  scripts/Step08_Measure/measure_slice.py <slice.ply> --tree-id <id> --up-axis y --out <csv>
Rscript scripts/Step08_Measure/measure_slice.R  <slice.ply> --tree-id <id> --up-axis y --out <csv>
```

A whole folder of slices: `--batch` (path is a folder, one row per `*.ply`) — supported by `measure_slice.py`/`.R`, `fit_dab.py`/`.R`, `dendro_tape.py`, `median_polygon_*.py`.

### Leaning stems

A horizontal slice through a leaning stem is an **ellipse**, and it overestimates. `fit_dab.py --axis-ply <tall_segment.ply>` estimates the stem axis and rotates the slice before fitting.

> **⚠️ The axis segment must be a TALL trunk segment — never a thin slice.** If it isn't taller than the trunk is wide, PCA latches onto a *diameter* direction instead of the stem axis and silently corrupts the fit. Rule of thumb: **≥ 2× the trunk diameter in height**. The script warns when `s0/s1` looks too low.
>
> For near-vertical stems, skip `--axis-ply` entirely — a plain horizontal slice is accurate to ~1–2% even at 15° of lean.

### Outputs

- **Your working workbook** (e.g. `field_measurements_Anon.xlsx`, outside the repo) — Python & R tape diameters (mm) per location, low-confidence `Flags`, alongside the field `Dendrometer_Reading`. Uses internal code numbers rather than original identifiers.
- **Per-disc viz bundle** (`--viz-dir`): `*_slice.ply` (the measured band), `*_ring_*.ply` (fitted circle), `*_hull_*.ply` (tape wrap), `*_slice_fit.png`, `*_measure.txt`.
- **Median-polygon geometry** (`--poly-dir` on `median_polygon_*.py` / `.R`): the median surface polygon (cyan) and its hull (magenta) as `.ply`, to load in CloudCompare next to the original slice.
- **`results/*.csv` + `results/plots/*.png`** — where the analysis scripts write. **This folder ships empty**: the repo is a toolkit, not a dataset, so it carries no results of its own. Running Step 13 against your own sheet populates it with field accuracy vs. field reading and the hull-method comparison, both size-stratified. Point clouds are never written here (and are gitignored by extension anyway).

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
| Measure distance | Point-pair / ruler tool | — |
| Colour by height (find the buttress top) | `Edit > Scalar fields > Export coord to SF`, then a colour scale | — |

**Two rough in-CloudCompare sanity checks**, useful before you trust a scripted number — neither is an analysis result:
- Select the slice and read its **bounding box** dimensions in `Properties`, or point-pick a couple of diameters by hand.
- `Tools > Fit > Circle` on a slice returns a radius directly; `Tools > Fit > Cylinder` on a taller (~10–20 cm) trunk section returns a radius *and* an axis, and is less sensitive to one bad slice. Then `C = 2πr`, `D = 2r`.

## Gotchas (don't repeat)

- **Y-up**: always `--up-axis y`. A correct slice is a full ~360° ring; two side-bands means the wrong axis. `fit_dab.py`, `fit_dab.R` and `dab_itsme.R` still default to `z` — pass the flag explicitly, every time.
- **Convex hull is not outlier-robust** — a single stray point inflates the tape. Clean slices before fitting (Step 10); `median_polygon_*` is a scripted fix for this specific problem.
- **SOR conservatively** — over-denoising erodes the trunk surface and biases diameter down.
- **Partial rings** (< ~270° coverage) give unreliable fits and are flagged. The convex-hull tape method is **not** valid on partial rings at all.
- **`--axis-ply` needs a tall segment, never a thin slice** — see [Leaning stems](#leaning-stems).
- **The `--from-sheet` manifest must be `.xlsx`.** Both languages read Excel directly (`openpyxl`, `readxl`); there is no CSV reader, and adding one has broken the write-back path before. Convert your records to `.xlsx` before running `--from-sheet`. (Script `--out` files are still CSVs — that's output, not input.)
- **`Unused/loopclose.py` on a small flap should report LOW fitness (~0.2–0.3).** High fitness there means it collapsed onto the wrong surface.
- **The low-confidence RMS flag is miscalibrated for large, rough trunks** — it fires routinely on big buttressed boles that are fine, and doesn't catch every real outlier. Don't treat it as a reliable data-quality signal on large trees without also checking the numbers.
- **`scripts/Unused/disc_dbh_template.R` slices on Z and must not be used to measure anything here.** It's the pre-Y-up prototype, kept deliberately as a record of the mistake that cost a whole first batch — see the [Script index](#unused--not-part-of-the-workflow). Use `dab_itsme.R` instead, which does the same thing correctly for Y-up clouds.
- **Don't conflate the sheet's R columns.** `dab_itsme.R`'s `RScript` columns are a **concave** functional diameter; `dendro_tape.R`'s are a **convex** true hull. Different geometric constructs, different columns.

## Open questions

Carried over from the project's design notes — unresolved, and worth stating plainly rather than leaving implied:

- **Fixed slice thickness, or adaptive by point density?** The pipeline uses a fixed 6 cm band throughout.
- **The measurement-height rule is not standardized.** "Above the buttress" is an operator judgment call. A written rule (e.g. "0.3 m above the visual buttress top") would make it reproducible across operators — at the cost of flexibility on trees that don't fit the rule.
- **Buttress-top detection could be automated** — e.g. from a cross-sectional area or roundness curve against height — removing the judgment call entirely.
- **There is no uncertainty budget.** Scan noise, slice thickness and fit residual all contribute; combining them into per-tree error bars has not been done.
- **The primary metric for publication is still open**: hull circumference vs. best-fit circle. This README recommends the hull (see [What we're actually measuring](#what-were-actually-measuring-read-this-first)), but the argument should be made explicitly in the write-up.
- **Repeatability is untested.** For dendrometer trees the real prize is whether a re-scan recovers the same diameter within the dendrometer's detectable growth increment. That would establish point-cloud *monitoring*, not just one-off measurement — and it needs a second scanning campaign.
