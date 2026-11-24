#!/usr/bin/env python
"""
run_measure.py -- run any or all of the Python step 6 measure scripts, at any
or all sites, from one place.

Pick the methods, sites and percentiles in the CONFIG block below, then run:

    python scripts/Step06_Measure/run_measure.py

Each method runs in --from-sheet mode, once per site (and, for the binned
hulls, once per percentile). The site and the sheet columns are passed to the
script on the command line (--site, --output-col, --flag-col, --height-col),
so no script file is changed. Each script still reads everything else (the
sheet path, the slice folder, the file name pattern) from its own CONFIG.

This runs the Python scripts only. run_measure.R is its twin for the R
scripts. They are written separately and share nothing, so a lab with only
one language can use the one it has.

Before anything runs, every sheet column the jobs will write into is checked.
A job whose column is missing is skipped and listed, rather than measuring
every slice and then failing at the write.
"""
import os
import subprocess
import sys

# =============================================================================
# CONFIG -- choose what to run.
# =============================================================================
METHODS = [                      # delete any you don't want
    "dendro_tape",
    "dab_itsme_concave_hull",
    "bin_fixed_angle",
    "bin_mean_distance_radius",
    "circle_fit",
]
SITES = ["Dendrometer", "TopFlag", "LowerFlag", "ForestGeoPaint", "DendroPaint"]
PERCENTILES = [50, 90]           # binned hulls only. Every value needs an entry in PERCENTILE_TAG.

DRY_RUN = False                  # True = print each command and the column check, run nothing
SHOW_SKIPS = False               # True = list every tree a script skipped. A skip is usually a
                                 # tree with no slice or no picked height at that site.

# The sheet the measure scripts write into. Used here only to check the columns
# exist before running. It must match SHEET_PATH in the measure scripts' CONFIG.
SHEET_PATH = "C:/Projects/LiDAR_Project/Working_Steps/field_measurements_Draft2_Working.xlsx"
SHEET_NAME = 0                   # tab name or 0-based index, as in the measure scripts

# Where each script's results CSV goes. The CSVs are appended to, not
# replaced, so a second run adds its rows below the first.
OUT_DIR = "C:/Projects/LiDAR_Project/Working_Steps/6_Measure"
VIZ_DIR = None                   # dendro_tape only: a folder for the per-slice pictures, or None

UP_AXIS = "y"                    # ForestScanner clouds are Y-up

# ---- sheet column names ----
# How each column is named. {site} is the site, {lang} is "pythonScript".
# The binned hulls add a percentile tag after the method: the 90th has none
# (those columns came first) and the 50th has "P50".
PERCENTILE_TAG = {90: "", 50: "P50"}
COLUMNS = {
    "dendro_tape":              ("{site}_DendroTape_{lang}_Diameter_mm",
                                 "{site}_DendroTape_MaxEdgeFrac"),
    "dab_itsme_concave_hull":   ("{site}_DabItsme_ConcaveHull_{lang}_Diameter_mm", None),
    "bin_fixed_angle":          ("{site}_BinFixedAngle{tag}_{lang}_Diameter_mm",
                                 "{site}_BinFixedAngle{tag}_MaxEdgeFrac"),
    "bin_mean_distance_radius": ("{site}_BinMeanDistanceRadius{tag}_{lang}_Diameter_mm",
                                 "{site}_BinMeanDistanceRadius{tag}_MaxEdgeFrac"),
    "circle_fit":               ("{site}_CircleFit_{lang}_Diameter_mm", None),
}
LANG = "pythonScript"
# ITSMe re-cuts its band from the picked height, so it also needs the height
# column. It is Y_value_<site>, except for the two paint sites, whose headers
# are named this way in this project's sheet.
HEIGHT_COLS = {"ForestGeoPaint": "Y_value_ForestGeoPaint (Red)",
               "DendroPaint": "Y_value_DendroPaint (Blue)"}
BINNED = {"bin_fixed_angle", "bin_mean_distance_radius"}
# =============================================================================

HERE = os.path.dirname(os.path.abspath(__file__))


def build_jobs():
    jobs = []
    for method in METHODS:
        if method not in COLUMNS:
            sys.exit(f"Unknown method {method!r}. Choose from: {', '.join(COLUMNS)}")
        pcts = PERCENTILES if method in BINNED else [None]
        for pct in pcts:
            if pct is not None and pct not in PERCENTILE_TAG:
                sys.exit(f"Percentile {pct} has no entry in PERCENTILE_TAG, so its columns have no name.")
            tag = PERCENTILE_TAG[pct] if pct is not None else ""
            for site in SITES:
                out_pat, flag_pat = COLUMNS[method]
                fill = dict(site=site, tag=tag, lang=LANG)
                cols = {"--output-col": out_pat.format(**fill)}
                if flag_pat:
                    cols["--flag-col"] = flag_pat.format(**fill)
                if method == "dab_itsme_concave_hull":
                    cols["--height-col"] = HEIGHT_COLS.get(site, f"Y_value_{site}")
                csv_name = f"{method}_python{'_' + tag.lower() if tag else ''}.csv"
                cmd = [sys.executable, os.path.join(HERE, f"{method}.py"),
                       "--from-sheet", "--up-axis", UP_AXIS, "--site", site,
                       "--out", os.path.join(OUT_DIR, csv_name)]
                for flag, col in cols.items():
                    cmd += [flag, col]
                if pct is not None:
                    cmd += ["--percentile", str(pct)]
                if method == "dendro_tape" and VIZ_DIR:
                    cmd += ["--viz-dir", VIZ_DIR]
                label = f"{method}{' P' + str(pct) if pct is not None else ''}"
                jobs.append(dict(label=label, site=site, cmd=cmd, cols=list(cols.values())))
    return jobs


def sheet_headers():
    import openpyxl
    wb = openpyxl.load_workbook(SHEET_PATH, read_only=True)
    ws = wb[SHEET_NAME] if isinstance(SHEET_NAME, str) else wb.worksheets[SHEET_NAME]
    headers = {c.value for c in next(ws.iter_rows(max_row=1)) if c.value is not None}
    wb.close()
    return headers


def main():
    jobs = build_jobs()
    headers = sheet_headers()
    ready, missing = [], []
    for j in jobs:
        gone = [c for c in j["cols"] if c not in headers]
        (missing if gone else ready).append((j, gone))
    print(f"{len(jobs)} jobs: {len(ready)} ready, {len(missing)} with a missing sheet column.")
    for j, gone in missing:
        print(f"  [no column] {j['label']} at {j['site']}: {', '.join(gone)}")

    results = []
    for j, _ in ready:
        print(f"\n===== {j['label']}  {j['site']}")
        if DRY_RUN:
            print(" ".join(f'"{a}"' if " " in a else a for a in j["cmd"]))
            continue
        os.makedirs(OUT_DIR, exist_ok=True)
        r = subprocess.run(j["cmd"], capture_output=True, text=True)
        lines = (r.stdout + r.stderr).splitlines()
        wrote = [l for l in lines if l.startswith("Wrote ") and "value(s)" in l]
        skips = [l for l in lines if l.startswith("[skip]")]
        flags = [l for l in lines if l.startswith("[flagged]")]
        # the first "Wrote N value(s)" line is the diameter column
        n_done = int(wrote[0].split()[1]) if wrote else 0
        print(f"  measured {n_done}, skipped {len(skips)}, flagged {len(flags)}")
        for l in (skips if SHOW_SKIPS else []) + flags:
            print("  " + l)
        if r.returncode != 0:
            print("  -- failed, last lines of output:")
            for l in lines[-15:]:
                print("     " + l)
        results.append((j, r.returncode, n_done, len(skips), len(flags)))

    if DRY_RUN:
        print("\nDRY_RUN is on: nothing was run.")
        return
    print("\n===== summary")
    print(f"{'method':<30} {'site':<15} {'result':<8} {'measured':>8} {'skipped':>7} {'flagged':>7}")
    for j, rc, n_done, n_skip, n_flag in results:
        print(f"{j['label']:<30} {j['site']:<15} {'ok' if rc == 0 else 'FAILED':<8} "
              f"{n_done:>8} {n_skip:>7} {n_flag:>7}")
    for j, gone in missing:
        print(f"{j['label']:<30} {j['site']:<15} {'no col':<8}")
    n_bad = sum(rc != 0 for _, rc, _, _, _ in results) + len(missing)
    sys.exit(1 if n_bad else 0)


if __name__ == "__main__":
    main()
