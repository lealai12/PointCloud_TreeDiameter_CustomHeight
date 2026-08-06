# DAB from Point Clouds — Workflow Protocol

**Project:** Feasibility of monitoring tree diameter at a custom, operator-chosen height (e.g. Diameter Above Buttress, DAB) in heavily buttressed tropical trees using mobile-LiDAR point clouds.
**Version:** 0.2 (living document — expand as the workflow evolves)

---

## Software stack

- **CloudCompare** — interactive/visual steps: importing, segmenting, stitching (registration), and slicing.
- **Python** — all numeric analysis: reading clouds, denoising, circle/hull fitting, lean correction, validation, plots. **No R needed** — everything R's forestry packages would give us is covered below.

| Job | Python package |
|---|---|
| Read PLY (and LAS/LAZ if ever exported) | `plyfile`, `laspy` |
| Circle fit, hull perimeter, PCA lean correction | `numpy`, `scipy` |
| SOR denoise, downsample, optional scripted ICP | `open3d` |
| Results table + validation plots | `pandas`, `matplotlib` |

See `scripts/requirements.txt` to install, and `scripts/fit_dab.py` for a runnable fitter.

---

## 0. What we're actually measuring (read this first)

We are **not** measuring diameter directly. From a point cloud we can only measure the **cross-sectional geometry of the trunk** at a chosen height. Our pipeline is:

1. Extract a thin horizontal **slice** of trunk points at the chosen DAB height.
2. Fit a shape to that ring of points to recover **circumference** and an **equivalent diameter**.
3. Report both, because for irregular (fluted/buttressed) tropical trunks, "diameter" is a modeled quantity, not a physical one.

**Two diameter conventions — decide and stay consistent:**

- **Equivalent-circle diameter** `D = C / π`, where `C` is the fitted circumference. This mirrors how a DBH tape works (a tape measures circumference and back-computes diameter). **Recommended for comparison with tape-measured DBH/DAB.**
- **Best-fit-circle diameter** — CloudCompare/least-squares circle fit returns a radius directly. For a perfectly round stem this equals the above; for irregular stems it differs. Useful as a cross-check.

For this project's core metric, report **circumference** as primary and **equivalent-circle diameter** as derived, since that's what matches field tape practice.

**DAB point selection (per this project): per-tree, above the buttress.** For each tree you visually determine the height where the buttress flares merge into a roughly cylindrical bole, and take the slice just above that. Record that height per tree — it is a real data column, not a nuisance.

---

## Per-tree workflow (triage)

The trees are not uniform — route each one through only the steps it needs. First categorize the tree (record the flags in `field_data/field_measurements.csv`), then follow the conditional steplist.

**Categorize (per tree):**

| flag | values | decides |
|---|---|---|
| `cloud_quality` | clean / messy | how much cleaning in step 1 |
| `needs_fuse` | yes / no | do step 2 (multiple clouds to merge) |
| `needs_loopclose` | yes / no | do step 3 (single cloud, wrap didn't close) |
| `has_dendrometer` | yes / no | enters the validation comparison (step "validate") |

**Conditional steplist (per tree):**

1. **Clean point cloud** — always. Segment out non-trunk points, conservative SOR. (§3)
2. **Fuse clouds** — *only if* multiple clouds cover the tree: point-pair align → ICP → merge → re-denoise. (registration; see §5)
3. **Close loop** — *only if* a single cloud's circumferential wrap didn't close (SLAM drift seam): cut the overlap → register → merge. (§3.5)
4. **Select DAB location, clean slice ring, & measure circumference** — always: slice at the selected site, manually remove non-trunk/outlier points from the slice ring, then fit circle + convex-hull perimeter; report circumference and equivalent diameter, and flag low-confidence fits. (§6–§7)

Then **validate** against tape / dendrometer where available (§8). Trees with no field data still produce a DAB estimate; they just don't enter the accuracy comparison.

**Notes**
- **Fuse ≠ close loop.** Fuse merges *separate* clouds (multi-file giants or track-loss fragments) into one. Close loop repairs a seam *within a single continuous* cloud. Usually a tree needs one or the other; occasionally both.
- For multi-cloud (fuse) trees, lightly clean each piece first, fuse, then do a final SOR — step 1 brackets step 2.
- Both fuse and close-loop are **registration** (aligning real overlapping surface), not smoothing — they don't bias the measured shape.

---

## 1. Project setup & file organization

Do this once. A clean folder structure saves you from registration/versioning chaos later.

```
PointCloud_TreeDiameter_CustomHeight/
├── raw_ply/                 # untouched ForestScanner exports (READ ONLY — never edit)
│   ├── tree01_scanA.ply
│   ├── tree01_scanB.ply     # multi-scan giants get scanA/B/C
│   └── ...
├── cleaned/                 # after denoising + segmentation
├── stitched/                # merged multi-scan trees
├── slices/                  # extracted trunk cross-sections
├── results/                 # circle fits, CSV of DAB per tree
├── field_data/             # DBH/DAB tape values, dendrometer IDs, pole heights
│   └── field_measurements.csv
└── DAB_Workflow_Protocol_v0.1.md
```

**Metadata to record now** (`field_data/field_measurements.csv`), one row per tree:

| column | meaning |
|---|---|
| `Tree_Tag` | tree tag / matches the PLY filename stem |
| `Number_scans` | 1 for single-file, 2+ for multi-file giants |
| `cloud_quality` | clean / messy (drives how much cleaning) |
| `needs_fuse` | yes if multiple clouds must be merged (step 2) |
| `needs_loopclose` | yes if a single cloud's wrap didn't close (step 3) |
| `has_dendrometer` | yes / no (enters validation; also implies site type) |
| `Measure_Height` | height (m) of the measurement slice (above base / lower flag) |
| `field_dbh_cm` | tape DBH if measured |
| `field_dab_cm` | tape DAB if measured |
| `field_dab_height_m` | height above ground the tape DAB was taken |
| `pole_mark_height_top_cm` | upper flag height on the pole (cm) |
| `pole_mark_height_low_cm` | lower flag height on the pole (cm); `top − low` should = 100 cm (field-side 1 m check) |
| `Date_time` | scan date (YYYYMMDD) |
| `scale_check_m` | cloud-side measured distance between the two pole flags (should = 1.000 m) |
| `status` | processing state: raw / cleaned / fused / looped / measured / validated |
| `notes` | buttress severity, lean, obstructions, etc. |

This CSV is the ground truth you'll validate the point-cloud DAB against — the whole point of the feasibility study.

---

## 2. Import into CloudCompare

ForestScanner (iOS LiDAR) exports metrically-scaled clouds, so **no rescaling should be needed** — the pole is a *validation* check, not a scaling input (see §4).

1. `File > Open` → select a `.ply` from `raw_ply/`.
2. In the import dialog, if prompted about coordinates being large, **accept the global shift** ("Yes to all"). This just recenters the cloud near the origin for numerical precision; it does not change relative geometry. Keep the shift consistent across scans of the same tree (CloudCompare offers to reuse it).
3. Confirm units: CloudCompare is unitless but ForestScanner data is in **meters**. Sanity check by measuring the pole later.
4. Rename the cloud in the DB tree to match `Tree_Tag` so you don't lose track.

**Tip:** Set the color to a scalar field or RGB (`Properties > Colors`) so you can actually see structure. For cleaning, coloring by height (`Edit > Scalar fields > Export coord to SF > Z`, then a color scale) makes the buttress zone obvious.

---

## 3. Cleaning the point clouds

Goal: remove ground, understory, other stems, and sensor noise so only the target trunk remains. Order matters — do coarse manual segmentation first, then statistical denoising.

### 3.1 Coarse manual segmentation (isolate the trunk)
1. Select the cloud in the DB tree.
2. Activate the **Segment** tool (scissors icon, or `Edit > Segment`, shortcut `T`).
3. Rotate so the trunk is vertical and you're looking side-on. Draw a polygon around the trunk + buttress; press `Enter` to keep the inside (or use the in/out toggle). Press the confirm (green check) to split.
4. You'll get `.segmented` and `.remaining` clouds. Keep the trunk, hide/delete the rest.
5. Rotate 90° and repeat to trim front/back clutter. A few passes from different angles cleanly isolates the bole.

### 3.2 Ground removal
For DAB you don't need the ground, but you need a **ground reference height** to place slices. Two options:
- **Quick:** note the Z of the lowest trunk-base points as local ground ≈ 0, and work in height-above-base. Good enough given per-tree slice selection.
- **Cleaner:** `Tools > Segmentation > Cross Section` or use `Tools > Projection > Cloud/Cloud Dist` against a fitted ground plane. For 20 trees the quick option is usually fine.

### 3.3 Statistical noise removal (SOR)
1. Select the isolated trunk cloud.
2. `Tools > Clean > Statistical Outlier Removal (SOR)`.
3. Start with **k = 6 neighbors**, **n_sigma = 1.0**. Increase `n_sigma` (looser) if it eats real trunk points; decrease (stricter) if noise remains. iPhone LiDAR is fairly clean, so be conservative — you don't want to erode the trunk surface, which biases diameter **downward**.
4. Optionally follow with `Tools > Clean > Noise filter` (radius-based) for stray floaters.

### 3.4 Downsample only if needed
If a cloud is huge and sluggish, `Edit > Subsample > Space` with a **~2–5 mm minimum spacing**. Do **not** downsample below the detail you need for circle fitting. Keep the full-resolution version archived in `cleaned/`.

**Save** each finished trunk to `cleaned/tree01.ply` (`File > Save`, binary PLY).

---

## 3.5 (conditional) Loop-closure fusing — drift-affected trees
**Applies only to trees whose scan lost SLAM tracking** (watch for "Lost track" in the console, or a trunk that looks like a sheet of paper rolled into a cylinder where the two edges don't meet). The circumferential wrap didn't close: the start and end edges image the same bark but are offset by accumulated drift.

This is a **registration** problem, not a smoothing one — we align regions that capture the same physical surface, so it does NOT bias the shape. Sketch of the fix (to be developed with a real problem tree):
1. Top-down view; locate the seam (open gap or two overlapping-but-offset edges) and confirm there is genuine overlap.
2. Segment the overlapping edge flap into its own cloud (leaving the main body).
3. Coarse-align the flap to the body with **Align (point pairs picking)** on shared bark features, then **ICP** restricted to the overlap.
4. Merge, then subsample to remove duplicate points in the overlap.
5. **Validate:** the pole length must still check out and the DAB-slice circle-fit RMS should drop. If the seam won't close without a kink, the drift is distributed around the whole loop (not rigid) → flag the tree / re-scan; rigid fusing can't fully recover it.

TODO: build this out (and decide whether to script it in open3d for batch use) once we work through a real affected tree.

---

## 4. Scale / height validation using the pole

The raised pole carries **two forest-flagging markers exactly 1 m apart**. That fixed 1 m separation is a **known real-world distance** you can measure in the cloud to confirm scale — and it works **even when the ground isn't identifiable** (common in these scans). Use it to prove scale is correct and to catch drift or a bad stitch.

1. Open a cloud that contains the pole (before you segment it away — do this validation early, or keep one un-segmented copy per site).
2. Use the point-pair distance tool (`Tools > Point picking`, or the ruler / point-list picking): pick the **upper flag**, then the **lower flag**.
3. The measured distance should read **1.000 m** within a few mm. Record it as `scale_check_m`.
4. If it's off by more than ~1–2%, investigate before trusting DAB numbers (bad global-shift reuse, scan drift on a long capture, or a partial/duplicated stitch). Re-run this check after any fuse or loop-close.

**Height datum:** the two flags also anchor height. If the ground is visible, the lower flag's height above ground (`pole_mark_height_low_cm`) lets you express `Measure_Height` as true height-above-ground; if the ground is not identifiable, work in height above the **lower flag** instead and note that.

---

## 5. Stitching giant trees (multi-scan registration)

Trees too big for one ForestScanner pass have `scanA`, `scanB`, ... Merge them into one cloud with **coarse alignment → fine ICP**.

### 5.1 Prep
- Clean each scan lightly first (§3.1 coarse segment), but keep enough **overlap region** (shared trunk surface, buttress features) — ICP needs overlap to lock on.
- Load all scans of one tree into the DB tree.

### 5.2 Coarse alignment (manual point pairs)
1. Select the two clouds (one as **reference/"aligned"**, one as **"to align"**).
2. `Tools > Registration > Align (point pairs picking)`.
3. Pick **≥ 4 clearly corresponding features** on both clouds (a branch fork, a buttress edge, a bark scar — anything distinctive). Aim for well-spread points, not clustered.
4. Apply. This gets you roughly overlapped.

### 5.3 Fine alignment (ICP)
1. Select both clouds.
2. `Tools > Registration > Fine registration (ICP)`.
3. Settings: **Final overlap** ≈ realistic overlap % (e.g. 30–50%), enable **random sampling limit** ~50k, leave rotation/translation unconstrained unless you have a reason. Run.
4. Check the reported **RMS** — for good LiDAR trunk overlap you want RMS on the order of a few mm to ~1–2 cm. High RMS means bad correspondences; redo point pairs.
5. Repeat for scanC, etc., aligning each new scan to the growing merged model.

### 5.4 Merge
1. Select all aligned scans → `Edit > Merge` (`Merge multiple clouds`).
2. Optionally `Edit > Subsample` to even out density where scans overlap (overlap doubles point density and can bias fits slightly).
3. Re-run §3.3 SOR on the merged cloud.
4. Save to `stitched/tree01.ply`.

**Validation:** after stitching, re-check the pole/known feature length (§4) on the merged cloud to confirm the merge didn't distort scale.

---

## 6. Selecting the measurement site & extracting the slice

The measurement site is **operator-chosen, per tree** — there is no fixed height. Pick one of two modes (the mode is implied by `has_dendrometer`):

- **Over the dendrometer** (dendrometer trees): locate the dendrometer band visually in the **RGB** cloud and measure at that exact height, so the point-cloud circumference is directly comparable to the dendrometer's own girth reading. Cut the band just above or below the dendrometer hardware so the device itself doesn't inflate the circumference.
- **Above the buttress** (all other trees): rotate the cloud and pick, by judgment, a height where the buttress flares have merged into a roughly round bole. Somewhat arbitrary is fine — just record the height and keep your rule consistent across trees.

Either way, record `Measure_Height` (height above base / lower flag); `has_dendrometer` already captures which mode was used.

**Cut the slice manually** — you segment the band yourself; don't rely on an automatic height:

1. Color by **RGB** (to see the dendrometer) or by height **Z** (to see the buttress top), and rotate to the site.
2. Cut a thin band, ~**2–5 cm** tall — either with the **Segment** tool (`T`; draw a box around the band and keep it) or the **Cross Section** tool (`Tools > Segmentation > Cross Section`, box icon) with the box thickness set to 2–5 cm. Thin enough that taper is negligible, thick enough for a stable fit. For a leaning stem, orient the slice **perpendicular to the stem axis**, not horizontal, or you'll cut an ellipse and overestimate.
3. Export the band as a new cloud → `slices/tree01_slice.ply`.
4. Inspect from directly above (plan view): you want a closed ring. Note any gaps/occlusion — one-sided rings bias circle fits (§7.3).
5. **Manual ring clean-up (before fitting):** re-open/inspect `slices/tree01_slice.ply`, remove obvious non-trunk and outlier points left in the band, then re-check plan view to confirm a clean closed ring while preserving real stem geometry.

Then fit the circumference (§7); `scripts/fit_dab.py` takes this exported slice directly.

---

## 7. Fitting circumference / diameter

Three routes, in increasing rigor. Start with (A) to get moving, move to (C) for the real analysis.

### 7.A Quick in-CloudCompare check
- With the slice selected, look at the **bounding box** dimensions (`Properties`), or use **point picking** to measure a couple of diameters manually. Rough, but a fast sanity value.

### 7.B CloudCompare circle/cylinder fit
- Small vertical trunk section → `Tools > Fit > Circle` (if available in your CC version) gives a radius directly.
- Alternatively `Tools > Fit > Cylinder` on a taller (~10–20 cm) trunk section returns a radius and axis; robust for round-ish boles and less sensitive to a single bad slice. Read radius → `C = 2πr`, `D = 2r`.

### 7.C Python least-squares fit (recommended for the analysis)
Export the slice as PLY/CSV and fit in Claude Code. This gives you circumference, equivalent diameter, residuals (a data-quality metric!), and reproducibility across all your trees. A starter approach:

```python
# fit_dab.py — algebraic (Kåsa) circle fit on a trunk slice, projected to XY
import numpy as np
from plyfile import PlyData

def load_xy(path):
    p = PlyData.read(path)['vertex']
    xyz = np.c_[p['x'], p['y'], p['z']]
    # If the stem leans, rotate xyz so the stem axis = Z before this step.
    return xyz[:, :2]

def fit_circle_kasa(xy):
    x, y = xy[:,0], xy[:,1]
    A = np.c_[x, y, np.ones(len(x))]
    b = x**2 + y**2
    cx, cy, c = np.linalg.lstsq(A, b, rcond=None)[0]
    cx, cy = cx/2, cy/2
    r = np.sqrt(c + cx**2 + cy**2)
    resid = np.hypot(x-cx, y-cy) - r
    return dict(cx=cx, cy=cy, r=r,
                rms_mm=1000*np.sqrt(np.mean(resid**2)),
                circumference_cm=100*2*np.pi*r,
                diameter_cm=100*2*r)

xy = load_xy("slices/tree01_slice.ply")
print(fit_circle_kasa(xy))
```

**Better than a plain circle for buttressed/fluted stems:** compute the **convex-hull perimeter** of the slice points (mimics a tape wrapped around the stem — a tape can't dip into concavities). Report tape-equivalent circumference from the hull, and equivalent diameter `= hull_perimeter / π`. This is often the *most defensible* comparison to field tape DAB.

```python
from scipy.spatial import ConvexHull
def tape_circumference_cm(xy):
    h = ConvexHull(xy)
    per = np.sum(np.linalg.norm(np.diff(xy[h.vertices][np.r_[0:len(h.vertices),0]], axis=0), axis=1))
    return 100*per, 100*per/np.pi   # circumference_cm, equiv_diameter_cm
```

### 7.1 Report per tree
For each tree, log: `Measure_Height`, `n_points_in_slice`, `circle_diameter_cm`, `circle_rms_mm`, `hull_circumference_cm`, `hull_equiv_diameter_cm`.

### 7.2 Handle leaning stems
If a stem leans, a horizontal slice is an ellipse. Before fitting, estimate the stem axis (PCA on a trunk segment, or the ICP/cylinder axis) and rotate the slice so the axis aligns with Z. Then fit in the true cross-sectional plane.

In `fit_dab.py` this is the `--axis-ply` option: export a **tall trunk segment** (taller than the stem is wide) alongside the thin slice, and the script derives the stem axis from it and rotates the slice before fitting:

```
python fit_dab.py slices/tree01_slice.ply --tree-id tree01 --axis-ply slices/tree01_segment.ply
```

**Critical gotcha (verified in testing):** the axis segment must be *taller than the trunk diameter*, or PCA latches onto a diameter direction instead of the stem axis and silently corrupts the fit. Rule of thumb: make the segment ≥ 2× the trunk diameter in height. The script warns (`s0/s1` too low) when the segment looks too short, and the `low_confidence` / `coverage_deg` columns will flag a corrupted result. For near-vertical stems, skip `--axis-ply` — a plain horizontal slice is accurate to ~1–2% even at 15° of lean.

### 7.3 Handle partial rings
One-sided scans give arcs, not full circles. A least-squares circle can still fit an arc but with high uncertainty. Flag any slice with angular coverage < ~270° and treat its diameter as low-confidence. The convex-hull tape method is **not** valid on partial rings — only use it on well-closed slices.

---

## 8. Validation against field data (the feasibility question)

This is the study's payoff. For trees with tape DBH/DAB and/or dendrometers:

1. Match point-cloud DAB to `field_dab_cm` **at the same height** (`field_dab_height_m` vs your `Measure_Height` — align them, or note the offset).
2. Compute error: `residual = pc_diameter − field_diameter`, plus % error and RMS across all matched trees.
3. Plot pc vs. field (1:1 line), and residual vs. buttress severity / scan quality (`circle_rms_mm`, slice coverage). This tells you *when* the method works and when it fails — the actual deliverable of a feasibility study.
4. For dendrometer trees, the value is **repeatability**: if you can re-scan and recover the same DAB within the dendrometer's detectable growth increment, point-cloud monitoring is viable.

---

## 9. Suggested run order for your trees

1. Build `field_measurements.csv` (§1).
2. Import + pole validation on each site (§2, §4).
3. Clean all single-scan trees (§3) → `cleaned/`.
4. Stitch the giants (§5) → `stitched/`.
5. Extract slices above buttress (§6) → `slices/`.
6. Batch-fit in Python (§7.C) → `results/dab_results.csv`.
7. Validate vs. field (§8).

---

## Open questions / to refine in later versions
- Fixed slice thickness vs. adaptive by point density?
- Standardize `Measure_Height` rule (e.g. "0.3 m above visual buttress top") for reproducibility across operators.
- Automate buttress-top detection (e.g. cross-sectional area/roundness vs. height curve).
- Uncertainty budget: scan noise + slice thickness + fit residual → per-tree error bars.
- Decide primary metric for the paper: hull circumference vs. best-fit circle.

---

## Appendix — CloudCompare tool quick reference
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

*Menu wording varies slightly by CloudCompare version; if a path differs, tell me your version and I'll update this table.*
