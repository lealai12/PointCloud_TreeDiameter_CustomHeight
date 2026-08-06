#!/usr/bin/env python3
"""
xlsx_write_back.py -- thin CLI wrapper around sheet_batch.write_back_all(),
so scripts/sheet_batch.R can shell out to it instead of writing the xlsx
itself.

WHY THIS EXISTS
----------------
Testing found that R's openxlsx package, when it loads-then-saves a workbook
it did not originally create (e.g. one a Python script previously wrote
into with openpyxl), can round-trip missing metadata into a form openpyxl
then refuses to re-read (confirmed: empty bookViews window attributes, and
a dangling worksheet->drawing relationship pointing at a file that was never
written). openpyxl's own write path showed no such issue in either
direction during testing. Rather than chase individual openxlsx quirks
against a real, irreplaceable spreadsheet, every actual write to the sheet
routes through this one proven-safe path -- R only ever reads the sheet
(via readxl, read-only, no risk) and calls this script for the write.

USAGE
-----
    python scripts/xlsx_write_back.py --sheet <path.xlsx> --sheet-name <name-or-index> \
        --output-col <column header> --updates-csv <path to a 2-col CSV: row,value>

`updates-csv` has no header row: each line is `<sheet row number>,<value>`.
"""
from __future__ import annotations
import argparse
import csv
import sys

from sheet_batch import SheetConfig, write_back_all


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sheet", required=True, help="Path to the .xlsx workbook.")
    ap.add_argument("--sheet-name", required=True,
                    help="Sheet/tab name, or a 0-based integer index.")
    ap.add_argument("--output-col", required=True, help="Header of the column to write into.")
    ap.add_argument("--updates-csv", required=True,
                    help="No-header CSV of <sheet row>,<value> pairs to write.")
    args = ap.parse_args()

    sheet_name: str | int = args.sheet_name
    try:
        sheet_name = int(sheet_name)
    except ValueError:
        pass  # a real sheet name, not an index

    updates = []
    with open(args.updates_csv, newline="") as f:
        for row_str, value_str in csv.reader(f):
            updates.append((int(row_str), float(value_str)))

    if not updates:
        sys.exit("No updates in --updates-csv -- nothing to write.")

    cfg = SheetConfig(sheet_path=args.sheet, tree_id_col="", ply_folder="",
                      output_col=args.output_col, sheet_name=sheet_name)
    write_back_all(cfg, updates)


if __name__ == "__main__":
    main()
