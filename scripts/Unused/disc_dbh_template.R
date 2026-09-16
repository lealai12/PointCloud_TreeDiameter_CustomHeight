# ------------------------------------------------------------------
# Barebones template: DBH from a segmented disc using the ITSMe package
# ------------------------------------------------------------------
# Workflow: in CloudCompare you segmented a disc from the tree and
# exported it (e.g. as a .txt/.xyz with X Y Z columns, or .ply).
# You pick a Z value (height) and fit a circle to a thin slice there
# to get the diameter.
# ------------------------------------------------------------------

# install.packages("remotes")
# remotes::install_github("lmterryn/ITSMe")   # ITSMe = Individual Tree Structural Measurements
library(ITSMe)

# ---- 1. Inputs -----------------------------------------------------
disc_path       <- "path/to/your_disc.txt"  # exported disc from CloudCompare
z_value         <- 1.30                       # height (m) you select
slice_thickness <- 0.06                       # m; slice is z_value +/- thickness/2

# ---- 2. Read the disc point cloud ---------------------------------
# read_tree_pc expects X Y Z (first 3 columns). samplefactor = 1 keeps all points.
pc <- read_tree_pc(path = disc_path, samplefactor = 1)

# ---- 3. Fit a circle to the slice at the chosen Z -----------------
# diameter_slice_pc extracts points within [z - thickness/2, z + thickness/2]
# and fits a circle. functional = FALSE uses a normal least-squares circle fit.
res <- diameter_slice_pc(pc            = pc,
                         slice_height    = z_value,
                         slice_thickness = slice_thickness,
                         functional      = FALSE,
                         plot            = TRUE)   # TRUE = show the fitted circle

# ---- 4. Result -----------------------------------------------------
dbh <- res$diameter          # diameter (m) at the selected Z
cat("Diameter at z =", z_value, "m:", round(dbh, 4), "m",
    "(", round(dbh * 100, 2), "cm )\n")
# res also contains: $residual (fit quality), $center, etc.
