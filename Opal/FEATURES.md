# O-Suite — Feature Registry
# Deployed at: Opal Energy
#
# PURPOSE: Cross-check before iterating any tool. Confirms what has and has not
# been verified in AutoCAD LT 2027. All forked tools are considered NON-WORKING
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
#   Canonical implementation: _odc-poly-pts / _odc-poly-bbox in odc/odc-1.09.lsp.
#   Tools with known LWPOLYLINE-only bug: O-SET v1.0, O-COUNT v1.0, O-JUMP v1.0.
#
# FORMAT:
#   [x.xx]           = version introduced
#   [x.xx untested]  = written but NOT yet verified in AutoCAD
#   [x.xx broken]    = tested and known to fail (describe issue)
#   [x.xx works]     = confirmed working in AutoCAD LT 2027
# ============================================================


## O-LOAD
Commands: O-LOAD, OLOAD
File: oload/oload-1.04.lsp
Latest confirmed: 1.03 works

### Current Features
- [1.04 untested] Relocatable root: _oload-root returns *o-suite-root* when bound (set by the deploy bootstrap), else the original hardcoded dev path. Enables the ApplicationPlugins bundle install.
- [1.04 untested] Auto-run of O-SET on load is now suppressed in quiet mode, so silent startup (bootstrap) never opens a calibration prompt.
- [1.04 untested] Quiet load line and banner de-branded; points users to OHELP / O.
- [1.0 works] Loads oconfig first (layer globals), then all tool subfolders in Opal root
- [1.0 works] Detects highest-versioned .lsp per folder via ASCII lexicographic sort on filename
- [1.0 works] Prints [OK] / [skip] per tool with UPDATE flag when version changes between loads
- [1.0 works] Tracks loaded versions in *oload-versions* alist: ((folder-name . "x.xx") ...)
- [1.0 works] Auto-runs O-SET if *oset-mod-w* is nil or zero after all tools are loaded
- [1.01 works] Skips ".", "..", tools/ from directory scan
- [1.02 works] *oload-quiet* T suppresses per-tool output (used by acad.lsp auto-loader)
- [1.02 works] Quiet mode: single summary line "O-Suite loaded -- N tools. O-REF for help."
- [1.03 works] Version extraction from filename: "obound-1.02.lsp" → "1.02" (major.minor only)
- [1.03 works] Skipped folders listed at end: "Skipped (no .lsp): ..."

### Globals written
- *oload-versions* -- alist of (folder-name . "x.xx") for every loaded tool
- *oload-quiet*    -- suppress per-tool output when T (set before loading)

### Assumptions / constraints
- Root path hardcoded: C:\Users\adria\CAD\Automations\Opal\
- Version sort is ASCII; avoid version numbers where ASCII order ≠ numeric order
  (e.g., "1.9" sorts after "1.10" → use "1.09", "1.10", not "1.9", "1.10")
- Folder skip list: dormant, oload, oconfig, test, tools (case-insensitive match)

---

## O-SET
Commands: O-SET, OSET
File: oset/oset-1.0.lsp
Latest confirmed: 1.0 broken (LWPOLYLINE-only; Opal modules are heavyweight POLYLINE)

### Current Features
- [1.0 broken] Box-select any 2x2+ grid of modules; derives mod-W, mod-H, gap-X, gap-Y from bboxes
- [1.0 broken] Module filter: 4-vertex LWPOLYLINE only — finds ZERO modules on Opal drawings
- [1.0 works] Layer denylist function _oset-non-module-layer: substring match on 18 known tool layers
  (PV-STRINGING, PV-DC-PATH, PV-HOMERUN, PV-CABLE-JUMP, PV-TAGS, PV-SCHEDULES, PV-LAYOUT,
  PV-XDATA, E-CONDUIT, G-ANNO-TEXT, DC-ARROW, LABEL, TABLE, CALLOUT, STRUCTURE, etc.)
  -- this function is reused by O-DC and other tools, so it does work even if O-SET itself fails
- [1.0 works] Requires minimum 4 accepted entities with ≥2 distinct X-centers and ≥2 distinct Y-centers
- [1.0 works] Center dedup tolerance: 1.0 drawing units (hardcoded)
- [1.0 works] Gap formula: pitch = distance between adjacent row/col centers; gap = pitch - module-dimension
- [1.0 works] Prints calibration summary to console on success

### Globals written
- *oset-mod-w*  -- module width (X span of bbox)
- *oset-mod-h*  -- module height (Y span of bbox)
- *oset-gap-x*  -- horizontal gap between adjacent modules in same row
- *oset-gap-y*  -- vertical gap between adjacent modules in same column

### Fix needed
- Change module ssget filter from `(0 . "LWPOLYLINE")` to `(0 . "*POLYLINE")`
- Add VERTEX sub-entity walk for POLYLINE type (reference _odc-poly-pts in odc-1.09)

---

## O-CONFIG
File: oconfig/oconfig-1.02.lsp
Latest confirmed: 1.02 untested (1.0 works)

### Current Features
- [1.0 works] Sets 18 *ocfg-layer-* globals for all Opal layer names
- [1.0 works] Loaded first by O-LOAD before any tool; single edit point for re-deployment
- [1.02 untested] *ocfg-layer-dc* repointed "PV-DC-PATH" -> "E-STRINGING" (O-DC string path layer)

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

## O-ROWSPACE
Commands: O-ROWSPACE, OROWSPACE  ->  opens [Set/Measure]
File: orespace/orespace-1.09.lsp  (folder still named orespace/)
Latest confirmed: 1.09 untested (1.08 works)

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

## O-LAUNCH
Commands: O, OPAL, O-MENU
File: olaunch/olaunch-1.0.lsp  (+ olaunch.dcl)
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] DCL "toolbox" dialog: Opal mark (gold diamond + split disc on charcoal,
  drawn with vector_image/fill_image) + version, with grouped buttons (Draw / Layers / Setup).
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
- *olaunch-ver*, *olaunch-map*, *olaunch-cmd*

---

## OHELP
Commands: OHELP, O-HELP
File: ohelp/ohelp-1.0.lsp
Latest confirmed: 1.0 untested

### Current Features
- [1.0 untested] Prints a grouped, plain-language list (Draw / Layers / Setup) of the
  commands that are actually loaded (checked via atoms-family + member).
- [1.0 untested] Plain-text fallback for O-LAUNCH; works in headless/script sessions.

### Entities created
- None (prints to the command line).

### Globals
- *ohelp-cmds*
