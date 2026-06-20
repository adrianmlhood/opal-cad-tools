;; odc-1.25 -- Changes vs 1.24:
;;   SIMPLIFY + make module scanning flexible/robust. Stop parsing module
;;   geometry by hand and let AutoCAD compute it.
;;
;;   Background: v1.22-1.24 read each module by walking heavyweight-POLYLINE
;;   VERTEX sub-entities, pulling raw group-10 codes, running OCS->WCS trans,
;;   and computing min/max by hand. That manual pipeline kept producing
;;   "bad argument type: numberp: nil" on real drawings (a corner with a nil
;;   coordinate reaching _odc-list-min/max). v1.24's defensive guards did not
;;   stop it -- there is a vertex/entity shape the hand parser still can't
;;   survive, and it is not reproducible without the drawing.
;;
;;   Fix: AutoCAD-native geometry via VLA.
;;     - _odc-ent-bbox : vla-getBoundingBox -> WCS axis-aligned bbox of ANY
;;       entity type (heavyweight POLYLINE, LWPOLYLINE, ...). No group codes,
;;       no OCS math, no custom min/max.
;;     - _odc-ent-dir  : vlax-curve-getPointAtParam 0->1 -> module first-edge
;;       direction for arrowhead orientation (same vector the old _odc-mod-dir
;;       produced).
;;   Both wrapped in vl-catch-all-apply: a single unmeasurable entity is
;;   SKIPPED, never fatal. (vl-load-com is already loaded by oload; idiom
;;   matches ocondsched-1.0.) Removed: _odc-poly-pts, _odc-poly-bbox,
;;   _odc-mod-dir, _odc-geom-vertex-p, _odc-list-min, _odc-list-max.
;;
;;   Carried over unchanged from 1.24: layer/linetype/lineweight setup, the
;;   pick loop, live LINE feedback, LWPOLYLINE join, _odc-box-arrow, aliases.
;; ============================================================

(vl-load-com)

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
;; 0.22 × short-side ≈ 17" at typical 77"-wide module.
(defun _odc-asize (rec / w h s)
  (if (and (boundp (quote *ocfg-dc-arrow-size*)) *ocfg-dc-arrow-size* (> *ocfg-dc-arrow-size* 0))
    *ocfg-dc-arrow-size*
    (progn
      (setq w (- (nth 3 rec) (nth 1 rec))
            h (- (nth 4 rec) (nth 2 rec))
            s (if (< w h) w h))
      (* 0.22 s))))

;; --- WCS axis-aligned bbox of ANY entity, via AutoCAD's native getBoundingBox.
;;     Returns (minx miny maxx maxy) or nil if the entity can't be measured.
;;     No group-code / OCS / vertex-walk handling -- AutoCAD does the geometry. ---
(defun _odc-ent-bbox (ent / res obj mn mx)
  (setq res (vl-catch-all-apply
              (function (lambda ()
                (setq obj (vlax-ename->vla-object ent))
                (vla-getBoundingBox obj 'mn 'mx)
                (setq mn (vlax-safearray->list (vlax-variant-value mn))
                      mx (vlax-safearray->list (vlax-variant-value mx)))
                (list (car mn) (cadr mn) (car mx) (cadr mx))))))
  (if (vl-catch-all-error-p res) nil res))

;; --- module edge direction (normalized 2D WCS vector) from the curve API.
;;     param 0 -> param 1 is the module's first edge. Falls back to (1 0) on
;;     any error or degenerate edge. ---
(defun _odc-ent-dir (ent / res p0 p1 dx dy len)
  (setq res (vl-catch-all-apply
              (function (lambda ()
                (setq p0  (vlax-curve-getPointAtParam ent 0.0)
                      p1  (vlax-curve-getPointAtParam ent 1.0)
                      dx  (- (car p1)  (car p0))
                      dy  (- (cadr p1) (cadr p0))
                      len (sqrt (+ (* dx dx) (* dy dy))))
                (if (> len 1e-9) (list (/ dx len) (/ dy len)) (list 1.0 0.0))))))
  (if (vl-catch-all-error-p res) (list 1.0 0.0) res))

;; --- ensure the DC linetype is loaded; return a usable linetype name ---
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
                    '(62 . 7)
                    (cons 6 ltname)
                    (cons 370 lw)))
    (progn
      (_odc-set-layer-prop lname 62 7)
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
  (if (= 0 (getvar "LWDISPLAY"))
    (prompt "\nO-DC note: LWDISPLAY is OFF -- the 0.50mm lineweight won't show until you turn it on (LWDISPLAY 1).")))

;; --- collect module records once: (ent minx miny maxx maxy cx cy) ---
;; Positive filter: "*POLYLINE" (POLYLINE or LWPOLYLINE) ON the module layer only.
;; Each entity's bbox comes from AutoCAD (_odc-ent-bbox); unmeasurable ones are skipped.
(defun _odc-collect-modules (mlayer / ss i e bb recs)
  (setq recs '())
  (setq ss (ssget "X" (list '(0 . "*POLYLINE") (cons 8 mlayer))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (if (setq bb (_odc-ent-bbox e))
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
;;     sides oriented along dir (module edge direction vector). ---
(defun _odc-box-arrow (cen dir sz lname / h cx cy len ux uy vx vy bl br tl tr)
  (setq h  (/ sz 2.0)
        cx (car cen)
        cy (cadr cen)
        len (sqrt (+ (* (car dir) (car dir)) (* (cadr dir) (cadr dir)))))
  (if (< len 1e-9)
    (setq ux 1.0 uy 0.0)
    (setq ux (/ (car dir) len) uy (/ (cadr dir) len)))
  (setq vx (- uy) vy ux)
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
  (setvar "OSMODE" 0)
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
                (redraw ent 3)
                (setq hl (cons ent hl))
                (setq path (cons cen path))
                (if (null frec) (setq frec rec))
                (setq lrec rec)
                (if prev
                  (setq segs
                    (cons (entmakex (list '(0 . "LINE")
                                          (cons 8 lname)
                                          (cons 62 256)
                                          (cons 10 prev)
                                          (cons 11 cen)))
                          segs)))
                (setq prev cen))
              (prompt "  -- same module, ignored.")))))
      (foreach e hl (redraw e 4))
      ;; --- join segments into one LWPOLYLINE ---
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
          (foreach s segs (if s (entdel s)))))
      ;; --- arrowheads oriented to module edge, not string direction ---
      (if path
        (progn
          (setq n  (length path)
                fc (car path)
                lc (nth (1- n) path))
          (_odc-box-arrow fc (_odc-ent-dir (car frec)) (_odc-asize frec) lname)
          (if (> n 1)
            (_odc-box-arrow lc (_odc-ent-dir (car lrec)) (_odc-asize lrec) lname))
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

(prompt "\nO-DC v1.25 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
