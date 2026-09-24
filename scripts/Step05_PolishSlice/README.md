# Step 06 — Polish the slice ring

**Tool:** CloudCompare, by hand. No script.

| | |
|---|---|
| **Takes** | the raw band from Step 05 (`Cut_Slices_to_polish\<tag>__<Site>\<tag>__<Site>_slice.ply`) |
| **Makes** | `Working\Polished_Slices\<tag>_<Site>_slice.bin` |
| **Feeds** | Step 07 — export to `.ply` |

## What happens here

Look at the band from directly above (along Z axis for most clouds, y axis if scanned by CloudCompare). It should be a single closed ring. Remove everything that isn't the bark surface: stray points inside or outside the ring, bits of foliage or lichen, ghost points from the scan. Save as `.bin`.

## Not optional in practice

The workflow docs call this step "optional but highly recommended". The numbers say do it every time:

- Polishing changed the hull reading on **28 of 32** sites — median shift −37.9 mm of equivalent diameter, maximum −247.0 mm.
- **24 of 32** shifted by more than the 18 mm error floor in this project's report.
- Only four bands were clean enough that skipping would have made no difference: `180904__Dendrometer`, `2033__TopFlag`, `3031__Dendrometer`, `4092__TopFlag`. The script's `low_confidence` flag does **not** identify them — tree 3853 reads `True` both before and after polishing.

There is no way to know in advance which four they will be, so polish all of them.

## This project's run

- **32 of 32** rings polished.
