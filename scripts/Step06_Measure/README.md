# Step 06 — Measure

Tools: Python and R, run independently. Eight scripts in this folder.

Note: Input is the polished ring from Step 5, Working_Steps\5_PolishedSlices\<tag>__<Site>.ply. Output CSVs and pictures go to Working_Steps\6_Measure\.

The methods, and the sheet column each one writes:
- dendro_tape.py / .R: convex hull of the raw points, the taut-tape reading. <Site>_DendroTape_{pythonScript,RScript}_Diameter_mm
- dab_itsme_concave_hull.R / .py: ITSMe circle fit plus concave hull, which dips into grooves where a tape would bridge them. The .R runs the ITSMe package, and the .py is a Python port of the same method. <Site>_DabItsme_ConcaveHull_{RScript,pythonScript}_Diameter_mm
- bin_fixed_angle.py / .R: convex hull of a binned polygon, one wedge every 2°. <Site>_BinFixedAngle_{pythonScript,RScript}_Diameter_mm
- bin_mean_distance_radius.py / .R: the same, but each wedge spans a fixed ~10 mm of bark. <Site>_BinMeanDistanceRadius_{pythonScript,RScript}_Diameter_mm

The binned scripts take the 90th percentile radius in each wedge, not the median, since the median cuts inside the bark. PERCENTILE and MIN_POINTS_PER_BIN are set in CONFIG.

Steps:
1. In each script's CONFIG, set SITE_LABEL and the site prefix on OUTPUT_COL and FLAG_COL for the site you are running. For dab_itsme_concave_hull.R and .py, also set HEIGHT_COL to that site's Y_value column.
2. Run every script from the repo root:

    python  scripts/Step06_Measure/dendro_tape.py                --from-sheet --up-axis y
    Rscript scripts/Step06_Measure/dendro_tape.R                 --from-sheet --up-axis y
    Rscript scripts/Step06_Measure/dab_itsme_concave_hull.R      --from-sheet --up-axis y
    python  scripts/Step06_Measure/dab_itsme_concave_hull.py     --from-sheet --up-axis y
    python  scripts/Step06_Measure/bin_fixed_angle.py            --from-sheet --up-axis y
    Rscript scripts/Step06_Measure/bin_fixed_angle.R             --from-sheet --up-axis y
    python  scripts/Step06_Measure/bin_mean_distance_radius.py   --from-sheet --up-axis y
    Rscript scripts/Step06_Measure/bin_mean_distance_radius.R    --from-sheet --up-axis y

3. Repeat steps 1 and 2 for each site: TopFlag, LowerFlag, PaintMarker, Dendrometer.
4. Check the <Site>_<Method>_MaxEdgeFrac columns. For anything over 0.5, open the ring's picture and decide whether it is a real gap in the scan or a flute the tape would bridge anyway.

Note: The gap check flags, it doesn't block. Every ring gets a diameter, and MaxEdgeFrac records the longest hull edge as a fraction of the diameter. A flagged ring is drawn with its long edge in magenta, labelled PARTIAL RING. The sheet value is rounded to 3 decimals, and the scripts decide on the unrounded value, so a flagged ring can read exactly 0.500 in the sheet (two do on the second pass). A > 0.5 filter would keep them.

Note: ITSMe underestimates on incomplete scans. Where an arc is missing, the concave hull cuts inward into the gap, while the convex hull bridges it the way a tape does. This is a strength of the convex-hull method.

Note: ITSMe also re-cuts its own band from the sheet height, even though the polished ring is already cut. That second cut loses a few points sitting right on the band edge to rounding: 2 of 195,304 on 5926__LowerFlag and 4 of 180,236 on 2033__TopFlag. The other scripts measure the polished ring whole and lost none across all 41 slices. The loss is far too small to move a diameter, but it means the ring you polish is exactly the ring this method measures, and not quite the ring ITSMe measures.

Note: ITSMe has no Python package, so dab_itsme_concave_hull.py re-implements what ITSMe's diameter_slice_pc() does, including the concaveman concave hull ITSMe calls. On all 41 second-pass slices it matches the R run exactly on the circle fit, and to within 0.1 mm on the concave-hull diameter, where an occasional point rounds the other way. It is slower, about 30 seconds a slice.

Note: Diameters are written to the sheet in whole mm, except ITSMe (both versions), which writes tenths of a mm. The CSVs keep full precision.

Note: The Python and R twins should agree exactly, since a convex hull has one answer. Any difference is a bug. The R binned scripts have no --batch mode, so use --from-sheet or loop over the files.

Kept as the record: fit_dab.py and fit_dab.R at the scripts/ root are the untouched originals cut_slice was copied from. measure_slice.py and .R, which measured the first pass, are retired to Unused/.


This project's run:
- First pass: 32 of 32 tree-sites measured.
- Second pass: 41 of 41 tree-sites measured by all six dendro_tape and binned scripts, Python and R identical on every one.
