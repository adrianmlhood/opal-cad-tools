;; odc-1.10 -- Fixes vs 1.09:
;;   (1) Detect modules POSITIVELY by the configured module layer
;;       (*ocfg-layer-modules*, default "PV-MODULES LAYOUT") instead of a
;;       denylist. The denylist matched ~10k non-module polylines
;;       (structure / annotation / dimensions) and clicks landed inside
;;       huge ones -> centers far off-screen, lines drawn in the void,
;;       repeat clicks reused the same giant -> no new lines.
;;   (2) OCS->WCS via entity-name trans (trans pt ent 0) -- unambiguous
;;       regardless of extrusion (replaces the integer "(trans pt 2 0)").
;;   Lines go on *ocfg-layer-dc* (PV-DC-PATH), auto-created if absent.
;;   Click INSIDE a module -> its center; outside any module -> ignored.
;;   Real LINE drawn immediately on the 2nd+ click. OSNAP off, restored
;;   on exit and on Esc.
;; ============================================================

;; --- small list helpers (self-contained) ---
(defun _odc-list-min (lst / v r) (setq r (car lst)) (foreach v (cdr lst) (if (< v r) (setq r v))) r)
(defun _odc-list-max (lst / v r) (setq r (car lst)) (foreach v (cdr lst) (if (> v r) (setq r v))) r)

;; --- DC line layer (config-driven) ---
(defun _odc-lname ()
  (if (and (boundp (quote *ocfg-layer-dc*)) *ocfg-layer-dc*)
    *ocfg-layer-dc*
    "PV-DC-PATH"))

;; --- module source layer (config-driven) ---
(defun _odc-mlayer ()
  (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
    *ocfg-layer-modules*
    "MODULES"))

;; --- ensure the DC line layer exists; warn if it would hide the lines ---
(defun _odc-ensure-layer (lname / rec flags clr)
  (if (not (tblsearch "LAYER" lname))
    (entmakex (list '(0 . "LAYER")
                    '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 lname)
                    '(70 . 0)
                    '(62 . 4)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblsearch "LAYER" lname)
            flags (cdr (assoc 70 rec))
            clr   (cdr (assoc 62 rec)))
      (cond
        ((and flags (= (logand flags 1) 1))
         (prompt (strcat "\nO-DC WARNING: layer '" lname "' is FROZEN -- thaw it to see lines.")))
        ((and clr (< clr 0))
         (prompt (strcat "\nO-DC WARNING: layer '" lname "' is OFF -- turn it on to see lines.")))))))

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

;; ============================================================

(defun C:O-DC ( / old-err old-os old-ce lname mlayer recs prev hl pt wpt rec ent cen e)

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
      (setq prev nil hl '())
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
            (redraw ent 3)                      ; highlight node
            (setq hl (cons ent hl))
            (if (and prev (> (distance prev cen) 1e-6))
              (entmakex (list '(0 . "LINE")
                              (cons 8 lname)
                              (cons 62 256)
                              (cons 10 prev)
                              (cons 11 cen))))   ; line visible immediately
            (setq prev cen))))
      (foreach e hl (redraw e 4))))             ; clear highlights

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (prompt "\nO-DC: done.")
  (princ))

(defun C:ODC      () (C:O-DC))
(defun C:O-STRING () (C:O-DC))
(defun C:OSTRING  () (C:O-DC))

(prompt "\nO-DC v1.10 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
