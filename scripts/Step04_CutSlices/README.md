# Step 04 — Cut the slices

Tools: cut_slice.py (Python) or cut_slice.R (R), and CloudCompare to pick the heights

Note: Input is the cleaned segment from Step 3, Working_Steps\3_CleanedSegments_Final\<tag>_CleanedSegment.ply

Steps:
1. Open the cleaned segment in CloudCompare and pick the measurement height for each site: over the dendrometer band or paint marker, or the lowest point where the trunk reads as roughly cylindrical above the buttress.
2. Read the height off the Y axis (ForestScanner clouds are Y-up) and record it in the sheet's Y_value_<Site> column.
3. Cut every recorded height at once, from the repo root:

    python  scripts/Step04_CutSlices/cut_slice.py --from-sheet --up-axis y
    Rscript scripts/Step04_CutSlices/cut_slice.R  --from-sheet --up-axis y

4. Check each slice from directly above. It should be a single full ring. Two separate bands means the wrong axis was used.

Output goes to Working_Steps\4_CutSlices\<tag>__<Site>\ : the slice cloud (in the scan's own colours), a fit picture, the circle and hull overlays, and measure.txt. It also writes cut_slices_python.csv and the <Site>_CutSlice_pythonScript_Diameter_mm column.

Note: The diameter written here is a ceiling, not the result. The raw band still has stray points in it, and the hull can only get smaller once they are removed in Step 5.

To cut a single slice instead:

    python scripts/Step04_CutSlices/cut_slice.py <section.ply> --tree-id <tag>__<Site> --up-axis y --slice-height <Y> --slice-thickness 0.06 --viz-dir <folder>


Converting a legacy .bin (not part of this workflow, everything here is already .ply):

    CloudCompare -SILENT -AUTO_SAVE OFF -O <in.bin> -C_EXPORT_FMT PLY -SAVE_CLOUDS FILE <out.ply>

Keep -AUTO_SAVE OFF, otherwise CloudCompare also writes an extra copy next to the input.


This project's run:
- First pass: 19 of 19 sections exported to .ply for cutting.
- Second pass: 41 tree-sites cut, 0 failures, every ring closed.
- Paint sources: 4 new slices cut for 6647 and 3853, one at each red and blue mark. The other 15 paint sites were at the same height as the old PaintMarker site, so those slices were reused.
