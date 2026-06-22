# LayerKit — Feature Registry
# AutoCAD layer/utility tools | Ocotillo Labs
#
# PURPOSE: Cross-check before iterating any tool. Confirms what has and has not been
# verified under the LayerKit loader in AutoCAD 2027.
#
# UPDATE RULE: Add new features as [x.xx works] at write time. After confirming a
# feature works in AutoCAD, drop the "untested" tag. When something fails, note what
# failed so the next session has context. Helper commands are listed as features of
# their parent tool.
#
# FORMAT:
#   [x.xx]           = version introduced; behavior carried from the pre-LayerKit tool
#   [x.xx works]  = not yet verified under the LayerKit loader
#   [x.xx broken]    = tested and known to fail (describe issue)
#   [x.xx works]     = confirmed working in AutoCAD 2027
# ============================================================


## LK-LOAD
Commands: LK-LOAD, LKLOAD
File: lkload/lkload-1.6.lsp  (1.6: relocatable root for the deploy bundle)
Latest confirmed: 1.1 works (1.0 as PV-LOAD)

### Current Features
- [1.6 untested] Relocatable root: _lkload-root returns *lk-suite-root* when bound (set by the
  deploy bootstrap), else the original hardcoded dev path. Enables the ApplicationPlugins bundle.
- [1.0 works] Scans every tool subfolder in the LayerKit root and loads the
  highest-versioned .lsp in each
- [1.0 works] Highest version chosen via ASCII lexicographic sort on filename
  (_pvload-str< + insertion sort _pvload-sort-str + _pvload-best-lsp)
- [1.0 works] Prints [OK] / [skip] per tool, with ** UPDATE ** flag when a folder's
  version changes between loads
- [1.0 works] Tracks loaded versions in *pvload-versions* alist: ((folder . "x.xx") ...)
- [1.0 works] *lkload-quiet* T suppresses per-tool output and prints one summary line
  ("LayerKit loaded -- N tool(s).") — used by layerkit-load.lsp
- [1.0 works] LKLOAD undashed alias
- [1.0 works] Skipped folders listed at end ("Skipped (no .lsp): ...")
- [1.1 works] Rebrand PV→LK: command LK-LOAD/LKLOAD, helpers _lkload-*, globals *lkload-*

### Globals written
- *lkload-versions* -- alist of (folder-name . "x.xx") for every loaded tool
- *lkload-quiet*    -- suppress per-tool output when T (set before loading)

### Assumptions / constraints
- Root path: *lk-suite-root* if bound (deploy bundle), else hardcoded C:\Users\adria\CAD\Automations\layer-kit\
- Folder skip list (case-insensitive): lkload, config, archive, test, tools
- Version sort is ASCII; use "1.09"/"1.10", never "1.9"/"1.10"

---

## LK-CLEANUP
Commands: LK-CLEANUP, LK-APPLY
File: lkcleanup/lkcleanup-1.47.lsp
- [1.47 works (headless)] An UNMATCHED layer with 0 entities is no longer prompted to merge into a
  standard -- it's classified [EMPTY] and queued for auto-purge (new cond branch in classify Level 4:
  (= 0 (lk:count-on-layer layer-name)) -> "[EMPTY] name (0 entities) -> purge", no prompt, no zoom).
  lk:purge-empty-layers (the existing global -PURGE in the execute block) removes them; the execute
  step now also fires when empties are the ONLY actionable items (gate is (or (> total-assigns 0)
  empty-purge)), so an empties-only drawing still gets cleaned. Summary gained an "Empty -> purge: N"
  line. Verified headless: a lone empty LAYER13 was classified [EMPTY], not prompted, and purged
  (GONE after execute). Scope: only UNMATCHED empties; an empty layer that matches a keyword/static
  mapping still follows its normal rename path.
- [1.46 works (headless)] Config dir now DEFAULTS to the suite's own config folder, not the drawing
  folder. lk:suite-root (mirrors _lkload-root: *lk-suite-root* when bound, else the dev path) +
  lk:suite-config-dir give <suite-root>config\; lk:get-config-dir priority is now
  *lk-config-dir* -> <suite-root>config\ -> DWGPREFIX. This points Save/Set at the git-tracked
  layer-kit\config\ (in DEV) or the bundle's config\ (in an install) instead of DWGPREFIX, which
  is what the 1.45 stale-path fallback was wrongly hitting. On load, a remembered dir that no
  longer exists is dropped (clears a stale session value too), so the renamed LayerKit\config\
  can't override the default.
- [1.46 works (headless)] lk:backup-csv: shared helper that copies a master CSV to
  <dir>\backups\<name>-YYYYMMDD-HHMMSS.csv before it is overwritten. Used by LK-STD Save and
  LK-FILTER Save (1.23+) so a mistaken Save is one-step recoverable, independent of git.
- [1.45 untested-live] lk:get-saved-dir now VALIDATES the remembered ConfigDir exists
  (vl-file-directory-p, trailing separator stripped) before trusting it. A stale path -- e.g.
  the suite folder renamed LayerKit -> layer-kit -- now returns nil so lk:get-config-dir falls
  back to DWGPREFIX instead of handing callers a dead directory (was: silent "Cannot write" on
  CSV save). Old stale registry value was corrected out-of-band.
- [1.44 untested-live] UNMATCHED LAYERS ARE NOW INTERACTIVE (not just reported). Clarification:
  LK-CLEANUP/LK-APPLY has NEVER auto-purged unapproved layers -- since pvcleanup-1.0 a layer
  matching no static/keyword mapping was Level-4 "unmatched", reported for manual assignment and
  LEFT in the drawing (only EMPTY layers get purged, plus any layer explicitly mapped to the
  "Purge" target). 1.44 upgrades that Level-4 branch: for each unapproved layer it ZOOMs to the
  layer's model-space objects (lk:zoom-layer: switch to MODEL if in a layout, ssget "_X" by
  layer + (410 . "Model"), ZOOM _O; all wrapped in vl-catch-all-apply so headless/no-view can't
  abort) then offers a MERGE into a chosen approved layer. lk:pick-standard prints the standards
  (lk:std-name-list = real-case names from PV_layer_standards.csv, cached once into `std-list`)
  as a NUMBERED menu; the user picks a number (0 = skip), then [Permanent/Once] (Permanent
  appends source,target to PV_static_mappings.csv + merges; Once merges this run). No Purge /
  no deletion -- unapproved geometry is always merged onto a standard, never destroyed.
  Assignments flow through the existing summary + "Execute now? [Yes/No]" confirmation (the
  count/preview gate). Verified headless: file loads, C:LK-CLEANUP + lk:zoom-layer +
  lk:std-name-list + lk:pick-standard defined; lk:std-name-list returns the 38 standards.
  ZOOM + the numbered getint pick + getkword are GUI-only (untested-live). Live: the Permanent
  path is writing correct source,target rows to the static map (e.g. ANSI import layers ->
  PV-RACK / G-HATCH / G-ANNO-DIMS).
  (Earlier 1.44 cut offered [Assign/Purge/Skip]; replaced per request with merge-by-numbered-list,
  Purge removed.)
- [1.43 untested-live] CONFIRMATION DIRECTION FIX. 1.42 prompted on the CSV->drawing CREATE
  side (LK-STD>Set / LK-FILTER>Set), which is wrong: those instantiate already-curated layers,
  so it would nag ~38x on a fresh stamp. Moved the prompt to the direction that ADDS new names
  to a curated list -- LK-STD>Save. lk:confirm-new-layer reworded ("New layer X not in <list>
  -- add? [Yes/No/Reject=never]") and is now called only by Save; the CREATE paths just check
  lk:rejected-p (silent, no prompt) so a rejected name is never instantiated. Verified headless:
  Save adds confirmed-new, drops rejected even if listed, keeps existing; std-apply creates 40
  curated layers silently and skips a rejected one.
- [1.42 untested-live] Shared REJECT LIST + confirm engine (defined here since lkcleanup holds
  lk:reg-key and loads first): lk:confirm-new-layer / lk:rejected-p / lk:reject-add /
  lk:reject-load (restores *lk-rejected* on load) / lk:reject-save / lk:reject-manage
  (LK-STD>Rejects: list + Clear). Permanent rejects persist in the registry (value
  "RejectedLayers" under lk:reg-key, comma-joined UPPER). *lk-confirm-new* (default T) nil =
  accept silently; rejected layers are skipped regardless. (1.42 wired the prompt to the create
  paths; superseded by the 1.43 direction fix above.)
- [1.38] keyword prompt reworded: Permanent / Once / Skip / Never (Never = self-map, leave
  alone forever); old Other dropped.
- [1.39] one-shot orchestrator: (C:LK-CLEANUP) then lk:filter-set then lk:std-apply (so
  filter-created layers get styled). Focused commands stay.
- [1.40] orchestrator renamed LK-SETUP -> APPLY, then [1.41] -> LK-APPLY (keep the LK- prefix).
  Verified loads headless; LK-SETUP / APPLY no longer defined.
(historical header below)
File: lkcleanup/lkcleanup-1.37.lsp
Latest confirmed: 1.36 auto force-del + 1.34 std-protect/A-WALL->S-SITE confirmed live.
1.37 COMMAND CONSOLIDATION (verified loads headless):
  - LK-CLEANUP now prompts [Full/Preview]; Preview calls lk:report (the old LK-REPORT, now a
    helper, not a command).
  - LK-CONFIG removed as a command -> lk:set-config-dir helper (called by LK-STD > Config).
  - LK-VPORTS, LK-PURGELYR removed as commands; their helpers (lk:sweep-viewports,
    lk:force-del-stuck) still run automatically inside LK-CLEANUP.
  - So lkcleanup now exposes ONE command. (Files unchanged elsewhere; logic intact.)

### Current Features
- [1.0 works] LK-CLEANUP: scans all drawing layers and classifies each in priority order,
  then optionally executes renames/merges after a Yes/No confirmation
- [1.0 works] 4-level classification:
    1. Static  — exact case-insensitive match from PV_static_mappings.csv
    2. PDF     — layers matching "PDF*_*" grouped by prefix (e.g. "PDF2")
    3. Keyword — name tokenized on - _ ( ) space, matched against PV_keywords.csv
                 (single-token match first, then multi-word substring match)
    4. Unmatched — reported with entity count for manual / LLM assignment
- [1.0 works] System layers "0" and "DEFPOINTS" always skipped
- [1.38] Keyword hits prompt per layer: Permanent / Once / Skip / Never (default Skip).
  (Reworded from Hard/Soft/Other/Skip; the "Other" custom-target option was dropped.)
    Permanent = apply now + append source,target to PV_static_mappings.csv (auto next run)
    Once      = apply this session only
    Skip      = leave it this time (asked again next run)
    Never     = don't change AND append a self-map (source,source) so it's [STD-OK]/[OK]
                and never flagged again
- [1.0 works] lk:do-rename — already-correct (skip); target layer does not exist
  (._-RENAME); target exists (entmod every entity's group-8 onto the target = merge,
  leaving the empty source for PURGE). Moves CLAYER off the source first if needed.
- [1.01 works] lk:do-rename "PURGE" target: deletes every entity on the source layer
  (entdel) and reports [DELETE] with the count; CLAYER moved to "0" first if needed. Lets a
  mapping send a junk layer to deletion instead of a rename.
- [1.03 works] lk:remap-blocks (old new): walks EVERY block definition via VLA
  (vla-get-blocks → vlax-for blk → vlax-for ent) and moves entities on the old layer to the
  new layer. ssget "X" only sees model/paper space, so block-internal entities hold hidden
  layer references that block PURGE — this clears them. Each vla-put-layer is wrapped in
  vl-catch-all-apply so a locked/odd entity can't abort the run; returns the remap count.
- [1.03 works] lk:do-rename now also calls lk:remap-blocks on both paths: PURGE target remaps
  block entities to "0" ([DELETE] reports "N deleted, M block refs remapped"); merge target
  remaps to the new layer ([MERGE] reports "N moved, M in blocks").
- [1.03 works] lk:purge-empty-layers reordered to actually clear layers: purge BLOCKS first
  (5× -PURGE _BL) to release block-held layer refs, THEN layers (5× -PURGE _LA), then
  everything else (3× -PURGE _ALL). Supersedes the 1.01 layers-then-all order, which left
  block-referenced layers un-purgeable.
- [1.10 untested] PERFORMANCE REWORK (cleanup was taking minutes). The block-internal remap
  was the bottleneck: the old lk:remap-blocks did a full COM walk of EVERY block definition
  ONCE PER renamed layer = O(layers × block-entities). Replaced with a queue + single pass:
  lk:do-rename calls lk:blk-add to push (old → new) onto *lk-blkmap*; after all layers are
  processed, lk:remap-blocks-run walks the block table ONE time and remaps every queued layer
  via an assoc lookup. Same end result, ~O(block-entities) instead of ×layers.
- [1.10 untested] Block pass now SKIPS layout blocks (IsLayout) and xref blocks (IsXRef):
  model/paper-space entities are already handled by ssget "X" + entmod/entdel, and xref
  internals can't be edited. Only reusable block definitions (where purge-blocking layer refs
  live) are walked.
- [1.10 untested] Renames (target layer absent) no longer queue a block remap at all —
  -RENAME renames the layer record, so every reference including block-internal follows
  automatically. Only merges (→ existing layer) and PURGE (→ "0") need the walk.
- [1.10 untested] lk:purge-empty-layers trimmed from 13 passes to 5 (2× _BL, 2× _LA, 1× _ALL).
- [1.35 works] LK-PURGELYR: force-removes the EMPTY layers that wouldn't purge (the *lk-stuck*
  entries with 0 objects from the last LK-CLEANUP) via native LAYDEL, which clears layer-state /
  VP-freeze references a plain PURGE can't. Confirmed working by the user in live AutoCAD.
- [1.36 untested-live] That force-remove now runs AUTOMATICALLY at the end of LK-CLEANUP:
  lk:force-del-stuck (shared by LK-CLEANUP and LK-PURGELYR) LAYDELs the empty stuck layers right
  after detection, prints "Force-removed N empty layer(s) via LAYDEL.", and the final report
  shows only layers that TRULY remain (those with objects still on them). LAYDEL is GUI-only so
  the auto path is untested headless; helper + load verified.
- [1.34 works] PROTECT standard layers: lk:std-names reads PV_layer_standards.csv; any layer
  whose name is a canonical standard is classified [STD-OK] (kept) BEFORE static/PDF/keyword, so
  it's never suggested for merge. Fixes E-SLD-EX getting pulled by the "sld" keyword. Applies to
  LK-CLEANUP and LK-REPORT. Verified headless: 34 std names loaded, E-SLD-EX = PROTECTED.
- [1.33 untested] At the end of a run (after purge) auto-applies layer standards by calling
  lk:std-apply (lkstd tool) if it's loaded AND a PV_layer_standards.csv exists -- so merged
  layers come out with their correct color/linetype/lineweight/plot/vp-freeze. Silent if no
  CSV (returns -1). Reports "Applied layer standards to N layer(s)."
- [1.32 untested] Sweep now ALSO moves each layout's overall "sheet" paper-space viewport
  (group 69 id 0/1), controlled by *lk-vport-sheet* (default T). Previously these were always
  skipped. Safe because lk:prep-layer forces the target on+thawed before the move; set
  *lk-vport-sheet* nil to restore skip-sheet behavior. ⚠ keep *lk-vport-layer* on/thawed
  (a sheet VP on a frozen/off layer blanks that layout).
- [1.31 works] FIX: 1.20/1.30 used CHPROP/ERASE, which only act on the CURRENT space ->
  "The object is not in current space" for viewports/objects living in layouts while in model
  space (the move silently failed and the leftover args became "Unknown command LA / <layer>").
  New lk:move-ss / lk:erase-ss use VLA (vla-put-layer / vla-delete) which are space-independent
  and work on viewports, with an entmod/entdel fallback. Each move is VERIFIED by re-reading
  group 8, so the printed count = objects ACTUALLY moved. (VLA is proven working in the user's
  drawing -- the block remap runs clean there. Not headless-testable: accoreconsole has no COM.)
- [1.30 untested] VIEWPORT POLICY: ALL real floating viewports are moved onto one dedicated
  layer (*lk-vport-layer*, default "G-VPORT"), regardless of what their old layer maps to.
  lk:sweep-viewports runs FIRST in the execute phase (so the old layers empty and then
  merge/purge normally) and reports "Viewports -> G-VPORT: N moved." Uses CHPROP; unlocks the
  source layers + target first. SKIPS the per-layout overall paper-space viewport (DXF group
  69 = 0 or 1) -- moving that to a layer that's ever frozen/off would blank the sheet; real
  viewports have id >= 2. Verified headless: 2 real VPs -> G-VPORT, JUNKVP emptied, 2 overall
  VPs left on layer 0.
- [1.30 untested] New standalone command LK-VPORTS: runs the viewport sweep on demand (no
  layer-rename needed), with its own *error*/CMDECHO handling; lk:ensure-layer creates the
  target layer if absent (preserving CLAYER). *lk-vport-layer* overrides the target layer.
- [1.20 untested] ROOT-CAUSE FIX (viewports): the stuck layers held VIEWPORT objects, and
  entmod SILENTLY no-ops on a viewport's layer (returns success, layer unchanged) -- so
  "N moved" was a lie and the layer never emptied. Replaced the per-entity entmod loop with
  ONE native command per layer: merge -> (command "._CHPROP" ss "" "_LA" target "");
  delete/PURGE -> (command "._ERASE" ss ""). CHPROP/ERASE move/erase viewports (and everything
  else) reliably. Verified headless end-to-end: a viewport layer now merges to the target and
  PURGE removes it.
- [1.20 untested] Honest post-run report: after purge, re-checks every matched source layer.
  Prints "** STILL PRESENT **" with, per layer, either "N object(s) remain on it" or
  "empty but won't purge (VP-freeze / layer state / underlay ref)". Final line is "Done." (no
  longer claims "renamed, merged, and purged" unconditionally).
- [1.20 untested] lk:remap-blocks-run hardened: COM acad-object acquisition wrapped in
  vl-catch-all-apply so a missing/!COM environment skips the block pass instead of aborting.
- [1.11 untested] FIX: merged/purged layers wouldn't actually empty (so PURGE kept them) when
  the source layer was LOCKED or FROZEN. Locked: ssget selects the entities (count looked
  right) but interactive AutoCAD blocks entmod/entdel on a locked layer, so nothing moved
  ("N moved" was sslength, not actual moves). Frozen: ssget "X" skips frozen-layer entities
  entirely, so it found 0 and moved nothing. (accoreconsole does NOT enforce lock, which is
  why the bug only showed in the live GUI.) New lk:prep-layer runs BEFORE the ssget in the
  merge and PURGE branches: thaws (clears 70-bit 1), unlocks (clears 70-bit 4) and turns the
  layer on (62 positive) via entmod on the layer record — so frozen entities become
  selectable and locked entities become modifiable. Verified headless: flags 5→0, color -7→7.
- [1.10 untested] Execute wrapped in CMDECHO 0 (restored at end and in *error*) to kill the
  per-command echo spam from -RENAME/-PURGE. [DELETE]/[MERGE] lines now report the model/paper
  count only; a single "Remapping block-internal layers... N refs." line reports the batch total.
- [1.0 works] Summary counts (static / hard / soft / pdf / unmatched); on execute, writes
  an audit row per action to PV_mapping_log.csv (created with header if absent)
- [1.0 works] Reports unmatched layers (with entity counts) and PDF groups at the end
- [1.0 works] Local *error* handler: clean abort message, restores prior *error*
- [1.0 works] LK-REPORT: dry-run classification preview — prints each layer's bucket and
  counts (already-correct / static renames / pdf / keyword / unmatched); makes NO changes
- [1.0 works] LK-CONFIG: sets *lk-config-dir* (the directory holding the CSVs); ensures a
  trailing backslash; defaults shown from lk:get-config-dir
- [1.02 works] LK-CONFIG now PERSISTS the directory across sessions: on change it writes
  the value to the Windows registry (lk:save-dir) and confirms "Remembered -- loads
  automatically every session until changed."
- [1.02 works] On load, the tool restores the remembered directory into *lk-config-dir*
  (lk:get-saved-dir), unless a value was already set this session. No saved value → falls
  back to DWGPREFIX as before. Load banner prints "CSV dir (remembered): <dir>" when set.
- [1.02 works] Persistence backend: vl-registry-read/write under
  HKEY_CURRENT_USER\Software\Ocotillo\LayerKit, value "ConfigDir" (lk:reg-key). Verified to
  round-trip and auto-restore across separate accoreconsole processes.

### CSV / config
- PV_static_mappings.csv  source_layer,target_layer[,date]   exact-match map (Hard writes append here)
- PV_keywords.csv         keyword,target_layer               token/substring map
- PV_mapping_log.csv      timestamp,source_layer,target_layer,method   audit log (written on execute)
- Config dir: *lk-config-dir* if set, else DWGPREFIX (the open drawing's folder).
  Master/template CSVs ship in LayerKit\config\.

### Globals read/written
- *lk-config-dir* -- CSV directory override (nil → DWGPREFIX at runtime)

### Notes
- Internal helpers use the lk: namespace (lk:read-csv, lk:tokenize, lk:do-rename, ...).
- [1.04 works] Full PV→LK rebrand of lkcleanup-1.03: commands PV-CLEANUP/PV-REPORT/PV-CONFIG →
  LK-CLEANUP/LK-REPORT/LK-CONFIG; pv: helpers → lk:; *pv-config-dir* → *lk-config-dir*. Logic
  unchanged from 1.03. CSV filenames keep the PV_ prefix (solar/PV data, not commands). The old
  PV-named version files (pvcleanup-1.0…1.03, pvload-1.0) are preserved under
  archive\pre-LK-rebrand\.

---

## LK-STD (layer standards)
Commands: LK-STD  [Save/Set/Config/Rejects]   (1.2: was LK-STDSAVE/LK-STDSET; Config folds in old LK-CONFIG)
File: lkstd/lkstd-1.24.lsp
- [1.24 untested-live] Save VERIFIES both directions of standards change, with a symmetric NAMED CLI readout:
  - ADD: a layer in the drawing not yet in the CSV is gated by lk:confirm-new-layer ([Yes/No/Reject], existing
    behavior). Confirmed adds are now listed by name: "Added to standards (N confirmed): LAYER-A, LAYER-B";
    declines reported as a count ("Declined N new layer(s).").
  - REMOVE: a layer in the old CSV but no longer in the drawing (and not permanently rejected) is gated by
    lk:confirm-remove-std ("...is in standards but no longer in the drawing -- remove from standards? [Yes/No]
    <No>"); declining writes the layer's original CSV row back, so nothing is silently dropped. Confirmed
    removals listed: "Removed from standards (N confirmed, no longer in drawing): LAYER-A, LAYER-B".
  - Prompt strings use a literal forward-slash separator ([Yes/No]); a backslash ([Yes\No]) eats the separator
    and breaks AutoCAD's keyword highlighting.
  - Contrast LK-FILTER Save, which only PRINTS removed filters/members — no prompt (kept by design).
- [1.23 works (headless)] Save now backs up the previous PV_layer_standards.csv to config\backups\
  (lk:backup-csv) before overwriting, so a mistaken Save is one-step recoverable. (Headless: file
  loads clean + lk:backup-csv verified copying to config\backups\; end-to-end Save flow GUI-pending.)
- [1.22 untested-live] LK-STD > Save now CONFIRMS new layers before they enter the standards
  list. Save reads the existing CSV first; layers already listed (and "0") are written as-is, a
  layer NOT yet listed is gated by lk:confirm-new-layer [Yes/No/Reject], and a permanently-
  rejected layer is DROPPED even if currently listed (so a Save purges junk). First-ever Save
  (no CSV) writes everything. Reports "New layers: N added, M declined" / "Dropped K rejected".
  Row-building factored into lk:std-row. Verified headless: junk1 declined->absent, junk2
  added->present, rejected+listed S-ROOF dropped, normal E-SLD kept.
- [1.22 untested-live] lk:std-apply CREATE path no longer prompts (these are curated CSV
  layers); it only skips a permanently-rejected name via lk:rejected-p. Styling still runs only
  when the layer exists. Verified headless: std-apply creates 40 layers, skips rejected G-LOGO.
- [1.21, superseded] First cut put a per-layer create prompt in std-apply; replaced by the
  Save-direction gate above (1.22) because prompting on Set/Apply nags for curated layers.
- New LK-STD > Rejects sub-option (lk:reject-manage): list the permanently-rejected layers and
  Clear them all.
Latest confirmed: 1.1 untested-live (1.0 round-trip verified). 1.1: lk:std-apply now CREATES
any standard layer that doesn't exist (entmake) before styling it, so the full standard layer
set POPULATES on LK-STDSET / on every LK-CLEANUP run. Verified headless: all 34 CSV layers
created + styled in a blank drawing (A-BLDG->252, A-SETB->HIDDEN, S-SITE->253, etc.; custom
linetype Dash Style-13 falls back to Continuous when not loadable from acad.lin).

### Current Features
- [1.0 untested] LK-STDSAVE: exports every layer's standard to PV_layer_standards.csv in the
  LK config dir. Columns: layer,color,linetype,lineweight,plot,vpfreeze. Reads the FULL layer
  record via (entget (tblobjname "LAYER" name)) -- NOT the tblnext record, which omits
  lineweight(370) and plot(290) (that omission was the 1.0 first-cut bug, fixed before ship).
- [1.0 untested] LK-STDSET: applies the CSV to matching existing layers. Per layer sets
  color(62, on/off sign preserved), linetype(6), lineweight(370), plot(290), and new-vp-freeze
  (group 70 bit 2). Skips layer "0". Returns count, or -1 if no CSV. entmod per layer wrapped
  in vl-catch-all-apply.
- [1.0 untested] lk:ensure-ltype loads a missing linetype from acad.lin (CONTINUOUS always ok);
  if it still can't load, that layer's linetype is left unchanged.
- [1.0 untested] lk:std-apply is the shared engine; LK-CLEANUP 1.33 calls it automatically at
  the end of a run (auto-apply standards to the cleaned/merged layers).
- [1.0 untested] Pure DXF (entget/entmod/tblnext) -- no COM; fully headless-testable. Round-trip
  verified: set color=3/DASHED/lw=50/noplot/vpfreeze -> save -> clobber -> set -> all restored.

### Standard properties (CSV columns)
- color     ACI 1-255 (true/RGB color NOT captured -- ACI only)
- linetype  linetype name (must be loadable from acad.lin, else left as-is)
- lineweight  1/100 mm; -3 = Default
- plot      1 = plots, 0 = no-plot
- vpfreeze  1 = New VP Freeze (frozen by default in new viewports), 0 = not.
            (This is the layer default; per-existing-viewport VP-freeze overrides are NOT handled.)

### Globals
- *lk-config-dir* (shared) -- dir holding PV_layer_standards.csv

---

## LK-BYLAYER (force color ByLayer everywhere)
Commands: LK-BYLAYER, LK-SKIP  [Add/Layer/List/Clear]   (1.4: 4 LK-SKIP* commands -> one LK-SKIP)
File: lkbylayer/lkbylayer-1.4.lsp
Latest confirmed: 1.3 untested in live AutoCAD (layer-skip; layer honoring + cross-process
persistence verified headless). Prior 1.2 no-seed/pick-at-init; 1.1 block/element persistence.

### Excluded blocks / elements (persistent)
- [1.01 untested] *lk-bylayer-skip* = list of block-name wildcards (case-insensitive) whose
  colors are PRESERVED -- both the block DEFINITION's internal geometry AND any INSERTs of it
  are left untouched (lk:skip-block-p via wcmatch).
- [1.1 untested] LK-SKIPADD: pick objects to exclude. A picked INSERT adds its block NAME to
  *lk-bylayer-skip*, saved in the registry (HKCU\Software\Ocotillo\LayerKit\BylayerSkipBlocks,
  "|"-joined) so it persists across drawings/sessions. A picked non-block element is tagged
  with "LKSKIP" XDATA (regapp), which is saved inside the DWG (so that specific element is
  preserved in that drawing). Counts both.
- [1.1 untested] On load, the saved block list is restored from the registry into
  *lk-bylayer-skip* (authoritative). lk:bl-load-skip / lk:bl-save-skip / lk:bl-split handle the
  registry string.
- [1.2 untested] No more "*NORTH*" seed -- the list is EMPTY until the user saves their own.
- [1.2 untested] LK-BYLAYER calls the pick step (lk:skip-pick) at the START of every run, so
  you can add exclusions on the spot; press Enter to skip and run with the saved list. The pick
  logic is factored into lk:skip-pick (shared by LK-SKIPADD and LK-BYLAYER); empty selection
  makes no change.
- [1.3 untested] LAYER-level skip: LK-SKIPLAYER picks objects and adds their LAYER(s) to
  *lk-bylayer-skiplayers*, saved in the registry (BylayerSkipLayers, restored on load) -- the
  same persistence as block names. Any entity (top-level OR block-internal) whose layer matches
  is left alone (lk:skiplayer-p via wcmatch; checked in lk:skip-ent-p and the Part-2 walk).
  LK-SKIPLIST shows blocks + layers; LK-SKIPCLEAR clears both. Generic lk:reg-get/lk:reg-put
  back both lists. Verified headless: element on KEEPLYR preserved, element on a normal layer
  -> ByLayer; KEEPLYR persisted across two separate processes.
- [1.3 untested] The ByLayer work is factored into lk:bylayer-run (no interactive pick);
  C:LK-BYLAYER = (lk:skip-pick) + (lk:bylayer-run). Lets the engine be tested without a pick.
- [1.1 untested] LK-BYLAYER honors both: lk:skip-ent-p skips INSERTs of excluded blocks and any
  element carrying LKSKIP XDATA (Part 1); the block-def walk skips excluded block defs and any
  LKSKIP-tagged internal entity (Part 2).
- [1.1 untested] LK-SKIPLIST prints the saved block list. LK-SKIPCLEAR empties the saved block
  list (registry + session); element XDATA tags remain in the drawing.
- Verified headless: block name persists across two separate processes (restored on load);
  excluded block internals (color 6) + an XDATA-tagged element (color 5) preserved while a
  normal element went ByLayer.

### Current Features
- [1.0 untested] Sets every entity's color to ByLayer (group 62 = 256) and strips any
  true-color override (group 420), across ALL spaces AND inside ALL block definitions.
  Native SETBYLAYER only does the CURRENT space (and optionally blocks) -- objects in other
  layouts / paper space / block defs get left behind; this catches them all.
- [1.0 untested] Part 1: (ssget "X") -> every top-level entity in every space; entmod each.
  (ssget "X" + entmod are cross-space; CHPROP/SETBYLAYER are not -- "object not in current
  space".) Part 2: walks every block DEFINITION via (entnext (tblobjname "BLOCK" name)) to
  ENDBLK. Layout blocks (*Model_Space/*Paper_Space*) skipped (done by Part 1); xref defs
  skipped (can't edit).
- [1.0 untested] Temporarily clears lock(70 bit4) AND freeze(70 bit1) on all layers first
  (entmod is blocked on locked/frozen) via lk:prep-all, and RESTORES the original flags after
  via lk:restore-layers. Each entmod wrapped in vl-catch-all-apply.
- [1.0 untested] Reports "Color set ByLayer on N object(s)" + how many layers were temporarily
  unlocked/thawed.
- [1.0 untested] Verified headless: block-internal line, inserted block, paper-space line,
  true-color line, locked-layer line, frozen-layer line -> ALL ByLayer; 420 stripped; locked
  and frozen layers restored.

### Notes / not yet done
- Color only (group 62/420). Linetype/lineweight ByLayer not done here -- use LK-STDSET, or ask
  to extend LK-BYLAYER to linetype(6)/lineweight(370) ByLayer too.
- Block-internal entities ARE set ByLayer (changes how those blocks display). That's intended
  ("all elements"); there's no skip-blocks flag yet.

---

## LK-FILTER (layer group filters)
Commands: LK-FILTER  [Set/Save]   (1.2: was LK-FILTERSET/LK-FILTERSAVE -> one LK-FILTER)
File: lkfilter/lkfilter-1.24.lsp
- [1.24 untested-live] Save now diffs old CSV vs new output and reports: "Removed filter: X" for any
  filter that no longer exists in the drawing's ACLYDICTIONARY, and "Filter 'X': removed N layer(s):
  A, B" for any filter that lost members. Old CSV is read before backup/overwrite.
- [1.23 works (headless)] Save now backs up the previous PV_layer_filters.csv to config\backups\
  (lk:backup-csv, shared with LK-STD) before overwriting, so a mistaken Save is one-step recoverable.
- [1.22 untested-live] lk:filt-ensure-layer creates curated CSV members WITHOUT prompting, but
  skips a permanently-rejected name via lk:rejected-p (returns nil -> that layer is left out of
  the filter, no member added). Matches the 1.43 direction fix: no prompts on the create side;
  the reject list is the only gate here. Pre-existing layers and the *lk-filt-new* count path
  are unchanged.
- [1.21, superseded] First cut prompted per missing member via lk:confirm-new-layer; replaced by
  silent reject-honoring (1.22).
Latest confirmed: 1.01 WORKS in live AutoCAD -- LK-FILTERSET created the group filters and they
appear in the Layer Properties Manager AFTER the drawing is reloaded. 1.1 adds auto-create of
missing layers (verified headless). CSV: config/PV_layer_filters.csv (name,layer1,...).

### Structure (discovered from the user's 2027 drawing)
- Modern AutoCAD stores the layer-filter TREE in the LAYER table's extension dictionary under
  key "ACLYDICTIONARY". (Legacy "ACAD_LAYERFILTERS" dict is present but EMPTY/vestigial.)
- Each GROUP filter is an XRECORD child of ACLYDICTIONARY:
  (100 . "AcDbXrecord")(280 . 1)(1 . "AcLyLayerGroup")(90 . 1)(300 . <name>) then
  (330 . <layer ename>) one per member layer. (Property filters would have a different code-1
  value; LK-FILTER only handles group filters.)

### Current Features
- [1.0 works] LK-FILTERSET: reads PV_layer_filters.csv; for each row (filter name + layer
  names) creates/refreshes a group filter. Removes any existing filter with the same display
  name (300), then entmakex the XRECORD + dictadd into ACLYDICTIONARY (key = filter name).
- [1.1 untested-live] CREATES any CSV-listed layer that doesn't exist yet (lk:filt-ensure-layer:
  entmake a white/Continuous AcDbLayerTableRecord; no CLAYER side effect) so it becomes a filter
  member. Reports "Created N missing layer(s)" and suggests LK-STDSET to style them. Verified
  headless: starting with only L1, a filter of (L1 L2 L3) created L2+L3 and all three became
  members. (New layers default white/Continuous; reload still required for the filter to show.)
- [1.0 untested] LK-FILTERSAVE: reads ACLYDICTIONARY, writes every AcLyLayerGroup back to the
  CSV (name + member layer names resolved from the 330 enames; only 330s that point to LAYER
  records are members -- owner/reactor 330s are skipped by type).
- [1.0 untested] lk:acly-dict finds ACLYDICTIONARY; if absent, creates the layer-table xdict +
  sub-dict via VLA (GUI only; returns nil headless -> command prints a clear message).

### Display caveat (confirmed behavior)
- [1.01 works] The filters appear only AFTER the drawing is reloaded (save/close/reopen). AutoCAD
  builds the in-memory layer-filter tree at open time and does not refresh it when the dictionary
  is edited via LISP. LK-FILTERSET prints a "SAVE and REOPEN" reminder. The persistent reactor
  (102 ACAD_REACTORS) and the (290 . 1) flag on AutoCAD's own filters turned out NOT to be needed
  for the filter to display.
- Open item: an in-session refresh (so a reload isn't required) -- not yet found; reload works.
