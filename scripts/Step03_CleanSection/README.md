# Step 03 — Clean the section

**Tool:** CloudCompare, by hand. No script.

| | |
|---|---|
| **Takes** | `Working\Segment_Disc\<tag>_Disc.bin` from Step 02 |
| **Makes** | `Working\Final_Disc\<tag>_Ready.bin` — the finished section, treated as read-only from here on |
| **Feeds** | Step 04 — export to `.ply` |

## What happens here

A second, closer clean on the section alone: stray points, foliage, anything that isn't bark. Conservative SOR if needed. The section is small now, so it is easier to see what should go than it was on the whole tree.

**And, for some trees, merge.** In this project the Step 03 pass was not only cleaning. Six trees show a real gap (2–20 minutes) between the Step 02 and Step 03 saves. Of those, three got *smaller* (3853, 5213, 5926 — cleaned) and three got *larger*: 2683 (+36 %), 4146 (+25 %), 4524 (+13 %). Those three grew because they were **merged at this stage** — confirmed by the operator. Merging adds points; the sheet records all three as `needs_loopclose = Yes` with a loop-close RMS (0.026, 0.033, 0.028). So the merge for those trees happened here, on the section, rather than on the whole cloud at Step 01.

After any merge, **subsample** the result to remove the duplicated points in the overlap zone. That does not appear to have been done on 2683, 4146 or 4524.

## This project's run

- **19 of 19** trees have a `Final_Disc` file.
