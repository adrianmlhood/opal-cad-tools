;; odc-1.22 -- Changes vs 1.21:
;;   (1) Arrowhead square reduced: size multiplier 0.4 → 0.22 (≈55% of prior,
;;       yielding ~17" side vs prior ~31" at typical module scale).
;;   (2) Arrowhead square is now ALWAYS axis-aligned to the WCS (ux=1, uy=0).
;;       Prior behavior oriented the square along the string direction, causing
;;       diagonal placement when the last/first segment was at an angle.
;;       _odc-box-arrow no longer accepts or uses a direction argument.
;;
;;   Carried over unchanged from 1.21.
;; ============================================================

;; --- small list helpers (self-contained) ---
(defun _odc-list-min (lst / v r) (setq r (car lst)) (foreach v (cdr lst) (if (< v r) (setq r v))) r)
(defun _odc-list-max (lst / v r) (setq r (car lst)) (foreach v (cdr lst) (if (> v r) (setq r v))) r)

;; --- DC line layer (config-driven) ---
(defun _odc-lname ()
  (if (and (boundp (quote *ocfg-layer-dc*)) *ocfg-layer-dc*)
    *ocfg-layer-dc*
    "E-STRINGING"))

;; --- module source layer (config-driven) ---
(defun _odc-mlayer ()
  (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
    *ocfg-layer-modules*
    "MODULES"))

;; --- DC layer linetype / lineweight (config-overridable) ---
(defun _odc-ltname ()
  (if (and (boundp (quote *ocfg-dc-linetype*)) *ocfg-dc-linetype*)
    *ocfg-dc-linetype*
    "Dash Style-13"))
(defun _odc-lweight ()
  (if (and (boundp (quote *ocfg-dc-lineweight*)) *ocfg-dc-lineweight*)
    *ocfg-dc-lineweight*
    50))                                  ; hundredths of mm -> 50 = 0.50mm

;; --- box arrowhead edge length for a module record (ent minx miny maxx maxy cx cy) ---
;; *ocfg-dc-arrow-size* (>0) forces an absolute size; otherwise auto-sizes to the
;; module so the box is always visible at module scale.
;; 0.22 × short-side ≈ 17" at typical 77"-wide module (was 0.4 ≈ 31").
(defun _odc-asize (rec / w h s)
  (if (and (boundp (quote *ocfg-dc-arrow-size*)) *ocfg-dc-arrow-size* (> *ocfg-dc-arrow-size* 0))
    *ocfg-dc-arrow-size*
    (progn
      (setq w (- (nth 3 rec) (nth 1 rec))
            h (- (nth 4 rec) (nth 2 rec))
            s (if (< w h) w h))
      (* 0.22 s))))

;; --- ensure the DC linetype is loaded; return a usable linetype name ---
;; "Dash Style-13" is a custom linetype that should already live in the
;; drawing/template. If absent we do NOT -LINETYPE load (not in any standard
;; .lin; the prompt could hang the command); we warn and fall back to
;; CONTINUOUS so layer creation still succeeds.
(defun _odc-ensure-ltype (ltname)
  (if (tblsearch "LTYPE" ltname)
    ltname
    (progn
      (prompt (strcat "\nO-DC WARNING: linetype '" ltname
                      "' is not loaded -- " (_odc-lname) " will use CONTINUOUS."
                      " Load '" ltname "' (LINETYPE command) and re-run O-DC to apply it."))
      "Continuous")))

;; --- set/replace one group code on an existing LAYER table record ---
(defun _odc-set-layer-prop (lname grp val / en ed)
  (if (setq en (tblobjname "LAYER" lname))
    (progn
      (setq ed (entget en))
      (if (assoc grp ed)
        (setq ed (subst (cons grp val) (assoc grp ed) ed))
        (setq ed (append ed (list (cons grp val)))))
      (entmod ed))))

;; --- ensure the DC line layer exists with the right props; warn if hidden ---
(defun _odc-ensure-layer (lname / rec flags clr ltname lw)
  (setq ltname (_odc-ensure-ltype (_odc-ltname))
        lw     (_odc-lweight))
  (if (not (tblsearch "LAYER" lname))
    (entmakex (list '(0 . "LAYER")
                    '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 lname)
                    '(70 . 0)
                    '(62 . 7)                  ; WHITE
                    (cons 6 ltname)
                    (cons 370 lw)))
    (progn
      ;; existing layer -> bring its props up to the deliverable default
      (_odc-set-layer-prop lname 62 7)         ; WHITE (was cyan)
      (_odc-set-layer-prop lname 6 ltname)
      (_odc-set-layer-prop lname 370 lw)
      (setq rec   (tblsearch "LAYER" lname)
            flags (cdr (assoc 70 rec))
            clr   (cdr (assoc 62 rec)))
      (cond
        ((and flags (= (logand flags 1) 1))
         (prompt (strcat "\nO-DC WARNING: layer '" lname "' is FROZEN -- thaw it to see lines.")))
        ((and clr (< clr 0))
         (prompt (strcat "\nO-DC WARNING: layer '" lname "' is OFF -- turn it on to see lines."))))))
  ;; lineweight only displays if LWDISPLAY is on
  (if (= 0 (getvar "LWDISPLAY"))
    (prompt "\nO-DC note: LWDISPLAY is OFF -- the 0.50mm lineweight won't show until you turn it on (LWDISPLAY 1).")))

;; --- WCS corner points of a heavyweight POLYLINE (walk VERTEX subents) or LWPOLYLINE ---
;; OCS->WCS uses the entity-name form (trans pt ent 0): correct for any extrusion.
(defun _odc-poly-pts (ent / ed etype pts pair v ved)
  (setq ed (entget ent) etype (cdr (assoc 0 ed)) pts '())
  (cond
    ((= etype "LWPOLYLINE")
     (foreach pair ed
       (if (= (car pair) 10)
         (setq pts (cons (trans (list (cadr pair) (caddr pair) 0.0) ent 0) pts)))))
    ((= etype "POLYLINE")
     (setq v (entnext ent))
     (while (and v (= (cdr (assoc 0 (setq ved (entget v)))) "VERTEX"))
       (setq pts (cons (trans (cdr (assoc 10 ved)) ent 0) pts))
       (setq v (entnext v)))))
  pts)

;; --- WCS bbox from a poly's corner points; nil if fewer than 3 ---
(defun _odc-poly-bbox (ent / pts xv yv p)
  (setq pts (_odc-poly-pts ent) xv '() yv '())
  (foreach p pts (setq xv (cons (car p) xv) yv (cons (cadr p) yv)))
  (if (>= (length pts) 3)
    (list (_odc-list-min xv) (_odc-list-min yv)
          (_odc-list-max xv) (_odc-list-max yv))
    nil))

;; --- collect module records once: (ent minx miny maxx maxy cx cy) ---
;; Positive filter: "*POLYLINE" (POLYLINE or LWPOLYLINE) ON the module layer only.
(defun _odc-collect-modules (mlayer / ss i e bb recs)
  (setq recs '())
  (setq ss (ssget "X" (list '(0 . "*POLYLINE") (cons 8 mlayer))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (if (setq bb (_odc-poly-bbox e))
          (setq recs
            (cons (list e (nth 0 bb) (nth 1 bb) (nth 2 bb) (nth 3 bb)
                        (/ (+ (nth 0 bb) (nth 2 bb)) 2.0)
                        (/ (+ (nth 1 bb) (nth 3 bb)) 2.0))
                  recs)))
        (setq i (1+ i)))))
  recs)

;; --- module whose bbox contains wpt; nearest-center tiebreak; nil if none ---
(defun _odc-module-at (wpt recs / best best-d r d)
  (setq best nil best-d nil)
  (foreach r recs
    (if (and (>= (car wpt)  (nth 1 r)) (<= (car wpt)  (nth 3 r))
             (>= (cadr wpt) (nth 2 r)) (<= (cadr wpt) (nth 4 r)))
      (progn
        (setq d (distance wpt (list (nth 5 r) (nth 6 r) 0.0)))
        (if (or (null best-d) (< d best-d))
          (setq best r best-d d)))))
  best)

;; --- "Box filled" arrowhead: SOLID-filled square of edge sz, centered at cen,
;;     ALWAYS axis-aligned to WCS (sides parallel to X/Y). Direction is ignored
;;     so the square never rotates with a diagonal string endpoint. ---
(defun _odc-box-arrow (cen sz lname / h cx cy bl br tl tr)
  (setq h  (/ sz 2.0)
        cx (car cen)
        cy (cadr cen))
  (setq bl (list (- cx h) (- cy h) 0.0)
        br (list (+ cx h) (- cy h) 0.0)
        tl (list (- cx h) (+ cy h) 0.0)
        tr (list (+ cx h) (+ cy h) 0.0))
  (entmakex (list '(0 . "SOLID")
                  (cons 8 lname)
                  (cons 62 256)
                  (cons 10 bl)
                  (cons 11 br)
                  (cons 12 tl)
                  (cons 13 tr))))

;; ============================================================

(defun C:O-DC ( / old-err old-os old-ce lname mlayer recs prev hl pt wpt rec ent cen e
                  path n fc lc segs frec lrec plpts c s)

  (setq old-err *error*)
  (defun *error* (msg)
    (foreach e hl (redraw e 4))
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-DC error: " msg)))
    (princ))

  (setq old-os (getvar "OSMODE")
        old-ce (getvar "CMDECHO"))
  (setvar "OSMODE" 0)            ; OSNAP off per spec
  (setvar "CMDECHO" 0)

  (setq lname  (_odc-lname)
        mlayer (_odc-mlayer))
  (_odc-ensure-layer lname)

  (prompt (strcat "\nO-DC: scanning layer '" mlayer "' for modules..."))
  (setq recs (_odc-collect-modules mlayer))
  (if (null recs)
    (prompt (strcat " none found on '" mlayer "' -- check *ocfg-layer-modules*."))
    (progn
      (prompt (strcat " " (itoa (length recs))
                      " modules. Click INSIDE modules; Enter to finish."))
      (setq prev nil hl '() path '() segs '() frec nil lrec nil)
      (while (setq pt (if prev
                        (getpoint (trans prev 0 1) "\nNext module: ")
                        (getpoint "\nFirst module: ")))
        (setq wpt (trans pt 1 0)
              rec (_odc-module-at wpt recs))
        (if (null rec)
          (prompt "  -- not inside a module, ignored.")
          (progn
            (setq ent (car rec)
                  cen (list (nth 5 rec) (nth 6 rec) 0.0))
            (if (or (null prev) (> (distance prev cen) 1e-6))
              (progn
                (redraw ent 3)                     ; highlight node
                (setq hl (cons ent hl))
                (setq path (cons cen path))        ; ordered string path
                (if (null frec) (setq frec rec))   ; first picked module
                (setq lrec rec)                    ; last picked module
                (if prev
                  (setq segs
                    (cons (entmakex (list '(0 . "LINE")
                                          (cons 8 lname)
                                          (cons 62 256)
                                          (cons 10 prev)
                                          (cons 11 cen)))   ; live feedback segment
                          segs)))
                (setq prev cen))
              (prompt "  -- same module, ignored.")))))
      (foreach e hl (redraw e 4))                  ; clear highlights
      ;; --- join the segments into ONE open LWPOLYLINE through the centers ---
      (setq path (reverse path))
      (if (> (length path) 1)
        (progn
          (setq plpts '())
          (foreach c path
            (setq plpts (cons (cons 10 (list (car c) (cadr c))) plpts)))
          (setq plpts (reverse plpts))
          (entmakex (append (list '(0 . "LWPOLYLINE")
                                  '(100 . "AcDbEntity")
                                  (cons 8 lname)
                                  (cons 62 256)
                                  '(100 . "AcDbPolyline")
                                  (cons 90 (length path))
                                  '(70 . 0))
                            plpts))
          (foreach s segs (if s (entdel s)))))     ; drop the temp LINE segments
      ;; --- axis-aligned box arrowheads at first and last module of the string ---
      (if path
        (progn
          (setq n  (length path)
                fc (car path)
                lc (nth (1- n) path))
          (_odc-box-arrow fc (_odc-asize frec) lname)
          (if (> n 1)
            (_odc-box-arrow lc (_odc-asize lrec) lname))
          (prompt (strcat "\nO-DC: " (itoa n) " modules strung, "
                          (if (> n 1) "joined to 1 polyline, 2 box arrowheads"
                                      "1 box arrowhead") " placed."))))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (prompt "\nO-DC: done.")
  (princ))

(defun C:ODC      () (C:O-DC))
(defun C:O-STRING () (C:O-DC))
(defun C:OSTRING  () (C:O-DC))

(prompt "\nO-DC v1.22 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
