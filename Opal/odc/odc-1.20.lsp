;; odc-1.20 -- Feature add vs 1.10:
;;   (1) PV-DC-PATH layer now created (and existing one updated) with the
;;       deliverable default props:
;;         - linetype  "Dash Style-13"   (group 6)
;;         - lineweight 0.50mm           (group 370 = 50)
;;       Linetype is config-overridable via *ocfg-dc-linetype*; if it is not
;;       loaded in the drawing the layer falls back to CONTINUOUS + a warning
;;       (load the linetype once, then re-run O-DC to apply it).
;;   (2) "Box filled" arrowheads (SOLID-filled square, 0.18" / config
;;       *ocfg-dc-arrow-size*) placed at the FIRST and LAST module centers of
;;       the string after the click loop. ByLayer, oriented to the adjacent
;;       segment. A single-module string gets one box.
;;
;;   Carried over from 1.10:
;;   - Modules detected POSITIVELY by *ocfg-layer-modules* (default "MODULES")
;;     and "*POLYLINE" type (heavyweight POLYLINE VERTEX-walk AND LWPOLYLINE).
;;   - OCS->WCS via entity-name trans (trans pt ent 0).
;;   - Click INSIDE a module -> its center; outside any module -> ignored.
;;     Real LINE drawn immediately on the 2nd+ click. OSNAP off, restored on
;;     exit and on Esc.
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

;; --- DC layer linetype / lineweight / arrow size (config-overridable) ---
(defun _odc-ltname ()
  (if (and (boundp (quote *ocfg-dc-linetype*)) *ocfg-dc-linetype*)
    *ocfg-dc-linetype*
    "Dash Style-13"))
(defun _odc-lweight ()
  (if (and (boundp (quote *ocfg-dc-lineweight*)) *ocfg-dc-lineweight*)
    *ocfg-dc-lineweight*
    50))                                  ; hundredths of mm -> 50 = 0.50mm
(defun _odc-arrow-size ()
  (if (and (boundp (quote *ocfg-dc-arrow-size*)) *ocfg-dc-arrow-size*)
    *ocfg-dc-arrow-size*
    0.18))

;; --- ensure the DC linetype is loaded; return a usable linetype name ---
;; "Dash Style-13" is a custom linetype that should already live in the
;; drawing/template. If it is absent we do NOT try to -LINETYPE load (it is
;; not in any standard .lin and the prompt could hang the command); we warn
;; and fall back to CONTINUOUS so layer creation still succeeds.
(defun _odc-ensure-ltype (ltname)
  (if (tblsearch "LTYPE" ltname)
    ltname
    (progn
      (prompt (strcat "\nO-DC WARNING: linetype '" ltname
                      "' is not loaded -- PV-DC-PATH will use CONTINUOUS."
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
                    '(62 . 4)
                    (cons 6 ltname)
                    (cons 370 lw)))
    (progn
      ;; existing layer -> bring its props up to the deliverable default
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
  (if (and (getvar "LWDISPLAY") (= 0 (getvar "LWDISPLAY")))
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

;; --- "Box filled" arrowhead: SOLID-filled square of arrow-size, centered at
;;     cen, edges aligned to dir (a 2D direction vector; zero -> X axis) ---
(defun _odc-box-arrow (cen dir lname / sz h cx cy len ux uy vx vy bl br tl tr)
  (setq sz (_odc-arrow-size)
        h  (/ sz 2.0)
        cx (car cen)
        cy (cadr cen)
        len (sqrt (+ (* (car dir) (car dir)) (* (cadr dir) (cadr dir)))))
  (if (< len 1e-9)
    (setq ux 1.0 uy 0.0)
    (setq ux (/ (car dir) len) uy (/ (cadr dir) len)))
  (setq vx (- uy) vy ux)                          ; perpendicular
  (setq bl (list (- cx (* h ux) (* h vx)) (- cy (* h uy) (* h vy)) 0.0)
        br (list (+ cx (* h ux) (- (* h vx))) (+ cy (* h uy) (- (* h vy))) 0.0)
        tl (list (+ (- cx (* h ux)) (* h vx)) (+ (- cy (* h uy)) (* h vy)) 0.0)
        tr (list (+ cx (* h ux) (* h vx)) (+ cy (* h uy) (* h vy)) 0.0))
  (entmakex (list '(0 . "SOLID")
                  (cons 8 lname)
                  (cons 62 256)
                  (cons 10 bl)
                  (cons 11 br)
                  (cons 12 tl)
                  (cons 13 tr))))

;; ============================================================

(defun C:O-DC ( / old-err old-os old-ce lname mlayer recs prev hl pt wpt rec ent cen e
                  path n fc lc fdir ldir)

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
      (setq prev nil hl '() path '())
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
                (if prev
                  (entmakex (list '(0 . "LINE")
                                  (cons 8 lname)
                                  (cons 62 256)
                                  (cons 10 prev)
                                  (cons 11 cen))))  ; line visible immediately
                (setq prev cen))
              (prompt "  -- same module, ignored.")))))
      (foreach e hl (redraw e 4))                  ; clear highlights
      ;; --- box-filled arrowheads at first and last module of the string ---
      (setq path (reverse path))
      (if path
        (progn
          (setq n  (length path)
                fc (car path)
                lc (nth (1- n) path))
          (setq fdir (if (> n 1)
                       (list (- (car (nth 1 path)) (car fc))
                             (- (cadr (nth 1 path)) (cadr fc)))
                       (list 1.0 0.0)))
          (_odc-box-arrow fc fdir lname)
          (if (> n 1)
            (progn
              (setq ldir (list (- (car lc) (car (nth (- n 2) path)))
                               (- (cadr lc) (cadr (nth (- n 2) path)))))
              (_odc-box-arrow lc ldir lname)))
          (prompt (strcat "\nO-DC: " (itoa n) " modules strung, "
                          (if (> n 1) "2 box arrowheads" "1 box arrowhead") " placed."))))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (prompt "\nO-DC: done.")
  (princ))

(defun C:ODC      () (C:O-DC))
(defun C:O-STRING () (C:O-DC))
(defun C:OSTRING  () (C:O-DC))

(prompt "\nO-DC v1.20 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
