# DAB Workflow Protocol — RETIRED

**This document has been retired (2026-09-04). Do not follow it.** Its content is superseded by the README, which is the single source of truth for the workflow:

→ [README.md](README.md) — the 14-step walkthrough, the per-tree checklist, and the script index.

## Why it was retired

It was the **oldest** generation of this project's documentation, and it contradicted the working pipeline in three ways that would actively mislead someone following it:

| This document said | Reality |
|---|---|
| "**No R needed** — everything R's forestry packages would give us is covered below," with a Python-only software stack | The project's core design is **two independent language implementations**; `dab_itsme.R` plus four other R/Python pairs |
| Fitting code projected to **XY** and instructed "rotate xyz so the stem axis = **Z**" | ForestScanner clouds are **Y-up**. This exact assumption voided an entire first batch of measurements |
| Cut a **2–5 cm** band, single pass | **6 cm** (`--slice-thickness 0.06`), and a **two-pass** cut → hand-polish → re-measure workflow |

It also had no mention of `dendro_tape.*`, `median_polygon_*`, `--from-sheet`, the polished-slice stage, or the measurements sheet, and its loop-close section still ended in "TODO: build this out."

## What was preserved

Everything of lasting value was migrated into the README before retirement:

- **The "what we're actually measuring" argument** — that diameter is a modeled quantity and circumference is the real measurement, plus the two diameter conventions and why equivalent-circle `C/π` matches tape practice → README, *What we're actually measuring*
- **The CloudCompare menu/tool quick reference**, and the two rough in-CloudCompare sanity checks → README, *CloudCompare quick reference*
- **The open questions** — slice thickness, standardizing the height rule, automating buttress-top detection, the uncertainty budget, the primary-metric decision, and the untested repeatability question → README, *Open questions*

The procedural half was not migrated: the README's walkthrough already covers it, correctly and against the current scripts.

*This file can be deleted once nothing external links to it.*
