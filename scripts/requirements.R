# DAB point-cloud analysis — R dependencies
# Install:  Rscript scripts/requirements.R
#
# Package -> script(s) that use it:
#   readxl              validate_field_accuracy.R, compare_hull_methods.R, sheet_batch.R (read the manifest sheet)
#   dplyr, tidyr         validate_field_accuracy.R, compare_hull_methods.R (analysis pipelines)
#   ggplot2, scales      validate_field_accuracy.R, compare_hull_methods.R, plot_style.R (all results/plots/*.png)
#   Rvcg                 dendro_tape.R, median_polygon.R, median_polygon_2deg.R (PLY reader)
#   ITSMe (+ lidR, Rcpp, RcppEigen, RcppArmadillo)   dab_itsme.R only
#   openxlsx, xml2, zip   xlsx_repair.R -- only used for --from-sheet's spreadsheet
#                         WRITE step, and only as a fallback when no Python
#                         interpreter is on PATH (the default write path shells
#                         out to Python's openpyxl instead; see
#                         scripts/sheet_batch.R's header for why). Installed
#                         here regardless so the fallback works out of the box
#                         on a Python-less machine.

install.packages(c("readxl", "dplyr", "tidyr", "ggplot2", "scales", "Rvcg", "remotes",
                    "openxlsx", "xml2", "zip"),
                 repos = "https://cloud.r-project.org")

# Gotcha: lidR is currently archived on CRAN -- install the prebuilt binary
# from the maintainer's R-universe BEFORE installing ITSMe, or the ITSMe
# build fails.
install.packages("lidR", repos = c("https://r-lidar.r-universe.dev", "https://cloud.r-project.org"))

remotes::install_github("lmterryn/ITSMe")   # also needs Rvcg, already installed above

cat("\nDone. Verify with:\n",
    '  Rscript -e \'sapply(c("readxl","dplyr","tidyr","ggplot2","scales","Rvcg","lidR","ITSMe","openxlsx","xml2","zip"), requireNamespace, quietly=TRUE)\'\n',
    sep = "")
