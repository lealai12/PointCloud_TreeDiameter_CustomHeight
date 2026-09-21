# Step 03 — Clean the section

Tools: CloudCompare or other Point Cloud Interface



Steps:
1. Use CloudCompare interface so that scans are viewed from directly above/below (along Z axis for most clouds, y axis if collected from ForestScanner).
2. Use the "Segment" tool to clean points in the cloud that are not actually a part of the tree
3. Save entity as .ply file
4. Create .xlsx file containing columns for Tree Identifier and CloudCompare height of measurement. Configure script config headers to match.

Optional Steps: If fusing an overlap, merging two incomplete stems, or point cleaning by Statistical Outlier Filter (SOR). Repeat steps 1-3 after optional steps. 


Batch Processing:

Note: If batch processing, make sure that the correct cleaned segments are referenced by the spreadsheet. Having some trees that require optional steps and others that don't may require an additional organization of files to ensure that the correct segments are processed.

Fusing an overlap:
3a. Use the "Segment" tool to cut the section that is overlapping the other, without including the main underlapping area.
4a. Use the "Align" Tool to orient the newly cut section to the existing tree.
5a. Drag the section to overlap target area.
6a. Select the "Finely registers (roughly) aligned entities (clouds or meshes)" tool to visualize scans' overlap.
7a. Use the "Merge multiple clouds" Tool to fuse the overlapping section to the tree
8a. Subsample the fused cloud to remove the duplicated points in the overlap zone to prevent density inconsistencies within the overlap.

Merging multiple scans:
3b. Bring the scans next to each other
4b. Identify multiple locations that in both scans that will be used as stitching reference points for the fusion, preferably as close as possible to the gap site. Recommend using at least one point on opposite side of stem to ensure correct orientation
5b. Use "Align" Tool to orient the scans to each other
6b. Drag the scans to overlap each other.
7b. Select the "Finely registers (roughly) aligned entities (clouds or meshes)" tool to visualize scans' overlap.
8b. Use "Merge multiple clouds" Tool to merge the overlapping scans. 
9b. Check the merge: view the overlap zone from above. Doubled or ghosted bark means the alignment is off — go back to 5b. The ICP RMS reported in 7b should be in the mm–cm range.
10b. Subsample the merged cloud to remove the duplicated points in the overlap zone.


Alternatively, a section can be cut using the "segment" tool from one tree and stitched to the other using the "merge multiple clouds" tool. This is preferred if one scan is far superior overall to the other.




To clean cloud automatically by removing statistical outliers (SOR):
3c. Select SOR tool in CloudCompare
4c. Choose number of points to use for mean distance estimation and the standard deviation multiplier threshold. May take multiple tries to remove noise without removing legitimate stem area.
5c. Be conservative. Over-aggressive SOR erodes the bark surface and biases the diameter down. When in doubt, use a larger standard deviation multiplier and clean the rest by hand with "Segment".