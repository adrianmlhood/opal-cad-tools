;; ofeed-2.15.lsp -- Ocotillo AC Feeder Schedule Recompute + Setup
;; Commands: O-FEED (alias OFEED)   O-FEEDSET (alias OFEEDSET)   O-FEEDTEST (headless engine self-test)
;;
;; RECOMPUTE an existing native AutoCAD table (ACAD_TABLE): the user keeps the schedule and types
;; the assumed-correct inputs; O-FEED sizes the rest. See header of 2.0 for the full design.
;;
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
;;                *ofeed-table-th* *ofeed-table-rowh* *ofeed-table-hdrh* *ofeed-table-wscale*
;; v2.15
;; ============================================================

(vl-load-com)

;; --- persistent globals -------------------------------------
(if (not (boundp '*term-temp*))        (setq *term-temp* 90))
(if (not (boundp '*vd-coeff*))         (setq *vd-coeff* 2.0))
(if (not (boundp '*ofeed-tint*))       (setq *ofeed-tint* T))
(if (not (boundp '*ofeed-neutral-max*)) (setq *ofeed-neutral-max* 2)) ; feeders numbered above this -> no neutral ("-")
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
  (setq *ofeed-cond-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\conductors.csv"))
    (if (>= (length r) 5)
      (setq *ofeed-cond-table*
        (cons (list (nth 0 r) (atoi (nth 1 r)) (atoi (nth 2 r)) (atof (nth 3 r)) (atof (nth 4 r)))
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
  (length *ofeed-cond-table*))

;; ============================================================
;; ENGINE  (unchanged from 1.0)
;; ============================================================

(defun _ofeed-amp-col (row) (if (= *term-temp* 90) (nth 2 row) (nth 1 row)))

(defun _ofeed-cond-row (size / r)
  (foreach row *ofeed-cond-table* (if (= size (nth 0 row)) (setq r row))) r)

(defun _ofeed-cond-R (size / row) (setq row (_ofeed-cond-row size)) (if row (nth 3 row) 0.0))
(defun _ofeed-cond-area (size / row) (setq row (_ofeed-cond-row size)) (if row (nth 4 row) 0.0))

(defun _ofeed-ocp-pick (i / r)
  (foreach s *ofeed-ocp-sizes* (if (and (not r) (>= s i)) (setq r s))) r)

(defun _ofeed-egc-pick (ocp / r)
  (foreach e *ofeed-egc-table* (if (and (not r) (<= ocp (car e))) (setq r (cadr e)))) r)

(defun _ofeed-cond-pick (i / r)
  (foreach row *ofeed-cond-table*
    (if (and (not r) (>= (_ofeed-amp-col row) i)) (setq r (nth 0 row)))) r)

(defun _ofeed-vd-volts (L i R) (/ (* *vd-coeff* L i R) 1000.0))

(defun _ofeed-phase-count (phase) (if (= phase 1) 2 3))

(defun _ofeed-parallel-sets (i125 / maxamp)
  (setq maxamp (_ofeed-amp-col (last *ofeed-cond-table*)))
  (if (<= i125 maxamp) 1 (fix (+ 0.9999 (/ i125 (float maxamp))))))

(defun _ofeed-conduit-pick (area / r last-c)
  (foreach c *ofeed-emt-table*
    (if (and (not r) (< (/ area (cadr c)) 0.40))
      (setq r (list (car c) (* 100.0 (/ area (cadr c)))))))
  (if r r
    (progn (setq last-c (last *ofeed-emt-table*))
      (list (car last-c) (* 100.0 (/ area (cadr last-c)))))))

(defun _ofeed-size-feeder (id load phase volts length neutral /
                           i125 sets per ocp cond egc R basedamp vdv vdp np area-tot cp wire neut gnd)
  (setq i125     (* load 1.25)
        sets     (_ofeed-parallel-sets i125)
        per      (/ i125 (float sets))
        ocp      (_ofeed-ocp-pick i125)
        cond     (_ofeed-cond-pick per)
        egc      (_ofeed-egc-pick ocp)
        R        (_ofeed-cond-R cond)
        basedamp (fix (* sets (_ofeed-amp-col (_ofeed-cond-row cond))))
        vdv      (_ofeed-vd-volts length (/ load (float sets)) R)
        vdp      (* 100.0 (/ vdv (float volts)))
        np       (_ofeed-phase-count phase)
        area-tot (* sets (+ (* np (_ofeed-cond-area cond))
                            (if neutral (_ofeed-cond-area cond) 0.0)
                            (_ofeed-cond-area egc)))
        cp       (_ofeed-conduit-pick area-tot)
        wire     (strcat (if (> sets 1) (strcat (itoa sets) " SETS OF ") "")
                         "(" (itoa np) ") " cond " CU THHN/THWN-2")
        neut     (if neutral (strcat "(1) " cond " CU THHN/THWN-2") "-")
        gnd      (strcat "(1) " egc " CU GND"))
  (list (cons "ID" id) (cons "SETS" sets) (cons "WIRE" wire)
        (cons "NEUTRAL" neut) (cons "GROUND" gnd)
        (cons "CONDUIT" (strcat (car cp) " EMT"))
        (cons "FILL" (strcat (rtos (cadr cp) 2 2) "%"))
        (cons "LENGTH" length) (cons "LOAD" load) (cons "LOAD125" i125)
        (cons "OCP" ocp) (cons "VOLTS" volts) (cons "BASEDAMP" basedamp)
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
    (cons "VOLTAGE DROP (V)"     "calc")
    (cons "VOLTAGE DROP (%)"     "calc")
    (cons "GENERAL FORMULA"      "static")))

(defun _ofeed-computed-idx () '(1 2 3 4 5 6 10 12))
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
(defun _ofeed-doregen (tbl)
  (vl-catch-all-apply 'vlax-put-property (list tbl 'RegenerateTableSuggested :vlax-true))
  (vl-catch-all-apply 'vla-Update (list tbl)))

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

;; ============================================================
;; HEADER / COLUMN MAP
;; ============================================================

(defun _ofeed-canon-index (normhdr / i found)
  (setq i 0 found nil)
  (foreach pair (_ofeed-columns)
    (if (and (not found) (= (_ofeed-norm (car pair)) normhdr)) (setq found i))
    (setq i (1+ i)))
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
      (setq fvolts  (cond (voltok (atoi voltstr)) ((> commonv 0) commonv) (T 480)) ; fload+fnum already set (agg-aware)
            flen    (if lenok (atof lenstr) 0.0)
            neutral (cond ((null fnum)                              ; non-AC id -> read the NEUTRAL cell
                           (_ofeed-neutral-p (if (_ofeed-col map 3) (_ofeed-cell tbl r (_ofeed-col map 3)) "")))
                          ((> fnum *ofeed-neutral-max*) nil)         ; AC-3+ -> no neutral ("-")
                          (T T))                                     ; AC-1/AC-2 -> neutral sized to the phase conductor
            phase   (_ofeed-phase-from-wire (if (_ofeed-col map 2) (_ofeed-cell tbl r (_ofeed-col map 2)) ""))
            rec     (vl-catch-all-apply '_ofeed-size-feeder (list feeder fload phase fvolts flen neutral)))
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
          ;; VOLTAGE DROP override: write the COMPUTED V (idx 13) and % (idx 14) even over a live formula
          ;; -- the user wants the calculated value to win. Needs length + an effective voltage.
          ;; (2.08 rolled back a VD force-overwrite that broke a live run; this is revertable via the
          ;; blue-preview [Yes/No] and each write is catch-wrapped, so a bad cell is skipped, not fatal.)
          (if (and lenok volteff)
            (foreach k (list 13 14)
              (if (setq tcol (_ofeed-col map k))
                (progn
                  (setq oldval (_ofeed-cell tbl r tcol) newval (nth k cells))
                  (if (/= (_ofeed-norm oldval) (_ofeed-norm newval))
                    (setq writes (cons (list r tcol newval oldval) writes)))))))
          ;; self-heal: refill a DELETED 125% (idx 9) / GENERAL FORMULA (idx 15) cell (blank + not a live
          ;; formula). VD is handled above (forced); these stay blank-only so live calcs are preserved.
          (foreach kk (list (list 9 T) (list 15 T))
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
          (prompt (strcat "\n  " (nth 0 cells)
            "  SETS " (nth 1 cells) " | BRK " (nth 10 cells)
            " | " (nth 2 cells) " | N " (nth 3 cells) " | G " (nth 4 cells)
            " | " (nth 5 cells) " " (nth 6 cells) " | AMP " (nth 12 cells) note))
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

(defun _ofeed-recompute (tbl / ncols nrows hrow map bluecol redcol r feeder plan total commonv
                              datapos synth allflags allwrites pending errs nok nskip ans p)
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
         (setq r (1+ hrow) nok 0 nskip 0 allflags nil allwrites nil pending nil errs nil
               total   (_ofeed-branch-total tbl nrows hrow map)
               commonv (_ofeed-common-volts tbl nrows hrow map)
               bluecol (if *ofeed-tint* (_ofeed-make-color 173 216 230) nil)
               redcol  (if *ofeed-tint* (_ofeed-make-color 255 180 180) nil))
         (if (and *ofeed-tint* (null bluecol))
           (prompt "\n(Cell coloring unavailable on this build -- using the command-line preview below.)"))
         (prompt "\nO-FEED recompute (125% / GENERAL FORMULA left as table calcs; VOLTAGE DROP forced to computed):")
         (if (> total 0.0)
           (prompt (strcat "\n  AC-1/AC-2 load = sum of AC-3..n = " (rtos total 2 1) " A (corrected if the cell differs)")))
         (if (> commonv 0)
           (prompt (strcat "\n  System voltage = " (itoa commonv) " V (blank VOLTAGE cells assume this)")))
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
                         ".")))))))

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

;; ensure all 16 canonical columns exist in order, inserting + heading any that are missing.
;; assumes present columns appear in canonical order (a subsequence) -- typical for these schedules.
(defun _ofeedset-ensure-columns (tbl / hrow ncols cancols tc canhdr curhdr)
  (setq ncols (vla-get-Columns tbl)
        hrow  (_ofeed-find-header-row tbl ncols (vla-get-Rows tbl)))
  (if hrow
    (progn
      (setq cancols (_ofeed-columns) tc 0)
      (foreach pair cancols
        (setq canhdr (_ofeed-norm (car pair))
              ncols  (vla-get-Columns tbl)
              curhdr (if (< tc ncols) (_ofeed-norm (_ofeed-cell tbl hrow tc)) nil))
        (if (and curhdr (= curhdr canhdr))
          (setq tc (1+ tc))                                  ; present & aligned -> advance
          (progn                                             ; missing -> insert + head it here
            (vl-catch-all-apply 'vla-InsertColumns (list tbl (min tc ncols) 24.0 1))
            (vl-catch-all-apply 'vla-SetText (list tbl hrow tc (car pair)))
            (setq tc (1+ tc)))))))
  hrow)

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

;; 16 column widths in canonical order, EXACT from the production E-2.0 table (DXF group 142)
(defun _ofeedset-colw-list ()
  '(0.988 0.932 2.541 2.464 1.909 2.459 0.954 0.954 0.977 0.980 1.779 0.920 1.004 0.899 0.929 2.559))

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
                          nrows 16 *ofeed-table-rowh* (* *ofeed-table-wscale* 0.7))))
      (if (vl-catch-all-error-p tbl)
        (prompt (strcat "\nO-FEEDSET: could not create the table -- " (vl-catch-all-error-message tbl)))
        (progn
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
;; COMMANDS
;; ============================================================

(defun c:O-FEED ( / obj)
  (vl-load-com)
  (if (null *ofeed-cond-table*) (_ofeed-load-refs))
  (if (null *ofeed-cond-table*)
    (prompt "\nO-FEED: could not load config\\conductors.csv -- check the config folder.")
    (progn
      (setq obj (_ofeed-pick-table))
      (if obj (_ofeed-recompute obj) (prompt "\nO-FEED: no feeder table selected."))))
  (princ))

;; SETUP: select a table to repair its structure, or Enter to create a new one (prompts # inverters)
(defun c:O-FEEDSET ( / ss obj)
  (vl-load-com)
  (if (null *ofeed-cond-table*) (_ofeed-load-refs))
  (prompt "\nO-FEEDSET: select a feeder table to set up/repair (click or window), or Enter to create a new one.")
  (setq ss (ssget '((0 . "ACAD_TABLE"))))
  (if ss
    (progn
      (setq obj (vlax-ename->vla-object (ssname ss 0)))
      (_ofeedset-repair obj))
    (_ofeedset-create))
  (princ))
(defun c:OFEEDSET () (c:O-FEEDSET))

(defun c:O-FEEDTEST ( / recs)
  (_ofeed-load-refs)
  (setq recs (list
    (_ofeed-size-feeder "AC-1" 96.2 3 480 10  T)
    (_ofeed-size-feeder "AC-2" 96.2 3 480 25  T)
    (_ofeed-size-feeder "AC-3" 48.1 3 480 80  nil)
    (_ofeed-size-feeder "AC-4" 48.1 3 480 150 nil)))
  (prompt (strcat "\n--- O-FEED self-test (term-temp " (itoa *term-temp*)
                  ", vd-coeff " (rtos *vd-coeff* 2 2) ") ---"))
  (foreach r recs
    (prompt (strcat "\n" (cdr (assoc "ID" r))
      "  WIRE=" (cdr (assoc "WIRE" r))
      " | N=" (cdr (assoc "NEUTRAL" r))
      " | G=" (cdr (assoc "GROUND" r))
      " | " (cdr (assoc "CONDUIT" r)) " fill " (cdr (assoc "FILL" r))
      " | BRK=" (itoa (cdr (assoc "OCP" r)))
      " | AMP=" (itoa (cdr (assoc "BASEDAMP" r)))
      " | VD=" (rtos (cdr (assoc "VDV" r)) 2 2) "V (" (rtos (cdr (assoc "VDP" r)) 2 2) "%)")))
  (prompt "\n--- end ---")
  (princ))

(defun c:OFEED () (c:O-FEED))

(prompt "\nOFEED v2.15 loaded. White+centered create cells; AC-1/2 = sum of AC-3..n.  O-FEED = recompute, O-FEEDSET = create/repair.")
(princ)
