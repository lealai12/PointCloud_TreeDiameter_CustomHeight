# Python Glossary — Point-Cloud Tree Diameter at Custom Height

A plain-English reference for the Python used in this project's scripts
(`scripts/fit_dab.py`, `scripts/loopclose.py`, `scripts/dendro_tape.py`). Every entry says **what it does**,
shows a **snippet from our code**, and — where useful — gives an **R note** comparing
it to something you already know from R.

This doc grows as the code does: whenever a script uses a new construct, it gets added
here. Skim the "How to read a script" section first; the rest is a lookup table.

> **Big-picture R → Python differences to keep in mind**
> - **Indexing starts at 0**, not 1. `x[0]` is the first element; `x[-1]` is the last.
> - **Zero-based, half-open ranges:** `x[0:3]` is elements 0,1,2 (not 3). `range(4)` is 0,1,2,3.
> - **Whitespace is syntax.** Indentation (4 spaces) defines blocks — there are no `{}` braces around function bodies or loops.
> - **You must `import` libraries** before use (like R's `library()`), and you call functions as `library.function()`, e.g. `np.mean()`.
> - **Assignment is `=`** (not `<-`). `==` is comparison.
> - **Objects have methods** you call with a dot: `pcd.voxel_down_sample()` — the thing before the dot is *acted on*. R does this less.

---

## 1. How to read a Python script (anatomy)

Our scripts always have the same skeleton, top to bottom:

| Part | Example | What it is |
|---|---|---|
| **Shebang** | `#!/usr/bin/env python3` | Lets the file run as a program on Mac/Linux. Harmless on Windows. |
| **Module docstring** | `"""fit_dab.py — Fit DAB..."""` | The big triple-quoted text block at the very top: describes what the whole file does. |
| **Imports** | `import numpy as np` | Loads libraries (see §2). |
| **Function definitions** | `def load_xyz(path):` | Reusable named blocks of code (see §3). They *define* behavior but don't run until called. |
| **`def main():`** | | The function that orchestrates everything. |
| **The launch line** | `if __name__ == "__main__":` | "If this file was run directly (not imported), call `main()`." This is why the script *does* something when you run it. |

**R note:** A Python script is read top-to-bottom like an R script, but functions are
defined once and only *run* when called — and the `if __name__ == "__main__"` line at
the bottom is the actual "go" button.

---

## 2. Running scripts & imports

### Virtual environments (`venv`) & `pip` — the project's isolated toolbox
A **virtual environment** is a private, per-project copy of Python + its packages, so
this project's libraries can't clash with anything else on your machine. Ours is the
folder `DAB_Project_Environment/` (it is git-ignored — you rebuild it, never commit it).
**R note:** this is exactly R's `renv` idea.
```bash
python -m venv DAB_Project_Environment        # create it (once)
# --- use it: either "activate" the environment for your whole terminal session... ---
DAB_Project_Environment\Scripts\Activate.ps1  # Windows PowerShell
source DAB_Project_Environment/bin/activate   # Mac/Linux
# ...or just call the env's python directly, without activating:
DAB_Project_Environment/Scripts/python.exe scripts/loopclose.py ...   # Windows
```
**`pip`** is Python's package installer (like `install.packages()` in R). Inside the env:
```bash
python -m pip install -r scripts/requirements.txt  # install everything the project needs
python -m pip install open3d                       # install one package
python -m pip freeze                               # list installed packages + exact versions
```
`requirements.txt` is the project's dependency list (its `renv.lock` equivalent). Once an
environment is set up you rarely touch pip again.

### Running a script from the terminal
```bash
python scripts/fit_dab.py slices/tree01_slice.ply --dab-height 2.3
```
`python` = the interpreter; then the script path; then **arguments** the script reads
(see `argparse`, §7). **R note:** like `Rscript myscript.R arg1 arg2`.

### `import`
```python
import numpy as np          # load numpy, refer to it as "np"
import os, sys, math        # load several standard-library modules
from plyfile import PlyData # load just ONE name out of a library
```
Loads a library so you can use it. `as np` gives it a short alias. `from X import Y`
pulls a single tool `Y` out so you can write `PlyData` instead of `plyfile.PlyData`.
**R note:** like `library(numpy)`, except you keep the `np.` prefix on every call
(which is why you can always tell *where* a function came from).

### `from __future__ import annotations`
```python
from __future__ import annotations
```
A compatibility line that makes newer type-hint syntax work on older Pythons. Just
leave it at the top; nothing to do.

### Guarded import (fail with a helpful message)
```python
try:
    import open3d as o3d
except ImportError:
    sys.exit("Missing dependency: pip install open3d")
```
Tries to load a library; if it isn't installed, prints an install hint and stops
cleanly instead of crashing with a confusing traceback. (`try/except` = §6.)

---

## 3. Functions

### Defining a function
```python
def load_xyz(path: str) -> np.ndarray:
    """Load an Nx3 array of XYZ from a PLY file."""
    ply = PlyData.read(path)
    return np.c_[...]
```
- `def name(args):` defines a function. The indented block below is its body.
- `path: str` and `-> np.ndarray` are **type hints** — optional labels saying "expects
  a string, returns a numpy array." They're documentation; Python doesn't enforce them.
- The `"""..."""` right under `def` is the function's **docstring** (its help text).
- `return` hands a value back to whoever called the function.

**R note:** `load_xyz <- function(path) { ... }`, but Python uses `def`, a colon, and
indentation instead of `{ }`, and hints the types inline.

### Default argument values
```python
def loopclose(paths, tag, voxel=0.01, max_corr_dist=0.02):
```
`voxel=0.01` means if the caller doesn't supply `voxel`, it defaults to 0.01. **R note:**
identical idea to R's `function(voxel = 0.01)`.

### Keyword arguments when calling
```python
analyze_slice(f, tree_id=args.tree_id, dab_height=2.3)
```
Naming arguments (`tree_id=...`) makes calls self-documenting and order-independent.

---

## 4. Core data types

| Type | Looks like | Notes / R analogue |
|---|---|---|
| **str** (string) | `"tree01"` | Text. Single or double quotes. |
| **int / float** | `8`, `0.02` | Whole number / decimal. |
| **bool** | `True`, `False` | Note the capital T/F (R uses `TRUE`). |
| **None** | `None` | "no value / missing." Like R's `NULL`. |
| **list** | `[pA, pB]` | Ordered, editable sequence. R's closest is an unnamed `list()` / vector. |
| **dict** (dictionary) | `{"cx": 1.2, "r": 0.4}` | Key→value lookup table. Like a named R `list`; access with `d["cx"]`. |
| **tuple** | `(down, fpfh)` | Like a list but fixed/unchangeable. Often used to return two things at once. |

### Dictionaries (used everywhere for results)
```python
row = {"tree_id": "t01", "n_points": n}
row["coverage_deg"] = 271.4      # add / set a key
row.update({"hull_valid": True}) # merge in several keys at once
```
Our fitters build a `row` dict per slice, then hand a list of rows to pandas to make a
CSV. **R note:** think of one `row` dict as one row of a data.frame, keyed by column name.

---

## 5. numpy (`np`) — the numeric workhorse

numpy gives you fast **arrays** (vectors/matrices) and math over them. This is the
heart of the geometry.

### Making / shaping arrays
```python
np.asarray(v["x"])                 # turn data into a numpy array
.astype(float)                     # cast to floating-point numbers
np.c_[x, y, z]                     # stack 1-D columns into an Nx3 array (column-bind)
np.r_[ang, ang[0] + 2*np.pi]       # concatenate into one long 1-D array (row-bind)
np.vstack([loop, loop[0]])         # stack arrays vertically (repeat first point to close a loop)
np.eye(3)                          # 3x3 identity matrix
np.linspace(0, 2*np.pi, 500)       # 500 evenly spaced values from 0 to 2*pi (angles for a circle)
np.full(500, z)                    # an array of 500 copies of the value z
np.tile(rgb, (n, 1))               # repeat a row n times -> Nx3 (one color per point)
```
**R note:** `np.c_` ≈ `cbind`, `np.r_` ≈ `c()`/`rbind`, `np.eye(3)` ≈ `diag(3)`,
`np.linspace` ≈ `seq()`, `np.full` ≈ `rep()`.

### Indexing & slicing (0-based!)
```python
xyz[:, :2]     # ALL rows, first 2 columns (the X,Y of every point)
xyz[:, 0]      # ALL rows, column 0 (just the X values)
ang[0]         # first element
loop[h.vertices]  # pick the rows listed in the array h.vertices
```
`:` means "everything along this axis." The comma separates row-selector, column-selector.
**R note:** like `m[, 1:2]` but 0-based and the upper bound is *excluded*.

### Elementwise math & reductions
```python
x**2 + y**2                # elementwise square and add (whole arrays at once)
np.hypot(x - cx, y - cy)   # sqrt(a^2+b^2) elementwise = distance of each point to center
X - X.mean(axis=0)         # subtract the column-means (center the data). axis=0 = down columns
np.sqrt(np.mean(resid**2)) # RMS: root-mean-square of residuals
np.sort(ang)               # sorted copy
np.diff(arr)               # successive differences (arr[1]-arr[0], arr[2]-arr[1], ...)
np.diff(loop, axis=0)      # differences DOWN rows -> each polygon edge as an (dx,dy) vector
np.linalg.norm(v, axis=1)  # length of EACH row-vector -> here, each edge's length (axis=1 = per row)
np.arctan2(dy, dx)         # angle (radians) of the point (dx,dy) from center — full -pi..pi, quadrant-aware
gaps.max()                 # largest value
```
**Taut-tape idiom (`dendro_tape.py`):** `norm(np.diff(loop, axis=0), axis=1).sum()` is the
whole perimeter in one line — difference consecutive hull corners into edge vectors, take
each edge's length, add them up. `arctan2` gives each point's bearing from the centroid so
we can measure the largest angular gap (coverage). **R note:** `arctan2` ≈ `atan2`; the
`.sum()` of edge lengths ≈ `sum(sqrt(rowSums(diff(loop)^2)))` in `dendro_tape.R`.
**R note:** numpy is vectorized just like R — you rarely write loops. `axis=0` = "collapse
rows, one result per column"; `axis=1` = "one result per row."

### Linear algebra (the lean-correction + circle math)
```python
np.linalg.lstsq(A, b, rcond=None)[0]   # least-squares solve A x = b  (the circle fit)
np.linalg.svd(X, full_matrices=False)  # singular value decomposition (finds the stem axis)
np.linalg.norm(v)                      # length/magnitude of a vector
np.cross(a, b) ; np.dot(a, b)          # vector cross product ; dot product
xyz @ R.T                              # matrix multiply (rotate every point). @ = matmul
```
- `@` is matrix multiplication (**R note:** R's `%*%`). `.T` transposes (**R:** `t()`).
- `lstsq(...)[0]` — the function returns several things in a tuple; `[0]` grabs the first
  (the solution). Trailing `[0]`/`[1:]` after a call is "take this piece of what came back."
- **SVD/PCA gotcha (documented in `fit_dab.py`):** the largest-variance direction of a
  *tall* trunk segment is the stem axis — but of a *thin slice* it's a diameter. Never
  PCA a thin slice to find the axis.

---

## 6. Control flow

### `if` / `elif` / `else`
```python
if cov >= 270:
    row["hull_valid"] = True
elif fit > max_overlap:
    ...
else:
    row["hull_valid"] = False
```
Runs the first block whose condition is true. Indentation defines each block.

### `for` loop
```python
for i, p in enumerate(paths[1:], start=1):
    src = load_cloud(p)
```
Iterates over items. `enumerate(...)` gives you `(index, item)` pairs; `start=1` makes
the count begin at 1. `paths[1:]` = "all paths except the first." **R note:** like
`for (p in paths)`, but `enumerate` hands you the counter too.

### `try` / `except` (handle errors gracefully)
```python
try:
    row = analyze_slice(f, ...)
except Exception as e:
    print(f"[skip] {f}: {e}")   # log it and move on instead of crashing
```
Attempts risky code; if it raises an error, the `except` block runs instead of the whole
program dying. Used so one bad slice doesn't abort a whole `--batch` run.

### Ternary (one-line if/else)
```python
files = sorted(glob.glob(...)) if args.batch else [args.path]
```
Reads as "use the glob **if** batch, **else** just the single path." **R note:**
`ifelse()`-like, but for picking one value.

### List comprehension (build a list in one line)
```python
missing = [p for p in paths if not os.path.exists(p)]
```
"Make a list of every `p` in `paths` that doesn't exist." A compact loop-that-builds-a-list.
**R note:** like `paths[!file.exists(paths)]` / a vectorized filter.

---

## 7. `argparse` — command-line options

Turns terminal words into variables your script reads.
```python
ap = argparse.ArgumentParser(description="...")
ap.add_argument("path")                              # a required positional arg
ap.add_argument("--batch", action="store_true")      # a yes/no flag (present = True)
ap.add_argument("--voxel", type=float, default=0.01) # an option with a number + default
ap.add_argument("pieces", nargs="+")                 # one OR MORE positional values
ap.add_argument("--tag", required=True)              # a must-supply option
args = ap.parse_args()
# ...then use args.voxel, args.batch, args.tag, etc.
```
- `--name` = optional flag; a bare `name` = required positional.
- `action="store_true"` = a switch (`--batch` on the command line makes `args.batch` True).
- `nargs="+"` = "collect one or more" (that's how `loopclose.py` takes many fragment files).
- `type=float` converts the text `"0.01"` into the number `0.01`.

---

## 8. Strings & printing

### f-strings (formatted text)
```python
print(f"voxel={voxel*1000:.0f} mm   fitness={fit:.3f}")
print(f"{row['tree_id']:<14} rms={rms:.1f}mm")
```
An `f"..."` string drops variables/expressions into text inside `{ }`. The `:` starts a
**format spec**:
- `:.3f` = 3 decimal places; `:.0f` = 0 decimals (whole number).
- `:<14` = left-pad to 14 characters wide (makes columns line up).
- `:,` = thousands separators (`1,234,567`).

**R note:** like `sprintf("%.3f", fit)` / `glue::glue()`, but inline and much shorter.

---

## 9. `os` / files & paths

```python
os.path.basename(path)        # "15.ply" from a full path
os.path.splitext(name)[0]     # drop the extension -> "15"
os.path.join(out_dir, "x.ply")# join folders + file with the right slash for the OS
os.path.exists(p)             # True if the file/folder is there
os.makedirs(out_dir, exist_ok=True)  # create folder(s); don't error if they exist
```
Always build paths with `os.path.join` (not by gluing strings with `/`) so the code works
on Windows and Mac alike. **R note:** analogous to `basename()`, `file.path()`,
`file.exists()`, `dir.create()`.

### `glob` — match many files by pattern
```python
glob.glob("slices/*.ply")     # list every .ply file in slices/
```
`*` = "anything." Returns a list of matching paths. **R note:** like `Sys.glob()` /
`list.files(pattern=...)`.

---

## 10. plyfile & scipy (used in `fit_dab.py`)

```python
from plyfile import PlyData
ply = PlyData.read(path)          # read a PLY point cloud
v = ply["vertex"]                 # the vertex table
np.asarray(v["x"])                # pull the X coordinate column
```
```python
from scipy.spatial import ConvexHull
h = ConvexHull(xy)                # smallest convex polygon enclosing the 2-D points
h.vertices                        # indices of the hull's corner points (the "tape" outline)
```
The convex hull perimeter is our **tape-equivalent circumference** — it mimics a tape
pulled taut around the trunk cross-section.

---

## 11. open3d (`o3d`) — point-cloud engine (used in `loopclose.py`)

open3d is the 3-D library doing the registration (aligning drifted scan pieces).

### Point clouds: read, write, inspect
```python
pcd = o3d.io.read_point_cloud(path)     # load a cloud
o3d.io.write_point_cloud(out, merged)   # save a cloud
len(pcd.points)                         # how many points
np.asarray(pcd.points)                  # get the XYZ as a numpy array
pcd.transform(T)                        # apply a 4x4 rigid transform (move/rotate in place)
merged += src                           # merge two clouds into one
```

### Downsampling & normals (prep for alignment)
```python
down = pcd.voxel_down_sample(voxel)     # thin the cloud onto a regular grid (dedupe/speed)
pcd.estimate_normals(                    # compute each point's surface-normal direction
    o3d.geometry.KDTreeSearchParamHybrid(radius=voxel*2, max_nn=30))
```
- **voxel downsample** = overlay a 3-D grid of cell size `voxel` and keep one point per
  cell. Used both to speed up matching and to *dedupe* the overlap after merging.
- **normals** = the "which way is the surface facing" arrow at each point; the alignment
  math (point-to-plane ICP, FPFH features) needs them.
- **KDTreeSearchParamHybrid** = "look at neighbors within this radius, up to this many" —
  how open3d decides which nearby points to use.

### Registration (the actual loop-close)
```python
fpfh = o3d.pipelines.registration.compute_fpfh_feature(down, ...)   # per-point "fingerprint"
o3d.pipelines.registration.registration_ransac_based_on_feature_matching(...)  # coarse align
o3d.pipelines.registration.registration_icp(                        # fine align
    src, tgt, max_corr_dist, init_T,
    o3d.pipelines.registration.TransformationEstimationPointToPlane())
```
- **FPFH feature** = a numeric fingerprint of the local shape around each point, so two
  clouds can find matching bark patches without you clicking points.
- **RANSAC** = coarse, no-initial-guess alignment by matching those fingerprints and
  throwing out matches that don't agree.
- **ICP** (Iterative Closest Point) = fine alignment that nudges one cloud onto the other.
  It returns `.transformation` (the 4×4 move), `.fitness` (fraction of points that found a
  match — the *overlap*), and `.inlier_rmse` (how tight the matched points are, in meters).
- **`max_corr_dist`** = the leash: ICP only pairs points closer than this. **This is the
  key safety knob** — the manual ICP on tree 15 failed because it assumed 100% overlap
  and dragged a small arc onto the wrong bark. A tight leash + watching `fitness` prevents
  that (see `loopclose.py`'s docstring).

---

## 12. matplotlib — making the 2D figure (used in `fit_dab.py`)

matplotlib draws the cross-section figure (points + fitted circle + hull, labeled).
```python
import matplotlib
matplotlib.use("Agg")            # "headless" backend: write image files, never pop a window
import matplotlib.pyplot as plt  # the plotting interface, conventionally aliased plt

fig, ax = plt.subplots(figsize=(6, 6))   # make a figure + one axes (the plot area), 6x6 inches
ax.scatter(x, y, s=2, c="0.6")           # scatter points (s=size, c=color; "0.6"=gray)
ax.plot(cx + r*np.cos(t), cy + r*np.sin(t), "r-", lw=1.5)  # a red ("r-") line = the circle
ax.plot(loop[:,0], loop[:,1], "g-")      # green outline = the hull
ax.set_aspect("equal", "datalim")        # 1 unit x == 1 unit y, so a circle looks circular
ax.set_xlabel("x (m)"); ax.set_title(...) # labels/title
ax.legend(fontsize=7)                    # key for the labeled series
fig.tight_layout()                       # tidy spacing
fig.savefig(path, dpi=150)               # write the PNG (dpi = resolution)
plt.close(fig)                           # free memory — important inside a --batch loop
```
**Mental model:** a **figure** is the whole image; an **axes** (`ax`) is one plot inside it.
You add things to `ax`, then `savefig`. **R note:** very like building a plot in base R /
`ggplot` layer by layer, then `ggsave()`. `matplotlib.use("Agg")` is the "don't try to open a
window on a server" switch — must be set *before* importing `pyplot`.

Color/style shorthand: `"r-"` = red solid line, `"g-"` = green, `"r+"` = red plus markers.

---

## 13. Writing files by hand (`np.savetxt`, plain `open`)

We write the overlay clouds as **ASCII PLY** without a library, so you can see exactly
what a PLY is: a short text header describing the columns, then rows of numbers.
```python
np.savetxt(path, data,                       # write a numeric array as text
           fmt="%.6f %.6f %.6f %d %d %d",     # per-column format: 6 floats then 3 ints
           header=header_string, comments="") # comments="" stops numpy prefixing header with '#'
```
```python
with open(path, "w") as f:   # open a text file for writing; auto-closes at end of block
    f.write("some text\n")   # \n = newline
```
- `with open(...) as f:` is the standard safe way to write a file — it closes itself even if
  an error happens. **R note:** like `writeLines()` / `cat(file=...)`, but the `with` block
  handles the open/close for you.
- `fmt="%.6f ... %d"` controls how each number is printed (`%.6f` = 6 decimals, `%d` = integer).

---

*Add to this file whenever a script introduces something new.*
