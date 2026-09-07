# DAB per-tree processing checklist

**Moved.** This checklist now lives in the README, as the tickable short form of the full walkthrough:

→ [README.md § Per-tree checklist](README.md#per-tree-checklist)

It was folded in so there is one description of the workflow rather than two that drift apart. The standalone version that used to live here was stale: it recorded into `field_data/field_measurements.csv` (the project now uses `field_measurements_Anon.xlsx`), used a `Measure_Height` column (now the per-site `Y_value_TopFlag` / `Y_value_LowerFlag` / `Y_value_Dendrometer` columns), and its measurement command passed `--dab-height` with no `--up-axis y` — which does **not** cut a band (`--dab-height` only labels the output row; `--slice-height` is the flag that cuts) and would fit on the wrong axis.

This file can be deleted once nothing external links to it.
