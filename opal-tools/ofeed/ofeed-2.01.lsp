;; ofeed-2.01.lsp -- Ocotillo AC Feeder Schedule Recompute
;; Commands: O-FEED (alias OFEED)   O-FEEDTEST (headless engine self-test)
;;
;; RECOMPUTE an existing native AutoCAD table (ACAD_TABLE): the user keeps the schedule and types
;; the assumed-correct inputs; O-FEED sizes the rest. See header of 2.0 for the full design.
;;
;;   INPUT cells (read, never overwritten):  FEEDER, CIRCUIT LOAD (A), VOLTAGE (V),
;;                                           LENGTH (FT), NEUTRAL (presence = yes/no, "-" = no)
;;   COMPUTED cells (filled/corrected):      # OF PARALLEL SETS, WIRE TYPE, NEUTRAL, GROUND,
;;                                           CONDUIT, CONDUIT FILL, CIRCUIT LOAD (A) 125%,
;;                                           BREAKER SIZE (A), BASED AMPACITY (A),
;;                                           VOLTAGE DROP (V), VOLTAGE DROP (%), GENERAL FORMULA
;;
;; 2.01: per-feeder REPORT -- prints each recomputed feeder with its sized values and which cells
;;       actually changed (so a no-op re-run reads "[no change]"); grip-highlights the table after.
;; 2.0:  initial recompute rewrite (replaced the 1.0 CLI wizard + drawn grid).
;;
;; Phase inferred from the existing WIRE TYPE "(N)" count (N=2 -> 1ph, else 3ph), default 3-phase.
;; Calc basis: *term-temp* 90, *vd-coeff* 2.0 (set *term-temp* 75 for compliant termination ampacity).
;;
;; Globals read:  *o-suite-root* *term-temp* *vd-coeff*
;; v2.01
;; ============================================================

(vl-load-com)

;; --- persistent globals -------------------------------------
(if (not (boundp '*term-temp*))        (setq *term-temp* 90))   ; 90 = matches sheet; 75 = compliant
(if (not (boundp '*vd-coeff*))         (setq *vd-coeff* 2.0))   ; 2.0 = legacy convention
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

;; split S on single-char SEP -> list of fields (keeps empties)
(defun _ofeed-split (s sep / pos out)
  (setq out nil)
  (while (setq pos (vl-string-search sep s))
    (setq out (cons (substr s 1 pos) out)
          s   (substr s (+ pos 1 (strlen sep)))))
  (reverse (cons s out)))

;; read a CSV: skip #-comment lines and the first data (header) line; trim CR
(defun _ofeed-read-csv (path / f line rows seenhdr trimmed)
  (setq rows nil seenhdr nil)
  (if (setq f (open path "r"))
    (progn
      (while (setq line (read-line f))
        (setq trimmed (vl-string-trim " \t\r" line))
        (cond
          ((= trimmed "") nil)
          ((= (substr trimmed 1 1) "#") nil)
          ((not seenhdr) (setq seenhdr T))                 ; header -> skip
          (T (setq rows (cons (_ofeed-split trimmed ",") rows)))))
      (close f)))
  (reverse rows))

;; field N of row R as non-empty string, else nil
(defun _ofeed-fld (r n / v) (setq v (nth n r)) (if (and v (> (strlen v) 0)) v nil))

;; load all five reference CSVs into globals; returns conductor row count
(defun _ofeed-load-refs ( / root)
  (setq root (_ofeed-root))
  (regapp "OCOTILLO")
  ;; conductors: (size amp75 amp90 r-ohm/kft area-thhn)
  (setq *ofeed-cond-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\conductors.csv"))
    (if (>= (length r) 5)
      (setq *ofeed-cond-table*
        (cons (list (nth 0 r) (atoi (nth 1 r)) (atoi (nth 2 r)) (atof (nth 3 r)) (atof (nth 4 r)))
              *ofeed-cond-table*))))
  (setq *ofeed-cond-table* (reverse *ofeed-cond-table*))
  ;; emt: (trade internal-area)
  (setq *ofeed-emt-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\conduit_emt.csv"))
    (if (>= (length r) 2)
      (setq *ofeed-emt-table* (cons (list (nth 0 r) (atof (nth 1 r))) *ofeed-emt-table*))))
  (setq *ofeed-emt-table* (reverse *ofeed-emt-table*))
  ;; egc: (max-ocp egc-size)
  (setq *ofeed-egc-table* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\egc.csv"))
    (if (>= (length r) 2)
      (setq *ofeed-egc-table* (cons (list (atoi (nth 0 r)) (nth 1 r)) *ofeed-egc-table*))))
  (setq *ofeed-egc-table* (reverse *ofeed-egc-table*))
  ;; ocpd: rating
  (setq *ofeed-ocp-sizes* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\ocpd.csv"))
    (if (>= (length r) 1) (setq *ofeed-ocp-sizes* (cons (atoi (nth 0 r)) *ofeed-ocp-sizes*))))
  (setq *ofeed-ocp-sizes* (reverse *ofeed-ocp-sizes*))
  ;; inverters: (model output-a phase volts)  -- loaded for the deferred Create mode; unused by recompute
  (setq *ofeed-inverters* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\inverters.csv"))
    (if (>= (length r) 4)
      (setq *ofeed-inverters*
        (cons (list (nth 0 r) (atof (nth 1 r)) (atoi (nth 2 r)) (atoi (nth 3 r))) *ofeed-inverters*))))
  (setq *ofeed-inverters* (reverse *ofeed-inverters*))
  (length *ofeed-cond-table*))

;; ============================================================
;; ENGINE  (pure functions over the loaded tables -- unchanged from 1.0)
;; ============================================================

(defun _ofeed-amp-col (row)               ; 75 or 90 ampacity per *term-temp*
  (if (= *term-temp* 90) (nth 2 row) (nth 1 row)))

(defun _ofeed-cond-row (size / r)
  (foreach row *ofeed-cond-table* (if (= size (nth 0 row)) (setq r row))) r)

(defun _ofeed-cond-R (size / row) (setq row (_ofeed-cond-row size)) (if row (nth 3 row) 0.0))
(defun _ofeed-cond-area (size / row) (setq row (_ofeed-cond-row size)) (if row (nth 4 row) 0.0))

(defun _ofeed-ocp-pick (i / r)            ; smallest standard OCPD >= i
  (foreach s *ofeed-ocp-sizes* (if (and (not r) (>= s i)) (setq r s))) r)

(defun _ofeed-egc-pick (ocp / r)          ; smallest adequate EGC for an OCPD
  (foreach e *ofeed-egc-table* (if (and (not r) (<= ocp (car e))) (setq r (cadr e)))) r)

(defun _ofeed-cond-pick (i / r)           ; smallest conductor carrying >= i at term temp
  (foreach row *ofeed-cond-table*
    (if (and (not r) (>= (_ofeed-amp-col row) i)) (setq r (nth 0 row)))) r)

(defun _ofeed-vd-volts (L i R) (/ (* *vd-coeff* L i R) 1000.0))

(defun _ofeed-phase-count (phase) (if (= phase 1) 2 3))

(defun _ofeed-parallel-sets (i125 / maxamp)
  (setq maxamp (_ofeed-amp-col (last *ofeed-cond-table*)))
  (if (<= i125 maxamp) 1 (fix (+ 0.9999 (/ i125 (float maxamp))))))

;; smallest EMT where fill < 40%; -> (trade-size fill-pct). Fallback: largest EMT.
(defun _ofeed-conduit-pick (area / r last-c)
  (foreach c *ofeed-emt-table*
    (if (and (not r) (< (/ area (cadr c)) 0.40))
      (setq r (list (car c) (* 100.0 (/ area (cadr c)))))))
  (if r r
    (progn (setq last-c (last *ofeed-emt-table*))
      (list (car last-c) (* 100.0 (/ area (cadr last-c)))))))

;; size one feeder -> assoc record. neutral = T/nil.
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

;; record -> 16 ordered display strings (matches _ofeed-columns order exactly)
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
;; TABLE SCHEMA  (single source of truth, shared with the deferred Create mode)
;; ordered 0..15; role = "input" (never overwritten) | "computed" | "static"
;; ============================================================

(defun _ofeed-columns ()
  (list
    (cons "FEEDER"                "input")
    (cons "# OF PARALLEL SETS"    "computed")
    (cons "WIRE TYPE"             "computed")
    (cons "NEUTRAL"              "computed")
    (cons "GROUND"               "computed")
    (cons "CONDUIT"              "computed")
    (cons "CONDUIT FILL"         "computed")
    (cons "LENGTH (FT)"          "input")
    (cons "CIRCUIT LOAD (A)"     "input")
    (cons "CIRCUIT LOAD (A) 125%" "computed")
    (cons "BREAKER SIZE (A)"     "computed")
    (cons "VOLTAGE (V)"          "input")
    (cons "BASED AMPACITY (A)"   "computed")
    (cons "VOLTAGE DROP (V)"     "computed")
    (cons "VOLTAGE DROP (%)"     "computed")
    (cons "GENERAL FORMULA"      "static")))

;; canonical column indices the recompute WRITES back (everything except inputs 0,7,8,11)
(defun _ofeed-computed-idx () '(1 2 3 4 5 6 9 10 12 13 14 15))

;; header string at canonical index k
(defun _ofeed-hdr (k) (car (nth k (_ofeed-columns))))

;; join a list of strings with SEP
(defun _ofeed-join (lst sep / s)
  (setq s "")
  (foreach x lst (setq s (if (= s "") x (strcat s sep x))))
  s)

;; ============================================================
;; TEXT NORMALIZE  (strip MTEXT formatting so header/cell text compares cleanly)
;; ============================================================

;; remove {..} grouping and \<code>..; format runs; \P -> space; keep escaped literals
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
         ((member nxt '("P" "X"))                                  ; paragraph / align break
          (setq out (strcat out " ") i (+ i 2)))
         ((member nxt '("F" "C" "H" "A" "T" "Q" "W" "L" "O" "K"))  ; format run -> skip to ';'
          (setq i (+ i 2))
          (while (and (<= i n) (/= (substr s i 1) ";")) (setq i (1+ i)))
          (setq i (1+ i)))
         (T (setq out (strcat out (substr s (1+ i) 1)) i (+ i 2)))))  ; escaped literal char
      (T (setq out (strcat out ch) i (1+ i)))))
  out)

(defun _ofeed-norm (s)
  (strcase (vl-string-trim " \t\r\n" (_ofeed-strip-mtext s))))

;; ============================================================
;; ACAD_TABLE CELL I/O  (defensive VLA wrappers)
;; ============================================================

(defun _ofeed-cell (tbl r c / v)
  (setq v (vl-catch-all-apply 'vla-GetText (list tbl r c)))
  (if (vl-catch-all-error-p v) "" v))

(defun _ofeed-set (tbl r c val / e)
  (setq e (vl-catch-all-apply 'vla-SetText (list tbl r c val)))
  (not (vl-catch-all-error-p e)))

;; canonical index (0..15) of a normalized header string, else nil
(defun _ofeed-canon-index (normhdr / i found)
  (setq i 0 found nil)
  (foreach pair (_ofeed-columns)
    (if (and (not found) (= (_ofeed-norm (car pair)) normhdr)) (setq found i))
    (setq i (1+ i)))
  found)

;; first row index whose any cell normalizes to "FEEDER", else nil
(defun _ofeed-find-header-row (tbl ncols nrows / r c hr)
  (setq r 0 hr nil)
  (while (and (< r nrows) (not hr))
    (setq c 0)
    (while (and (< c ncols) (not hr))
      (if (= (_ofeed-norm (_ofeed-cell tbl r c)) "FEEDER") (setq hr r))
      (setq c (1+ c)))
    (setq r (1+ r)))
  hr)

;; alist (canonical-index . table-column) from the header row
(defun _ofeed-build-colmap (tbl hrow ncols / c k map)
  (setq c 0 map nil)
  (while (< c ncols)
    (setq k (_ofeed-canon-index (_ofeed-norm (_ofeed-cell tbl hrow c))))
    (if (and k (not (assoc k map))) (setq map (cons (cons k c) map)))
    (setq c (1+ c)))
  map)

(defun _ofeed-col (map k) (cdr (assoc k map)))

;; NEUTRAL input cell present (a conductor) vs absent ("-"/blank)
(defun _ofeed-neutral-p (s / v)
  (setq v (_ofeed-norm s))
  (and (/= v "") (/= v "-") (/= v "--")))

;; phase from the existing WIRE TYPE "(N)" count: N=2 -> 1ph, else 3ph; default 3
(defun _ofeed-phase-from-wire (s / p1 p2 nstr)
  (setq s (_ofeed-norm s) nstr nil)
  (if (setq p1 (vl-string-search "(" s))
    (if (setq p2 (vl-string-search ")" s))
      (if (> p2 (1+ p1)) (setq nstr (substr s (+ p1 2) (- p2 p1 1))))))
  (cond ((null nstr) 3)
        ((= (atoi nstr) 2) 1)
        (T 3)))

;; ============================================================
;; RECOMPUTE  (the MVP)  -- writes computed cells, prints a per-feeder report
;; ============================================================

;; write the computed cells of one data row; returns the list of changed header names
(defun _ofeed-write-row (tbl r map cells flen / changed k tcol newval oldval)
  (setq changed nil)
  (foreach k (_ofeed-computed-idx)
    (if (setq tcol (_ofeed-col map k))
      (progn
        (setq newval (if (and (member k '(13 14)) (<= flen 0.0)) "" (nth k cells))
              oldval (_ofeed-cell tbl r tcol))
        (if (/= (_ofeed-norm oldval) (_ofeed-norm newval))
          (setq changed (cons (_ofeed-hdr k) changed)))
        (_ofeed-set tbl r tcol newval))))
  (reverse changed))

;; one-line per-feeder readout of the sized values + what changed
(defun _ofeed-report-row (cells flen changed / nchg tag)
  (setq nchg (length changed)
        tag  (cond ((= nchg 0) "[no change]")
                   ((>= nchg 10) (strcat "[" (itoa nchg) " cells set]"))
                   (T (strcat "[changed: " (_ofeed-join changed ", ") "]"))))
  (prompt (strcat "\n  " (nth 0 cells)
    "  BRK " (nth 10 cells)
    " | " (nth 2 cells)
    " | N " (nth 3 cells)
    " | G " (nth 4 cells)
    " | " (nth 5 cells) " " (nth 6 cells)
    " | " (if (<= flen 0.0) "VD blank (no length)"
            (strcat "VD " (nth 13 cells) "V " (nth 14 cells)))
    "  " tag)))

(defun _ofeed-recompute (tbl / ncols nrows hrow map r feeder fload fvolts flen neutral phase
                                rec cells changed nok nskip warnlen nchanged)
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
         (setq r (1+ hrow) nok 0 nskip 0 warnlen 0 nchanged 0)
         (prompt "\nO-FEED recompute:")
         (while (< r nrows)
           (setq feeder (_ofeed-norm (_ofeed-cell tbl r (_ofeed-col map 0))))
           (if (/= feeder "")
             (progn
               (setq fload   (atof (_ofeed-cell tbl r (_ofeed-col map 8)))
                     fvolts  (atoi (_ofeed-cell tbl r (_ofeed-col map 11)))
                     flen    (if (_ofeed-col map 7) (atof (_ofeed-cell tbl r (_ofeed-col map 7))) 0.0)
                     neutral (_ofeed-neutral-p (if (_ofeed-col map 3) (_ofeed-cell tbl r (_ofeed-col map 3)) ""))
                     phase   (_ofeed-phase-from-wire (if (_ofeed-col map 2) (_ofeed-cell tbl r (_ofeed-col map 2)) "")))
               (if (or (<= fload 0.0) (<= fvolts 0))
                 (setq nskip (1+ nskip))               ; not a sizable data row (note/blank)
                 (progn
                   (setq rec     (_ofeed-size-feeder feeder fload phase fvolts flen neutral)
                         cells   (_ofeed-row-cells rec)
                         changed (_ofeed-write-row tbl r map cells flen))
                   (_ofeed-report-row cells flen changed)
                   (if (> (length changed) 0) (setq nchanged (1+ nchanged)))
                   (if (<= flen 0.0) (setq warnlen (1+ warnlen)))
                   (setq nok (1+ nok))))))
           (setq r (1+ r)))
         (vl-catch-all-apply 'vla-Update (list tbl))
         (prompt (strcat "\nSummary: recomputed " (itoa nok) " feeder(s), " (itoa nchanged) " changed"
                         (if (> nskip 0)   (strcat ", skipped " (itoa nskip) " row(s) (no load/voltage)") "")
                         (if (> warnlen 0) (strcat ", " (itoa warnlen) " missing length -> VD blank") "")
                         ".")))))))

;; grip-highlight an entity (non-destructive; clears on next click / Esc)
(defun _ofeed-highlight (ent / ss)
  (setq ss (ssadd))
  (ssadd ent ss)
  (sssetfirst nil ss))

;; ============================================================
;; COMMANDS
;; ============================================================

(defun c:O-FEED ( / es ent obj done)
  (vl-load-com)
  (if (null *ofeed-cond-table*) (_ofeed-load-refs))
  (if (null *ofeed-cond-table*)
    (prompt "\nO-FEED: could not load config\\conductors.csv -- check the config folder.")
    (progn
      (setq done nil)
      (while (not done)
        (setq es (entsel "\nSelect feeder table to recompute: "))
        (cond
          ((null es) (setq done T) (prompt "\nO-FEED: nothing selected."))
          (T (setq ent (car es) obj (vlax-ename->vla-object ent))
             (if (= (vla-get-ObjectName obj) "AcDbTable")
               (progn (_ofeed-recompute obj) (_ofeed-highlight ent) (setq done T))
               (prompt "\nThat is not a table -- pick an AutoCAD table (ACAD_TABLE)."))))))
    )
  (princ))

;; headless self-test: sizes the four reference feeders and prints results (no GUI calls)
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

(prompt "\nOFEED v2.01 loaded. O-FEED = select a feeder table -> recompute + report.  O-FEEDTEST = engine self-test.")
(princ)
