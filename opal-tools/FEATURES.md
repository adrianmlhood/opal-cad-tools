# O-Suite — Feature Registry
# Deployed at: Opal Energy
#
# PURPOSE: Cross-check before iterating any tool. Confirms what has and has not
# been verified in AutoCAD 2027. All forked tools are considered NON-WORKING
# until confirmed in a live drawing session.
#
# UPDATE RULE: After confirming a tool works in AutoCAD, drop "untested" tag.
# When a tool fails, note what failed so the next session has context.
#
# DORMANT: Untested/broken/stub tools live in dormant/ and are NOT loaded by
# O-LOAD. To activate a tool for development: move its folder to the Opal root,
# then run O-LOAD. Move back to dormant/ when shelving.
#
# ★ CRITICAL — MODULE ENTITY TYPE (read before touching any geometry tool):
#   Opal modules are OLD-STYLE HEAVYWEIGHT POLYLINE (DXF type "POLYLINE").
#   Corners are in separate VERTEX sub-entities; walk with entnext until SEQEND.
#   LWPOLYLINE filters find ZERO modules on these drawings.
#   Correct ssget filter: (0 . "*POLYLINE")  -- matches both types.
#   VERTEX group 10 → (trans pt 2 0) to WCS, same as LWPOLYLINE group 10.
#   Canonical (live, working) reader: _oset-poly-pts in oset/oset-1.11.lsp
#   (LWPOLYLINE group-10 + heavyweight-POLYLINE VERTEX walk, OCS->WCS trans pt ent 0).
#   O-SET is FIXED (1.04+). Tools that still have the LWPOLYLINE-only bug are all
#   dormant: O-COUNT v1.0, O-JUMP v1.0.
#
# FORMAT:
#   [x.xx]           = version introduced
#   [x.xx untested]  = written but NOT yet verified in AutoCAD
#   [x.xx broken]    = tested and known to fail (describe issue)
#   [x.xx works]     = confirmed working in AutoCAD 2027
# ============================================================


## O-LOAD
Commands: O-LOAD, OLOAD
File: oload/oload-1.10.lsp
Latest confirmed: 1.03 works

### Current Features
- [1.10 works] O-LOAD now ALSO (re)loads LayerKit, so OLOAD refreshes both suites in one shot -- they're no longer reloaded independently. _oload-lk-root resolves the sibling layer-kit\ root (honors *lk-suite-root* when it points at a real folder, else derives it beside the O-Suite root via vl-filename-directory; true in both dev and bundle), _oload-layerkit loads the lkload loader if C:LK-LOAD isn't defined yet, sets *lk-suite-root*, mirrors *oload-quiet* into *lkload-quiet*, and calls C:LK-LOAD. Headless: OLOAD loaded LayerKit with lkstd 1.24 + lkfilter 1.24 active. NOTE: command-existence is tested with (car (atoms-family 1 (list "C:LK-LOAD"))) -- the bare atoms-family list is (nil) when undefined, which is TRUTHY, so null/not-null tests are wrong (that was the first-cut bug that aborted O-LOAD with "no function definition: C:LK-LOAD"). The bundle bootstrap no longer calls C:LK-LOAD separately (O-LOAD owns it -- no double load).
- [1.04 untested] Relocatable root: _oload-root returns *o-suite-root* when bound (set by the deploy bootstrap), else the original hardcoded dev path. Enables the ApplicationPlugins bundle install.
- [1.04 untested] Auto-run of O-SET on load is now suppressed in quiet mode, so silent startup (bootstrap) never opens a calibration prompt.
- [1.04 works] On a manual (non-quiet) load O-SET is ALWAYS re-run -- dropped the "already calibrated -- skip" branch and the stale "box-select any 2x2+ block" prompt (O-SET is click-free now), so geometry recalibrates every OLOAD. NOTE: OLOAD does not reload the loader itself (oload/ is on the skip list), so editing oload-1.04 needs a manual (load "...oload-1.04.lsp") or an AutoCAD restart to take effect.
- [1.04 untested] Quiet load line and banner de-branded; points users to OHELP / O.
- [1.0 works] Loads oconfig first (layer globals), then all tool subfolders in Opal root
- [1.0 works] Detects highest-versioned .lsp per folder via ASCII lexicographic sort on filename
- [1.0 works] Prints [OK] / [skip] per tool with UPDATE flag when version changes between loads
- [1.0 works] Tracks loaded versions in *oload-versions* alist: ((folder-name . "x.xx") ...)
- [1.04 works] Auto-runs O-SET after all tools load on a manual (non-quiet) load -- now unconditional (was: only if *oset-mod-w* nil/zero)
- [1.01 works] Skips ".", "..", tools/ from directory scan
- [1.02 works] *oload-quiet* T suppresses per-tool output (set by the bundle bootstrap.lsp on
  silent startup; the old dev acad.lsp auto-loader was removed -- it was broken (stale Opal\ path)
  and unused; the ApplicationPlugins bootstrap.lsp is the only autoloader)
- [1.02 works] Quiet mode: single summary line "O-Suite loaded -- N tools. O-REF for help."
- [1.03 works] Version extraction from filename: "obound-1.02.lsp" → "1.02" (major.minor only)
- [1.03 works] Skipped folders listed at end: "Skipped (no .lsp): ..."

### Globals written
- *oload-versions* -- alist of (folder-name . "x.xx") for every loaded tool
- *oload-quiet*    -- suppress per-tool output when T (set before loading)

### Assumptions / constraints
- Root path: *o-suite-root* if bound (deploy bundle), else C:\Users\adria\CAD\Automations\opal-tools\
- Version sort is ASCII; avoid version numbers where ASCII order ≠ numeric order
  (e.g., "1.9" sorts after "1.10" → use "1.09", "1.10", not "1.9", "1.10")
- Folder skip list: dormant, oload, oconfig, test, tools (case-insensitive match)

---

## OMODE
Commands: O-MODE, OMODE
File: omode/omode-1.02.lsp
Latest confirmed: 1.0 works (live DEV->BUNDLE->DEV verified, git summary shown, no O-SET prompt)

### Current Features
- [1.02 untested] Public hooks omode:to-bundle / omode:to-dev -- thin wrappers over the internal
  switch helpers (no getkword prompt) so the O toolbox "Switch to Bundle" button can flip mode.
  omode:to-bundle remembers the source first so a later BUNDLE->DEV can find it.
- [1.0 works] Reports current load mode: DEV (loading from the live source tree) vs
  BUNDLE (loading from a frozen prod-test copy or an installed plugin copy). Detection: the
  current *o-suite-root* contains "OpalTools-prodtest" or "ApplicationPlugins" → BUNDLE, else DEV.
- [1.0 works] OMODE getkword [Dev/Bundle] <Report>. Report (default) just prints mode + both
  suite roots. Dev/Bundle flip the RUNNING session by repointing *o-suite-root* / *lk-suite-root*
  and reloading each suite's loader (O-LOAD + the LayerKit loader) from the new root. _omode-reload
  forces *oload-quiet*/*lkload-quiet* ON during the reload so the switch never triggers O-LOAD's
  auto-O-SET calibration prompt (restored after).
- [1.0 works] BUNDLE flip is SESSION-ONLY by design — it never rewrites the installed startup
  pointer, so DEV stays the permanent startup mode and a restart returns to DEV automatically.
- [1.0 works] BUNDLE flip runs ..\opal-cad-installer\Snapshot-Bundle.ps1 (via startapp), which
  robocopies opal-tools + layer-kit into %LOCALAPPDATA%\Autodesk\OpalTools-prodtest using the same
  exclusions as Package.ps1 (+ omode). LISP polls %TEMP%\omode-done.flag (DELAY 200ms, ~20s cap)
  then prints %TEMP%\omode-status.txt.
- [1.01 untested] CMDECHO forced off around the DELAY poll so the wait does not echo
  "_.DELAY ... 200" repeatedly to the command line (restored after).
- [1.0 works] Snapshot-Bundle.ps1 prints what is NOT on GitHub (uncommitted file count +
  unpushed commit count) for awareness only. OMODE never commits/pushes.
- [1.0 works] Source tree location remembered in *o-source-root* / *lk-source-root* and in
  registry HKCU\Software\Ocotillo\OpalTools\SourceRoot (captured whenever observed in DEV) so a
  BUNDLE->DEV flip can find the source.
- DEV-ONLY: omode is excluded from the packaged release (Package.ps1 /XD, Snapshot-Bundle.ps1).
  The command stays defined in-session after a BUNDLE flip, so you can still OMODE back to DEV.

### Assumptions / constraints
- Prod-test copy path is fixed: %LOCALAPPDATA%\Autodesk\OpalTools-prodtest\ (must match between
  omode.lsp and Snapshot-Bundle.ps1).
- The live-reload + startapp + DELAY-poll path needs LIVE GUI verification (cannot be exercised
  headless). Report/detection/source-resolution helpers are headless-testable.

---

## O-SET
Commands: O-SET, OSET
File: oset/oset-1.14.lsp
Latest confirmed: 1.12 works (live on TSC11590: 287 polylines -> 254 4-corner -> 227 modules,
ignored 27; module 44.41 x 89.69; Gap X 14.58 + 13.60 (two spacings), Gap Y 0.25)

### Current Features
- [1.14 untested] Honors an active O-ZONE: when *ozone-bounds* is set, O-SET keeps only modules
  whose centre (nth 1 in the O-SET record) is inside the zone before calibrating, via ogeo's
  _ogeo-pt-in-zone. Lets the user calibrate ONE array when model space holds several. No zone ->
  unchanged (scans all modules on the layer). Reports the in-zone count when it trims.
- [1.12 works] Module match is ORIENTATION-AGNOSTIC and gates on the LONG side. Each polyline's
  (short,long) edge pair is compared to the module's (short,long): LONG side matched tightly
  (tol = max(2.0, 2% of long)) because panel length is the stable signal separating modules from
  shorter clutter (87x41 frames, half panels); SHORT side gets slack (tol = max(4.0, 10% of short))
  so slightly-narrower edge modules (41x90 beside the dominant 44x90) are no longer dropped, and a
  module wound from a different start corner still matches. Fixes under-count on TSC11590
  (223 -> 227: kept 44x90 x221 + 43x90 x2 + 41x90 x4, excluded all 82-87 long clutter). SUPERSEDES
  the [1.08] orientation-sensitive 5% footprint match below.
- [1.11 works] FULLY AUTOMATIC -- no click. ssget "X" (0 . "*POLYLINE") on *ocfg-layer-modules*
  ("PV-MODS"); corners via _oset-poly-pts (LWPOLYLINE group-10 + heavyweight-POLYLINE VERTEX walk,
  OCS->WCS (trans pt ent 0)). Fixes the 1.0 LWPOLYLINE-only bug -- works on Opal POLYLINE modules.
- [1.04 works] Defensive: every entity read is wrapped in vl-catch-all-apply, and each corner is
  validated numeric; a bad/odd polyline (missing group 10, non-numeric corner) is skipped, never
  fatal (was the "numberp: nil" crash). If nothing is usable it prints the first entity's type +
  corner count to diagnose unexpected geometry.
- [1.08 works] Module footprint = the MODE of W x H over all 4-corner polylines (robust to a few
  odd sizes). (The match TOLERANCE that follows was the orientation-sensitive 5% test; replaced by
  the orientation-agnostic long-tight/short-loose match in [1.12] above.) This handles non-module
  clutter on PV-MODS (the live drawing carries ~31 non-module objects).
- [1.05 works] Spacing is sampled from EVERY matched module (nearest in-band neighbour along each
  module axis), not one reference module -- so an edge/row-end module can't yield a 2-pitch gap.
- [1.09 works] Spacing = the MOST COMMON pitch (mode cluster), not the smallest. Gap = pitch - size.
- [1.10 works] Per axis, detects 1 OR 2 spacings. A second spacing is reported only when a
  distinct-but-close mode group exists: >= 8% support (ignores stray counts), refined means
  >= 0.75 apart (a bin-boundary split isn't faked into two), and <= 1.6 apart (a 2-pitch jump is
  not mistaken for a sibling spacing). On the live drawing X = 14.5 (common) + 13.5.
- [1.11 works] Fast-scan readout: scan counts + X/Y pitch-cluster histograms print first (context),
  then an aligned MODULE / GAP X / GAP Y summary block (2 decimals) prints last.

### Globals written
- *oset-mod-w*  -- module width  (modal footprint; the module's own first-edge length)
- *oset-mod-h*  -- module height (modal footprint)
- *oset-gap-x*  -- primary (most common) gap along the width axis
- *oset-gap-y*  -- primary gap along the height axis
- *oset-gap-x2* -- secondary gap when a 2nd distinct spacing is detected on X, else nil
- *oset-gap-y2* -- secondary gap on Y, else nil

### Notes / assumptions
- Module layer is "PV-MODS" (oconfig 1.03). The modal footprint defines "a module"; if PV-MODS
  legitimately holds two module sizes, O-SET calibrates to the more common one and treats the
  other as non-module. Pitch-cluster tol 0.5 keeps two real gaps (e.g. 58 vs 59) distinct.
  Footprint match (1.12): LONG side tol = max(2.0, 2% of long), SHORT side tol = max(4.0, 10% of short).

---

## O-MODSIZE
Commands: O-MODSIZE, OMODSIZE
File: omodsize/omodsize-1.02.lsp
Latest confirmed: 1.01 worked live (227 modules normalized). 1.02 engine PASSES headless
(mixed array: 8 matched, BEFORE off-target 3 -> Normalize -> AFTER 0; narrow module resized to
44.41x89.69 with centre kept). 1.02 prompts (List/last-used/regen) untested in GUI.

### Current Features
- [1.02 works headless] Shares **ogeo** (detection/records/module-dims). FIXES the misleading
  off-target: now measured vs the CHOSEN TARGET, so a uniform array reads off=0 (was vs a stale
  modal -> always non-zero, e.g. 227). Target sources: [Yes] default = last-used (remembered in
  registry HKCU\Software\Ocotillo\OpalTools LastModW/H) else config dims; [List] pick a named
  module from *ocfg-modules*; [Custom] type W,H (defaulting to last-used). Resize is winding-proof
  (each vertex placed by the SIGN of its projection on the module's short/long axes). Quiet:
  CMDECHO 0 + single vla-regen at end (no per-entity entupd -> kills the 227x viewport-switch spam).
- [1.01 works headless] Opens with [Report/Normalize] <Report>. REPORT is read-only: prints the
  footprint distribution (size buckets short x long -> count, min/max short & long side + spread,
  count off the modal/target). Run it BEFORE and AFTER a normalize to verify. Detection shared with
  Normalize via _oms-detect, so both see the same set. Verified: before=3 buckets/off=13, after=1
  bucket/off=0.
- [1.0 works headless] Resize engine: rebuilds each module's 4 corners about its OWN centre along
  its OWN edge axes (u = p1-p0, v = p3-p0), so position + rotation are preserved and only side
  lengths change. Writes corners back in place via entmod on the polyline's own vertices + entupd
  (heavyweight POLYLINE) or entmod of the group-10 list (LWPOLYLINE) -- entity identity / handle /
  XDATA preserved (no delete+recreate). Verified headless: 41x90 @ 20deg -> 44.41x89.69, centre kept.
- [1.0 works headless] Orientation-agnostic: the target's LONG dimension is laid on whichever module
  edge is currently the long one, so a module wound from a different start corner normalizes correctly.
- [1.0 untested] Detection mirrors O-SET 1.12 exactly (own copy of the dual-path reader, modal
  footprint, long-tight/short-loose match) so it sees the SAME module set (227 on TSC11590).
  Prefers O-SET's calibrated *oset-mod-w/h* as the default target when present.
- [1.0 untested] UI: reports count + modal footprint; [Yes/No/Custom] target (Custom prompts W/H);
  prints off-size vs already-on-size counts; explicit [Yes/No] <No> gate before any edit; only
  resizes modules off by > 0.01; reports resized / unchanged / failed (locked layer or not 4-corner).
- [1.0 design] MODULES ONLY -- edits polylines on *ocfg-layer-modules*; racking/strings/annotation
  untouched. Intended as a pre-stringing cleanup, paired with O-MODSPACE (rows + columns).

### Notes / assumptions
- Only resizes polylines with exactly 4 geometry vertices; anything else is left untouched.
- Resize is about the centroid, so a normalized module grows/shrinks symmetrically -- spacing to
  neighbours shifts by half the size delta per side. Regularize spacing afterwards with O-MODSPACE.
- Destructive: always gated behind an explicit Yes. No multi-step undo beyond AutoCAD's U.

---

## O-GRID
Commands: O-GRID, OGRID
File: ogrid/ogrid-1.0.lsp
Latest confirmed: 1.0 engine PASSES headless (north-bay array: detect-pattern -> rm10-evo,
col-gap 0.25, _ogeo-place resize+move to target exact). Full command (entsel + getpoint +
confirm) untested in GUI.

### Current Features
- [1.0 works headless] "Make this array perfect." Pick a REFERENCE module (its size = target,
  and seeds the flood-fill array), pick a FIXED corner point (origin -- the nearest module stays
  put), O-GRID auto-detects the row pattern + within-row gap (confirm/override [Yes/Pattern/Type]),
  then RESIZES every module to the reference size AND snaps it to its ideal lattice node. Modules
  only (PV-MODS). Explicit Yes before any change; CMDECHO 0 + single vla-regen.
- Reuses ogeo: _ogeo-array-from (flood-fill), _ogeo-detect-pattern / _ogeo-col-gap (auto-detect),
  _ogeo-row-positions (pattern -> cumulative offsets), _ogeo-place (winding-proof resize+move).
- Lattice: rows grouped along the module short axis (pattern spacing), cols along the long axis
  (uniform within-row gap). Origin module's (i0,j0) anchors the grid so it doesn't move.

### Notes / assumptions
- Anchor point selects which corner module is the fixed origin (nearest module); the point need
  not coincide with a module. Pattern auto-detected from current geometry vs *ocfg-patterns*.
- v1.0 uniform lattice per axis with the chosen pattern; assumes a regular grid (one flood-filled
  array). Uses the reference module's edge axes for the whole array (perfect alignment).

---

## Config + ogeo (shared, CSV-driven)
Files: config/modules.csv, config/patterns.csv ; oconfig/oconfig-1.07.lsp parses them ;
ogeo/ogeo-1.09.lsp (shared lib, no command).
Latest confirmed: parse + ogeo helpers PASS headless (1 module, 5 patterns; module-dims snaps to
canonical; flood-fill isolates one array of two; north-bay row-positions 0/57.91/116.82/175.73).

### Current Features
- [1.04 works headless] oconfig parses config\modules.csv -> *ocfg-modules* (name short long
  within-gap) and config\patterns.csv -> *ocfg-patterns* (name kind gaps end-side). CSV so the
  user adds modules/patterns in Excel. Pattern `kind`: uniform | endbay (north-bay) | alternating
  (dual-tilt) | sequence. Seeded: gridflex10, rm10-evo, fr10-dual, uniform, north-bay.
  Fallback to built-in defaults if a CSV is missing. oload-1.07 skips the config\ data folder.
- [1.0 works headless] ogeo shared lib: module reader/record (ent typ center ushort ulong short
  long nverts), _ogeo-module-dims (snap detected dominant to config), _ogeo-array-from (proximity
  flood-fill, thr = 1.4 x long), _ogeo-detect-pattern / _ogeo-col-gap (measure vs config),
  _ogeo-row-positions, _ogeo-place. Consumed by O-GRID and O-MODSPACE. Seeds the
  roadmap's planned ogeo/ refactor.
- [1.01 untested] _ogeo-all-modules graceful layer fallback (configured layer, else shape-gated
  all-layer scan -- 4-corner + footprint within tol of *ocfg-modules*; NOT a denylist). Shared
  _ogeo-pick-pattern (was ogrid local), _ogeo-axis-groups (row/col grouping), _ogeo-move.
- [1.03 untested] _ogeo-real-modules (recs): keep only records matching the dominant
  (modal) footprint -- the "real modules" O-SET counts. Mirrors oset's _oset-match-mods tolerances
  (tol-s = max(4.0, 0.10*short), tol-l = max(2.0, 0.02*long)), orientation-agnostic; returns recs
  unchanged if the footprint is indeterminate. The single home for "what counts as a module".
  Built on _ogeo-dominant (no footprint math re-derived).
- [1.04 untested] _ogeo-modules (): THE high-level entry for "the real modules in the drawing" --
  composes _ogeo-all-modules (scan + graceful fallback + viewport filter) with _ogeo-real-modules
  (footprint gate). SSM (1.1) / ZZA (1.2) / QQA (1.2) all call this instead of repeating the
  two-step `(_ogeo-real-modules (_ogeo-all-modules))` inline, so the working module set is
  defined in exactly ONE place.
- [1.05 untested] _ogeo-nearest-rec (recs pt) + _ogeo-array-at (pt): the click->array primitive.
  _ogeo-array-at seeds the flood-fill from the shared real-module set (_ogeo-modules), so EVERY
  "click a module" tool resolves the SAME array for the same click (no tool seeds off clutter --
  fixes a latent inconsistency where ssa seeded off the raw set, qqa off the real set). Replaced
  the per-tool copies: _omsp-nearest-rec/_omsp-array-at (omodspace 1.3 -> now a thin delegate, so
  opvspace inherits), _qqa-nearest + inline (qqa 1.3), _ssa-nearest + inline (ssa 1.1).
- [1.07 untested] _ogeo-all-modules no longer prints the raw "[modules] N on layer PV-MODS"
  element count on the success path. Standing rule: NO O-Suite tool reports the raw PV-MODS
  element count -- ONLY the real-module count (surfaced by the consuming tool after the footprint
  gate). The graceful-fallback message (layer empty -> shape-gated scan) and the viewport-outlier
  message stay (neither is the raw layer count). Affects every consumer (SSA / QQA / SSM / O-GRID /
  O-MODSPACE / O-PVSPACE / O-MODSIZE) in one place. (O-SET's own calibration funnel is separate --
  it still shows raw -> 4-corner -> modules as a diagnostic; flag to the user if that must change.)
- [1.06 untested] _ogeo-array-from flood-fill: membership tested against a VISITED ename list with
  the built-in (member) (short-circuits in C) instead of the linear, non-short-circuiting
  _ogeo-ename-in scan over the growing result -- the redundant O(n) re-scan per candidate is gone
  on the suite's hottest path (QQA/SSA/O-MODSPACE/O-PVSPACE click->array; SSM/ZZA per array).
  Same connected set; _ogeo-ename-in dropped.
- [1.02 untested] _ogeo-all-modules ends with a VIEWPORT-VISIBILITY filter (_ogeo-filter-shown):
  module-shaped objects whose centre is not inside any layout viewport's model-space window are
  ignored -- template copies parked in model space, cutsheet/detail geometry. Locks every consuming
  tool (O-MODSPACE, O-PVSPACE, O-GRID, O-MODSIZE) onto the ONE documented concentration of modules.
  Windows from VLA AcadPViewport props (ViewCenter/ViewHeight/Width/Height/TwistAngle); plan-view,
  non-paper-background (DXF id 1), twist-aware; clipped/3D viewports kept permissively. SAFE: filter
  off (*ocfg-filter-viewport* nil), no viewports in the drawing, or a filter that would drop ALL
  modules -> keeps everything. Reports the count ignored. Headless: load + window math + twist tested;
  live VLA viewport read on a real sheet UNTESTED.  (Filter REMOVED in ogeo-1.09 -- see below.)
- [1.09 works (headless)] Viewport / E-1.0 visibility filter REMOVED. Both the 1.02 _ogeo-filter-shown
  gate and the 1.08 sheet-scoping (_ogeo-vp-window-of / _ogeo-vp-windows-all / _ogeo-vp-windows-sheet
  / _ogeo-vp-windows / _ogeo-pt-shown-p) never produced windows on a real sheet -- confirmed live:
  E1.0win=0, ALLwin=0, so the keep-all safety always fired and tools "counted everything." Deleted in
  ogeo-1.09. _ogeo-all-modules now returns the footprint-gated real modules; an active O-ZONE
  rectangle (_ogeo-zone-keep / _ogeo-pt-in-zone) scopes the set. Flags *ocfg-filter-viewport* /
  *ocfg-module-sheet* removed (oconfig-1.07). Headless: load + 227 real / 103 zoned on TSC11590.

---

## O-CONFIG
File: oconfig/oconfig-1.07.lsp
Latest confirmed: 1.07 untested (1.0 works)

### Current Features
- [1.0 works] Sets 18 *ocfg-layer-* globals for all Opal layer names
- [1.0 works] Loaded first by O-LOAD before any tool; single edit point for re-deployment
- [1.07] *ocfg-module-sheet* and *ocfg-filter-viewport* REMOVED -- they fed the viewport / E-1.0
  visibility filter, deleted in ogeo-1.09 (it never produced windows on a real sheet). Module set
  is now all footprint-gated real modules; scope with O-ZONE. (*ocfg-module-sheet* was added in 1.06.)
- [1.02 untested] *ocfg-layer-dc* repointed "PV-DC-PATH" -> "E-STRINGING" (O-DC string path layer)
- [1.03 untested] *ocfg-layer-modules* "PV-MODS" (module source layer, confirmed live)
- [1.04 untested] modules.csv/patterns.csv -> *ocfg-modules* / *ocfg-patterns* (see Config + ogeo)
- [1.05 untested] *ocfg-filter-viewport* behavior flag (default T): the shared collector ignores
  module-shaped objects not shown in any layout viewport. Set nil to disable (consumed by ogeo).

### Globals written (all strings, all *ocfg-layer-* prefix)
- stringing      "PV-STRINGING"
- fill           "PV-STRINGING-FILL"
- count          "PV-STRINGING-COUNT"
- dc             "E-STRINGING"  (was "PV-DC-PATH"; changed in oconfig 1.02)
- homerun-n      "PV-HOMERUN-N"
- homerun-p      "PV-HOMERUN-P"
- jump           "PV-CABLE-JUMP"
- modules        "MODULES"  (corrected in oconfig 1.01; was "PV-MODULES LAYOUT")
- tags           "PV-TAGS"
- homerun-tags   "PV-HOMERUN-TAGS"
- schedules      "PV-SCHEDULES"
- nums           "PV-LAYOUT-NUMS"
- grid           "PV-LAYOUT-GRID"
- xdata          "PV-XDATA-LABELS"
- notes          "PV-NOTES"
- conduit        "E-CONDUIT RUN"
- conduit-tags   "E-PV-CONDUIT-TAGS"
- anno           "G-ANNO-TEXT"

---

## O-XLIB
Commands: O-XINSPECT/OXINSPECT, O-XCLEAR/OXCLEAR, O-XTEST/OXTEST
File: oxlib/oxlib-1.0.lsp
Latest confirmed: 1.0 works (O-XTEST passed)

### Current Features
- [1.0 works] Packed single-string XDATA schema v2.0: all fields in one "key=value|key=value" string
- [1.0 works] Backward compatible with v1.x multi-group format (separate group codes per field)
- [1.0 works] Namespace: "OCOTILLO" (shared with Stringtag suite — suites interoperate on same drawing)
- [1.0 works] Public API:
    _oxd-write  (ent fields-alist)         write/overwrite all XDATA
    _oxd-read   (ent) → alist              read all fields as ((key . value) ...)
    _oxd-get    (ent key) → string         read one field value
    _oxd-update (ent key value)            update one field, preserve others
    _oxd-field  (ent key) → string         alias for _oxd-get
    _oxd-set-field (ent key value)         alias for _oxd-update
- [1.0 works] O-XINSPECT: pick entity → print all XDATA key=value pairs to console
- [1.0 works] O-XCLEAR: pick entity → delete OCOTILLO XDATA block
- [1.0 works] O-XTEST: 6-test self-test (write / read / update / mref / legacy compat / round-trip)

### Standard XDATA field conventions (across all tools)
- type        entity role: "module", "PV-STRINGING", "PV-TAGS", "PV-DC-PATH", "PV-HOMERUN", etc.
- inverter    "INV-1" format (PV-TAGS, PV-HOMERUN tools)
- polarity    "N" or "P" (homerun tools)
- mppt        MPPT number as string (O-TAG mode 2)
- string      string number as string (O-TAG mode 2)
- module-ct   module count per boundary (O-BOUND)
- mref        space-separated entity handles of enclosed modules (O-BOUND)
- subarray    grid subarray index (O-GO / O-NAV)
- row         grid row index
- col         grid column index

---

## O-REF
Commands: O-REF, OREF
File: oref/oref-1.0.lsp
Latest confirmed: 1.0 works

### Current Features
- [1.0 works] Prints all O-Suite commands with short descriptions to command line
- [1.0 works] Prints current *ocfg-layer-* values
- [1.0 works] Prints *oset-mod-w/h/gap-x/gap-y* calibration values (or "not calibrated")
- [1.0 works] Prints loaded tool versions from *oload-versions*

---

## O-DC
Commands: O-DC, ODC, O-STRING, OSTRING
File: odc/odc-1.28.lsp
Latest confirmed: 1.28 untested (1.27, 1.26, 1.25, 1.24, 1.23, 1.22, 1.21, 1.20, 1.10 untested)

### Current Features
- [1.09 untested] Click INSIDE module rectangles to draw straight DC string LINEs center-to-center
- [1.10 untested] Module detection POSITIVE by layer: ssget "X" ((0 . "*POLYLINE") (8 . <module layer>)) -- heavyweight POLYLINE (VERTEX-subent walk) AND LWPOLYLINE; bbox-containment pick, nearest-center tiebreak; clicks outside any module ignored. Scan prints the layer name + count.
- [1.10 untested] Module layer from *ocfg-layer-modules* (default "MODULES") via _odc-mlayer
- [1.10 untested] OCS->WCS via entity-name trans (trans pt ent 0) -- correct for any extrusion (was integer "(trans pt 2 0)")
- [1.10 untested] No dependency on O-SET calibration
- [1.09 untested] Real LINE drawn immediately on the 2nd+ click (entmakex) -- visible during the command, not after
- [1.09 untested] Transient module highlight (redraw 3/4) for per-click node feedback
- [1.09 untested] OSNAP disabled for the command, restored on normal exit and on Esc via local *error* handler
- [1.09 untested] O-STRING / OSTRING aliases -- same command
- [1.21 untested] Layer from *ocfg-layer-dc*, now "E-STRINGING" (repointed in oconfig 1.02; was PV-DC-PATH), auto-created (+FROZEN/OFF warning). Layer color WHITE (ACI 7), was cyan (4); existing layer's color is corrected to 7 too.
- [1.20 untested] Layer created/updated with deliverable default props: linetype "Dash Style-13" (group 6), lineweight 0.50mm (group 370=50). Existing layer is brought up to these props via entmod. Linetype overridable via *ocfg-dc-linetype*; lineweight via *ocfg-dc-lineweight*.
- [1.20 untested] _odc-ensure-ltype: if the DC linetype is not loaded in the drawing, falls back to CONTINUOUS + warning (does NOT attempt -LINETYPE load -- "Dash Style-13" is a custom linetype expected in the drawing/template). Warns if LWDISPLAY is off so the lineweight shows.
- [1.21 untested] String JOINED into ONE entity: live LINE segments give click feedback during the loop, then on Enter they are deleted (entdel) and replaced by a single OPEN LWPOLYLINE (group 90=N, 70=0) through all module centers, ByLayer on the DC layer.
- [1.21 untested] "Box filled" arrowheads (SOLID-filled square) at the FIRST and LAST module centers, drawn after the loop, ByLayer, edges oriented to the adjacent segment. Size auto-scales to the module (edge = 0.4 x module short side) so it is visible at module scale -- the prior fixed 0.18 was sub-pixel. Absolute override via *ocfg-dc-arrow-size* (>0). Single-module string gets one box.
- [1.22 untested] Arrowhead square size reduced: multiplier 0.4 → 0.22 (≈17" side at typical module vs prior ≈31").
- [1.22 untested] Arrowhead square ALWAYS axis-aligned to WCS (sides parallel to X/Y axes). Prior behavior rotated the square to match the string direction, causing diagonal placement on angled endpoints.
- [1.23 untested] Arrowhead square orientation now derived from the MODULE's own polyline edge (_odc-mod-dir), not the string path. Sides are always parallel to the module sides regardless of string direction. Fixes diagonal squares on rotated-module drawings where WCS axis-alignment (1.22) still looked wrong relative to the module grid.
- [1.20 untested] Consecutive same-module clicks deduped (distance <= 1e-6) -> "same module, ignored", so first/last arrowhead anchors are clean.
- [1.24 untested] FIX attempt (did NOT stop the crash): _odc-poly-pts numeric-coord guards + non-geometry-vertex skip + nil-safe min/max. Superseded by 1.25's VLA approach.
- [1.25 untested] SIMPLIFY/ROBUST module scan: stop parsing geometry by hand. _odc-ent-bbox uses native vla-getBoundingBox for the WCS axis-aligned bbox of ANY entity (no group codes / OCS / vertex walk); _odc-ent-dir uses vlax-curve-getPointAtParam 0->1 for the module first-edge arrowhead direction. Both wrapped in vl-catch-all-apply so a single unmeasurable entity is SKIPPED, never fatal. Requires VLA/COM (vl-load-com; already loaded by oload). (Still scanned the module layer -- see 1.26.)
- [1.26 untested] DROP the scan-a-layer model entirely (replaced by per-click ssget). BROKEN in practice: (ssget pt) dropped into interactive window-select ("Specify opposite corner...") and then "can't measure that entity" on the viewport/titleblock it grabbed; also a closed UNFILLED panel polyline is not selectable from its interior. Superseded by 1.27.
- [1.27 untested] PURE CLICK-TO-CLICK. No entity identification at all -- no ssget / entsel / vla / layer / COM. getpoint loop, Enter finishes, nodes join into one LWPOLYLINE. Robust but dropped the center-snap users relied on; superseded by 1.28.
- [1.28 untested] GRACEFUL CENTER-SNAP restored without the fragility. Per click: _odc-candidates does (ssget "_C" ll ur ((0 . "*POLYLINE"))) over a small box around the click, sized to VIEWSIZE/40 -- two explicit corners so it never goes interactive ("Specify opposite corner", the 1.26 bug), no layer filter (no "none found", the 1.25 bug), local so no over-collection. _odc-snap-center picks the candidate whose bbox CONTAINS the click with a nearest-center tiebreak and returns its center. _odc-safe-bbox wraps the numeric-validated vertex parse (LWPOLYLINE group-10 + heavyweight-POLYLINE VERTEX walk, non-geometry vertices skipped, nil-safe min/max) in vl-catch-all-apply, so a malformed entity is skipped -- never "numberp: nil" (1.22-1.24 bug). If nothing valid contains the click -> fall back to the raw click point (so worst case == 1.27, can never regress). Summary reports "(K centered, M by click)". Arrowheads/output unchanged from 1.27.

### Entities created
- LWPOLYLINE: one open polyline through all module centers (group 90/70, group-10 xy, color 256/ByLayer) [1.21]
- SOLID: box-filled arrowhead at first (and last) module center (groups 10/11/12/13, color 256/ByLayer) [1.20]
- LINE: transient per-click feedback segments, deleted at end of loop (replaced by the LWPOLYLINE) [1.21]

### Globals read
- *ocfg-layer-dc*      -- target layer for the DC string lines (now "E-STRINGING")
- *ocfg-dc-linetype*   -- DC layer linetype name (optional; default "Dash Style-13") [1.20]
- *ocfg-dc-lineweight* -- DC layer lineweight in 1/100 mm (optional; default 50 = 0.50mm) [1.20]
- *ocfg-dc-arrow-size* -- box arrowhead edge length, absolute units; if >0 overrides the 0.4x-module auto-size [1.21]

### Dropped
- [1.28] pure click-to-click as the ONLY mode (1.27) -- center-snap restored as graceful default in 1.28; raw click point is now just the fallback when no panel is found under the click.
- [1.27] all entity identification at click time -- _odc-pick-ent (ssget pt), _odc-ent-bbox (vla-getBoundingBox), _odc-bbox-center, _odc-ent-dir (vlax-curve), and the VLA/COM dependency. (ssget pt) went interactive ("Specify opposite corner") and grabbed the wrong entity; closed unfilled panel polylines aren't interior-selectable anyway. Replaced by connecting raw click points. Arrowhead orientation now derives from the string segment, not the panel edge.
- [1.26] the scan-a-layer module model -- _odc-collect-modules, _odc-module-at, _odc-mlayer, the "scanning layer 'MODULES'" prompt, the "none found" branch, and the *ocfg-layer-modules* dependency. Fragile: depended on the module layer name + entity type matching; broke as a crash (pre-1.25) and as "none found" (1.25, panels not on MODULES). Replaced by per-click (ssget pt) live pick -- AutoCAD reports what's under the cursor; no scan needed.
- [1.25] manual geometry parsing for module bbox/orientation -- _odc-poly-pts (VERTEX-subent walk + group-10 read + OCS->WCS trans), _odc-poly-bbox, _odc-mod-dir, _odc-geom-vertex-p, _odc-list-min/max. Fragile: repeatedly produced "numberp: nil" on real drawings (a corner with a nil coordinate reaching the min/max helpers), not survivable by defensive guards (1.24). Replaced by native vla-getBoundingBox + vlax-curve-getPointAtParam, wrapped in vl-catch-all-apply.
- [1.21] separate LINE segments as the FINAL output -- replaced by one joined open LWPOLYLINE (LINEs now only transient click feedback).
- [1.21] fixed 0.18-unit arrowhead size -- sub-pixel at module scale (invisible); now auto-sizes to 0.4x module short side unless *ocfg-dc-arrow-size* overrides.
- [1.10] denylist detection (accept any *POLYLINE not on a tool layer) -- matched ~10k non-module
  polylines (structure/annotation/dims) on a real drawing; clicks hit giant ones -> lines drawn
  far off-screen, repeat clicks reused same giant. Replaced by positive module-layer filter.
- [1.09] LWPOLYLINE-only collection -- matched none of Opal's heavyweight POLYLINE modules
- [1.09] grdraw-only previews + deferred end-of-loop drawing -- lines now draw live on each click
- [1.09] snap-to-nearest-within-tolerance -- replaced by true "inside the module" bbox containment
- [1.09] row-normalization, direction arrows, start dot, ZOOM Extents, *oset-mod-w* tolerance dependency

---

## O-MODSPACE  (was O-ROWSPACE)
Commands: O-MODSPACE, OMODSPACE  ->  opens [Set/Measure]
File: omodspace/omodspace-1.3.lsp   (new folder; predecessor orespace/ shelved to dormant/)
Latest confirmed: 1.3 PASSES headless load. 1.3 = _omsp-array-at now delegates to shared
_ogeo-array-at (real-module-seeded; dropped local _omsp-nearest-rec). GUI untested.

### 1.0 -- rename + generalize to rows AND columns
- [1.0 untested] Renamed O-ROWSPACE -> O-MODSPACE (alias OMODSPACE); new folder omodspace/.
  Generalized from row-only to BOTH axes: rows step along the module SHORT edge, columns along
  the LONG edge. Helpers _omsp-*; predecessor orespace/ moved to dormant/.
- [1.0 untested] SINGLE module pick floods the whole array (shared _ogeo-array-from). The old
  "select the array (ssget) then pick a module" two-step is gone. Records are built on the picked
  module's OWN layer, so it works on whatever layer the array lives on (not only the config layer).
- [1.0 untested] Measure reports BOTH axes (rows + columns: per-gap list + min/max/avg) plus the
  detected config pattern name.
- [1.0 untested] Set corrects BOTH axes in one run, anchored on the picked module (its row AND its
  column stay fixed): Rows [Uniform/North-bay/Pattern/Skip] (defaults from *ocfg-patterns* via
  _ogeo-detect-pattern; Pattern opens the shared picker for the no-match case); Columns [Set/Skip]
  (default within-gap from *ocfg-modules*). Each axis is independent -- Skip leaves it untouched.
  Plan prints; explicit Yes. Modules only (no racking/strings moved -- consistent with O-GRID).
- [1.0 untested] Built on ogeo: _ogeo-axis-groups (grouping), _ogeo-row-positions (ideal positions),
  _ogeo-move (locked-safe). The two axes are orthogonal, so row + column shifts are computed from the
  original record set and applied independently.

### 1.1 -- anchor-point model + reusable engine
- [1.1 untested] Set replaces the module pick with an ANCHOR POINT (OSNAP on, snap to a corner).
  Array = the array of the module NEAREST the point (`_omsp-array-at` -> `_ogeo-all-modules` +
  `_ogeo-array-from`). The point also selects the FIXED row + column (`_omsp-group-idx-at`: the
  groups nearest the point stay put). Handles arrays with NO module at the corner -- anchors on the
  point + nearest group, never on a module-at-corner.
- [1.1 untested] Measure switches to click-anywhere-near (OSNAP off); nearest module identifies
  the array (no anchor needed; read-only).
- [1.1 untested] North-bay (only) now picks an edge-validated module in the NORTH-END row
  (`_omsp-pick-north`): re-prompts if the picked module is not on an end row; sets `endside`
  (low/high). Replaces the old `[Yes/No]` "is the fixed row the north-bay row" question.
- [1.1 untested] Set body factored into `_omsp-set-one (arr anchorpt rtgt ctgt)` so O-PVSPACE can
  batch many arrays with no duplicated spacing math.

### 1.2 -- split the apply core out of _omsp-set-one
- [1.2 untested] The move core is split into `_omsp-apply-one (arr anchorpt rtgt ctgt)` -- NO
  prompts: recomputes the fixed row/col from the array's own anchor point, builds the shifts, moves
  modules (CMDECHO off), returns `(nok nfail)`. `_omsp-set-one` keeps the single-array plan +
  `[Yes/No]` and calls `_omsp-apply-one` on Yes (O-MODSPACE behavior unchanged). O-PVSPACE 1.1
  drives `_omsp-apply-one` directly to batch one param set across many arrays with one combined confirm.

## SSA  (VVN nomenclature)  --  "All Arrays" (SELECT ARRAYS), drawing-wide
Commands: SSA  ->  select every real module + report total + per-array breakdown
File: ssa/ssa-2.0.lsp   (new folder)
Latest confirmed: 2.0 PASSES the offline paren/string-balance check (net 0, never negative).
Headless accoreconsole load could not be exercised this session (the runner hangs on (load)
from an untrusted path / redirected stdout); GUI run + selection untested.
Naming: VVN grammar -- verb SS (select) + noun A (arrays), drawing-wide. SSA is the "All Arrays"
select tool; its single-array counterpart is QQA ("One Array"). Lives in opal-tools (runs today)
on the ogeo shared library; bare VVN name, no O- prefix / aliases.

### 2.0 -- REWRITE: unified drawing-wide SELECT ARRAYS (folds in SSM / "QQM")
- [2.0 untested] No pick. Collects every REAL module via the shared `_ogeo-modules` (layer +
  graceful fallback + footprint gate + viewport filter), grip-selects them all
  (`sssetfirst`), then prints: total REAL modules, number of distinct arrays (flood-fill
  `_ogeo-array-from` over the real set, visited-ename `member` test, no lambda), module footprint
  (`_ogeo-module-dims`), and a PER-ARRAY breakdown line (modules + rows x cols via
  `_ogeo-axis-groups`), largest array first (local insertion sort `_ssa-by-size`). This is the
  drawing-wide "array info for all arrays" the user asked for; it subsumes the old SSM (select all
  modules) and the "QQM" (query all modules) readout.
- [2.0 untested] Reports ONLY real modules -- the raw PV-MODS element count is NEVER shown. ogeo
  1.07 dropped the "[modules] N on layer ..." line from the shared collector, so no O-Suite tool
  prints the raw layer total; SSA reports the post-footprint-gate count.
- [2.0 design] No geometry/spacing math here -- every number comes from an ogeo helper. Replaces
  the v1.x "click one module -> select its array" behavior (that single-array role is QQA's).

### 1.x (superseded by 2.0) -- single-click array selection
- [1.0 untested] Click one module (OSNAP off, click-near; seed = nearest module centre, same
  read-only interaction as O-MODSPACE Measure). The connected array floods via shared
  `_ogeo-array-from` and is delivered to the active pickfirst set with `(sssetfirst nil ss)` --
  grips show, no window-drag. Nothing is modified; run any command next (ERASE/MOVE/CHPROP/layer/
  PROPERTIES) and it acts on the whole array.
- [1.0 untested] Built on ogeo only (`_ogeo-all-modules` with graceful layer fallback +
  `_ogeo-array-from`); local helper `_ssa-nearest`. No geometry re-implemented.
- [1.0 untested] VERIFY collision: confirm SSA is not a native command / pgp alias in use (VVN
  collision rule). If it collides, UNDEFINE in loader (native unused) or rename (native in use).

## ZZA  (VVN nomenclature)  -- ARCHIVED to dormant/zza/ (does not load)
Commands: ZZA  ->  zoom window to all PV array boundaries
File: dormant/zza/zza-1.3.lsp   (archived -- excluded from the oload scan; move back to a root
folder to re-activate)
STATUS: ARCHIVED. The zoom never worked correctly in the live GUI across two attempts and the
remaining diagnosis needs live GUI iteration. Headless load is clean (C:ZZA defines), but:
  - 1.2 (vla-ZoomWindow): only SHIFTED the view, never zoomed -- VLA zoom is unreliable in a
    paper-space viewport / non-World UCS.
  - 1.3 (command-line ZOOM Window, UCS-transformed points): zoom now fires, but on a layout it
    zooms WAY out -- the command zooms the ACTIVE space, so model-space-magnitude bbox corners
    blow the PAPER view out. A correct fix must force the zoom onto MODEL space and handle three
    contexts (Model tab / inside a floating viewport / paper space active), which is only
    verifiable live. Parked here until that live debugging happens.
NOTE: already dropped from the O toolbox in olaunch 1.18; not in OHELP. No active references.
Naming: VVN grammar -- verb ZZ (zoom, NEW verb) + noun A (array). Frames every PV module in one
view. Lives in opal-tools (runs today) on the ogeo shared library; bare VVN name, no aliases.

### 1.0 -- zoom to all arrays
- [1.0 untested] No pick. Collects every module via `_ogeo-all-modules` (configured layer first,
  shape-gated all-layer fallback), accumulates the WCS bounding box (`vla-getboundingbox` per
  module -- correct for rotated Solesca modules), and `vla-ZoomWindow`s to it with a 5% margin.
- [1.0 untested] View-only: nothing in the drawing is modified. No geometry re-implemented
  (ogeo for detection; getboundingbox for extents).
- [1.0 untested] VERIFY collision: confirm ZZA is not a native command / pgp alias in use
  (acad.pgp checked: no ZZA alias).

### 1.1 -- frame only real modules
- [1.1 untested] Pipes `_ogeo-all-modules` through `_ogeo-real-modules` (ogeo 1.02) before the
  bbox loop, so stray clutter on the module layer (mismatched footprints) no longer stretches the
  zoom window. The framed count now equals O-SET's module count. Readout says "N real modules".

### 1.2 -- shared module-set entry
- [1.2 untested] Calls the shared `_ogeo-modules` (ogeo 1.04) instead of the inline
  `(_ogeo-real-modules (_ogeo-all-modules))`. Same behavior; the working module set is now defined
  in one place shared with SSM + QQA.

### 1.3 -- FIX the zoom (was only shifting the view)
- [1.3 untested-GUI] `vla-ZoomWindow` is unreliable when the active context is a layout /
  paper-space viewport (and with a non-World UCS): it recenters without fitting the window, so ZZA
  appeared to "shift the viewport but not zoom". Replaced with a command-line `ZOOM Window`, and the
  WCS bbox corners are transformed into the current UCS (`(trans p 0 1)`) because the ZOOM command
  reads points in the UCS, not WCS. Now frames the arrays correctly from the Model tab and from
  inside a floating layout viewport. Bbox math (per-module `vla-getboundingbox`) unchanged. CMDECHO
  saved/restored (also in `*error*`).

## SSM  (VVN nomenclature)  --  SUPERSEDED in the toolbox by SSA (All Arrays)
Commands: SSM  ->  select every real PV module + report (count / arrays / footprint)
File: ssm/ssm-1.1.lsp   (new folder)
Latest confirmed: 1.0 worked live (selected 227 modules). 1.1 untested-live (select + query combine).
NOTE: As of olaunch 1.22 / ohelp 1.07, SSM is no longer a toolbox button -- its "select all
modules drawing-wide + count" role is now SSA ("All Arrays", ssa-2.0), which adds the per-array
breakdown. SSM stays loadable on disk (O-LOAD still loads it; the user manages dormant), just
off the menu. Its readout prints only the real-module count (no raw PV-MODS element count).
Naming: VVN grammar -- verb SS (select) + noun M (module), drawing-wide (cf. QQA = one array).

### 1.0 -- select all modules
- [1.0 works] No pick. Real-module set -> `(sssetfirst nil ss)`. Grips active; nothing
  modified. Selected count equals O-SET's module count (254 -> 227 live).
- [1.0 untested] COLLISION: acad.pgp aliases `SSM -> *SHEETSET`. A LISP `C:SSM` is expected to
  shadow the pgp alias (no acad.pgp edit, per VVN rule). VERIFY live: type SSM and confirm it
  selects, not opens Sheet Set Manager. If SHEETSET opens, escalate to a rename.

### 1.1 -- select + query (folds in "QQM"); shared module-set entry
- [1.1 untested] Now SELECTS and REPORTS in one command. After grip-selecting every real module
  it prints a drawing-wide readout: MODULES (count), ARRAYS (distinct arrays via flood-fill
  `_ogeo-array-from` over the real set, marking visited enames -- member test, no lambda), and
  MODULE footprint (`_ogeo-module-dims`). This is the "query all modules" (QQM) behavior folded
  into SSM per user request ("ssm+qqm").
- [1.1 untested] Calls the shared `_ogeo-modules` (ogeo 1.04) instead of the inline
  `(_ogeo-real-modules (_ogeo-all-modules))`; one shared working-set definition with QQA. Guard
  now checks `_OGEO-MODULES` (needs ogeo 1.04+).

## SS  (VVN nomenclature)
Commands: SS  ->  select all objects on the picked entity's layer
File: ss/ss-1.0.lsp   (new folder)
Latest confirmed: 1.0 PASSES headless load (C:SS defined).
GUI select untested.
Naming: VVN grammar -- bare SS = the SELECT verb at full breadth (pick one object, get its whole
layer). Reassigned from the roster's planned "master tile menu" (no menu built yet); SSL is now
redundant and not built. Generic (any layer / object type); no ogeo dependency.

### 1.0 -- select by layer
- [1.0 untested] `(entsel)` -> picked entity's DXF group-8 layer -> `(ssget "X" (cons 8 lay))`
  -> `(sssetfirst nil ss)`. Grips active; nothing modified. Nil pick re-prompts via message.
- [1.0 untested] VERIFY collision: confirm bare SS is not a native command / pgp alias in use
  (acad.pgp checked: no SS alias).

## QQA  (VVN nomenclature)  --  "One Array", click + select + report
Commands: QQA  ->  click a module, report (incl. row-by-row qty) AND select its array
File: qqa/qqa-1.4.lsp   (new folder)
Latest confirmed: 1.0 worked live (reported the array). 1.4 PASSES the offline paren/string-
balance check; the row-by-row block + the _ogeo-array-at migration untested-live.
Naming: VVN grammar -- verb QQ (query) + noun A (array). The "One Array" select tool; its
drawing-wide counterpart is SSA ("All Arrays"). Selects + reports one clicked array.
1.3 = click->array via shared _ogeo-array-at (dropped local _qqa-nearest).

### 1.4 -- row-by-row module-quantity breakdown ("One Array")
- [1.4 untested] After the ARRAY / GRID / MODULE summary, QQA now prints a ROW QTY block: one
  line per row (Row n -> qty modules), from the same short-edge row groups (`_ogeo-axis-groups`)
  used for the GRID count. Surfaces partial / short rows a single "R rows x C cols" can't show.
  Local pad helper `_qqa-pad`; no new geometry. Pairs with SSA (All Arrays, per-array totals) --
  QQA drills into ONE array. Counts REAL modules only (raw PV-MODS count never shown; ogeo 1.07).

### 1.0 -- query array
- [1.0 works] Click-near (OSNAP off; seed = nearest module centre) -> `_ogeo-array-from`.
  Reports module count, rows x cols (`_ogeo-axis-groups`), module footprint
  (`_ogeo-module-dims`), row gaps (`_ogeo-row-gaps`), column gap (`_ogeo-col-gap`), and matched
  config pattern (`_ogeo-detect-pattern`). Read-only -- nothing drawn or modified.
- [1.0 works] Every number comes from an existing ogeo helper; no geometry/spacing math added.
  Local helpers `_qqa-nearest`, `_qqa-nstr` only. Should agree with O-MODSPACE Measure.

### 1.1 -- count real modules only
- [1.1 untested] Filters through `_ogeo-real-modules` before the flood-fill (same modal-footprint
  gate as SSM / ZZA), so the seed, the flooded array, and the ARRAY count are all real modules --
  footprint clutter no longer inflates the count.

### 1.2 -- select + query (folds in SSA); shared module-set entry
- [1.2 untested] After printing the array report, QQA now grip-selects the whole array
  (`ssadd` over the flooded members + `sssetfirst`) and prints SELECTED count -- so one click
  both reports AND selects. This folds the old standalone SSA into QQA per user request
  ("combine ssa and qqa"). SSA stays on disk but is dropped from the O toolbox.
- [1.2 untested] Calls the shared `_ogeo-modules` (ogeo 1.04) instead of the inline
  `(_ogeo-real-modules (_ogeo-all-modules))`; one shared working-set definition with SSM. Guard
  now checks `_OGEO-MODULES` (needs ogeo 1.04+).

## O-PVSPACE
Commands: O-PVSPACE, OPVSPACE
File: opvspace/opvspace-1.1.lsp
Latest confirmed: 1.1 untested

### Purpose
Re-space MANY arrays in a layout in one command, in two phases: batch-pick every array's
anchor point, then get prompted once, then apply that one param set to all at once.

### Current Features
- [1.1 untested] Phase 1 -- BATCH-PICK: loop anchor point (OSNAP on) -> `_omsp-array-at`;
  each point detects its array and fixes that array's anchor row/col. Re-picking the same array
  (seed-entity match) is skipped; each kept array is highlighted (`redraw` seed) + counted. Enter
  finishes; no arrays -> nothing to do.
- [1.1 untested] Phase 2 -- PROMPT ONCE: rows + columns resolved against the FIRST picked array
  as representative (`_omsp-rows-target` / `_omsp-cols-target`). North-bay picks the odd-bay end
  exactly once and reuses it for every array (arrays share orientation across a layout).
- [1.1 untested] Phase 3 -- ONE combined plan (array count + rows/cols target) + a single
  `[Yes/No]`, then `_omsp-apply-one` over every picked array; each array keeps its own anchored
  row/col fixed. Tallies arrays re-spaced + total module-moves; locked-layer warning on failures.
- [1.1 untested] Pure wrapper over O-MODSPACE's `_omsp-*` engine -- modules only, no duplicated math.

### Dropped
- [1.0] Per-array interleaved `[Same/Configure/Skip]` and the per-array plan + `[Yes/No]` confirm.
  Replaced by one uniform param set + one combined confirm applied to all picked arrays (the v1.0
  "Same is fine across a layout" assumption is now the default for the whole batch).

### Predecessor history -- O-ROWSPACE / O-RESPACE (folder orespace/, shelved to dormant/)

### Purpose
Re-space an array's rows when the racking system changes (e.g. Unirac GridFlex 10 ->
RM10 EVO). Anchor row stays put; every subsequent row is pushed away by a cumulative
gap change, so all inter-row gaps grow (or shrink) by the amounts entered.

### Current Features
- [1.0 works] User SELECTS array entities (ssget) -- detail views / SLDs / title blocks are never touched; no layer filter, scope = the selection
- [1.01 works] Spacing direction is ALWAYS a two-point pick (handles Solesca rotated modules + this drawing's left-right rows): click the fixed row, then click toward the moving rows -- no keyword prompt
- [1.0 works] Each entity's WCS bbox center via native vla-getBoundingBox wrapped in vl-catch-all-apply -- type-agnostic (heavyweight POLYLINE, LWPOLYLINE, INSERT, ARC, CIRCLE, TEXT, MTEXT, DIMENSION); unmeasurable entity skipped + counted, never fatal
- [1.0 works] Rows = entities at the same projection onto the spacing direction; insertion-sort ascending, group by projection gap > tolerance (default 3.0), anchor = smallest projection
- [1.04 untested] ABSOLUTE target spacing: enter desired NORTH-BAY (first gap) and FIELD (all other gaps) inter-row spacing; tool sets every gap EXACTLY to target. shift(0)=0 (anchor); shift(k)=shift(k-1)+(target_gap(k)-current_gap(k)). Each gap lands on target independently, no error accumulation; corrects per-row anomalies + uniform offset in one pass. Defaults north 13.5, field 14.5 (RM10 EVO)
- [1.04 untested] MOVE now depends on measured edges (not just the readout) -> module pick matters for the result; O-RESPACE warns if no module picked
- [1.05 untested] O-SPACE opens with a [Set/Measure] mode prompt (default Set). Set = absolute spacing + move (1.04); Measure = report rows + current inter-row spacing, no move (former O-ROWS)
- [1.05 untested] Measure mode DROPS the two-point direction pick: direction derived from the picked module's SHORT edge (_ors-mod-stepdir; row-stepping axis, rotation-correct for landscape). Module pick also sets the measure layer.
- [1.07 untested] BOTH modes now: select array + pick ONE module -- the single pick sets measure layer + row direction + (Set) anchor + (Set) direction sign. Dropped the separate two-point direction pick AND the separate measure-layer pick from Set. Set: pick a module in the fixed row; direction auto-oriented (_ors-pick-setup) so that row becomes row 1; warns (_ors-in-group) if the picked module isn't in an end row
- [1.08 untested] Set asks "Is the fixed row the NORTH-BAY row?" [Yes/No] <Yes>. Yes -> odd north-bay gap is next to the fixed row (anchor end). No -> odd gap at the FAR end (anchor the SOUTH row but keep north bay at the north). Target assignment: north applies at k=1 (Yes) or k=lastk (No), field elsewhere. Plan title states where the odd bay sits
- [1.09 untested] Set spacing-pattern prompt [Uniform/North-bay] <North-bay>. Uniform = one value, all gaps equal (skips the north-bay question; north=field=one value). North-bay = odd end bay + field (1.08 flow). Name is geometry-based not product-based; RM10 EVO numbers (13.5/14.5) are just the North-bay defaults. Plan title reflects pattern. If ever generalized to either-end-as-norm, rename North-bay -> End-bay
- [1.02 untested] Reports INTER-ROW SPACING (edge-to-edge gap), not center-to-center pitch: each entity's TRUE geometry projected onto the direction (real polyline vertices via dual-path read; bbox corners only as fallback for inserts/text) so gaps are correct on rotated modules; row gap = next row near edge - this row far edge
- [1.02 untested] Plan table columns: row / ents / spacing(prev) / shift. Delta prompts reworded to "inter-row spacing change"
- [1.03 untested] Optional MODULE-LAYER measurement filter: pick ONE module (entsel) and spacing edges are measured from that layer only; racking/strings excluded from the readout. Grouping + MOVE still use the full selection (everything still moves). Enter at the pick = measure all (1.02 behavior). A row with no module-layer entity falls back to all its entities. "ents" column then shows modules-measured-per-row. Reason: on TSC11590 the all-entity reading varied 11.75-14.22 (tracking ents/row) because racking hardware sits in the module gap; module-only should read ~14.5 / ~13.5
- [1.0 works] vla-move per entity; locked-layer failures caught + reported as a fail count
- [1.02 untested] O-ROWS / OROWS (was O-RSCHK in 1.0-1.01): measure-only -- select + direction + tolerance, reports detected rows and inter-row spacing edge-to-edge (min/max/avg) with no changes; use to verify row detection and confirm the baseline gap before committing

### Entities created
- None (moves existing entities only)

### Globals read
- None (fully self-contained; no *oset-* calibration or *ocfg-* layer dependency)

### Dropped
- [1.07] Set mode's two-point direction pick AND its separate measure-layer pick. Replaced by a single module pick in the fixed row (sets layer + direction + anchor + sign). Reason: user request to tighten UI / drop the redundant second selection. Helpers _ors-get-dir and _ors-get-mlayer removed.
- [1.06] Command names O-SPACE / OSPACE / O-RESPACE / ORESPACE -- renamed to O-ROWSPACE / OROWSPACE. Reason: user request "change cmd name to o-rowspace". (Folder kept as orespace/ to preserve version history; O-LOAD loads by folder, name match is cosmetic.)
- [1.05] Standalone O-ROWS / OROWS command -- folded into O-SPACE's Measure mode. Reason: user request "purge orows command".
- [1.05] Two-point direction pick in measure path -- replaced by module-derived short-edge direction. Reason: user request "drop step to select to and from rows if measuring".
- [1.04] Relative delta input (dlt1 north-bay change / dlt2 subsequent change). Replaced by absolute target distances (enter the distance between rows, not the change). Reason: user request -- absolute targets force even spacing and fix irregularities, vs deltas which only shift uniformly.
- [1.02] Center-to-center "pitch" metric -- replaced by edge-to-edge inter-row spacing (the number the designer actually works in; ~13" on the GridFlex baseline, not ~50"). Reason: user request "prefer inter-row spacing to pitch".
- [1.02] Command name O-RSCHK / ORSCHK -- renamed to O-ROWS / OROWS (clearer; "what's orschk?" was cryptic). Reason: user request "choose a better name".
- [1.01] X / Y axis direction options (and the _ors-ucs-axis helper). Direction is now always the two-point pick. Reason: user request -- Pick is the only sensible mode for rotated Solesca arrays; the axis options added a prompt step with no real use.

### Notes / assumptions
- A racking element that physically SPANS multiple rows projects to a mid-row and would
  move with only that row -- keep such spanning entities out of the selection, or verify
  via O-SPACE Measure first. Modules/per-row racking segments group cleanly.
- Inter-row spacing is edge-to-edge between a row's far edge and the next row's near edge, measured from the SELECTED entities' true extents. For the cleanest reading select just modules (or modules + per-row racking); a string/homerun sticking out past a row edge can pull the reported gap in.
- Measure mode derives the row direction from the picked module's SHORT edge -- correct for landscape modules whose rows step along the short edge. If an array's rows step along the LONG edge, Measure would read the wrong axis; use Set mode (explicit two-point pick) or flag it.

---

## O-BOUND
Commands: O-BOUND, OBOUND, O-BLINK, OBLINK
File: dormant/obound/obound-1.02.lsp
Latest confirmed: 1.02 broken (hull shape wrong; see notes)

### Current Features
- [1.0] User selects modules → draws rectilinear hull LWPOLYLINE on PV-STRINGING layer
- [1.01] Accepts both LWPOLYLINE and POLYLINE entities (dual-path bbox read)
- [1.01] Layer denylist: rejects entities on all 18 known O-Suite tool layers
- [1.01] Row-cluster algorithm: groups modules by Y-center proximity (tolerance ~80% *oset-mod-h*);
  sorted rows used to compute hull step-points; hull walks column boundaries row by row
- [1.01] Hull output: closed LWPOLYLINE, 2D UCS coords, ByLayer color (group 70=1)
- [1.0] XDATA written to boundary entity: type="PV-STRINGING", module-ct=N,
  mref=space-separated handles of enclosed module entities
- [1.0] XDATA back-written to each enclosed module: key O-BOUND-id = boundary entity handle
- [1.0] O-BLINK: scans all existing PV-STRINGING LWPOLYLINEs, finds enclosed modules via
  ssget "CP" (crossing polygon), writes XDATA links without redrawing boundaries
- [1.02 broken] Hull shape wrong: produces simple bounding box regardless of selection shape;
  row-cluster step logic does not correctly skip inter-row gaps for non-rectangular selections

### Entities created
- LWPOLYLINE: closed rectilinear hull on PV-STRINGING (white/7 if new), color 256/ByLayer

### Globals read
- *oset-mod-h*           -- row-cluster Y-tolerance (80% of mod-h)
- *ocfg-layer-stringing* -- target layer name
- _oxd-write, _oxd-read  -- XDATA library (must be loaded)

### Fix needed
- Rectilinear hull step logic: handle concave/non-rectangular selections (U-shapes, gaps)
- O-BLINK ssget uses "module" layer keyword; update for Opal layer denylist approach

---

## O-FILL
Commands: O-FILL, OFILL
File: dormant/ofill/ofill-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] User selects string-boundary LWPOLYLINE(s) → one HATCH entity covering all selected
- [1.0 untested] HATCH pattern: SOLID, ACI color 8 (dark gray), layer PV-STRINGING-FILL (ACI 8 if new)
- [1.0 untested] Each selected polyline appended as outer loop via VLA vla-AppendOuterLoop; single hatch
- [1.0 untested] HATCH sent to draworder back: (command "_.DRAWORDER" ...) after creation

### Entities created
- HATCH: one per command run, SOLID pattern, ACI 8, layer PV-STRINGING-FILL

### Constraints
- Requires VLA/COM (vl-load-com) -- will fail in environments without COM
- Single HATCH per run; separate colors per inverter require multiple runs

---

## O-COUNT
Commands: O-COUNT, OCOUNT
File: dormant/ocount/ocount-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] User selects string-boundary LWPOLYLINE(s) → MTEXT count label at centroid of each
- [1.0 untested] Module detection: ssget "X" with filter (0 . "LWPOLYLINE") -- DOES NOT find POLYLINE modules
- [1.0 untested] Size filter: rejects LWPOLYLINEs whose bbox exceeds 1.5× mod-w or 1.5× mod-h;
  fallback if uncalibrated: 200.0 × 100.0 units
- [1.0 untested] Point-in-polygon test: ray-casting algorithm; tests module bbox center against
  boundary polygon vertices
- [1.0 untested] Center dedup tolerance: 0.5 units (prevents double-counting shared corners)
- [1.0 untested] Label text: integer count string, placed at mass center of accepted module centers
- [1.0 untested] MTEXT background mask: white (ACI 255, group 90=3, 441=2) or
  gray (ACI 9, group 90=1, 441=2); configurable
- [1.0 untested] MTEXT: color ACI 7, layer PV-STRINGING-COUNT (white/7 if new)
- [1.0 untested] MTEXT height: 0.4× *oset-mod-h* if calibrated, else 40.0 units

### Entities created
- MTEXT: one per selected boundary, layer PV-STRINGING-COUNT

### Globals read
- *oset-mod-w*, *oset-mod-h* -- size filter (fallback 200, 100)

### Fix needed
- Change module ssget filter to (0 . "*POLYLINE") and add VERTEX walk for POLYLINE type

---

## O-TAG
Commands: O-TAG, OTAG, O-TAGO, OTAGO, O-TAGFIX, OTAGFIX
File: dormant/otag/otag-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Two modes (select via O-TAGO):
    Mode 1 = PV terminal labels ("PV1", "PV2", ...) by inverter wirebox position
    Mode 2 = INV/MPPT/STRING labels from CSV row data
- [1.0 untested] CSV source: live mode reads current.txt pointer file from *O-TAG-live-dir* to get path;
  non-live mode opens file browser dialog
- [1.0 untested] *O-TAG-live-dir* default: "C:\Users\Stephen Hebert\Documents\CAD\Stringtag\csv-files\"
  (hardcoded; update for other users)
- [1.0 untested] CSV format auto-detected: Wente format (MPPT rows × INV columns) vs
  PFS format (INV/MPPT/STRING/MODULES/ARRAY/ROWS/COLOR columns; detected by header scan)
- [1.0 untested] Mode 1 wirebox order hardcoded for CPS 275KTL: MPPT sequence [1,11,5,3,9,7,8,12,4,6,10,2]
- [1.0 untested] Mode 2: places "INV-N MPPT-M STR-K" MTEXT at user-clicked insertion points
- [1.0 untested] MTEXT background mask: mask=1 → white bg (ACI 255, group 90=3);
  mask=2 → gray bg (ACI 9, group 90=1); group 441=2 for both
- [1.0 untested] MTEXT height: *O-TAG-ht* (default 0.4× *oset-mod-h* if calibrated, else 3.0)
- [1.0 untested] MTEXT rotation: *O-TAG-angle* (default 0)
- [1.0 untested] XDATA stamped to each MTEXT if _oxd-write loaded:
  type="PV-TAGS", inverter=, mppt=, string= fields
- [1.0 untested] O-TAGFIX: re-creates MTEXT entities with updated mask settings without moving them
- [1.0 untested] PFS color name→ACI map: YELLOW→2, ORANGE→30, RED→1, CYAN→4, GREEN→3, BLUE→5,
  MAGENTA→6, WHITE→7
- [1.0 untested] Terminal count→ACI map: 14→30 (orange), 15→150 (blue), etc. (hardcoded)

### Entities created
- MTEXT: one per terminal/string label, layer PV-TAGS (white/7 if new)

### Globals read/written
- *O-TAG-ht*, *O-TAG-angle*, *O-TAG-inv-prefix*, *O-TAG-invnum*, *O-TAG-csv*
- *O-TAG-live-mode*, *O-TAG-map-groups*, *O-TAG-inv-names*
- *O-TAG-pfs-colors*, *O-TAG-pfs-rows*, *O-TAG-mask*, *O-TAG-mode*
- *oset-mod-h* (default text height)

---

## O-TABLE
Commands: O-TABLE, OTABLE, O-TABLEO, OTABLEO
File: dormant/otable/otable-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Generates stringing schedule table from CSV (Wente or PFS format)
- [1.0 untested] Table cells: SOLID entities filled with ACI color keyed to string terminal count;
  color map hardcoded: 14→ACI 30 (orange), 15→ACI 150 (blue), etc.
- [1.0 untested] Table borders: closed 4-vertex LWPOLYLINE per row, ByLayer, layer PV-SCHEDULES
- [1.0 untested] Labels: MTEXT per cell and for column/row headers; bold Arial via {\\fArial|b1;}
- [1.0 untested] Legend: color-key beside ("R") or above ("A") the table (configurable)
- [1.0 untested] Paper-space mode (*O-TABLE-ps* T): all dimensions ÷ 80 (1:80 scale)
- [1.0 untested] Rotation: *O-TABLE-angle* rotates table insertion point only
- [1.0 untested] O-TABLEO: configure text height, cell width, row height, legend position, PS mode
- [1.0 untested] CSV source: same live-mode pointer (current.txt) as O-TAG
- [1.0 untested] Sub-modes via option prompt: conduit schedule, cable-jumper schedule
- [1.0 untested] PFS format: color names mapped to ACI; MPPT rows from ROWS column

### Entities created
- SOLID: one per filled cell, ACI by terminal count
- LWPOLYLINE: closed 4-vertex cell border, ByLayer
- MTEXT: cell values, headers, legend labels; layer PV-SCHEDULES (white/7 if new)

### Globals read/written
- *O-TABLE-ht*, *O-TABLE-cw*, *O-TABLE-rh*, *O-TABLE-legend-pos*
- *O-TABLE-ps*, *O-TABLE-angle*, *O-TABLE-pfs-colors*
- *oset-mod-h* (default row height = 2× text height)

---

## O-HOMERUN
Commands: O-HOMERUN, OHOMERUN, O-HROPT, OHROPT, O-VPC, OVPC
File: dormant/ohomerun/ohomerun-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Interactive node-by-node homerun cable/conduit path drawing
- [1.0 untested] User clicks module centers sequentially; each pair of accepted clicks adds a segment
- [1.0 untested] Four routing modes (O-HROPT → click-mode): gap, long, seq, pair
- [1.0 untested] Offset: *O-HOMERUN-off-dist* (distance), *O-HOMERUN-off-dir* (-1 or 1) from module edge
- [1.0 untested] Module snap: tolerance 60% *oset-mod-h* perpendicular; fallback to raw click
- [1.0 untested] Maintains axis chain (*O-HOMERUN-ctr-chain*) for co-linear segment collection
- [1.0 untested] Output layer: PV-HOMERUN-N (negative) or PV-HOMERUN-P (positive) by polarity
- [1.0 untested] O-VPC: sets viewport color overrides by polarity (N vs P layers)

### Entities created (expected)
- LINE or POLYLINE segments, layer PV-HOMERUN-N or PV-HOMERUN-P

### Globals read/written
- *O-HOMERUN-off-dist*, *O-HOMERUN-off-dir*, *O-HOMERUN-click-mode*
- *O-HOMERUN-line-mode*, *O-HOMERUN-last-orient*
- *O-HOMERUN-ctr-chain*, *O-HOMERUN-ctr-ent*
- *oset-mod-w*, *oset-mod-h*

---

## O-HRROUTE
Commands: O-HRROUTE, OHRROUTE
File: dormant/ohrroute/ohrroute-1.0.lsp
Latest confirmed: untested

---

## O-HRINV
Commands: O-HRINV, OHRINV, O-HRINVC, OHRINVC
File: dormant/ohrinv/ohrinv-1.0.lsp
Latest confirmed: untested

---

## O-HRLABEL
Commands: O-HRLABEL, OHRLABEL, O-HRLABELO, OHRLABELO
File: dormant/ohrlabel/ohrlabel-1.0.lsp
Latest confirmed: untested

---

## O-HRSCHED
Commands: O-HRSCHED, OHRSCHED, O-HRSCHEDO, OHRSCHEDO
File: dormant/ohrsched/ohrsched-1.0.lsp
Latest confirmed: untested

---

## O-CONDLABEL
Commands: O-CONDLABEL, OCONDLABEL, O-CONDLABELO, OCONDLABELO
File: dormant/ocondlabel/ocondlabel-1.0.lsp
Latest confirmed: untested

---

## O-CONDSCHED
Commands: O-CONDSCHED, OCONDSCHED, O-CONDSCHEDO, OCONDSCHEDO
File: dormant/ocondsched/ocondsched-1.0.lsp
Latest confirmed: untested

---

## O-JUMP
Commands: O-JUMP, OJUMP
File: dormant/ojump/ojump-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Two-click cable jump path: click start module center, click end module center
- [1.0 untested] Module snap: 3+ vertex LWPOLYLINE only (DOES NOT find POLYLINE modules);
  tolerance 75% *oset-mod-w* or fallback 50.0 units
- [1.0 untested] Output: SOLID diamond dot at start + SOLID triangle arrowhead at end
  (same geometry algorithm as O-DC pre-1.09)
- [1.0 untested] Layer: *ocfg-layer-jump* (PV-CABLE-JUMP, white/7 if new), entities ByLayer

### Entities created
- SOLID: diamond dot at start (groups 10–13, ±radius corners)
- SOLID: arrowhead triangle at end (groups 10=bl, 11=br, 12=tip, 13=tip)

### Globals read
- *oset-mod-w*       -- snap tolerance (75%)
- *ocfg-layer-jump*  -- target layer

### Fix needed
- Change module ssget filter to "*POLYLINE" and add VERTEX walk for heavyweight POLYLINE

---

## O-JMPLABEL
Commands: O-JMPLABEL, OJMPLABEL, O-JMPLABELO, OJMPLABELO
File: dormant/ojmplabel/ojmplabel-1.0.lsp
Latest confirmed: untested

---

## O-JMPSCHED
Commands: O-JMPSCHED, OJMPSCHED, O-JMPSCHEDO, OJMPSCHEDO
File: dormant/ojmpsched/ojmpsched-1.0.lsp
Latest confirmed: untested

---

## O-ROWJUMP
Commands: O-ROWJUMP, OROWJUMP
File: dormant/orowjump/orowjump-1.0.lsp
Latest confirmed: untested

---

## O-RJLABEL
Commands: O-RJLABEL, ORJLABEL
File: dormant/orjlabel/orjlabel-1.0.lsp
Latest confirmed: untested

---

## O-RJSCHED
Commands: O-RJSCHED, ORJSCHED
File: dormant/orjsched/orjsched-1.0.lsp
Latest confirmed: untested

---

## O-BOM
Commands: O-BOM, OBOM, O-BOMO, OBOMO, O-BOMN, OBOMN
File: dormant/obom/obom-1.0.lsp
Latest confirmed: untested

---

## O-INVINV
Commands: O-INVINV, OINVINV
File: dormant/oinvinv/oinvinv-1.0.lsp
Latest confirmed: untested

---

## O-GRID
Commands: O-GRID, OGRID
File: dormant/ogrid/ogrid-1.0.lsp
Latest confirmed: untested

---

## O-ROWNUM
Commands: O-ROWNUM, OROWNUM
File: dormant/orownum/orownum-1.0.lsp
Latest confirmed: untested

---

## O-POPULATE
Commands: O-POPULATE, OPOPULATE
File: dormant/opopulate/opopulate-1.0.lsp
Latest confirmed: untested

---

## O-PURGE
Commands: O-PURGE, OPURGE, O-RENAME, ORENAME
File: dormant/opurge/opurge-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Deletes legacy/deprecated layers and all entities on them
- [1.0 untested] Prompts Y/N before proceeding
- [1.0 untested] For each layer on purge list: unlock, thaw, turn on, VLA-delete all entities, then delete layer
- [1.0 untested] Hardcoded purge list: E-WIRE-0, E-WIRE-1, O-BOUND-FILL, Inv-5-N, Inv-5-P,
  Inv-6-N, Inv-6-P, "A. Rowlabels-OUTER", "A. String-directions", Rows,
  Left-edge-mods, Remove-mod
- [1.0 untested] O-RENAME: renames legacy layer names to current O-Suite standard names (stub)

### Constraints
- Purge list is hardcoded; edit code to add/remove entries
- Requires VLA/COM (vl-load-com) for entity deletion

---

## O-XDATA
Commands: O-XDATA, OXDATA
File: dormant/oxdata/oxdata-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Stamps OCOTILLO XDATA to all untagged entities on recognized O-Suite layers
- [1.0 untested] Layer → XDATA type map: MODULE layers → type="module"; PV-STRINGING → "PV-STRINGING";
  PV-DC-PATH → "PV-DC-PATH"; PV-HOMERUN-N → type="PV-HOMERUN", polarity="N"; etc.
- [1.0 untested] Inverter parsing: extracts "INV-N" from layer name via "INV-" prefix scan
- [1.0 untested] Polarity parsing: extracts "N" or "P" from layer name suffix "-N" / "-P"
- [1.0 untested] Skips entities that already carry OCOTILLO XDATA (non-destructive)

### Entities modified
- All types on recognized layers: XDATA appended via entmod group -3 OCOTILLO block

### Globals read
- *ocfg-layer-* family for layer name matching

---

## O-XVIEW
Commands: O-XVIEW, OXVIEW
File: dormant/oxview/oxview-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Places MTEXT debug label beside each entity that carries OCOTILLO XDATA
- [1.0 untested] Label content: all key=value pairs from XDATA, one per line
- [1.0 untested] Layer PV-XDATA-LABELS created OFF (color -7) so labels are invisible by default;
  turn layer on manually to inspect; turn off or freeze to hide

### Entities created
- MTEXT: one per XDATA-tagged entity, layer PV-XDATA-LABELS (off/-7 if new)

---

## O-NAV
Commands: O-NAV, ONAV, O-NAVD, ONAVD
File: dormant/onav/onav-1.0.lsp
Latest confirmed: 1.0 untested (stub)

### Current Features
- [1.0 untested] String/inverter navigator using grvecs viewport overlay (no permanent entities created)
- [1.0 untested] Highlights current string and inverter membership in viewport color overlay
- [1.0 untested] INV color map: INV-1→ACI 5 (blue), INV-2→ACI 210 (magenta), etc.
- [1.0 untested] Module grid stored in *O-NAV-grid*; entity handle map in *O-NAV-hdl-map*
- [1.0 untested] O-NAVD: dumps current nav state and string list to console

### Entities created
- None (grvecs overlay only; cleared on REGEN or REDRAWALL)

### Globals
- *O-NAV-grid*, *O-NAV-hdl-map*, *O-NAV-dirty*, *O-NAV-view-mode*
- *O-NAV-bnd-list*, *O-NAV-cur-str*, *O-NAV-mod-w*, *O-NAV-mod-h*
- *O-NAV-vecs*, *O-NAV-str-colors*

---

## O-ISO
Commands: O-ISO, OISO, O-ISONEG, OISONEG
File: dormant/oiso/oiso-1.0.lsp
Latest confirmed: untested

---

## O-SEL
Commands: O-SEL, OSEL
File: dormant/osel/osel-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] No implied selection: selects all entities on current layer (CLAYER system variable)
- [1.0 untested] With implied selection: selects all entities across every layer represented in the
  implied selection (multi-layer mode); useful after selecting a mixed group
- [1.0 untested] Activates the resulting selection via sssetfirst so AutoCAD grips/highlights it

### Entities created
- None (selection only; sssetfirst modifies active selection)

### Globals read
- CLAYER (AutoCAD system variable)

---

## O-FRONT
Commands: O-FRONT, OFRONT
File: dormant/ofront/ofront-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Sends implied or user-selected entities to draw order front
- [1.0 untested] Uses native AutoCAD DRAWORDER command: (command "._DRAWORDER" "_P" "" "_F")

### Entities modified
- All in selection (draw order only; no geometry change)

---

## O-TRANS
Commands: O-TRANS, OTRANS
File: dormant/otrans/otrans-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Applies transparency 0–90 to all entities on PV-STRINGING-FILL layer
- [1.0 untested] Prompts for integer 0–90; validates range before applying
- [1.0 untested] Applies via VLA EntityTransparency property on each entity returned by ssget

### Constraints
- Hardcoded to PV-STRINGING-FILL layer only (edit code to target other layers)
- Requires VLA/COM (vl-load-com)

---

## O-LABEL
Commands: O-LABEL, OLABEL
File: dormant/olabel/olabel-1.0.lsp
Latest confirmed: stub only

### Planned
- Professional deliverable callout labels: ByLayer, MTEXT with background mask, no per-entity color fills
- Full spec in plans/alright-time-to-build-spicy-stardust.md
- Implementation pending SLBL plan approval; Opal version uses *ocfg-* layer names

---

## O-GO
Commands: O-GO, OGO
File: dormant/ogo/ogo-1.0.lsp
Latest confirmed: stub only

### Current Features (partial stub)
- [1.0 untested] Word normalizer: maps user vocabulary to O-Suite entity type names
  ("module"→"module", "boundary"→"PV-STRINGING", "string"→"PV-STRINGING", etc.)
- [1.0 untested] Inverter qualifier parser: "INV-1", "inv1", "inverter 1" all normalized to "INV-1"
- [1.0 untested] Grid address lookup: retrieves module entity by (subarray, row, col) via XDATA query
  using _oxd-get to match subarray/row/col fields

### Planned
- Wire input parsing to dispatch actual O-Suite commands
- Activate once core geometry tools (O-BOUND, O-COUNT, O-DC) are confirmed working

---

## O-ANI
Commands: O-ANI, OANI
File: dormant/oani/oani-1.0.lsp
Latest confirmed: stub only

### Planned
- Splash animation on suite load (low priority; implement after all functional tools confirmed)
- NOTE: superseded as the brand surface by O-LAUNCH (a stable DCL dialog). The grvecs
  splash approach (see Stringtag SANI 3.10) is transient/flickery and is not the path.

---

## OADMIN
Commands: OADMIN, O-ADMIN
File: oadmin/oadmin-1.0.lsp
Latest confirmed: 1.0 untested
STATUS: VESTIGIAL. As of O-LAUNCH 1.13 the master-rewrite gate is DEV-vs-BUNDLE (the dialog
variant) + the dev-only Advanced submenu, NOT this flag. OADMIN still toggles the registry value
but nothing reads it anymore. Keep for now in case a grantable non-dev unlock is wanted later;
otherwise it can be retired.

### Current Features (historical -- no longer wired to the menu)
- [1.0 untested] Toggles the per-machine admin unlock that WAS read by olaunch 1.12's
  _olaunch-admin-p to reveal the master-rewrite actions. 1.13+ ignores it.
- [1.0 untested] Persisted in HKCU\Software\Ocotillo\OpalTools  Admin = "1"/"0" (the hive omode
  uses). A DEV machine is always admin regardless of the flag (_olaunch-admin-p). To grant a
  teammate, have them run OADMIN On once on their machine. OADMIN ships in the release (so the
  capability can be granted), unlike omode which is dev-only.
- [1.0 untested] OADMIN [On/Off] <toggle>; Enter flips the current state. Prints the new state and
  reminds the user to re-open the toolbox.

### Globals / state
- Registry HKCU\Software\Ocotillo\OpalTools  Admin  ("1" = unlocked)

### Notes
- This is an accident/role guard, not security: any user can opt in. Combined with the LK-STD/
  LK-FILTER verify + ban-list, the pre-write backup (config\backups\, lkstd/lkfilter 1.23+), and
  git on the source machine, a mistaken master rewrite is recoverable.

---

## O-LAUNCH
Commands: O, OPAL, O-MENU
File: olaunch/olaunch-1.22.lsp  (+ olaunch.dcl: 3 main variants opal_launcher / opal_launcher_dev /
      opal_launcher_prodtest, plus the opal_advanced submenu)
Latest confirmed: 1.08 works (dialog opens live, DEV/BUNDLE switch verified); 1.09-1.22 untested-live

### Current Features
- [1.22 untested] Select group is "One Array" (QQA) + "All Arrays" (SSA), mirroring Spacing's
  One/All split. Replaces "One Array" (QQA) + "All Modules" (SSM) -- SSM's all-modules role moves
  to SSA (All Arrays, drawing-wide select + per-array breakdown). DCL keys QQA + SSA in all three
  main variants (DCL edit needs a one-time AutoCAD restart to reparse).
- [DCL] Consistent toolbox labels/categories. "Draw" group renamed to "Spacing"; each scope group
  now reads "One Array" (single, clicked) then "All ..." (drawing-wide), in the same order:
  Spacing = "One Array" (O-MODSPACE) / "All Arrays" (O-PVSPACE); Select = "One Array" (QQA) /
  "All Arrays" (SSA) (was "All Modules" (SSM) before olaunch 1.22). Replaces the mismatched
  "Module Spacing"/"PV Spacing" + "All Modules"/"Array".
  DCL needs a one-time AutoCAD restart to reparse (the Select buttons changed in 1.22).
- [1.21 untested] Removed the "Reload Tools" button; O now reloads all tools QUIETLY at open in DEV
  (replaces the button) so the toolbox always reflects source edits. Quiet suppresses the load
  banner AND O-SET auto-calibrate. Dropped the OLOAD action_tile, the res-20 handler, and the DCL
  button (opal_launcher_dev Setup). BUNDLE mode does not auto-reload.
- [1.20] REVERTED the 1.19 DCL cache-buster. Loading the dialog from a temp COPY of olaunch.dcl
  broke O in the full GUI -- it dumped the DCL text to the command line and errored "bad argument
  type: streamp T" (passed headless, failed live). Back to loading olaunch.dcl directly by path
  (proven 1.18 behavior). CONSEQUENCE: AutoCAD caches a parsed DCL per session, so after a menu
  edit a one-time AutoCAD RESTART is needed to see it (OLOAD reloads LISP, not the cached DCL).
  Do NOT reintroduce a temp-copy cache-buster without testing in the full GUI (not headless-repro).
- [1.19 REVERTED] DCL cache-buster via temp copy (TEMPPREFIX+MILLISECS). Caused the live streamp-T
  regression above; superseded by 1.20.
- [1.18 untested] "Select" group trimmed to the two COMBINED tools: "All Modules" (SSM, now select +
  query: count/arrays/size) and "Array" (QQA, now select + query the clicked array). Dropped the
  standalone SSA and ZZA buttons (SSA folded into QQA; Zoom Arrays removed). DCL "Select"
  boxed_column is now 2 buttons in all three main variants. (Superseded the 1.17 four-button cut
  SSM/SSA/QQA/ZZA.)
- [1.14 untested] "Save Layers/Filters" moved out of the main DEV toolbox into a DEV-only
  "Advanced >" submenu (opal_advanced, key ADV -> done_dialog 40). Its "< Back" returns to the main
  toolbox (done_dialog 2 -> reopen), same as the old Layer Tools back. The submenu's one button
  "Save Layers/Filters -> master" runs olaunch:save-master (lk:std-save then lk:filter-save).
- [1.14 untested] "Back to DEV" button (key MODEDEV -> omode:to-dev) shown ONLY in BUNDLE
  (prod-test), via a third main variant opal_launcher_prodtest -- never in a real teammate BUNDLE
  install (they can't reach DEV). Main variant is now a 3-way pick: dev / prodtest / bundle.
- [1.13 untested] Gate is DEV vs BUNDLE (the dialog variant), NOT the OADMIN flag. Bundle/teammate
  toolboxes show "Standardize" (LK-APPLY) only. The 1.12 admin-unlock model (opal_layers_admin /
  _olaunch-admin-p) was dropped; OADMIN still exists as a command but no longer drives the menu.
  LK-APPLY already does cleanup + apply-standard + build-filters, so STDSET/FILBUILD are not in the
  menu (still typable via LK-STD / LK-FILTER).
- [1.11 untested] "Switch to Bundle" button in the DEV toolbox Setup group (key MODESW, dev variant
  only) flips to a prod-test via omode:to-bundle, then reopens the toolbox -- now the teammate
  variant showing "BUNDLE (prod-test)". Variant + mode are recomputed each loop pass so the reopen
  reflects the new mode. Guarded by _olaunch-have so a build without omode just prints a notice.
  Return to DEV is by restart or OMODE (the button is one-way by design; prod-test = teammate view).
- [1.10 untested] "Reload Tools" shows ONLY in DEV. DCL can't hide a tile at runtime, so there are
  two main dialog variants -- opal_launcher (bundle, no Reload) and opal_launcher_dev (adds Reload)
  -- and C:O picks one from _olaunch-mode, wiring the OLOAD button only in DEV.
- [1.08 untested] Dropped the "Calibrate" (O-SET) button -- OLOAD auto-calibrates. "Reload Tools"
  now runs the reload and REOPENS the main toolbox (done_dialog 20 -> C:O-LOAD -> loop) instead of
  closing. (O-SET is still typable at the command line.)
- [1.07 untested] FIX: "< Back" in the Layer Tools panel reliably returns to the main toolbox. It
  was is_cancel + is_default, which made a click report as the default (status 1) and fall out of
  the loop (escaping). Back is now key "back" wired to done_dialog 2; ESC also returns to main.
- [1.10 untested] Mode shown by folding it into the version line as "v1.0  <middot>  DEV"
  (middot = (chr 183), so source encoding can't garble it). 1.09's separate centered "mode" tile
  floated awkwardly and was removed from both dcl dialogs. If a build renders the middot as
  garbage, swap (chr 183) for " | " or " - ".
- [1.09 untested] Shows the load mode in the toolbox: DEV / BUNDLE / BUNDLE (prod-test).
  Detection is self-contained (_olaunch-mode reads *o-suite-root*: "OpalTools-prodtest" ->
  prod-test, "ApplicationPlugins" -> BUNDLE, else DEV) so it works in a packaged install where
  the omode tool is absent.
- [1.04 untested] Layers group collapsed into ONE "Layer Tools >" sub-panel (Clean up + standardize
  / Save standard / Apply standard / Build filters / Save filters) to kill the Standardize-vs-
  Standards name clash. Buttons call C:LK-APPLY, lk:std-save/set, lk:filter-set/save directly.
- [1.03 untested] Sub-menus: "Layer Standards" and "Layer Filters" open a sub-panel of buttons
  (Save / Set ; Build / Save) wired to lk:std-save/lk:std-set and lk:filter-set/lk:filter-save,
  so no command-line prompt. LK-APPLY button relabeled "Standardize Layers". Dispatch: main
  done_dialog 10/11 -> sub-panel via new_dialog on the same loaded dcl id.
- [1.02 untested] Trimmed toolbox: dropped DC String (O-DC), Force ByLayer (LK-BYLAYER), and
  Clean Up Layers (LK-CLEANUP) from the menu; clarified the layer buttons (Clean Up + Standardize,
  Layer Standards (Save / Set), Layer Group Filters). Those commands still load and are typable.
- [1.01 untested] Logo polish: symmetric gold diamond + real cream disc (filled circle drawn
  row-by-row) split into thirds by two charcoal bars; cream uses ACI 255 so it renders on the
  dark badge (1.0 used ACI 7 which drew black/invisible). Logo tile narrowed (dcl width 16->10).
- [1.0 untested] DCL "toolbox" dialog: Opal mark + version, with grouped buttons (Draw / Layers / Setup).
- NOTE: DCL has a hard visual ceiling (flat gray AutoCAD dialog). Planned: replace with a
  modern dockable .NET palette (see task / project notes); keep tool logic in LISP.
- [1.0 untested] Buttons map to commands via *olaunch-map*; a button whose command is not
  loaded is shown disabled (mode_tile 1), so the toolbox never offers a missing tool.
- [1.0 untested] Selecting a button sets *olaunch-cmd*, closes the dialog (done_dialog 1),
  then runs the command after the dialog is fully unloaded.
- [1.0 untested] Locates olaunch.dcl via *o-suite-root*, with a findfile fallback.
- [1.0 untested] This is the foundational visual identity; replaces a ribbon. The mark is a
  vector recreation of the Opal icon (matches the brand). A raster logo slide is not used
  (DCL slides do not capture raster cleanly); the vector mark scales and needs no asset file.

### Entities created
- None (dialog only; no drawing geometry).

### Globals
- *olaunch-ver*    -- version string shown in the dialog
- *olaunch-main*   -- alist of (tile-key . "C:COMMAND") for the generic main buttons
- *olaunch-layers* -- alist of (tile-key . "command") for the Layer Tools sub-panel
- *olaunch-go*     -- the command chosen by a button; run after the dialog unloads

---

## OHELP
Commands: OHELP, O-HELP
File: ohelp/ohelp-1.07.lsp  (1.01: list trimmed to match toolbox; O-DC/LK-BYLAYER archived, LK-CLEANUP no longer advertised)
Latest confirmed: 1.0 untested

### Current Features
- [1.07 untested] New "Select" group: QQA (One Array -- click one array, select + row-by-row qty)
  and SSA (All Arrays / SELECT ARRAYS -- select every real module + per-array breakdown). Groups
  list is now Draw / Select / Layers / Setup. Replaces the old SSM advertisement.
- [1.0 untested] Prints a grouped, plain-language list (Draw / Select / Layers / Setup) of the
  commands that are actually loaded (checked via atoms-family + member).
- [1.0 untested] Plain-text fallback for O-LAUNCH; works in headless/script sessions.

### Entities created
- None (prints to the command line).

### Globals
- *ohelp-cmds*

---

## O-ZONE
Commands: O-ZONE, OZONE
File: ozone/ozone-1.01.lsp
Latest confirmed: 1.0 untested (1.01: house-rule cleanup -- _ozone-bbox-of tracks min/max in the
walk instead of (apply 'min/'max ...); headless load-checked)

### Current Features
- [1.0 untested] O-ZONE [Set/Clear/Show]. SET rough-drags a rectangle (getpoint+getcorner),
  crossing-selects the modules grabbed (ssget "_C" + module layer filter), and stores
  *ozone-bounds* = the centre-bbox of those modules PADDED by half a module long-side, then
  SCALED by *ozone-margin* (default 2.0) about its centre. So a loose drag around one array
  yields a forgiving zone that won't reach a distant second array. Reports the in-zone count and
  grip-highlights the modules (sssetfirst).
- [1.0 untested] The zone SCOPES the module set: while set, every tool routed through ogeo
  (_ogeo-all-modules -> O-MODSIZE, SSA/SSM, click->array) and O-SET see only modules whose centre is
  inside the rectangle. No zone -> all footprint-gated real modules. CLEAR releases it; SHOW
  re-reports/highlights. This is the way to exclude clutter / a second array / parked template copies
  on the module layer (it replaces the removed viewport/E-1.0 visibility filter).
- [1.0 untested] Self-contained: *ozone-bounds* / *ozone-margin* live here; the filter helpers
  (_ogeo-pt-in-zone / _ogeo-zone-keep) live in ogeo (always loaded), so ogeo never depends on
  ozone and the gate is inert when no zone is set.

### Entities created
- None (stores a bounds global; grip-highlights existing modules).

### Globals
- *ozone-bounds*  (xmin ymin xmax ymax) WCS, or nil
- *ozone-margin*  expansion factor about the grabbed-system centre (default 2.0)

### Notes / not yet done
- Interactive drag + grip-highlight need the GUI; the zone-keep engine is headless-testable by
  setting *ozone-bounds* directly. Live AutoCAD run UNTESTED.
