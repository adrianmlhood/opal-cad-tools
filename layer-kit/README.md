# LayerKit

AutoCAD AutoLISP utility suite (Ocotillo Labs). A home for `LK-`-prefixed layer/utility
tools, run through one master loader. Sibling project to Stringtag and Opal.

Root: `C:\Users\adria\CAD\Automations\layer-kit\`

## Commands

**Active commands** (each multi-purpose one has a `[sub-option]` prompt). Note: `LK-BYLAYER` /
`LK-SKIP` are currently **shelved** — their folder is under `archive/`, so `LK-LOAD` does not load
them.

| Command | What it does |
|---|---|
| `LK-APPLY` | **Do it all** for a drawing: runs `LK-CLEANUP` (Full) → `LK-FILTER` Set (build group filters, creating missing layers) → re-applies standards to style them. Save & reopen to see the filters. |
| `LK-CLEANUP` | Prompts `[Full/Preview]`. **Preview** = dry-run classification (no changes). **Full** = classify → merge/delete → purge → sweep viewports to `G-VPORT` → apply standards → force-remove empty stragglers. |
| `LK-BYLAYER` | Forces **every** entity's color to **ByLayer** — all spaces *and* inside block definitions (more thorough than native `SETBYLAYER`). Strips true-color; handles locked/frozen. Starts by asking you to pick exclusions (Enter to skip). |
| `LK-SKIP` | Manage ByLayer exclusions: `[Add` (pick blocks/elements) `/ Layer` (pick objects → their layers) `/ List / Clear]`. Saved across sessions (registry) / in the drawing. |
| `LK-STD` | Layer standards: `[Save` (export current layers' look to `PV_layer_standards.csv`) `/ Set` (apply it; also auto-runs in cleanup) `/ Config` (set the CSV folder, remembered)`]`. |
| `LK-FILTER` | Layer **group filters**: `[Set` (build from `PV_layer_filters.csv`, creating missing layers) `/ Save` (export current filters to the CSV)`]`. Reopen the drawing to see filters. |
| `LK-DIMS` | Brings all `DIMENSION`s to the front and applies a `DIMTFILL` background mask so dims read cleanly over hatches/geometry. |
| `LK-ZEROBLOCK` / `LK-ZB` | Pick one block reference → recursively move **all** nested geometry (every level of nested blocks) onto layer `0`, so the block draws in its insertion layer. Edits the shared block definition; the clicked reference keeps its own layer. |
| `LK-LOAD` / `LKLOAD` | Reloads all LayerKit tools. |
| `LK-BYLAYER` / `LK-SKIP` | *(Currently shelved — folder archived, not loaded.)* Force every entity's color ByLayer everywhere incl. block defs; `LK-SKIP` manages exclusions. |

> **Excluding things from ByLayer:** `LK-BYLAYER` starts by asking you to pick blocks/elements
> to exclude (Enter to skip and use the saved list). Use `LK-SKIP` to manage the lists: **Add**
> (north arrow / title block / any element whose colors must stay — blocks saved by name in the
> registry, elements tagged in the drawing), **Layer** (protect a whole layer), **List**, **Clear**.
> All exclusion lists start **empty** — they only hold what you've saved.

> **Layer standards:** set up one drawing with every standard layer looking exactly right,
> run `LK-STD` → **Save** to capture them to `config\PV_layer_standards.csv`, then every
> `LK-CLEANUP` (or `LK-STD` → **Set**) re-applies that color/linetype/lineweight/plot/new-VP-freeze
> to the matching layers (creating any that are missing). Color is ACI only; linetypes must be
> loadable from `acad.lin`. Standard layers are also **protected from merge** during cleanup.

> **Viewport policy:** every cleanup run sweeps all viewports onto one layer
> (`*lk-vport-layer*`, default `G-VPORT`) regardless of their old layer's mapping — so
> viewports never block a layer from merging/purging. This includes each layout's overall
> **sheet** viewport (`*lk-vport-sheet*`, default on; set nil to skip them). ⚠ Keep
> `G-VPORT` **on and thawed** — a sheet viewport on a frozen/off layer blanks that layout.
> Consider setting `G-VPORT` non-plotting so viewport borders don't print.

## How it loads

`layerkit-load.lsp` silently loads the whole suite. Load it once per session via **APPLOAD →
Startup Suite**, or add this line to your single real `acad.lsp` / `acaddoc.lsp`:

```lisp
(load "C:\\Users\\adria\\CAD\\Automations\\layer-kit\\layerkit-load.lsp")
```

> It is **not** named `acad.lsp` on purpose — AutoCAD auto-loads only the first `acad.lsp` on
> the support path, which would collide with `Opal\acad.lsp`.

First time loading the `.lsp` files, AutoCAD may show a "Load anyway?" trust prompt
(`SECURELOAD`). Add the LayerKit folder to **Options → Files → Trusted Locations** to silence it.

## Folder layout

```
LayerKit\
  layerkit-load.lsp        loader entry point (load this)
  README.md                this file
  CLAUDE.md                context for AI sessions
  FEATURES.md              per-tool feature registry (what's tested vs not)
  lkload\                  LK-LOAD master loader (scans tool folders, loads highest version)
  lkcleanup\               LK-CLEANUP + LK-APPLY (highest .lsp = active)
  lkstd\                   LK-STD        lkfilter\     LK-FILTER
  lkdims\                  LK-DIMS       lkzeroblock\  LK-ZEROBLOCK
  config\                  CSVs: PV_static_mappings, PV_keywords, PV_layer_standards, PV_layer_filters
  archive\                 parked artifacts (old zips, flow diagram, old logs),
                           pre-LK-rebrand\ = old PV-named folders, lkbylayer\ = LK-BYLAYER/LK-SKIP (shelved)
```

## The CSVs

LK-CLEANUP is data-driven by two CSVs (filenames keep the `PV_` prefix — they're solar/PV
design data, not commands):

- **`PV_static_mappings.csv`** — `source_layer,target_layer` exact-match renames. A target of
  `PURGE` deletes the layer's contents.
- **`PV_keywords.csv`** — `keyword,target_layer` token/substring suggestions (you confirm each).
- **`PV_layer_standards.csv`** — `layer,color,linetype,lineweight,plot,vpfreeze`; the look of each
  standard layer (`LK-STD` → Save writes, Set applies / auto in `LK-CLEANUP`).
- **`PV_layer_filters.csv`** — `filter,layer1,layer2,…`; layer **group filter** membership per
  sheet (`LK-FILTER` → Save writes, Set applies).

Master copies live in `config\`. **At runtime** the tool reads CSVs from the directory set by
`LK-STD` → **Config** (remembered), or — if none set — from the open drawing's folder (`DWGPREFIX`).
A `PV_mapping_log.csv` audit file is written to that same directory on execute.

## Adding / updating tools

- One folder per command (`lk<name>\`), versioned files (`lk<name>-1.0.lsp`). The loader runs
  the **highest-versioned** `.lsp` in each folder, so ship a change by writing the next version
  file — no loader edit.
- Versioning: `+0.01` for fixes/small features, round to `x.N0` for milestones, `+1.0` for a
  rewrite. Copy the previous version first, then edit. Keep old versions in place.
- Record changes in `FEATURES.md` (new behavior tagged `untested` until confirmed in AutoCAD).

See `CLAUDE.md` for the full session protocol and AutoLISP rules.
