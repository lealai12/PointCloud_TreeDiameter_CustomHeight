# Step 05 — Polish the slice ring

Tools: CloudCompare or other Point Cloud Interface

Note: Input is the raw band from Step 4, Working_Steps\4_CutSlices\<tag>__<Site>\<tag>__<Site>_slice.ply

Steps:
1. Open the raw slice and view it from directly above (along Z axis for most clouds, y axis if collected from ForestScanner). It should be a single closed ring.
2. Use the "Segment" tool to remove everything that isn't the bark surface: stray points inside or outside the ring, foliage, lichen, neighbouring stems and ghost points from the scan.
3. Don't trim real flutes. The tape bridges them, so they belong in the ring.
4. Save as .ply into Working_Steps\5_PolishedSlices\, named <tag>__<Site>.ply (double underscore, no CloudCompare suffix). Step 6 finds its input by exactly that name.

Tip: The slice keeps the scan's colours, so bark is easy to tell apart from debris. Untick Colors in the Properties panel to switch to plain grey and back.

Note: This step is not optional in practice. On the first pass, polishing changed the hull reading on 28 of 32 sites, a median shift of −37.9 mm of equivalent diameter and a maximum of −247.0 mm. 24 of 32 shifted by more than the 18 mm error floor in this project's report. Only four bands were clean enough to skip (180904__Dendrometer, 2033__TopFlag, 3031__Dendrometer, 4092__TopFlag), and the script's low_confidence flag did not identify them. There is no way to know in advance which ones they will be, so polish all of them.


This project's run:
- First pass: 32 of 32 rings polished.
- Second pass: 41 of 41 rings polished.
