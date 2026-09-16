# Step 07 — Export the polished slice to `.ply`

**Tool:** CloudCompare command line. One command per tree-site.

| | |
|---|---|
| **Takes** | `Working\Polished_Slices\<tag>_<Site>_slice.bin` from Step 06 |
| **Makes** | `Working\Polished_Slices_ply\<tag>__<Site>.ply` |
| **Feeds** | Step 08 — measure (every measurement script reads this file) |

## Command

```
CloudCompare -SILENT -AUTO_SAVE OFF -O <in.bin> -C_EXPORT_FMT PLY -SAVE_CLOUDS FILE <out.ply>
```

Same command as Step 04. Name the output `<tag>__<Site>.ply` (double underscore) — that is what the Step 08 scripts' CONFIG pattern `{tree_id}__{site}.ply` expects, and what their `--batch` mode uses as the row ID.

## This project's run

- **32 of 32** exported.
