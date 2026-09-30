# =============================================================================
# plot_style.R -- shared method vocabulary/colour/shape lookup for
# results/plots/*.png, sourced by validate_field_accuracy.R,
# compare_hull_methods.R, plot_error_by_size.R, plot_by_method.R and
# compare_fig_notes.R so a colour and a name mean
# the same thing in every figure. (bin_fixed_angle_demo.R does not
# source this -- it colours by SITE, not by method, and defines its own scale.) Revised 2026-08-02 per the plot-cleanup spec ("one method
# vocabulary everywhere" / "one colour per method, fixed across figures").
#
# Not subject to the "two independent implementations, deliberately kept
# separate" convention the measurement scripts follow -- that convention is
# about the actual measurement pipelines (Python vs R fitting the same tree
# independently, as a correctness cross-check), not about plotting/reporting
# code. Sharing this lookup is plain DRY, not a violation of that convention.
#
# Each script's internal `method` values (its own CSV column names -- left
# untouched by this file) get mapped through METHOD_LABELS to a human-facing
# display label ONLY for use in plot aes()/legends, via relabel_method().
# =============================================================================

suppressMessages(library(ggplot2))

# old, per-script internal method value -> unified display label
METHOD_LABELS <- c(
  ForestScanner            = "ForestScanner (in-app)",
  Python                   = "Convex hull",
  R                        = "ITSMe concave hull",
  true_hull                = "Convex hull",
  Python_true_hull         = "Convex hull",
  bin_hull_FixedAngle     = "Binned hull, fixed angle",
  Python_bin_hull_FixedAngle       = "Binned hull, fixed angle",
  bin_hull_MeanDistanceRadius         = "Binned hull, mean-distance radius",
  Python_bin_hull_MeanDistanceRadius  = "Binned hull, mean-distance radius",
  Circle                   = "Circle fit (least squares)"   # circle_fit.py / .R (Step 6)
)

# canonical legend/plot order -- identical across every figure
METHOD_ORDER <- c("ForestScanner (in-app)", "Convex hull", "Binned hull, fixed angle",
                   "Binned hull, mean-distance radius", "ITSMe concave hull",
                   "Circle fit (least squares)")

# Okabe-Ito colourblind-safe palette, one fixed colour per method
METHOD_COLORS <- c(
  "ForestScanner (in-app)" = "#E69F00",
  "Convex hull"            = "#0072B2",
  "Binned hull, fixed angle"        = "#009E73",
  "Binned hull, mean-distance radius"     = "#CC79A7",
  "ITSMe concave hull"     = "#D55E00",
  "Circle fit (least squares)" = "#000000"
)

# one shape per method too, so overlapping points in scatters are still
# separable without relying on colour/hue alone
METHOD_SHAPES <- c(
  "ForestScanner (in-app)" = 15,  # filled square
  "Convex hull"            = 16,  # filled circle
  "Binned hull, fixed angle"        = 17,  # filled triangle
  "Binned hull, mean-distance radius"     = 18,  # filled diamond
  "ITSMe concave hull"     = 8,   # star
  "Circle fit (least squares)" = 4   # x
)

# Map a vector of a script's internal method values to the unified display
# label, as an ordered factor (unused levels drop out of legends
# automatically -- ggplot's discrete scale default). Anything not found in
# METHOD_LABELS passes through unchanged rather than becoming NA, so a typo
# fails loudly (shows up as a stray, uncoloured legend entry) instead of
# silently dropping points.
relabel_method <- function(x) {
  out <- unname(METHOD_LABELS[x])
  out[is.na(out)] <- x[is.na(out)]
  factor(out, levels = METHOD_ORDER)
}

scale_colour_method <- function(...) scale_colour_manual(values = METHOD_COLORS, breaks = METHOD_ORDER, name = "Method", ...)
scale_fill_method   <- function(...) scale_fill_manual(values = METHOD_COLORS, breaks = METHOD_ORDER, name = "Method", ...)
scale_shape_method  <- function(...) scale_shape_manual(values = METHOD_SHAPES, breaks = METHOD_ORDER, name = "Method", ...)
