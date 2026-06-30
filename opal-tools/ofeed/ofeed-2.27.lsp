;; ofeed-2.27.lsp -- Ocotillo AC Feeder Schedule Recompute + Setup
;; Commands: O-FEED (alias OFEED)   O-FEEDSET (alias OFEEDSET)   O-FEEDAMB (re-prompt design ambient)
;;           O-FEEDTEST (headless engine self-test)
;;
;; RECOMPUTE an existing native AutoCAD table (ACAD_TABLE): the user keeps the schedule and types
;; the assumed-correct inputs; O-FEED sizes the rest. See header of 2.0 for the full design.
;;
;; 2.27: AMPACITY ADJUSTMENTS (NEC 310.15) + ADJUSTED AMPACITY column. The conductor is now sized off
;;       the CORRECTED ampacity: raw 75C/90C table ampacity * a derate = ambient-temperature correction
;;       (310.15(B)(1), from config\ambient_correction.csv keyed by the design ambient) * >3-CCC
;;       bundling adjustment (310.15(C)(1)). Selection runs off raw ampacity * derate, so a hot ambient
;;       upsizes the conductor / adds a parallel set. A new ADJUSTED AMPACITY (A) column (canonical idx
;;       13, after BASED AMPACITY) shows the derated value; O-FEEDSET create + O-FEED auto-setup add it,
;;       and the VD/formula cells shifted +1 (V=14 %=15 FORMULA=16). The design ambient is gathered per
;;       run from a drawing "AMBIENT ..." TEXT/MTEXT note (auto-detect C/F: a bare number above
;;       *ofeed-amb-c-max* (50C) is read as Fahrenheit) or, if none, a prompt -> *ofeed-ambient-temp*.
;;       Each run-conduit's CCC = phase conductors + neutral IF *ofeed-neutral-is-ccc* (default nil);
;;       EGC never counts, so AC-3+ (no neutral) stay 3 CCC. Backward compatible: ambient 30C -> all
;;       factors 1.0 -> identical sizing to 2.26 (ADJUSTED == BASED), preserving the production sheet.
;; 2.26: AUTO-LAYER THE TABLE. The feeder schedule table is now placed on *ocfg-layer-feeder-table*
;;       (default "G-TEXT", from oconfig 1.08) -- set at O-FEEDSET CREATE and re-applied on every
;;       O-FEED run, so an existing table is moved onto the layer too. Layer is auto-created if missing
;;       (ByLayer color 7). Config-driven via _ofeed-table-layer (never a hardcoded layer string).
;; 2.25: HANG FIX -- targeted cell formatting. 2.23's _ofeed-format-all reformatted EVERY cell
;;       (rows x 16 cols = 2 COM calls each) on every recompute; on a real production schedule that
;;       per-cell volume froze O-FEED ("hung up again"). Replaced by _ofeed-format-inputs, which
;;       reformats ONLY the user-typed input cells -- LENGTH (7), CIRCUIT LOAD (8), VOLTAGE (11) on
;;       data rows. Those were the ONLY cells that kept their as-typed gray / right-aligned look; the
;;       sized + header cells already render white / middle-center, so the result is identical but the
;;       work drops ~5x+ (e.g. 16*rows -> 3*rows cells). Still inside the no-regen batch; the blue/red
;;       background tints are untouched. Engine + breaker sizing unchanged from 2.24.
;; 2.24: SIZE CONDUCTOR TO THE BREAKER (NEC 240.4 protection fix). Conductors were sized to carry the
;;       125% load current (i125), but the breaker rounds UP to the next standard rating -- so the
;;       conductor could land BELOW its own breaker (e.g. 2 SETS OF 350KCMIL AL = 560 A base ampacity
;;       under a 600 A breaker). sets / per-run current / conductor are now driven off the OCPD rating,
;;       so total base ampacity >= breaker >= i125. Matches the production sheet (432.9 A -> 600 A
;;       breaker -> conductor sized so ampacity clears 600; 144.3 A -> 200 A -> 3/0 CU, not 2/0). The
;;       material decision (single CU vs parallel AL) also keys off the OCPD now. Voltage drop still
;;       uses the actual per-run load current, not the breaker rating. NOTE: this is the conservative
;;       "conductor ampacity >= OCPD" approach; it does NOT take the NEC 240.4(B) next-size-up allowance
;;       (breaker one standard size above conductor) -- say so if you want that instead.
;; 2.23: UNIFORM CELL FORMATTING. O-FEED recompute now normalizes EVERY cell to WHITE text (ACI 7 ->
;;       plots black) + MIDDLE-CENTER (acMiddleCenter=5), matching O-FEEDSET create -- so the user's
;;       original input cells (LENGTH / CIRCUIT LOAD / VOLTAGE), which kept their as-typed gray / right-
;;       aligned formatting, now match the sized cells. _ofeed-format-all runs in PHASE 2 inside the
;;       no-regen batch. It is FORMATTING ONLY: it sets content color + alignment, never the value, so
;;       an unchanged-value cell is reformatted but NOT blue-highlighted and NOT added to the revert set
;;       (per the user: "can be overwritten but not highlighted as they keep same value"). The blue/red
;;       background tints (changed / flagged cells) are independent and unaffected. GUI-only (COM) --
;;       load-verified; needs a live pass.
;; 2.22: CRASH/HANG FIXES PORTED onto the 2.17 material-by-sizing line (continues the fresh 2.17
;;       engine -- material chosen by the size, ANY feeder that parallels -> *ofeed-parallel-material*,
;;       not the AC-number rule of the shelved 2.18-2.21). Three ports from the shelved AL-parallel work:
;;       - ALWAYS RELOAD REFS: c:O-FEED / c:O-FEEDSET now always call _ofeed-load-refs (was guarded by
;;         (null *ofeed-cond-table*)). A session that had loaded an OLD ofeed kept a stale 5-column
;;         *ofeed-cond-table*; being non-null it never reloaded, so _ofeed-cond-table-mat returned nil
;;         -> (last nil) "consp nil" crash. CSVs are tiny, so reloading every run is cheap.
;;       - NIL-SUBSET GUARD: _ofeed-parallel-sets returns 1 for an empty/nil conductor subset instead of
;;         calling (last nil) -- defense in depth for the same stale/empty-table disease.
;;       - CRASH-SAFE + HANG-FREE RECOMPUTE: the mutating body is split into _ofeed-recompute-core;
;;         _ofeed-recompute validates the table, force-cleans (_ofeed-doregen), runs the core inside
;;         vl-catch-all-apply, then ALWAYS _ofeed-doregen again -- so an unexpected nil/COM value mid-pass
;;         can no longer leave the table regen-SUPPRESSED (which was the cause of the recurring hang on
;;         repeated runs). _ofeed-doregen also calls vla-GenerateLayout so the table ends each run CLEAN.
;;       2.17's auto-setup (O-FEED adds missing columns) and O-FEEDSET = create-new-table are preserved.
;; 2.17: MATERIAL BY SIZING + O-FEED AUTO-SETUP + O-FEEDSET = CREATE.
;;       - MATERIAL IS CHOSEN BY THE SIZE, not the feeder number: a feeder that fits in ONE
;;         capped-copper run is sized in COPPER; a feeder that needs MULTIPLE parallel runs defaults
;;         to *ofeed-parallel-material* (aluminum). So the big AC-1/AC-2 aggregation loads naturally
;;         come out as multiple sets of aluminum, while every single-run feeder stays copper -- with
;;         no AC-number special-casing. *ofeed-max-cond* (default "500KCMIL") is the per-run cap that
;;         triggers paralleling for ALL feeders (was the agg-only *ofeed-agg-max-cond*). Replaces
;;         2.16's *ofeed-agg-material* / *ofeed-agg-max-cond* + caller-side material pick.
;;       - O-FEED AUTO-SETUP: if the picked table is missing any canonical column, O-FEED now runs
;;         the column repair (_ofeedset-ensure-columns) automatically before recomputing -- no need
;;         to run O-FEEDSET by hand first. (Blank-feeder rows are still auto-labeled by recompute.)
;;       - O-FEEDSET = CREATE: running O-FEEDSET on its own goes STRAIGHT to placing a new feeder
;;         table (prompts # inverters + insertion point) instead of asking you to select a table to
;;         repair. The repair path moved into O-FEED's auto-setup above.
;; 2.16: MATERIAL-AWARE SIZING + MULTI-SET LARGER CONDUCTORS AT AC-1/AC-2 + PER-RUN CONDUIT.
;;       - CONDUCTOR TABLE now carries MATERIAL (CU/AL) + INSULATION columns and is extended to
;;         KCMIL (250..1000). conductors.csv schema: size,material,insulation,amp75,amp90,r,area.
;;       - The AC-1/AC-2 AGGREGATION feeders (fnum <= *ofeed-neutral-max*) size from the ALUMINUM
;;         subset (*ofeed-agg-material*, default "AL"); branch feeders (AC-3+) stay COPPER. WIRE /
;;         NEUTRAL strings now read the material + insulation from the chosen conductor (e.g.
;;         "2 SETS OF (3) 500KCMIL AL XHHW-2"); branch copper output is unchanged ("(3) 4/0 CU THHN/THWN-2").
;;       - MULTIPLE SETS OF LARGER CONDUCTORS: with KCMIL available the sizer (auto-minimum) lands
;;         the big aggregation loads on parallel sets of large conductors. *ofeed-agg-max-cond*
;;         (default "500KCMIL") caps the per-run conductor on agg feeders so they PARALLEL into
;;         multiple runs of <= that size rather than one oversized conductor (nil = no cap).
;;       - PER-RUN CONDUIT: conduit/fill are now sized for ONE parallel run (was: one raceway for all
;;         sets, which over-sized parallel feeders). Matches a real schedule's per-set Raceway Size;
;;         the # OF PARALLEL SETS column carries the run count. Single-set feeders are unaffected.
;;       - EGC stays COPPER (NEC 250.122) regardless of phase-conductor material; its conduit-fill
;;         area is looked up in the CU subset (_ofeed-cond-area-egc) so AL feeders still fill correctly.
;;       - Engine helpers (_ofeed-cond-row/-R/-area/-pick, _ofeed-parallel-sets) now take the working
;;         conductor subset as an argument; _ofeed-size-feeder takes (... material capsize). O-FEEDTEST
;;         passes the agg/branch material per row.
;; 2.15: AUTO-LABEL + COMMON VOLTAGE + VD OVERRIDE + RED CLEARS.
;;       - AUTO-LABEL: a data row that carries a load but has a blank FEEDER cell is now LABELED
;;         AC-<data row #> and sized in place (was: flagged red + "add AC-x"), mirroring O-FEEDSET.
;;         Idempotent once the label is written.
;;       - COMMON VOLTAGE: _ofeed-common-volts takes the modal populated VOLTAGE; any blank VOLTAGE is
;;         ASSUMED equal to it (system architecture: one common AC voltage), filled into the cell, and
;;         used for the voltage-drop %. Falls back to 480 only if no row has a voltage.
;;       - VD OVERRIDE: VOLTAGE DROP (V) and (%) are now FORCED to the computed value, overriding a live
;;         formula (was: only refilled if the cell was deleted/blank). Revertable via the blue [Yes/No];
;;         each write is catch-wrapped. NOTE: 2.08 rolled back a VD force-overwrite that broke a live
;;         run -- test on a copy. 125% and GENERAL FORMULA are still left as live calcs (blank-only heal).
;;       - RED CLEARS: a now-present (or auto-labeled) FEEDER cell clears its stale red background; the
;;         old code never emitted a clear for the FEEDER column, so red persisted. Filled VOLTAGE/LENGTH/
;;         LOAD cells already self-clear.
;; 2.14: WHITE TEXT + CENTER + AGGREGATION CHECK. O-FEEDSET create writes WHITE cell text (ACI 7 ->
;;       plots black) and MIDDLE-CENTER (acMiddleCenter=5) on every cell. O-FEED now VERIFIES the
;;       aggregation feeders: AC-1/AC-2 load = sum of AC-3..n branch loads (_ofeed-branch-total), used
;;       for their sizing, and the CIRCUIT LOAD cell is CORRECTED (blue, revertible) when it differs.
;; 2.14: TEXT HEIGHT FIX. The table-geometry globals (*ofeed-table-th* etc.) were boundp-guarded, so a
;;       stale 0.16 from an older build stuck and create text showed 0.16 not 0.1. They are now ALWAYS
;;       set on load (track the production sheet). Also set text height per row type (1/2/4) so the
;;       HEADER row is explicitly 0.1, not just title+data.
;; 2.14: SPEED -- the REAL fix for the slow recompute. The 2.05 regen suppression
;;       (RegenerateTableSuggested := false, regen once at the end) was being DEFEATED by interleaved
;;       reads: a vla-GetText on a table left "dirty" by a prior vla-SetText FORCES the deferred regen
;;       so it can return a current value -> ~one full-table regen PER ROW (the ~10s/feeder, O(rows^2)
;;       overall). Recompute is now TWO PHASES: PHASE 1 (_ofeed-plan-row, reads only) plans every row
;;       and returns the flags + cell writes to make, mutating NOTHING; PHASE 2 applies all flags then
;;       all writes with no GetText interleaved, so the table regenerates ONCE. Same values, flags, and
;;       revert/confirm behavior as 2.13 -- only the order of COM calls changed. O-FEEDSET unchanged.
;; 2.13: O-FEEDSET create geometry now EXACT from the production E-2.0 table (read DXF groups 141/142):
;;       16 real column widths (_ofeedset-colw-list), data row 0.392, header row 0.588, text 0.1. Also
;;       drops the style's TITLE row to match E-2.0 (no title) -- vla-DeleteRows then detect the header
;;       row index (base) so content lands right whether or not the delete took. Earlier estimated
;;       widths were the "horrendous" sizing.
;; 2.12: O-FEEDSET create geometry matched to the production E-2.0 sheet: text height 0.1, row height
;;       0.1875, and PER-COLUMN widths (_ofeedset-colw-list) sized to content -- fixes "huge
;;       horizontally" (was one big base width on all 16 columns). Grid lines set WHITE (ACI 7) via
;;       _ofeed-make-aci + vla-SetGridColor so they plot black. *ofeed-table-wscale* scales all widths.
;;       (Color resolution refactored into _ofeed-color-obj, shared by _ofeed-make-color/-aci.)
;; 2.11: O-FEEDSET create geometry scaled ~12x smaller (the first cut was enormous in paper space).
;;       Dimensions are now globals: *ofeed-table-th* (text 0.16), *ofeed-table-rowh* (0.34),
;;       *ofeed-table-colw* (base 2.0); text-heavy columns widen relative to the base; cell text height
;;       is set explicitly via vla-SetTextHeight. Adjust the globals to taste.
;; 2.10: SETUP/CREATE mode (O-FEEDSET) -- large bump. Select a table to REPAIR its structure (insert
;;       any missing canonical columns in order + set headers, label rows AC-1..n, flag blank required
;;       cells red), or press Enter to CREATE a fresh schedule: prompts # of INVERTERS, builds
;;       inverters+2 feeders (AC-1/AC-2 aggregation + one per inverter), headers, AC labels, and reds
;;       the empty LENGTH / CIRCUIT LOAD / VOLTAGE cells. Native-table create + column insert are
;;       GUI-only (can't be headless-tested) -- load-verified here, need a live pass.
;; 2.08: NEUTRAL FIX (small bump on 2.07; the 2.08 that also force-wrote VD was rolled back -- that
;;       VD force-overwrite broke the live run). Neutral is now purely by feeder number: AC-1/AC-2
;;       (<= *ofeed-neutral-max*) ALWAYS carry a neutral sized to the phase conductor and counted in
;;       conduit fill + conductor area; AC-3+ forced "-"; a non-AC id still reads the cell. VOLTAGE
;;       DROP V/% still come from the 2.07 self-heal: delete the broken #### VD formula cell and
;;       O-FEED fills it with the computed value (no risky force-overwrite of a live field).
;; 2.07: SELF-HEAL deleted derived cells so the table returns to the complete layout. A DELETED
;;       (truly blank, not a live formula) CIRCUIT LOAD 125% / VOLTAGE DROP V / VOLTAGE DROP % /
;;       GENERAL FORMULA cell is refilled with its computed value (125% when load is valid; VD when
;;       length+voltage are valid; GENERAL FORMULA always) -- existing live formulas are still left
;;       untouched. A row whose FEEDER label was deleted but that still carries a load is flagged red
;;       ("FEEDER label missing") instead of being silently skipped. Sized cells already self-heal.
;; 2.06: CRASH FIX -- the 2.05 regen suppression used vla-put-RegenerateTableSuggested, a wrapper that
;;       isn't generated on every build and raised an UNCATCHABLE "bad function" that aborted O-FEED.
;;       Now via vlax-put-property (caught) -> no crash; speedup applies when the property exists, else
;;       it just runs at normal speed. Color resolution widened (ACADVER + app Version + spread); when
;;       cell coloring can't initialize, O-FEED says so once and falls back to the command-line preview.
;; 2.05: SPEED + NEUTRAL RULE.
;;   - Speed: suppress the table's auto-regen during the batch (vla-put-RegenerateTableSuggested
;;     :vlax-false) and regen ONCE at the end -- a native table regenerates on every cell write, which
;;     is what made each feeder take ~10s. Now it is one regen for the whole pass.
;;   - Neutral: feeders numbered above *ofeed-neutral-max* (default 2) are forced to NO neutral and
;;     show "-" (AC-3+ are inverter-to-panel branch feeders). AC-1/AC-2 keep their NEUTRAL cell.
;; 2.04: robust select + blue/red preview-confirm + graceful per-field errors.
;; 2.02: preserve table calcs (125% / VD / GENERAL FORMULA left alone).  2.0: recompute rewrite.
;;
;; Phase inferred from the existing WIRE TYPE "(N)" count (N=2 -> 1ph, else 3ph), default 3-phase.
;; Calc basis: *term-temp* 90, *vd-coeff* 2.0 (set *term-temp* 75 for compliant termination ampacity).
;;
;; Globals read:  *o-suite-root* *term-temp* *vd-coeff* *ofeed-tint* *ofeed-neutral-max*
;;                *ofeed-parallel-material* *ofeed-max-cond*
;;                *ofeed-table-th* *ofeed-table-rowh* *ofeed-table-hdrh* *ofeed-table-wscale*
;;                *ofeed-ambient-temp* *ofeed-neutral-is-ccc* *ofeed-amb-c-max* *ofeed-corr-table*
;; v2.27
;; ============================================================

(vl-load-com)

;; --- persistent globals -------------------------------------
(if (not (boundp '*term-temp*))        (setq *term-temp* 90))
(if (not (boundp '*vd-coeff*))         (setq *vd-coeff* 2.0))
(if (not (boundp '*ofeed-tint*))       (setq *ofeed-tint* T))
(if (not (boundp '*ofeed-neutral-max*)) (setq *ofeed-neutral-max* 2)) ; feeders numbered above this -> no neutral ("-")
;; Material model: a feeder that fits in ONE capped-copper run is sized in COPPER; a feeder that
;; needs MULTIPLE parallel runs defaults to this material (aluminum). Set "CU" to keep all-copper.
(if (not (boundp '*ofeed-parallel-material*)) (setq *ofeed-parallel-material* "AL"))
;; Largest conductor allowed in ONE run (per-run cap), for EVERY feeder. A load that exceeds one
;; capped-copper run parallels into multiple runs of <= this size and switches to the parallel
;; material above. A size string present in the conductor table (e.g. "500KCMIL"), or nil for no cap.
(if (not (boundp '*ofeed-max-cond*)) (setq *ofeed-max-cond* "500KCMIL"))
;; O-FEEDSET create geometry (paper-space units), all from the production E-2.0 table (DXF groups
;; 141/142). These are ALWAYS (re)set on load -- they track the production sheet, so they must not go
;; stale across versions (a sticky boundp-guarded *ofeed-table-th* held a 0.16 from an older build).
;; For a one-off session tweak, setq them AFTER loading; a reload restores these production values.
(setq *ofeed-table-th*   0.1)    ; cell text height (all rows)
(setq *ofeed-table-rowh* 0.392)  ; data row height
(setq *ofeed-table-hdrh* 0.588)  ; header row height
(if (not (boundp '*ofeed-table-wscale*)) (setq *ofeed-table-wscale* 1.0))  ; uniform column-width multiplier (persists)
(if (not (boundp '*ofeed-cond-table*)) (setq *ofeed-cond-table* nil))
(if (not (boundp '*ofeed-ocp-sizes*))  (setq *ofeed-ocp-sizes* nil))
(if (not (boundp '*ofeed-egc-table*))  (setq *ofeed-egc-table* nil))
(if (not (boundp '*ofeed-emt-table*))  (setq *ofeed-emt-table* nil))
(if (not (boundp '*ofeed-inverters*))  (setq *ofeed-inverters* nil))
;; Ampacity adjustments (NEC 310.15). Ambient = design high ambient in Celsius; 30 -> all factors
;; 1.0 (identical to pre-2.27, matches the production sheet). It is gathered per run from a drawing
;; "AMBIENT ..." note or a prompt (c:O-FEED / c:O-FEEDSET); the engine just reads this global.
(if (not (boundp '*ofeed-ambient-temp*)) (setq *ofeed-ambient-temp* 30.0))
;; Count the neutral as a current-carrying conductor for the >3-CCC bundling factor (310.15(C)/(E)).
;; nil = balanced 3-phase wye, neutral not counted -> AC-1/AC-2 = 3 CCC -> bundling 1.0. T = nonlinear
;; / harmonic loads -> AC-1/AC-2 (3 phase + neutral) = 4 CCC -> 0.80. EGC never counts. AC-3+ have no
;; neutral so they stay 3 CCC either way.
(if (not (boundp '*ofeed-neutral-is-ccc*)) (setq *ofeed-neutral-is-ccc* nil))
;; set once gather has prompted (or found a note) this session, so O-FEED does NOT re-prompt for ambient
;; on every run -- a getstring that fires each recompute reads as "O-FEED is hung / so slow". A drawing
;; note is always re-read (cheap, pre-filtered); the prompt fires only the first time there is no note.
(if (not (boundp '*ofeed-ambient-asked*)) (setq *ofeed-ambient-asked* nil))
;; Auto-detect units on a unit-less ambient number: <= this is read as Celsius, above it as
;; Fahrenheit (then converted). ~world-record high air temp; a bare "113" -> Fahrenheit -> 45C.
(if (not (boundp '*ofeed-amb-c-max*)) (setq *ofeed-amb-c-max* 50.0))
(if (not (boundp '*ofeed-corr-table*)) (setq *ofeed-corr-table* nil))

;; ============================================================
;; ROOT + CSV LOADER  (unchanged from 1.0)
;; ============================================================

(defun _ofeed-root ()
  (if (and (boundp '*o-suite-root*) *o-suite-root*)
    *o-suite-root*
    "C:\\Users\\adria\\CAD\\Automations\\opal-tools\\"))

(defun _ofeed-split (s sep / pos out)
  (setq out nil)
  (while (setq pos (vl-string-search sep s))
    (setq out (cons (substr s 1 pos) out)
          s   (substr s (+ pos 1 (strlen sep)))))
  (reverse (cons s out)))

(defun _ofeed-read-csv (path / f line rows seenhdr trimmed)
  (setq rows nil seenhdr nil)
  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq trimmed (vl-string-trim " \t\r" line))
        (cond
          ((= trimmed "") nil)
          ((= (substr trimmed 1 1) "#") nil)
          ((not seenhdr) (setq seenhdr T))
          (T (setq rows (cons (_ofeed-split trimmed ",") rows)))))
      (close f)))
  (reverse rows))

(defun _ofeed-fld (r n / v) (setq v (nth n r)) (if (and v (> (strlen v) 0)) v nil))

(defun _ofeed-load-refs ( / root)
  (setq root (_ofeed-root))
  (regapp "OCOTILLO")
  ;; conductors.csv: size,material,insulation,amp75,amp90,r_ohm_kft,area_in2
  (setq *ofeed-cond-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\conductors.csv"))
    (if (>= (length r) 7)
      (setq *ofeed-cond-table*
        (cons (list (nth 0 r) (strcase (nth 1 r)) (nth 2 r)
                    (atoi (nth 3 r)) (atoi (nth 4 r)) (atof (nth 5 r)) (atof (nth 6 r)))
              *ofeed-cond-table*))))
  (setq *ofeed-cond-table* (reverse *ofeed-cond-table*))
  (setq *ofeed-emt-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\conduit_emt.csv"))
    (if (>= (length r) 2)
      (setq *ofeed-emt-table* (cons (list (nth 0 r) (atof (nth 1 r))) *ofeed-emt-table*))))
  (setq *ofeed-emt-table* (reverse *ofeed-emt-table*))
  (setq *ofeed-egc-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\egc.csv"))
    (if (>= (length r) 2)
      (setq *ofeed-egc-table* (cons (list (atoi (nth 0 r)) (nth 1 r)) *ofeed-egc-table*))))
  (setq *ofeed-egc-table* (reverse *ofeed-egc-table*))
  (setq *ofeed-ocp-sizes* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\ocpd.csv"))
    (if (>= (length r) 1) (setq *ofeed-ocp-sizes* (cons (atoi (nth 0 r)) *ofeed-ocp-sizes*))))
  (setq *ofeed-ocp-sizes* (reverse *ofeed-ocp-sizes*))
  (setq *ofeed-inverters* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\inverters.csv"))
    (if (>= (length r) 4)
      (setq *ofeed-inverters*
        (cons (list (nth 0 r) (atof (nth 1 r)) (atoi (nth 2 r)) (atoi (nth 3 r))) *ofeed-inverters*))))
  (setq *ofeed-inverters* (reverse *ofeed-inverters*))
  ;; ambient_correction.csv: amb_high_c,factor75,factor90 (NEC 310.15(B)(1), 30C base). Ascending by
  ;; band upper bound. Missing file -> nil table -> _ofeed-temp-factor returns 1.0 (no derating).
  (setq *ofeed-corr-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\ambient_correction.csv"))
    (if (>= (length r) 3)
      (setq *ofeed-corr-table*
        (cons (list (atof (nth 0 r)) (atof (nth 1 r)) (atof (nth 2 r))) *ofeed-corr-table*))))
  (setq *ofeed-corr-table* (reverse *ofeed-corr-table*))
  (length *ofeed-cond-table*))

;; ============================================================
;; ENGINE
;; conductor row = (size material insulation amp75 amp90 r_ohm_kft area_in2)
;; The pick/size helpers take the WORKING conductor subset (CONDTAB) as an argument so a feeder can be
;; sized from just the copper or just the (optionally capped) aluminum conductors. CONDTAB must stay
;; in ascending-ampacity order -- the sizer takes the FIRST conductor that carries the per-run current.
;; ============================================================

;; RAW (uncorrected) table ampacity for the term-temp column. The NEC 310.15 adjustments
;; (ambient temp + >3-CCC bundling) are applied as a DERATE multiplier in _ofeed-size-feeder,
;; which drives the conductor pick off raw-ampacity * derate. See _ofeed-temp-factor /
;; _ofeed-bundle-factor and the ADJUSTED AMPACITY column.
(defun _ofeed-amp-col (row) (if (= *term-temp* 90) (nth 4 row) (nth 3 row)))

;; NEC 310.15(B)(1) ambient temperature correction. Walk *ofeed-corr-table* (ascending by band upper
;; bound) and return the first band whose upper bound >= the design ambient; pick the 90C or 75C
;; factor by *term-temp*. No table / ambient below the first band -> 1.0 (no derating, sheet-matching).
(defun _ofeed-temp-factor ( / amb f)
  (setq amb (if (boundp '*ofeed-ambient-temp*) *ofeed-ambient-temp* 30.0) f nil)
  (foreach band *ofeed-corr-table*
    (if (and (null f) (<= amb (nth 0 band)))
      (setq f (if (= *term-temp* 90) (nth 2 band) (nth 1 band)))))
  (if f f 1.0))

;; NEC 310.15(C)(1) adjustment for more than 3 current-carrying conductors in a raceway.
(defun _ofeed-bundle-factor (ccc)
  (cond ((<= ccc 3) 1.0) ((<= ccc 6) 0.80) ((<= ccc 9) 0.70)
        ((<= ccc 20) 0.50) ((<= ccc 30) 0.45) ((<= ccc 40) 0.40) (T 0.35)))

;; current-carrying conductor count for one run: phase conductors + neutral (only when counted as a
;; CCC per *ofeed-neutral-is-ccc*). The EGC is never a CCC.
(defun _ofeed-ccc (np neutral)
  (+ np (if (and neutral *ofeed-neutral-is-ccc*) 1 0)))

;; conductors of one material (CU/AL), preserving the CSV's ascending-ampacity order
(defun _ofeed-cond-table-mat (mat / out)
  (setq mat (strcase mat) out nil)
  (foreach row *ofeed-cond-table* (if (= (nth 1 row) mat) (setq out (cons row out))))
  (reverse out))

(defun _ofeed-cond-row (condtab size / r)
  (foreach row condtab (if (= size (nth 0 row)) (setq r row))) r)

;; cap a material subset at capsize (drop conductors larger than it) so a feeder PARALLELS into
;; multiple runs of <= capsize instead of one oversized conductor. nil / unknown capsize -> no cap.
(defun _ofeed-cap-table (condtab capsize / row capamp out)
  (if (null capsize)
    condtab
    (progn
      (setq row (_ofeed-cond-row condtab capsize))
      (if (null row)
        condtab
        (progn
          (setq capamp (_ofeed-amp-col row))
          (foreach r2 condtab (if (<= (_ofeed-amp-col r2) capamp) (setq out (cons r2 out))))
          (reverse out))))))

(defun _ofeed-cond-R (condtab size / row) (setq row (_ofeed-cond-row condtab size)) (if row (nth 5 row) 0.0))
(defun _ofeed-cond-area (condtab size / row) (setq row (_ofeed-cond-row condtab size)) (if row (nth 6 row) 0.0))

;; EGC is always copper (NEC 250.122 copper table) -- its conduit-fill area is looked up in the CU
;; subset regardless of the phase-conductor material, so an aluminum feeder still gets a correct fill %.
(defun _ofeed-cond-area-egc (size) (_ofeed-cond-area (_ofeed-cond-table-mat "CU") size))

(defun _ofeed-ocp-pick (i / r)
  (foreach s *ofeed-ocp-sizes* (if (and (not r) (>= s i)) (setq r s))) r)

(defun _ofeed-egc-pick (ocp / r)
  (foreach e *ofeed-egc-table* (if (and (not r) (<= ocp (car e))) (setq r (cadr e)))) r)

(defun _ofeed-cond-pick (condtab i / r)
  (foreach row condtab
    (if (and (not r) (>= (_ofeed-amp-col row) i)) (setq r (nth 0 row)))) r)

(defun _ofeed-vd-volts (L i R) (/ (* *vd-coeff* L i R) 1000.0))

(defun _ofeed-phase-count (phase) (if (= phase 1) 2 3))

(defun _ofeed-parallel-sets (condtab i125 / maxamp)
  (if (null condtab)
    1                                                   ; empty/nil subset -> don't (last nil); treat as 1 set
    (progn
      (setq maxamp (_ofeed-amp-col (last condtab)))
      (if (<= i125 maxamp) 1 (fix (+ 0.9999 (/ i125 (float maxamp))))))))

(defun _ofeed-conduit-pick (area / r last-c)
  (foreach c *ofeed-emt-table*
    (if (and (not r) (< (/ area (cadr c)) 0.40))
      (setq r (list (car c) (* 100.0 (/ area (cadr c)))))))
  (if r r
    (progn (setq last-c (last *ofeed-emt-table*))
      (list (car last-c) (* 100.0 (/ area (cadr last-c)))))))

;; size one feeder. CAPSIZE = a size string to cap the per-run conductor (forces paralleling) or nil.
;; Conductors are sized to the OCPD (breaker) rating so the breaker PROTECTS the conductor (total
;; ampacity >= OCPD), not merely to carry the 125% load. MATERIAL is chosen by the result: if the OCPD
;; is met by ONE capped-copper run -> COPPER; otherwise it parallels into multiple runs of
;; *ofeed-parallel-material* (aluminum). CONDUIT is sized PER RUN; the SETS value carries the run count.
(defun _ofeed-size-feeder (id load phase volts length neutral capsize /
                           cu material condtab i125 sets per ocp cond egc R basedamp adjamp vdv vdp np
                           area-set cp wire neut gnd insul ccc derate tf bf)
  (setq i125     (* load 1.25)
        ocp      (_ofeed-ocp-pick i125)                       ; breaker: next std rating >= 125% load
        np       (_ofeed-phase-count phase)
        ccc      (_ofeed-ccc np neutral)
        ;; NEC 310.15 derate = ambient-temp correction * >3-CCC bundling. 1.0 at 30C / <=3 CCC, so the
        ;; sizing is unchanged from pre-2.27. Selection runs off raw ampacity * derate (demand / derate
        ;; <= raw ampacity), so a hot ambient or counted-neutral bundling upsizes the conductor / adds a
        ;; set. Floored so a 0-factor case (term-temp 75 above 70C) can't divide-by-zero -- it just
        ;; fails to find a conductor (the existing "load too high" path).
        tf       (_ofeed-temp-factor)
        bf       (_ofeed-bundle-factor ccc)
        derate   (max 0.01 (* tf bf))
        cu       (_ofeed-cap-table (_ofeed-cond-table-mat "CU") capsize)
        ;; Size the conductor to PROTECT THE BREAKER -- total ampacity must reach the OCPD rating, not
        ;; just carry i125. Sizing to i125 can land the conductor BELOW the next-standard breaker (e.g.
        ;; 2x350KCMIL = 560 A under a 600 A breaker -- NEC 240.4). Driving sets/per/cond off ocp makes
        ;; basedamp >= ocp >= i125. A single capped-copper run that reaches the OCPD stays copper; else
        ;; it parallels in *ofeed-parallel-material*.
        material (if (= (_ofeed-parallel-sets cu (/ (float ocp) derate)) 1) "CU" *ofeed-parallel-material*)
        condtab  (_ofeed-cap-table (_ofeed-cond-table-mat material) capsize)
        sets     (_ofeed-parallel-sets condtab (/ (float ocp) derate))
        per      (/ (float ocp) sets)
        cond     (_ofeed-cond-pick condtab (/ per derate))
        egc      (_ofeed-egc-pick ocp)
        R        (_ofeed-cond-R condtab cond)
        insul    (nth 2 (_ofeed-cond-row condtab cond))
        basedamp (fix (* sets (_ofeed-amp-col (_ofeed-cond-row condtab cond))))
        adjamp   (fix (* sets derate (_ofeed-amp-col (_ofeed-cond-row condtab cond))))
        vdv      (_ofeed-vd-volts length (/ load (float sets)) R)
        vdp      (* 100.0 (/ vdv (float volts)))
        area-set (+ (* np (_ofeed-cond-area condtab cond))
                    (if neutral (_ofeed-cond-area condtab cond) 0.0)
                    (_ofeed-cond-area-egc egc))
        cp       (_ofeed-conduit-pick area-set)
        wire     (strcat (if (> sets 1) (strcat (itoa sets) " SETS OF ") "")
                         "(" (itoa np) ") " cond " " material " " insul)
        neut     (if neutral (strcat "(1) " cond " " material " " insul) "-")
        gnd      (strcat "(1) " egc " CU GND"))
  (list (cons "ID" id) (cons "SETS" sets) (cons "WIRE" wire)
        (cons "NEUTRAL" neut) (cons "GROUND" gnd)
        (cons "CONDUIT" (strcat (car cp) " EMT"))
        (cons "FILL" (strcat (rtos (cadr cp) 2 2) "%"))
        (cons "LENGTH" length) (cons "LOAD" load) (cons "LOAD125" i125)
        (cons "OCP" ocp) (cons "VOLTS" volts) (cons "BASEDAMP" basedamp)
        (cons "ADJAMP" adjamp) (cons "CCC" ccc) (cons "TEMPADJ" tf) (cons "FILLADJ" bf)
        (cons "VDV" vdv) (cons "VDP" vdp)))

(defun _ofeed-row-cells (rec)
  (list
    (cdr (assoc "ID" rec))
    (itoa (cdr (assoc "SETS" rec)))
    (cdr (assoc "WIRE" rec))
    (cdr (assoc "NEUTRAL" rec))
    (cdr (assoc "GROUND" rec))
    (cdr (assoc "CONDUIT" rec))
    (cdr (assoc "FILL" rec))
    (rtos (cdr (assoc "LENGTH" rec)) 2 0)
    (rtos (cdr (assoc "LOAD" rec)) 2 1)
    (rtos (cdr (assoc "LOAD125" rec)) 2 2)
    (itoa (cdr (assoc "OCP" rec)))
    (itoa (cdr (assoc "VOLTS" rec)))
    (itoa (cdr (assoc "BASEDAMP" rec)))
    (itoa (cdr (assoc "ADJAMP" rec)))
    (rtos (cdr (assoc "VDV" rec)) 2 2)
    (strcat (rtos (cdr (assoc "VDP" rec)) 2 2) "%")
    "VD = ((2*L*IR) / 1000)* 1/Vmax"))

;; ============================================================
;; TABLE SCHEMA
;; ============================================================

(defun _ofeed-columns ()
  (list
    (cons "FEEDER"                "input")
    (cons "# OF PARALLEL SETS"    "sized")
    (cons "WIRE TYPE"             "sized")
    (cons "NEUTRAL"              "sized")
    (cons "GROUND"               "sized")
    (cons "CONDUIT"              "sized")
    (cons "CONDUIT FILL"         "sized")
    (cons "LENGTH (FT)"          "input")
    (cons "CIRCUIT LOAD (A)"     "input")
    (cons "CIRCUIT LOAD (A) 125%" "calc")
    (cons "BREAKER SIZE (A)"     "sized")
    (cons "VOLTAGE (V)"          "input")
    (cons "BASED AMPACITY (A)"   "sized")
    (cons "ADJUSTED AMPACITY (A)" "sized")
    (cons "VOLTAGE DROP (V)"     "calc")
    (cons "VOLTAGE DROP (%)"     "calc")
    (cons "GENERAL FORMULA"      "static")))

(defun _ofeed-computed-idx () '(1 2 3 4 5 6 10 12 13))
(defun _ofeed-hdr (k) (car (nth k (_ofeed-columns))))

(defun _ofeed-join (lst sep / s)
  (setq s "")
  (foreach x lst (setq s (if (= s "") x (strcat s sep x))))
  s)

;; ============================================================
;; TEXT NORMALIZE + VALIDATION HELPERS
;; ============================================================

(defun _ofeed-strip-mtext (s / out i n ch nxt)
  (if (null s) (setq s ""))
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq ch (substr s i 1))
    (cond
      ((= ch "{") (setq i (1+ i)))
      ((= ch "}") (setq i (1+ i)))
      ((= ch "\\")
       (setq nxt (strcase (substr s (1+ i) 1)))
       (cond
         ((member nxt '("P" "X")) (setq out (strcat out " ") i (+ i 2)))
         ((member nxt '("F" "C" "H" "A" "T" "Q" "W" "L" "O" "K"))
          (setq i (+ i 2))
          (while (and (<= i n) (/= (substr s i 1) ";")) (setq i (1+ i)))
          (setq i (1+ i)))
         (T (setq out (strcat out (substr s (1+ i) 1)) i (+ i 2)))))
      (T (setq out (strcat out ch) i (1+ i)))))
  out)

(defun _ofeed-norm (s)
  (strcase (vl-string-trim " \t\r\n" (_ofeed-strip-mtext s))))

(defun _ofeed-cell-formula-p (s / u tr)
  (setq u (strcase s) tr (vl-string-trim " \t\r\n" s))
  (cond ((vl-string-search "%<" u) T)
        ((vl-string-search "\\ACEXPR" u) T)
        ((and (> (strlen tr) 0) (= (substr tr 1 1) "=")) T)
        (T nil)))

(defun _ofeed-has-digit (s / i n c f)
  (setq i 1 n (strlen s) f nil)
  (while (and (not f) (<= i n))
    (setq c (ascii (substr s i 1)))
    (if (and (>= c 48) (<= c 57)) (setq f T))
    (setq i (1+ i)))
  f)

;; trailing integer of a feeder id ("AC-3" -> 3), else nil
(defun _ofeed-trailing-int (s / i ds)
  (setq i (strlen s) ds "")
  (while (and (> i 0) (>= (ascii (substr s i 1)) 48) (<= (ascii (substr s i 1)) 57))
    (setq ds (strcat (substr s i 1) ds) i (1- i)))
  (if (> (strlen ds) 0) (atoi ds) nil))

;; ============================================================
;; ACAD_TABLE CELL I/O + COLOR + REGEN  (defensive VLA)
;; ============================================================

(defun _ofeed-cell (tbl r c / v)
  (setq v (vl-catch-all-apply 'vla-GetText (list tbl r c)))
  (if (vl-catch-all-error-p v) "" v))

(defun _ofeed-set (tbl r c val / e)
  (setq e (vl-catch-all-apply 'vla-SetText (list tbl r c val)))
  (not (vl-catch-all-error-p e)))

;; suppress / resume the table's auto-regen -- writing a native table cell-by-cell otherwise
;; triggers a full table regen per cell (the ~10s/feeder cost). Batch the edits, regen once.
;; Uses vlax-put-property (a real, always-defined function), NOT the vla-put- wrapper: on some builds
;; vla-put-RegenerateTableSuggested isn't generated and raised an uncatchable "bad function" that
;; aborted O-FEED. vlax-put-property routes through IDispatch by name, so a missing property is just a
;; normal catchable error -> worst case the speedup is skipped (slower), never a crash.
(defun _ofeed-noregen (tbl)
  (vl-catch-all-apply 'vlax-put-property (list tbl 'RegenerateTableSuggested :vlax-false)))
;; resume regen AND force the deferred layout to rebuild NOW (vla-GenerateLayout) so the table ends
;; the run truly CLEAN. Without this the table was left dirty/suppressed and the NEXT run's PHASE-1
;; GetText calls each forced a regen -> O(rows^2) -> progressively slower / hanging on repeated runs.
(defun _ofeed-doregen (tbl)
  (vl-catch-all-apply 'vlax-put-property (list tbl 'RegenerateTableSuggested :vlax-true))
  (vl-catch-all-apply 'vla-GenerateLayout (list tbl))
  (vl-catch-all-apply 'vla-Update (list tbl)))

;; target layer for the feeder schedule TABLE entity (config-driven; never hardcoded). oconfig 1.08
;; sets *ocfg-layer-feeder-table* = "G-TEXT"; fall back to that literal if oconfig is older/unloaded.
(defun _ofeed-table-layer ()
  (if (and (boundp '*ocfg-layer-feeder-table*) *ocfg-layer-feeder-table*
           (/= *ocfg-layer-feeder-table* ""))
    *ocfg-layer-feeder-table*
    "G-TEXT"))

(defun _ofeed-ensure-layer (ly)
  (if (and ly (/= ly "") (not (tblsearch "LAYER" ly)))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 ly) '(70 . 0) '(62 . 7) '(6 . "Continuous"))))
  ly)

;; place the table object on the target layer (auto-create the layer first). Catch-wrapped so a
;; locked/odd layer can never abort recompute or create.
(defun _ofeed-place-on-layer (tbl / ly)
  (setq ly (_ofeed-ensure-layer (_ofeed-table-layer)))
  (if ly (vl-catch-all-apply 'vla-put-Layer (list tbl ly))))

;; resolve a bare AcCmColor by trying ProgID version suffixes (ACADVER + app Version + a spread)
(defun _ofeed-color-obj ( / vv vers made col)
  (setq vers (list (substr (getvar "ACADVER") 1 2))
        vv   (vl-catch-all-apply 'vla-get-Version (list (vlax-get-acad-object))))
  (if (and (not (vl-catch-all-error-p vv)) (>= (strlen vv) 2))
    (setq vers (cons (substr vv 1 2) vers)))
  (setq vers (append vers '("26" "25" "24" "23" "22" "21" "20" "27" "28")) made nil)
  (foreach v vers
    (if (not made)
      (progn
        (setq col (vl-catch-all-apply 'vla-GetInterfaceObject
                    (list (vlax-get-acad-object) (strcat "AutoCAD.AcCmColor." v))))
        (if (not (vl-catch-all-error-p col)) (setq made col)))))
  made)

(defun _ofeed-make-color (r g b / c)
  (if (setq c (_ofeed-color-obj)) (progn (vl-catch-all-apply 'vla-SetRGB (list c r g b)) c) nil))

;; AcCmColor by ACI index (e.g. 7 = white -> plots black with a color/mono plot style)
(defun _ofeed-make-aci (n / c)
  (if (setq c (_ofeed-color-obj)) (progn (vl-catch-all-apply 'vla-put-ColorIndex (list c n)) c) nil))

(defun _ofeed-tint-cell (tbl r c col)
  (if col
    (progn
      (vl-catch-all-apply 'vla-SetCellBackgroundColorNone (list tbl r c :vlax-false))
      (vl-catch-all-apply 'vla-SetCellBackgroundColor (list tbl r c col)))))

(defun _ofeed-clear-tint (tbl r c)
  (vl-catch-all-apply 'vla-SetCellBackgroundColorNone (list tbl r c :vlax-true)))

(defun _ofeed-flag (tbl r c bad col)
  (if *ofeed-tint*
    (if bad
      (if col (_ofeed-tint-cell tbl r c col))
      (_ofeed-clear-tint tbl r c))))

;; Normalize ONLY the user-typed input cells -- LENGTH (7), CIRCUIT LOAD (8), VOLTAGE (11) on data
;; rows -- to WHITE content text (ACI 7 -> plots black) + MIDDLE-CENTER (acMiddleCenter = 5), matching
;; the sized cells. These were the only cells that kept their as-typed gray / right-aligned look; the
;; sized + header cells already render uniform, so the visible result equals the old "every cell" pass
;; at a fraction of the COM volume (the every-cell version, rows x 16 cols, froze big tables). FORMATTING
;; ONLY: never writes a value, so an unchanged cell is reformatted but NOT blue-tinted and NOT reverted.
;; Content color + alignment are independent of the blue/red BACKGROUND tints, so those stay intact.
;; Call inside the no-regen batch. GUI-only (COM); a missing AcCmColor just skips the color.
(defun _ofeed-format-inputs (tbl nrows hrow map / wcol r tcol ci)
  (setq wcol (_ofeed-make-aci 7))
  (foreach ci '(7 8 11)
    (if (setq tcol (_ofeed-col map ci))
      (progn
        (setq r (1+ hrow))
        (while (< r nrows)
          (vl-catch-all-apply 'vla-SetCellAlignment (list tbl r tcol 5))   ; 5 = acMiddleCenter
          (if wcol (vl-catch-all-apply 'vla-SetCellContentColor (list tbl r tcol wcol)))
          (setq r (1+ r))))))
  (if wcol (vl-catch-all-apply 'vlax-release-object (list wcol))))

;; ============================================================
;; HEADER / COLUMN MAP
;; ============================================================

;; header signature = an already-norm'd (uppercased) header with everything but A-Z/0-9 removed. This
;; makes header matching tolerant of unit-suffix / punctuation variance ("CONDUIT FILL (%)" recognizes
;; as canonical "CONDUIT FILL", so it is NOT treated as missing and duplicated). The kept letters/digits
;; still keep the two VOLTAGE DROP columns distinct: (V) -> ...DROPV vs (%) -> ...DROP.
(defun _ofeed-hdr-sig (s / i n ch a out)
  (setq i 1 n (strlen s) out "")
  (while (<= i n)
    (setq ch (substr s i 1) a (ascii ch))
    (if (or (and (>= a 65) (<= a 90)) (and (>= a 48) (<= a 57))) (setq out (strcat out ch)))
    (setq i (1+ i)))
  out)

(defun _ofeed-canon-index (normhdr / i found sig)
  (setq i 0 found nil sig (_ofeed-hdr-sig normhdr))
  (if (> (strlen sig) 0)
    (foreach pair (_ofeed-columns)
      (if (and (not found) (= (_ofeed-hdr-sig (_ofeed-norm (car pair))) sig)) (setq found i))
      (setq i (1+ i))))
  found)

(defun _ofeed-find-header-row (tbl ncols nrows / r c hr)
  (setq r 0 hr nil)
  (while (and (< r nrows) (not hr))
    (setq c 0)
    (while (and (< c ncols) (not hr))
      (if (= (_ofeed-norm (_ofeed-cell tbl r c)) "FEEDER") (setq hr r))
      (setq c (1+ c)))
    (setq r (1+ r)))
  hr)

(defun _ofeed-build-colmap (tbl hrow ncols / c k map)
  (setq c 0 map nil)
  (while (< c ncols)
    (setq k (_ofeed-canon-index (_ofeed-norm (_ofeed-cell tbl hrow c))))
    (if (and k (not (assoc k map))) (setq map (cons (cons k c) map)))
    (setq c (1+ c)))
  map)

(defun _ofeed-col (map k) (cdr (assoc k map)))

(defun _ofeed-neutral-p (s / v)
  (setq v (_ofeed-norm s))
  (and (/= v "") (/= v "-") (/= v "--")))

(defun _ofeed-phase-from-wire (s / p1 p2 nstr)
  (setq s (_ofeed-norm s) nstr nil)
  (if (setq p1 (vl-string-search "(" s))
    (if (setq p2 (vl-string-search ")" s))
      (if (> p2 (1+ p1)) (setq nstr (substr s (+ p1 2) (- p2 p1 1))))))
  (cond ((null nstr) 3)
        ((= (atoi nstr) 2) 1)
        (T 3)))

;; ============================================================
;; TABLE SELECTION  (auto-find + forgiving pick)
;; ============================================================

(defun _ofeed-is-feeder-table-p (obj / nm ncols nrows hrow map ok)
  (setq ok nil
        nm (vl-catch-all-apply 'vla-get-ObjectName (list obj)))
  (if (and (not (vl-catch-all-error-p nm)) (= nm "AcDbTable"))
    (progn
      (setq ncols (vl-catch-all-apply 'vla-get-Columns (list obj))
            nrows (vl-catch-all-apply 'vla-get-Rows (list obj)))
      (if (and (not (vl-catch-all-error-p ncols)) (not (vl-catch-all-error-p nrows))
               (setq hrow (_ofeed-find-header-row obj ncols nrows)))
        (progn
          (setq map (_ofeed-build-colmap obj hrow ncols))
          (if (and (_ofeed-col map 0) (_ofeed-col map 8) (_ofeed-col map 11)) (setq ok T))))))
  ok)

(defun _ofeed-feeder-tables ( / ss i obj out)
  (setq out nil)
  (if (setq ss (ssget "X" '((0 . "ACAD_TABLE"))))
    (progn (setq i 0)
      (while (< i (sslength ss))
        (setq obj (vlax-ename->vla-object (ssname ss i)))
        (if (_ofeed-is-feeder-table-p obj) (setq out (cons obj out)))
        (setq i (1+ i)))))
  (reverse out))

(defun _ofeed-first-feeder-in (ss / i obj found)
  (setq i 0 found nil)
  (while (and (not found) (< i (sslength ss)))
    (setq obj (vlax-ename->vla-object (ssname ss i)))
    (if (_ofeed-is-feeder-table-p obj) (setq found obj))
    (setq i (1+ i)))
  found)

(defun _ofeed-pick-table ( / feeders ss obj)
  (setq feeders (_ofeed-feeder-tables))
  (cond
    ((= (length feeders) 1) (prompt "\nFound feeder table.") (car feeders))
    (T
     (prompt (if (cdr feeders)
               "\nMultiple feeder tables -- select one (click or window): "
               "\nSelect the feeder table (click or window): "))
     (if (setq ss (ssget '((0 . "ACAD_TABLE"))))
       (progn
         (setq obj (_ofeed-first-feeder-in ss))
         (if obj obj (vlax-ename->vla-object (ssname ss 0))))
       nil))))

;; ============================================================
;; RECOMPUTE  (validate per-field, write+blue, confirm Y/Esc)
;; ============================================================

;; PLAN one data row -- PHASE 1, READS ONLY, mutates nothing. Returns:
;;   (sized-p  (flags...)  (writes...)  (errs...))
;;   flags  = (r c bad)            -> phase 2 calls (_ofeed-flag tbl r c bad redcol)
;;   writes = (r c newval oldval)  -> phase 2 SetText + blue-tint + records oldval for revert
;; Why reads-only: a vla-GetText on a table left "dirty" by a prior vla-SetText FORCES the deferred
;; regen so it can return a current value. Interleaving reads between writes therefore cost ~one
;; full-table regen per row (the ~10s/feeder, O(rows^2) overall). Planning every row first (no
;; writes), then applying every write (no reads), lets the RegenerateTableSuggested suppression
;; hold -> the table regenerates ONCE for the whole pass. Same values/flags as the old _ofeed-process-row.
(defun _ofeed-plan-row (tbl r map feeder total commonv /
                        loadstr voltstr lenstr loadok voltok volteff lenok aggp
                        fload fvolts flen fnum neutral phase rec cells note
                        flags writes errs k kk tcol oldval newval)
  (setq flags nil writes nil errs nil
        loadstr (_ofeed-cell tbl r (_ofeed-col map 8))
        voltstr (_ofeed-cell tbl r (_ofeed-col map 11))
        lenstr  (if (_ofeed-col map 7) (_ofeed-cell tbl r (_ofeed-col map 7)) "")
        fnum    (_ofeed-trailing-int feeder)
        aggp    (and fnum (<= fnum *ofeed-neutral-max*) (> total 0.0))  ; AC-1/AC-2 carry the branch total
        fload   (if aggp total (atof loadstr))
        loadok  (> fload 0.0)
        voltok  (> (atoi voltstr) 0)
        lenok   (_ofeed-has-digit lenstr)
        volteff (or voltok (> commonv 0)))            ; own voltage, or the assumed common one
  ;; verify+correct: an aggregation feeder's CIRCUIT LOAD must equal the sum of AC-3..n; fix if not
  (if (and aggp (> (abs (- (atof loadstr) total)) 0.005))
    (setq writes (cons (list r (_ofeed-col map 8) (rtos total 2 1) loadstr) writes)))
  ;; assume the common system voltage on a blank VOLTAGE cell (fill it so the schedule shows + clears red)
  (if (and (not voltok) (> commonv 0) (_ofeed-col map 11))
    (setq writes (cons (list r (_ofeed-col map 11) (itoa commonv) voltstr) writes)))
  (setq flags (cons (list r (_ofeed-col map 8)  (not loadok)) flags))
  (setq flags (cons (list r (_ofeed-col map 11) (not volteff)) flags))
  (if (_ofeed-col map 7) (setq flags (cons (list r (_ofeed-col map 7) (not lenok)) flags)))
  (if (not loadok) (setq errs (cons (strcat feeder ": CIRCUIT LOAD missing/invalid -- NOT sized") errs)))
  (if (not lenok)  (setq errs (cons (strcat feeder ": LENGTH missing/invalid -- sized, but voltage drop can't be computed") errs)))
  (if (not volteff) (setq errs (cons (strcat feeder ": VOLTAGE missing and no other row has one -- sized, but voltage drop % can't be computed") errs)))
  (if (not loadok)
    (list nil (reverse flags) nil (reverse errs))
    (progn
      ;; Material is auto (copper single run vs aluminum multi-run) inside _ofeed-size-feeder; the
      ;; per-run cap *ofeed-max-cond* drives paralleling. Neutral stays keyed off the feeder number.
      (setq fvolts  (cond (voltok (atoi voltstr)) ((> commonv 0) commonv) (T 480)) ; fload+fnum already set (agg-aware)
            flen    (if lenok (atof lenstr) 0.0)
            neutral (cond ((null fnum)                              ; non-AC id -> read the NEUTRAL cell
                           (_ofeed-neutral-p (if (_ofeed-col map 3) (_ofeed-cell tbl r (_ofeed-col map 3)) "")))
                          ((> fnum *ofeed-neutral-max*) nil)         ; AC-3+ -> no neutral ("-")
                          (T T))                                     ; AC-1/AC-2 -> neutral sized to the phase conductor
            phase   (_ofeed-phase-from-wire (if (_ofeed-col map 2) (_ofeed-cell tbl r (_ofeed-col map 2)) ""))
            rec     (vl-catch-all-apply '_ofeed-size-feeder (list feeder fload phase fvolts flen neutral *ofeed-max-cond*)))
      (if (vl-catch-all-error-p rec)
        (progn
          (if (_ofeed-col map 2)  (setq flags (cons (list r (_ofeed-col map 2)  T) flags)))
          (if (_ofeed-col map 10) (setq flags (cons (list r (_ofeed-col map 10) T) flags)))
          (list nil (reverse flags) nil
                (reverse (cons (strcat feeder ": load too high for the conductor/breaker table (add larger sizes)") errs))))
        (progn
          (setq cells (_ofeed-row-cells rec))
          (foreach k (_ofeed-computed-idx)
            (if (setq tcol (_ofeed-col map k))
              (progn
                (setq oldval (_ofeed-cell tbl r tcol))
                (if (not (_ofeed-cell-formula-p oldval))
                  (progn
                    (setq newval (nth k cells))
                    (if (/= (_ofeed-norm oldval) (_ofeed-norm newval))
                      (setq writes (cons (list r tcol newval oldval) writes))))))))
          ;; VOLTAGE DROP override: write the COMPUTED V (idx 14) and % (idx 15) even over a live formula
          ;; -- the user wants the calculated value to win. Needs length + an effective voltage.
          ;; (2.08 rolled back a VD force-overwrite that broke a live run; this is revertable via the
          ;; blue-preview [Yes/No] and each write is catch-wrapped, so a bad cell is skipped, not fatal.)
          ;; (idx +1 vs pre-2.27: ADJUSTED AMPACITY inserted at 13 shifted VD V/% to 14/15.)
          (if (and lenok volteff)
            (foreach k (list 14 15)
              (if (setq tcol (_ofeed-col map k))
                (progn
                  (setq oldval (_ofeed-cell tbl r tcol) newval (nth k cells))
                  (if (/= (_ofeed-norm oldval) (_ofeed-norm newval))
                    (setq writes (cons (list r tcol newval oldval) writes)))))))
          ;; self-heal: refill a DELETED 125% (idx 9) / GENERAL FORMULA (idx 16) cell (blank + not a live
          ;; formula). VD is handled above (forced); these stay blank-only so live calcs are preserved.
          ;; (GENERAL FORMULA moved 15 -> 16 with the ADJUSTED AMPACITY insert at 13.)
          (foreach kk (list (list 9 T) (list 16 T))
            (if (and (cadr kk) (setq tcol (_ofeed-col map (car kk))))
              (progn
                (setq oldval (_ofeed-cell tbl r tcol))
                (if (and (= (_ofeed-norm oldval) "") (not (_ofeed-cell-formula-p oldval)))
                  (progn
                    (setq newval (nth (car kk) cells))
                    (setq writes (cons (list r tcol newval oldval) writes)))))))
          (setq note (cond ((and (not lenok) (not volteff)) " | VD: no length/voltage")
                           ((not lenok) " | VD: no length")
                           ((not volteff) " | VD: no voltage")
                           ((and (not voltok) (> commonv 0)) (strcat " | V assumed " (itoa commonv)))
                           (T "")))
          (prompt (strcat "\n  " (cdr (assoc "ID" rec))
            "  CCC " (itoa (cdr (assoc "CCC" rec)))
            " | fill-adj " (rtos (cdr (assoc "FILLADJ" rec)) 2 2)
            " | AMP " (itoa (cdr (assoc "BASEDAMP" rec)))
            " -> ADJ " (itoa (cdr (assoc "ADJAMP" rec))) note))
          (list T (reverse flags) (reverse writes) (reverse errs)))))))

;; sum the CIRCUIT LOAD of the branch feeders (AC-3..n, fnum > neutral-max) -- reads only
(defun _ofeed-branch-total (tbl nrows hrow map / r feeder fnum tot)
  (setq r (1+ hrow) tot 0.0)
  (while (< r nrows)
    (setq feeder (_ofeed-norm (_ofeed-cell tbl r (_ofeed-col map 0)))
          fnum   (_ofeed-trailing-int feeder))
    (if (and fnum (> fnum *ofeed-neutral-max*))
      (setq tot (+ tot (atof (_ofeed-cell tbl r (_ofeed-col map 8))))))
    (setq r (1+ r)))
  tot)

;; most-common populated VOLTAGE among data rows (reads only); 0 if none -- the assumed system voltage
(defun _ofeed-common-volts (tbl nrows hrow map / r v counts pair best bestn)
  (setq r (1+ hrow) counts nil)
  (while (< r nrows)
    (setq v (atoi (_ofeed-cell tbl r (_ofeed-col map 11))))
    (if (> v 0)
      (if (setq pair (assoc v counts))
        (setq counts (subst (cons v (1+ (cdr pair))) pair counts))
        (setq counts (cons (cons v 1) counts))))
    (setq r (1+ r)))
  (setq best 0 bestn 0)
  (foreach c counts (if (> (cdr c) bestn) (setq best (car c) bestn (cdr c))))
  best)

;; T if the table HAS a FEEDER header but is missing one or more canonical columns -> O-FEED runs the
;; column repair before recomputing. nil when complete, or when there's no header at all (recompute
;; then reports that case itself -- column-insert can't help a table with no FEEDER cell to anchor on).
(defun _ofeed-missing-columns-p (tbl / ncols nrows hrow map kk miss)
  (setq ncols (vla-get-Columns tbl)
        nrows (vla-get-Rows tbl)
        hrow  (_ofeed-find-header-row tbl ncols nrows))
  (if (null hrow)
    nil
    (progn
      (setq map (_ofeed-build-colmap tbl hrow ncols) kk 0 miss nil)
      (while (< kk (length (_ofeed-columns)))
        (if (null (_ofeed-col map kk)) (setq miss T))
        (setq kk (1+ kk)))
      miss)))

;; the mutating recompute body -- runs inside the crash-safe wrapper below (which guarantees a
;; _ofeed-doregen after, so a mid-pass error can never leave the table regen-suppressed -> the hang).
(defun _ofeed-recompute-core (tbl ncols nrows hrow map / bluecol redcol r feeder plan total commonv
                              datapos synth allflags allwrites pending errs nok nskip ans p f w m)
       (progn
         (setq r (1+ hrow) nok 0 nskip 0 allflags nil allwrites nil pending nil errs nil
               total   (_ofeed-branch-total tbl nrows hrow map)
               commonv (_ofeed-common-volts tbl nrows hrow map)
               bluecol (if *ofeed-tint* (_ofeed-make-color 173 216 230) nil)
               redcol  (if *ofeed-tint* (_ofeed-make-color 255 180 180) nil))
         (if (and *ofeed-tint* (null bluecol))
           (prompt "\n(Cell coloring unavailable on this build -- using the command-line preview below.)"))
         (prompt (strcat "\nO-FEED ampacity adjustments (NEC 310.15): ambient "
                         (rtos *ofeed-ambient-temp* 2 0) "C, temp-adj " (rtos (_ofeed-temp-factor) 2 2)
                         " (term " (itoa *term-temp*) "C), neutral-CCC "
                         (if *ofeed-neutral-is-ccc* "on" "off") ":"))
         ;; ---- PHASE 1: READS ONLY -- plan every row, mutate nothing. The table stays clean through
         ;; this whole loop, so no vla-GetText ever forces a regen. ----------------------------------
         (while (< r nrows)
           (setq feeder  (_ofeed-norm (_ofeed-cell tbl r (_ofeed-col map 0)))
                 datapos (- r hrow))
           (cond
             ((/= feeder "")
              (setq plan (_ofeed-plan-row tbl r map feeder total commonv))
              (if (car plan) (setq nok (1+ nok)) (setq nskip (1+ nskip)))
              (setq allwrites (append allwrites (caddr plan))
                    allflags  (append allflags (cadr plan)
                                      (list (list r (_ofeed-col map 0) nil))) ; clear any stale FEEDER red
                    errs      (append errs (cadddr plan))))
             ;; blank FEEDER but the row carries a load -> AUTO-LABEL AC-<data row #> and size it (was:
             ;; dead-end on a red cell). Mirrors O-FEEDSET labeling; idempotent once the label is written.
             ((> (atof (_ofeed-cell tbl r (_ofeed-col map 8))) 0.0)
              (setq synth (strcat "AC-" (itoa datapos))
                    plan  (_ofeed-plan-row tbl r map synth total commonv))
              (if (car plan) (setq nok (1+ nok)) (setq nskip (1+ nskip)))
              (setq allwrites (append allwrites
                                      (list (list r (_ofeed-col map 0) synth ""))
                                      (caddr plan))
                    allflags  (append allflags
                                      (list (list r (_ofeed-col map 0) nil))
                                      (cadr plan))
                    errs      (append errs (cadddr plan)))))
           (setq r (1+ r)))
         ;; ---- PHASE 2: WRITES ONLY -- suppress regen, apply all flags then all writes (no GetText
         ;; interleaved), regen ONCE. ---------------------------------------------------------------
         (_ofeed-noregen tbl)
         (_ofeed-format-inputs tbl nrows hrow map)            ; white + middle-center on INPUT cells only
         (foreach f allflags (_ofeed-flag tbl (car f) (cadr f) (caddr f) redcol))
         (foreach w allwrites
           (_ofeed-set tbl (car w) (cadr w) (caddr w))
           (if (and *ofeed-tint* bluecol) (_ofeed-tint-cell tbl (car w) (cadr w) bluecol))
           (setq pending (cons (list (car w) (cadr w) (cadddr w)) pending)))
         (setq pending (reverse pending))
         (_ofeed-doregen tbl)                                  ; show blue/red now (single regen)
         (if errs
           (progn (prompt "\nNeeds attention:")
             (foreach m errs (prompt (strcat "\n  - " m)))))
         (if pending
           (progn
             (initget "Yes No")
             (setq ans (vl-catch-all-apply 'getkword
                         (list (strcat "\n" (itoa (length pending))
                                       " cell(s) changed (shown blue). Keep changes? [Yes/No] <Yes>: "))))
             (_ofeed-noregen tbl)
             (if (or (vl-catch-all-error-p ans) (= ans "No"))
               (progn
                 (foreach p pending
                   (_ofeed-set tbl (car p) (cadr p) (caddr p))
                   (if *ofeed-tint* (_ofeed-clear-tint tbl (car p) (cadr p))))
                 (prompt "\nReverted -- no changes kept."))
               (progn
                 (foreach p pending
                   (if *ofeed-tint* (_ofeed-clear-tint tbl (car p) (cadr p))))
                 (prompt "\nChanges kept.")))
             (_ofeed-doregen tbl)))
         (if bluecol (vl-catch-all-apply 'vlax-release-object (list bluecol)))
         (if redcol  (vl-catch-all-apply 'vlax-release-object (list redcol)))
         (prompt (strcat "\nSummary: sized " (itoa nok) " feeder(s)"
                         (if (> nskip 0) (strcat ", " (itoa nskip) " not sized (red)") "")
                         (if errs (strcat ", " (itoa (length errs)) " issue(s) flagged -- fix red cells + re-run") "")
                         "."))))

;; validate the table, then run the mutating core inside a catch so the table's regen is ALWAYS
;; restored -- a crash mid-pass can no longer leave it suppressed (the cause of the recurring hang),
;; and an unexpected nil is reported cleanly instead of dumping "bad argument type nil".
(defun _ofeed-recompute (tbl / ncols nrows hrow map err)
  (setq ncols (vla-get-Columns tbl)
        nrows (vla-get-Rows tbl)
        hrow  (_ofeed-find-header-row tbl ncols nrows))
  (cond
    ((null hrow)
     (prompt "\nO-FEED: no FEEDER header row found -- is this an AC feeder schedule table?"))
    (T
     (setq map (_ofeed-build-colmap tbl hrow ncols))
     (if (not (and (_ofeed-col map 0) (_ofeed-col map 8) (_ofeed-col map 11)))
       (prompt "\nO-FEED: required columns (FEEDER / CIRCUIT LOAD (A) / VOLTAGE (V)) not found in the header.")
       (progn
         (_ofeed-place-on-layer tbl)                                ; move table onto *ocfg-layer-feeder-table* (G-TEXT)
         (_ofeed-doregen tbl)                                       ; pre-clean (un-suppress any stale state)
         (setq err (vl-catch-all-apply '_ofeed-recompute-core (list tbl ncols nrows hrow map)))
         (_ofeed-doregen tbl)                                       ; ALWAYS restore regen, even on error
         (if (vl-catch-all-error-p err)
           (prompt (strcat "\nO-FEED: stopped on an unexpected value ("
                           (vl-catch-all-error-message err)
                           "). Table restored -- no partial suppression; please re-run."))))))))

;; ============================================================
;; SETUP / CREATE  (O-FEEDSET)  -- build a fresh table or repair a partial one
;; NOTE: native-table creation + column insertion cannot be tested headless (COM is GUI-only),
;; so these paths are load-verified only; they need a live AutoCAD pass.
;; ============================================================

;; color the empty required input cells (LENGTH 7, LOAD 8, VOLTAGE 11) red on one data row
(defun _ofeedset-red-row (tbl r map red / ci tcol)
  (foreach ci '(7 8 11)
    (if (setq tcol (_ofeed-col map ci))
      (if (= (_ofeed-norm (_ofeed-cell tbl r tcol)) "")
        (if (and *ofeed-tint* red) (_ofeed-tint-cell tbl r tcol red))))))

;; actual column index to insert canonical column kk at = just after the nearest PRESENT canonical
;; predecessor (largest j < kk that is mapped), or 0 if none of 0..kk-1 are present. colmap = canon->col.
(defun _ofeedset-insert-pos (colmap kk / j c r)
  (setq j (1- kk) r 0)
  (while (and (>= j 0) (= r 0))
    (if (setq c (_ofeed-col colmap j)) (setq r (1+ c)))
    (setq j (1- j)))
  r)

;; after inserting a column at actual index pos, every mapped column at >= pos shifts up by one.
(defun _ofeedset-shift-colmap (colmap pos / out pr)
  (setq out nil)
  (foreach pr colmap
    (setq out (cons (cons (car pr) (if (>= (cdr pr) pos) (1+ (cdr pr)) (cdr pr))) out)))
  (reverse out))

;; ensure the canonical columns exist -- ORDER-INDEPENDENT and CASCADE-PROOF. The old version walked
;; the header row as a positional subsequence; if the live columns were in a different order (or one
;; header didn't match) the walk desynced and inserted EVERY remaining canonical column -- it duplicated
;; a complete table with ~11 empty columns. This builds the canon-index->column map (the SAME recognizer
;; the recompute uses, so column ORDER does not matter) and inserts ONLY canonical indices that have no
;; column, each right after its nearest present predecessor.
;; SAFETY: if more than 2 columns look missing, or a KEY column (FEEDER 0 / CIRCUIT LOAD 8 / VOLTAGE 11)
;; is unrecognized, this is not a schedule we can safely restructure -> return nil (modify NOTHING) and
;; let the caller warn. HANG-SAFE: builds the map once, then inserts only (no GetText between writes).
(defun _ofeedset-ensure-columns (tbl / hrow ncols colmap missing kk pos cw)
  (setq ncols (vla-get-Columns tbl)
        hrow  (_ofeed-find-header-row tbl ncols (vla-get-Rows tbl)))
  (if (null hrow)
    nil
    (progn
      (setq colmap (_ofeed-build-colmap tbl hrow ncols) missing nil kk 0)
      (while (< kk (length (_ofeed-columns)))
        (if (null (_ofeed-col colmap kk)) (setq missing (cons kk missing)))
        (setq kk (1+ kk)))
      (setq missing (reverse missing))
      (cond
        ((null missing) hrow)                              ; already complete -> nothing to do
        ((or (> (length missing) 2)                        ; cascade guard: too much missing,
             (member 0 missing) (member 8 missing) (member 11 missing)) ; or a key input col unrecognized
         nil)                                              ; -> refuse to restructure
        (T
         (foreach kk missing
           (setq pos (_ofeedset-insert-pos colmap kk)
                 cw  (* (cond ((nth kk (_ofeedset-colw-list))) (T 1.0)) *ofeed-table-wscale*))
           (vl-catch-all-apply 'vla-InsertColumns (list tbl pos cw 1))
           (vl-catch-all-apply 'vla-SetText (list tbl hrow pos (car (nth kk (_ofeed-columns)))))
           (setq colmap (cons (cons kk pos) (_ofeedset-shift-colmap colmap pos))))
         hrow)))))

;; REPAIR an existing table: add missing columns/headers, label AC-1..n, red the blank inputs
(defun _ofeedset-repair (tbl / ncols nrows hrow map red i dnum feeder)
  (_ofeed-noregen tbl)
  (_ofeedset-ensure-columns tbl)
  (setq ncols (vla-get-Columns tbl)
        nrows (vla-get-Rows tbl)
        hrow  (_ofeed-find-header-row tbl ncols nrows))
  (if (null hrow)
    (progn (_ofeed-doregen tbl)
      (prompt "\nO-FEEDSET: no FEEDER header found -- can't repair. Press Enter at the prompt to build a fresh table instead."))
    (progn
      (setq map (_ofeed-build-colmap tbl hrow ncols)
            red (if *ofeed-tint* (_ofeed-make-color 255 180 180) nil)
            i   (1+ hrow) dnum 0)
      (while (< i nrows)
        (setq dnum   (1+ dnum)
              feeder (_ofeed-norm (_ofeed-cell tbl i (_ofeed-col map 0))))
        (if (= feeder "") (_ofeed-set tbl i (_ofeed-col map 0) (strcat "AC-" (itoa dnum))))
        (_ofeedset-red-row tbl i map red)
        (setq i (1+ i)))
      (if red (vl-catch-all-apply 'vlax-release-object (list red)))
      (_ofeed-doregen tbl)
      (prompt "\nO-FEEDSET: structure checked -- missing columns/headers added, feeders labeled AC-1..n, blank required cells flagged red. Fill them, then run O-FEED."))))

;; 17 column widths in canonical order; 16 are EXACT from the production E-2.0 table (DXF group 142).
;; The ADJUSTED AMPACITY (A) width (1.5", after BASED AMPACITY at idx 12) is new in 2.27.
(defun _ofeedset-colw-list ()
  '(0.988 0.932 2.541 2.464 1.909 2.459 0.954 0.954 0.977 0.980 1.779 0.920 1.004 1.5 0.899 0.929 2.559))

;; CREATE a fresh AC feeder schedule from a # of inverters (feeders = inverters + 2: AC-1/AC-2 + one each)
(defun _ofeedset-create ( / n nfeed pt doc space tbl nrows base i k w wcol red nr nc rr cc)
  (setq n (getint "\nNumber of inverters: "))
  (if (or (null n) (< n 1)) (setq n 1))
  (setq nfeed (+ n 2))
  (setq pt (getpoint "\nTop-left insertion point for the feeder schedule: "))
  (if (null pt)
    (prompt "\nO-FEEDSET: cancelled.")
    (progn
      (setq pt    (trans pt 1 0)
            doc   (vla-get-ActiveDocument (vlax-get-acad-object))
            space (vla-get-Block (vla-get-ActiveLayout doc))
            nrows (+ 2 nfeed)                                  ; title + header + data rows
            tbl   (vl-catch-all-apply 'vla-AddTable
                    (list space (vlax-3d-point (car pt) (cadr pt) (caddr pt))
                          nrows (length (_ofeed-columns)) *ofeed-table-rowh* (* *ofeed-table-wscale* 0.7))))
      (if (vl-catch-all-error-p tbl)
        (prompt (strcat "\nO-FEEDSET: could not create the table -- " (vl-catch-all-error-message tbl)))
        (progn
          (_ofeed-place-on-layer tbl)                          ; place new table on *ocfg-layer-feeder-table* (G-TEXT)
          (_ofeed-noregen tbl)
          ;; set text height per row type (title=1, header=2, data=4) so the HEADER is included
          (foreach rt '(1 2 4) (vl-catch-all-apply 'vla-SetTextHeight (list tbl rt *ofeed-table-th*)))
          ;; E-2.0 has NO title row -> drop the style's title row, then detect the header row index
          ;; (base): if the delete took, header is row 0; if not, it's still row 1.
          (vl-catch-all-apply 'vla-DeleteRows (list tbl 0 1))
          (setq base (if (<= (vla-get-Rows tbl) (1+ nfeed)) 0 1))
          (setq i 0)
          (foreach pair (_ofeed-columns) (_ofeed-set tbl base i (car pair)) (setq i (1+ i)))
          (setq k 0)
          (while (< k nfeed) (_ofeed-set tbl (+ base 1 k) 0 (strcat "AC-" (itoa (1+ k)))) (setq k (1+ k)))
          ;; row heights: header row taller, data rows shorter (from the production table)
          (vl-catch-all-apply 'vla-SetRowHeight (list tbl base *ofeed-table-hdrh*))
          ;; per-column widths EXACT from production, uniformly scaled by *ofeed-table-wscale*
          (setq i 0)
          (foreach w (_ofeedset-colw-list)
            (vl-catch-all-apply 'vla-SetColumnWidth (list tbl i (* w *ofeed-table-wscale*)))
            (setq i (1+ i)))
          ;; white grid + white text (ACI 7 -> plot black) and MIDDLE-CENTER every cell
          (setq wcol (_ofeed-make-aci 7) nr (vla-get-Rows tbl) nc (vla-get-Columns tbl) rr 0)
          (if wcol (vl-catch-all-apply 'vla-SetGridColor (list tbl 7 63 wcol)))
          (while (< rr nr)
            (setq cc 0)
            (while (< cc nc)
              (vl-catch-all-apply 'vla-SetCellAlignment (list tbl rr cc 5))   ; 5 = acMiddleCenter
              (if wcol (vl-catch-all-apply 'vla-SetCellContentColor (list tbl rr cc wcol)))
              (setq cc (1+ cc)))
            (setq rr (1+ rr)))
          (if wcol (vl-catch-all-apply 'vlax-release-object (list wcol)))
          (setq red (if *ofeed-tint* (_ofeed-make-color 255 180 180) nil) k 0)
          (while (< k nfeed)
            (foreach ci '(7 8 11) (if (and *ofeed-tint* red) (_ofeed-tint-cell tbl (+ base 1 k) ci red)))
            (setq k (1+ k)))
          (if red (vl-catch-all-apply 'vlax-release-object (list red)))
          (_ofeed-doregen tbl)
          (prompt (strcat "\nO-FEEDSET: created an AC feeder schedule, " (itoa nfeed)
                          " feeders (AC-1..AC-" (itoa nfeed) "). Fill the red LENGTH / CIRCUIT LOAD / VOLTAGE cells, then run O-FEED.")))))))

;; ============================================================
;; AMBIENT TEMPERATURE  (drawing-note finder + prompt -> *ofeed-ambient-temp*, NEC 310.15(B) input)
;; The engine reads *ofeed-ambient-temp* only; gathering happens here so c:O-FEEDTEST stays headless.
;; ============================================================

;; first numeric run (optional leading - / decimal) at or after 1-based index i0 in s.
;; Returns (value . end-index-just-past-number) or nil.
(defun _ofeed-num-at (s i0 / n i c started numstr)
  (setq n (strlen s) i i0 numstr "" started nil)
  (while (and (<= i n) (not started))
    (setq c (substr s i 1))
    (if (or (and (>= (ascii c) 48) (<= (ascii c) 57))
            (and (= c "-") (< i n) (>= (ascii (substr s (1+ i) 1)) 48) (<= (ascii (substr s (1+ i) 1)) 57)))
      (setq started T)
      (setq i (1+ i))))
  (if (not started)
    nil
    (progn
      (while (and (<= i n)
                  (or (and (>= (ascii (substr s i 1)) 48) (<= (ascii (substr s i 1)) 57))
                      (= (substr s i 1) ".") (= (substr s i 1) "-")))
        (setq numstr (strcat numstr (substr s i 1)) i (1+ i)))
      (cons (atof numstr) i))))

;; unit letter (C/F) within a short window just past the number; nil if none. The magnitude heuristic
;; in _ofeed-to-celsius is the real safety net when a degree glyph defeats this.
(defun _ofeed-unit-after (s i0 / tail pf pc)
  (setq tail (substr s i0 8) pf (vl-string-search "F" tail) pc (vl-string-search "C" tail))
  (cond ((and pf (or (null pc) (< pf pc))) "F") (pc "C") (T nil)))

;; value+unit -> Celsius. Explicit C/F wins; a unit-less number above *ofeed-amb-c-max* is read as
;; Fahrenheit (implausible as Celsius) and converted, else taken as Celsius.
(defun _ofeed-to-celsius (val unit / u)
  (setq u (if unit (strcase unit) nil))
  (cond ((= u "F") (/ (* (- val 32.0) 5.0) 9.0))
        ((= u "C") val)
        ((> val *ofeed-amb-c-max*) (/ (* (- val 32.0) 5.0) 9.0))
        (T val)))

;; full visible text of a TEXT/MTEXT entity. MTEXT longer than 250 chars is split into DXF group-3
;; overflow chunks (in order) followed by the final group 1 -- reading only group 1 sees just the TAIL
;; of a multi-line note (e.g. only the "Record low ambient" line), which is how the low temp got grabbed.
(defun _ofeed-entity-text (ed / s pr)
  (setq s "")
  (foreach pr ed (if (= (car pr) 3) (setq s (strcat s (cdr pr)))))
  (strcat s (cond ((cdr (assoc 1 ed))) (T ""))))

;; parse an "AMBIENT ..." note for the HIGH design ambient (Celsius), nil if none. Solar notes label BOTH
;; a record LOW and a record HIGH; ampacity derating (310.15(B)) needs the HIGH. Strategy: take the value
;; right after a "HIGH"/"MAX" label; if there is no usable label, fall back to the MAX of every plausible
;; ambient number ([-60,60]C, which drops elevations / dates / sheet numbers) after the AMBIENT keyword.
(defun _ofeed-parse-temp-note (raw / s hp num c hi vals v i)
  (setq s (_ofeed-norm raw) hi nil vals nil)
  (if (vl-string-search "AMBIENT" s)
    (progn
      (setq hp (cond ((vl-string-search "HIGH" s)) ((vl-string-search "MAX" s)) (T nil)))
      (if (and hp (setq num (_ofeed-num-at s (1+ hp))))
        (progn (setq c (_ofeed-to-celsius (car num) (_ofeed-unit-after s (cdr num))))
               (if (and (>= c -60.0) (<= c 60.0)) (setq hi c))))
      (if (null hi)
        (progn
          (setq i (+ (vl-string-search "AMBIENT" s) 8))
          (while (setq num (_ofeed-num-at s i))
            (setq c (_ofeed-to-celsius (car num) (_ofeed-unit-after s (cdr num))))
            (if (and (>= c -60.0) (<= c 60.0)) (setq vals (cons c vals)))
            (setq i (if (> (cdr num) i) (cdr num) (1+ i))))
          (foreach v vals (if (or (null hi) (> v hi)) (setq hi v)))))))
  hi)

;; Set *ofeed-ambient-temp* from a drawing "AMBIENT ..." note (first match wins) or, failing that, a
;; prompt. Enter at the prompt keeps the current value. GUI only (ssget / getstring).
(defun _ofeed-gather-ambient ( / ss i raw c got resp val)
  (if *ofeed-ambient-asked*
    ;; already established this session -> reuse silently (no per-run prompt = no "O-FEED is hung")
    (prompt (strcat "\nO-FEED: ambient " (rtos *ofeed-ambient-temp* 2 1) "C (O-FEEDAMB to change)."))
    (progn
      ;; PRE-FILTER on the C side: only TEXT/MTEXT containing "ambient" (ssget DXF-1 wildcard, case
      ;; variants OR'd). NEVER ssget "X" all text + scan in LISP -- a real plan set has thousands of text
      ;; entities. Take the HIGHEST high across all matching notes.
      (setq got nil)
      (if (setq ss (ssget "X" '((0 . "TEXT,MTEXT") (1 . "*AMBIENT*,*Ambient*,*ambient*"))))
        (progn
          (setq i 0)
          (while (< i (sslength ss))
            (setq raw (_ofeed-entity-text (entget (ssname ss i))))   ; full MTEXT (group 3 + 1), not just tail
            (if raw (progn (setq c (_ofeed-parse-temp-note raw))
                           (if (and c (or (null got) (> c got))) (setq got c))))
            (setq i (1+ i)))))
      ;; CONFIRM the high value (or prompt if no note). Enter accepts; type a value to override.
      (if got
        (setq resp (getstring T (strcat "\nAmbient HIGH from drawing note: " (rtos got 2 1)
                                        "C. Enter to accept, or type a different value: ")))
        (setq resp (getstring T (strcat "\nNo ambient note found. Highest ambient temp for the area (e.g. 45C"
                                        " / 113F) <" (rtos *ofeed-ambient-temp* 2 0) "C>: "))))
      (cond
        ((and resp (> (strlen resp) 0) (setq val (_ofeed-num-at (strcase resp) 1)))
         (setq *ofeed-ambient-temp* (_ofeed-to-celsius (car val) (_ofeed-unit-after (strcase resp) (cdr val)))))
        (got (setq *ofeed-ambient-temp* got)))       ; empty input + note found -> accept the note's high
      (setq *ofeed-ambient-asked* T)
      (prompt (strcat "\nO-FEED: ambient = " (rtos *ofeed-ambient-temp* 2 1) "C (NEC 310.15(B) correction)."))))
  *ofeed-ambient-temp*)

;; force a re-gather / re-prompt for the design ambient (clears the once-per-session latch).
(defun c:O-FEEDAMB ( )
  (setq *ofeed-ambient-asked* nil)
  (_ofeed-gather-ambient)
  (princ))
(defun c:OFEEDAMB () (c:O-FEEDAMB))

;; ============================================================
;; COMMANDS
;; ============================================================

(defun c:O-FEED ( / obj)
  (vl-load-com)
  (_ofeed-load-refs)                  ; ALWAYS reload -- a stale OLD-schema *ofeed-cond-table* from an
                                      ; earlier version (col 1 = ampacity, not "CU"/"AL") made the new
                                      ; material lookup return nil -> (last nil) "consp nil". CSVs are tiny.
  (if (null *ofeed-cond-table*)
    (prompt "\nO-FEED: could not load config\\conductors.csv -- check the config folder.")
    (progn
      (_ofeed-gather-ambient)           ; NEC 310.15(B): ambient from a drawing note or prompt
      (setq obj (_ofeed-pick-table))
      (if obj
        (progn
          ;; AUTO-SETUP: a partial table (missing canonical columns) is repaired in place before the
          ;; recompute, so the user never has to run O-FEEDSET first. ensure-columns is idempotent.
          (if (_ofeed-missing-columns-p obj)
            (progn
              (_ofeed-noregen obj)
              (if (_ofeedset-ensure-columns obj)
                (prompt "\nO-FEED: added the missing canonical column(s) (auto-setup).")
                (prompt (strcat "\nO-FEED: columns are non-standard or out of order -- NOT auto-adding"
                                " (avoids duplicating the table). Recompute uses the columns it"
                                " recognizes; rename headers to the canonical set or rebuild with"
                                " O-FEEDSET to get the ADJUSTED AMPACITY column.")))
              (_ofeed-doregen obj)))
          (_ofeed-recompute obj))
        (prompt "\nO-FEED: no feeder table selected."))))
  (princ))

;; SETUP: place a NEW feeder schedule -- prompts # inverters + insertion point, straight away.
;; Structure REPAIR of an existing table is now automatic inside O-FEED (see its AUTO-SETUP above),
;; so O-FEEDSET is dedicated to creating a fresh table (no select-a-table prompt).
(defun c:O-FEEDSET ( )
  (vl-load-com)
  (_ofeed-load-refs)                  ; always reload (see c:O-FEED)
  (_ofeed-gather-ambient)             ; so the created schedule's first O-FEED already has an ambient
  (_ofeedset-create)
  (princ))
(defun c:OFEEDSET () (c:O-FEEDSET))

(defun c:O-FEEDTEST ( / recs)
  (_ofeed-load-refs)
  (setq recs (list
    (_ofeed-size-feeder "AC-1" 432.9 3 480 20  T   *ofeed-max-cond*)
    (_ofeed-size-feeder "AC-2" 432.9 3 480 10  T   *ofeed-max-cond*)
    (_ofeed-size-feeder "AC-3" 144.3 3 480 10  nil *ofeed-max-cond*)
    (_ofeed-size-feeder "AC-4" 48.1  3 480 150 nil *ofeed-max-cond*)))
  (prompt (strcat "\n--- O-FEED self-test (term-temp " (itoa *term-temp*)
                  ", ambient " (rtos *ofeed-ambient-temp* 2 0) "C"
                  ", neutral-ccc " (if *ofeed-neutral-is-ccc* "Y" "N")
                  ", vd-coeff " (rtos *vd-coeff* 2 2)
                  ", parallel-mat " *ofeed-parallel-material*
                  ", max-cond " (if *ofeed-max-cond* *ofeed-max-cond* "none") ") ---"))
  (foreach r recs
    (prompt (strcat "\n" (cdr (assoc "ID" r))
      "  WIRE=" (cdr (assoc "WIRE" r))
      " | N=" (cdr (assoc "NEUTRAL" r))
      " | G=" (cdr (assoc "GROUND" r))
      " | " (cdr (assoc "CONDUIT" r)) " fill " (cdr (assoc "FILL" r))
      " | BRK=" (itoa (cdr (assoc "OCP" r)))
      " | AMP=" (itoa (cdr (assoc "BASEDAMP" r)))
      " | ADJ=" (itoa (cdr (assoc "ADJAMP" r)))
      " | VD=" (rtos (cdr (assoc "VDV" r)) 2 2) "V (" (rtos (cdr (assoc "VDP" r)) 2 2) "%)")))
  (prompt "\n--- end ---")
  (princ))

(defun c:OFEED () (c:O-FEED))

(prompt "\nOFEED v2.27 loaded. NEC 310.15 ampacity adjustments + ADJUSTED AMPACITY column (ambient from a drawing note or prompt).  O-FEED = recompute, O-FEEDSET = create new table.")
(princ)
