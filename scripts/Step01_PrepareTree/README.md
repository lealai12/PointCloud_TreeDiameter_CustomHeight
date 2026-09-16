# Step 01 — Prepare the tree

**Tool:** CloudCompare, by hand. No script.

| | |
|---|---|
| **Takes** | the raw ForestScanner `.ply` export(s) for one tree, from `Raw Data\` (read-only — never edited in place) |
| **Makes** | one usable cloud per tree, saved as `Working\Project_Bins\<tag>.bin` |
| **Feeds** | Step 02 — cut down to the trunk section |

## What happens here

Four things, all in one CloudCompare session, in this order:

1. **Import** — accept CloudCompare's global-shift offer on the first scan and **reuse the same shift for every other scan of that tree**, or later alignments will be off by the shift difference.
2. **Fuse** *(only if `needs_fuse`)* — more than one cloud covers the tree. Clean each piece first, then point-pair align → ICP → merge, then clean again. Keep the shared overlap intact before the merge; ICP needs it to lock on.
3. **Loop-close** *(only if `needs_loopclose`)* — a single scan's circumferential wrap didn't close (a SLAM drift seam). Find the seam, confirm real overlap, cut the flap, point-pair align, ICP on the overlap, merge, subsample.
4. **Clean** — segment out everything that isn't trunk, then a conservative Statistical Outlier Removal. Over-aggressive SOR erodes the bark surface and biases the diameter down.

Every fuse and loop-close in this project was done by hand here. `scripts/Unused/loopclose.py` / `.R` were not used for any of it — see [`../Unused/README.md`](../Unused/README.md).

Sanity-check any merge visually: doubled or ghosted bark in the overlap zone means a bad alignment; the ICP RMS should be in the mm–cm range.

## This project's run (19 trees)

- **Fuse flagged on 5 trees:** 2033, 4092, 4694, 5213, 5926. Only 5213 and 5926 are genuinely two scans (`Number_scans = 2`, fuse RMS 0.087 and 0.078). The other three are single-scan — for them the flag means fusing layers within one capture.
- **Loop-close flagged on 6 trees:** 2683, 4092, 4146, 4524, 180904, 5943. Recorded RMS: 180904 0.019, 2683 0.026, 4524 0.028, 4146 0.033 — and **4092 at 0.203**, roughly six times worse than any other. Worth re-checking.
- **SOR applied to 9 trees:** k=3 sd=1 on 2033, 4092; k=4 sd=1 on 4694, 5027, 5213, 5926, 7163; k=6 sd=1 on 4524; k=6 sd=2 on 2683. The other 10 record `none`.
- **Tree 6740** is marked `1 Bad scan` in the sheet and has no file at any later stage — the pipeline carries 19 trees where the sheet lists 20.
- `Project_Bins\` holds only **14 of 19** trees. That is not missing work: for most trees this whole step was one CloudCompare session and no intermediate was saved before cutting the section (Step 02). The first stage every tree has a file for is Step 02.
