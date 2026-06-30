;; ofeed-2.06.lsp -- Ocotillo AC Feeder Schedule Recompute
;; Commands: O-FEED (alias OFEED)   O-FEEDTEST (headless engine self-test)
;;
;; RECOMPUTE an existing native AutoCAD table (ACAD_TABLE): the user keeps the schedule and types
;; the assumed-correct inputs; O-FEED sizes the rest. See header of 2.0 for the full design.
;;
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
;; v2.06
;; ============================================================

(vl-load-com)

;; --- persistent globals -------------------------------------
(if (not (boundp '*term-temp*))        (setq *term-temp* 90))
(if (not (boundp '*vd-coeff*))         (setq *vd-coeff* 2.0))
(if (not (boundp '*ofeed-tint*))       (setq *ofeed-tint* T))
(if (not (boundp '*ofeed-neutral-max*)) (setq *ofeed-neutral-max* 2)) ; feeders numbered above this -> no neutral ("-")
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

;; build an AcCmColor by trying ProgID version suffixes (ACADVER + app Version + a spread) until one resolves
(defun _ofeed-make-color (r g b / vv vers made col)
  (setq vers (list (substr (getvar "ACADVER") 1 2))
        vv   (vl-catch-all-apply 'vla-get-Version (list (vlax-get-acad-object))))
  (if (and (not (vl-catch-all-error-p vv)) (>= (strlen vv) 2))
    (setq vers (cons (substr vv 1 2) vers)))
  (setq vers (append vers '("26" "25" "24" "23" "22" "21" "20" "27" "28"))
        made nil)
  (foreach v vers
    (if (not made)
      (progn
        (setq col (vl-catch-all-apply 'vla-GetInterfaceObject
                    (list (vlax-get-acad-object) (strcat "AutoCAD.AcCmColor." v))))
        (if (not (vl-catch-all-error-p col)) (setq made col)))))
  (if made (progn (vl-catch-all-apply 'vla-SetRGB (list made r g b)) made) nil))

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

;; process one data row; returns (sized-p  (changes...)  (err-msgs...))
(defun _ofeed-process-row (tbl r map feeder bluecol redcol /
                           loadstr voltstr lenstr loadok voltok lenok
                           fload fvolts flen fnum neutral phase rec cells note
                           changes errs k tcol oldval newval)
  (setq changes nil errs nil
        loadstr (_ofeed-cell tbl r (_ofeed-col map 8))
        voltstr (_ofeed-cell tbl r (_ofeed-col map 11))
        lenstr  (if (_ofeed-col map 7) (_ofeed-cell tbl r (_ofeed-col map 7)) "")
        loadok  (> (atof loadstr) 0.0)
        voltok  (> (atoi voltstr) 0)
        lenok   (_ofeed-has-digit lenstr))
  (_ofeed-flag tbl r (_ofeed-col map 8) (not loadok) redcol)
  (_ofeed-flag tbl r (_ofeed-col map 11) (not voltok) redcol)
  (if (_ofeed-col map 7) (_ofeed-flag tbl r (_ofeed-col map 7) (not lenok) redcol))
  (if (not loadok) (setq errs (cons (strcat feeder ": CIRCUIT LOAD missing/invalid -- NOT sized") errs)))
  (if (not lenok)  (setq errs (cons (strcat feeder ": LENGTH missing/invalid -- sized, but voltage drop can't be computed") errs)))
  (if (not voltok) (setq errs (cons (strcat feeder ": VOLTAGE missing/invalid -- sized, but voltage drop % can't be computed") errs)))
  (if (not loadok)
    (list nil nil (reverse errs))
    (progn
      (setq fload   (atof loadstr)
            fvolts  (if voltok (atoi voltstr) 480)
            flen    (if lenok (atof lenstr) 0.0)
            fnum    (_ofeed-trailing-int feeder)
            neutral (if (and fnum (> fnum *ofeed-neutral-max*))
                      nil                                         ; AC-3+ -> no neutral ("-")
                      (_ofeed-neutral-p (if (_ofeed-col map 3) (_ofeed-cell tbl r (_ofeed-col map 3)) "")))
            phase   (_ofeed-phase-from-wire (if (_ofeed-col map 2) (_ofeed-cell tbl r (_ofeed-col map 2)) ""))
            rec     (vl-catch-all-apply '_ofeed-size-feeder (list feeder fload phase fvolts flen neutral)))
      (if (vl-catch-all-error-p rec)
        (progn
          (_ofeed-flag tbl r (_ofeed-col map 2) T redcol)
          (_ofeed-flag tbl r (_ofeed-col map 10) T redcol)
          (list nil nil (reverse (cons (strcat feeder ": load too high for the conductor/breaker table (add larger sizes)") errs))))
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
                      (progn
                        (_ofeed-set tbl r tcol newval)
                        (if (and *ofeed-tint* bluecol) (_ofeed-tint-cell tbl r tcol bluecol))
                        (setq changes (cons (list r tcol oldval) changes)))))))))
          (setq note (cond ((and (not lenok) (not voltok)) " | VD: no length/voltage")
                           ((not lenok) " | VD: no length")
                           ((not voltok) " | VD: no voltage")
                           (T "")))
          (prompt (strcat "\n  " (nth 0 cells)
            "  SETS " (nth 1 cells) " | BRK " (nth 10 cells)
            " | " (nth 2 cells) " | N " (nth 3 cells) " | G " (nth 4 cells)
            " | " (nth 5 cells) " " (nth 6 cells) " | AMP " (nth 12 cells) note))
          (list T (reverse changes) (reverse errs)))))))

(defun _ofeed-recompute (tbl / ncols nrows hrow map bluecol redcol r feeder res
                              pending errs nok nskip ans p)
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
         (setq r (1+ hrow) nok 0 nskip 0 pending nil errs nil
               bluecol (if *ofeed-tint* (_ofeed-make-color 173 216 230) nil)
               redcol  (if *ofeed-tint* (_ofeed-make-color 255 180 180) nil))
         (if (and *ofeed-tint* (null bluecol))
           (prompt "\n(Cell coloring unavailable on this build -- using the command-line preview below.)"))
         (prompt "\nO-FEED recompute (125% / VOLTAGE DROP / GENERAL FORMULA left as table calcs):")
         (_ofeed-noregen tbl)                                  ; batch edits -> one regen at the end
         (while (< r nrows)
           (setq feeder (_ofeed-norm (_ofeed-cell tbl r (_ofeed-col map 0))))
           (if (/= feeder "")
             (progn
               (setq res (_ofeed-process-row tbl r map feeder bluecol redcol))
               (if (car res) (setq nok (1+ nok)) (setq nskip (1+ nskip)))
               (setq pending (append pending (cadr res))
                     errs    (append errs (caddr res)))))
           (setq r (1+ r)))
         (_ofeed-doregen tbl)                                  ; show blue/red now
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

(prompt "\nOFEED v2.06 loaded. Regen-crash fixed; faster batched regen; AC-3+ forced no-neutral.  O-FEED = recompute, O-FEEDTEST = self-test.")
(princ)
