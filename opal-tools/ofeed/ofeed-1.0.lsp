;; ofeed-1.0.lsp -- Ocotillo AC Feeder Auto-Sizer
;; Commands: O-FEED (alias OFEED)   O-FEEDO (alias OFEEDO)   O-FEEDTEST (headless self-test)
;;
;; Sizes AC feeders from inverter selection and draws a full feeder schedule table.
;; Input is CLI: pick an inverter model + feeder type + (count) + length; the load comes
;; from the inverter's continuous output current (x125% per NEC 690.8(B)/705.28).
;; All reference data lives in config\*.csv (sources cited in each file); nothing hard-coded.
;;
;; Engine ports the user's MVP (size-feeder / ocp-pick / cond-pick / egc-pick / vd-volts)
;; to _ofeed-* and adds conductor-area + EMT-area lookups for auto conduit fill.
;;
;; Calc basis (MVP, matches the established sheet): *term-temp* 90 (90C ampacity column),
;; *vd-coeff* 2.0. Set *term-temp* 75 for code-compliant termination ampacity.
;;
;; Drawing reuses the proven MTEXT + LWPOLYLINE grid pattern (see otable/ocondsched).
;; Entities are tagged with OCOTILLO XDATA (1000 = "feeder-sched") so re-running O-FEED
;; clears ONLY the prior feeder table (not the rest of the schedules layer) and redraws.
;;
;; Globals written: *ofeed-cond-table* *ofeed-ocp-sizes* *ofeed-egc-table*
;;                  *ofeed-emt-table* *ofeed-inverters* *O-FEED-ht* *O-FEED-cw*
;; Globals read:    *o-suite-root* (root) *ocfg-layer-schedules* (target layer) *term-temp* *vd-coeff*
;; Layer: *ocfg-layer-schedules* if bound, else "PV-SCHEDULES"
;; v1.0
;; ============================================================

(vl-load-com)

;; --- persistent globals -------------------------------------
(if (not (boundp '*term-temp*))        (setq *term-temp* 90))   ; 90 = matches sheet; 75 = compliant
(if (not (boundp '*vd-coeff*))         (setq *vd-coeff* 2.0))   ; 2.0 = legacy convention
(if (not (boundp '*O-FEED-ht*))        (setq *O-FEED-ht* 30))
(if (not (boundp '*O-FEED-cw*))        (setq *O-FEED-cw* 250))
(if (not (boundp '*ofeed-cond-table*)) (setq *ofeed-cond-table* nil))
(if (not (boundp '*ofeed-ocp-sizes*))  (setq *ofeed-ocp-sizes* nil))
(if (not (boundp '*ofeed-egc-table*))  (setq *ofeed-egc-table* nil))
(if (not (boundp '*ofeed-emt-table*))  (setq *ofeed-emt-table* nil))
(if (not (boundp '*ofeed-inverters*))  (setq *ofeed-inverters* nil))

;; ============================================================
;; ROOT + CSV LOADER
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
  ;; inverters: (model output-a phase volts)
  (setq *ofeed-inverters* nil)
  (foreach r (_ofeed-read-csv (strcat root "config\\inverters.csv"))
    (if (>= (length r) 4)
      (setq *ofeed-inverters*
        (cons (list (nth 0 r) (atof (nth 1 r)) (atoi (nth 2 r)) (atoi (nth 3 r))) *ofeed-inverters*))))
  (setq *ofeed-inverters* (reverse *ofeed-inverters*))
  (length *ofeed-cond-table*))

;; ============================================================
;; ENGINE  (pure functions over the loaded tables)
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

;; record -> 16 ordered display strings (column order)
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
;; DRAWING  (MTEXT + LWPOLYLINE grid, XDATA-tagged)
;; ============================================================

(defun _ofeed-layer ()
  (if (and (boundp '*ocfg-layer-schedules*) *ocfg-layer-schedules*)
    *ocfg-layer-schedules* "PV-SCHEDULES"))

(defun _ofeed-ensure-layer ( / ly)
  (setq ly (_ofeed-layer))
  (if (not (tblsearch "LAYER" ly))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 ly) '(70 . 0) '(62 . 7) '(6 . "Continuous")))))

;; tag an entity with OCOTILLO XDATA 1000 = "feeder-sched"; returns the ename
(defun _ofeed-xtag (e)
  (if e
    (entmod (append (entget e)
      (list (list -3 (list "OCOTILLO" (cons 1000 "feeder-sched")))))))
  e)

;; read the feeder-sched tag value of E, or nil
(defun _ofeed-tag (e / xd p)
  (setq xd (assoc -3 (entget e (list "OCOTILLO"))))
  (if xd (progn (setq p (assoc 1000 (cdr (cadr xd)))) (if p (cdr p)))))

;; delete ONLY previously-drawn feeder-table entities
(defun _ofeed-clear-table ( / ss i e)
  (setq ss (ssget "X" (list (list -3 (list "OCOTILLO")))))
  (if ss
    (progn (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (if (= (_ofeed-tag e) "feeder-sched") (entdel e))
        (setq i (1+ i))))))

(defun _ofeed-draw-rect (x1 y1 x2 y2 color / ly)
  (setq ly (_ofeed-layer))
  (if (/= color 0)
    (_ofeed-xtag
      (entmakex (list '(0 . "SOLID") '(100 . "AcDbEntity") '(100 . "AcDbTrace")
                      (cons 8 ly) (cons 62 color)
                      (cons 10 (list x1 y1 0)) (cons 11 (list x2 y1 0))
                      (cons 12 (list x1 y2 0)) (cons 13 (list x2 y2 0))))))
  (_ofeed-xtag
    (entmakex (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") '(100 . "AcDbPolyline")
                    (cons 8 ly) '(90 . 4) '(70 . 1) '(62 . 7)
                    (cons 10 (list x1 y1)) (cons 10 (list x2 y1))
                    (cons 10 (list x2 y2)) (cons 10 (list x1 y2))))))

(defun _ofeed-draw-text (x y txt ht bold / content)
  (setq content (if bold (strcat "{\\fArial|b1;" txt "}") txt))
  (_ofeed-xtag
    (entmakex (list '(0 . "MTEXT") '(100 . "AcDbEntity") '(100 . "AcDbMText")
                    (cons 8 (_ofeed-layer)) (cons 10 (list x y 0)) (cons 40 ht)
                    (cons 1 content) (cons 7 (getvar "TEXTSTYLE"))
                    '(71 . 5) '(72 . 5) '(62 . 7)))))

(defun _ofeed-headers ()
  (list "FEEDER" "# OF\\PPARALLEL\\PSETS" "WIRE TYPE" "NEUTRAL" "GROUND"
        "CONDUIT" "CONDUIT\\PFILL" "LENGTH\\P(FT)" "CIRCUIT\\PLOAD (A)"
        "CIRCUIT LOAD\\P(A) 125%" "BREAKER\\PSIZE (A)" "VOLTAGE\\P(V)"
        "BASED\\PAMPACITY (A)" "VOLTAGE\\PDROP (V)" "VOLTAGE\\PDROP (%)"
        "GENERAL FORMULA"))

(defun _ofeed-wmul ()
  (list 0.8 0.7 2.2 2.2 1.6 1.2 0.9 0.7 0.9 1.0 1.0 0.8 1.0 0.9 0.9 2.6))

(defun _ofeed-draw-table (recs ox oy / ht cw rh hh hdrs widths tw x y i w h rec cells c)
  (_ofeed-clear-table)
  (_ofeed-ensure-layer)
  (setq ht     *O-FEED-ht*
        cw     *O-FEED-cw*
        rh     (* ht 2.0)
        hh     (* rh 2.0)
        hdrs   (_ofeed-headers)
        widths (mapcar (function (lambda (m) (* m cw))) (_ofeed-wmul))
        tw     (apply (function +) widths)
        y      oy)
  ;; Title row
  (_ofeed-draw-rect ox (- y rh) (+ ox tw) y 254)
  (_ofeed-draw-text (+ ox (/ tw 2.0)) (- y (/ rh 2.0)) "AC FEEDER SCHEDULE" ht T)
  (setq y (- y rh))
  ;; Header row (taller, for multi-line headers)
  (setq x ox i 0)
  (foreach h hdrs
    (setq w (nth i widths))
    (_ofeed-draw-rect x (- y hh) (+ x w) y 9)
    (_ofeed-draw-text (+ x (/ w 2.0)) (- y (/ hh 2.0)) h ht T)
    (setq x (+ x w) i (1+ i)))
  (setq y (- y hh))
  ;; Data rows
  (foreach rec recs
    (setq cells (_ofeed-row-cells rec) x ox i 0)
    (foreach c cells
      (setq w (nth i widths))
      (_ofeed-draw-rect x (- y rh) (+ x w) y 0)
      (if (/= c "") (_ofeed-draw-text (+ x (/ w 2.0)) (- y (/ rh 2.0)) c ht nil))
      (setq x (+ x w) i (1+ i)))
    (setq y (- y rh)))
  (prompt (strcat "\nO-FEED: " (itoa (length recs)) " feeder(s) placed.")))

;; ============================================================
;; CLI INPUT
;; ============================================================

(defun _ofeed-pick-inverter ( / i c)
  (prompt "\n--- Inverter models (config\\inverters.csv) ---")
  (setq i 1)
  (foreach m *ofeed-inverters*
    (prompt (strcat "\n  " (itoa i) ". " (nth 0 m) "   "
                    (rtos (nth 1 m) 2 1) "A  " (itoa (nth 2 m)) "ph  " (itoa (nth 3 m)) "V"))
    (setq i (1+ i)))
  (setq c (getint (strcat "\nSelect inverter 1-" (itoa (length *ofeed-inverters*))
                          " (Enter = done): ")))
  (if (and c (>= c 1) (<= c (length *ofeed-inverters*)))
    (nth (1- c) *ofeed-inverters*)
    nil))

(defun _ofeed-cli ( / recs idx more inv typ n len id load neutral again)
  (setq recs nil idx 1 more T)
  (while more
    (setq inv (_ofeed-pick-inverter))
    (if (not inv)
      (setq more nil)
      (progn
        (initget "Inverter Aggregation")
        (setq typ (getkword "\nFeeder type [Inverter/Aggregation] <Inverter>: "))
        (if (null typ) (setq typ "Inverter"))
        (if (= typ "Aggregation")
          (progn
            (setq n (getint "\nNumber of inverters aggregated <2>: "))
            (if (null n) (setq n 2))
            (setq load (* n (nth 1 inv)) neutral T))
          (progn (setq load (nth 1 inv) neutral nil)))
        (setq len (getreal "\nRun length (ft): "))
        (if (null len) (setq len 0.0))
        (setq id (getstring (strcat "\nFeeder ID <AC-" (itoa idx) ">: ")))
        (if (or (null id) (= id "")) (setq id (strcat "AC-" (itoa idx))))
        (setq recs (cons (_ofeed-size-feeder id load (nth 2 inv) (nth 3 inv) len neutral) recs)
              idx  (1+ idx))
        (prompt (strcat "\n  added " id "  load " (rtos load 2 1) "A"
                        (if neutral "  (with neutral)" "  (no neutral)")))
        (initget "Yes No")
        (setq again (getkword "\nAdd another feeder? [Yes/No] <Yes>: "))
        (if (= again "No") (setq more nil)))))
  (reverse recs))

;; ============================================================
;; COMMANDS
;; ============================================================

(defun c:O-FEED ( / recs pt)
  (vl-load-com)
  (if (null *ofeed-cond-table*) (_ofeed-load-refs))
  (cond
    ((null *ofeed-cond-table*)
     (prompt "\nO-FEED: could not load config\\conductors.csv -- check the config folder.") (princ))
    ((null *ofeed-inverters*)
     (prompt "\nO-FEED: no inverters in config\\inverters.csv.") (princ))
    (T
     (setq recs (_ofeed-cli))
     (if (null recs)
       (prompt "\nO-FEED: nothing to draw.")
       (progn
         (setq pt (getpoint "\nPick top-left corner for the feeder schedule: "))
         (if pt
           (progn (setq pt (trans pt 1 0))
             (_ofeed-draw-table recs (float (car pt)) (float (cadr pt))))
           (prompt "\nCancelled."))))
     (princ))))

(defun c:O-FEEDO ( / hstr wstr)
  (prompt "\nO-FEEDO -- feeder schedule settings")
  (setq hstr (getstring (strcat "\nText height <" (rtos *O-FEED-ht* 2 0) ">: ")))
  (if (and hstr (/= hstr "") (> (atof hstr) 0.0)) (setq *O-FEED-ht* (atof hstr)))
  (setq wstr (getstring (strcat "Cell width base <" (rtos *O-FEED-cw* 2 0) ">: ")))
  (if (and wstr (/= wstr "") (> (atof wstr) 0.0)) (setq *O-FEED-cw* (atof wstr)))
  (_ofeed-load-refs)
  (prompt (strcat "\nApplied -- Height: " (rtos *O-FEED-ht* 2 0)
                  "  Width: " (rtos *O-FEED-cw* 2 0) "  (refs reloaded)"))
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

(defun c:OFEED ()  (c:O-FEED))
(defun c:OFEEDO () (c:O-FEEDO))

(prompt "\nOFEED v1.0 loaded. O-FEED=build+place  O-FEEDO=settings  O-FEEDTEST=self-test.")
(princ)
