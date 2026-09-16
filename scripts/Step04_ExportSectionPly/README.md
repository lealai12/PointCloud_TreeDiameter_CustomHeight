# Step 04 — Export the section to `.ply`

**Tool:** CloudCompare command line. One command per tree.

| | |
|---|---|
| **Takes** | `Working\Final_Disc\<tag>_Ready.bin` from Step 03 |
| **Makes** | `Working\Final_Disc_ply\<tag>.ply` |
| **Feeds** | Step 05 — cut the slice (`cut_slice.py` / `.R` read this file) |

## Why

The measurement scripts read `.ply`; they cannot read CloudCompare's native `.bin`. Nothing changes but the container.

## Command

```
CloudCompare -SILENT -AUTO_SAVE OFF -O <in.bin> -C_EXPORT_FMT PLY -SAVE_CLOUDS FILE <out.ply>
```

`-AUTO_SAVE OFF` matters: without it CloudCompare also writes an extra copy next to the input.

## This project's run

- **19 of 19** sections exported. File names are the bare tree tag (`3853.ply`), which is what `cut_slice`'s CONFIG pattern `{tree_id}.ply` expects.
