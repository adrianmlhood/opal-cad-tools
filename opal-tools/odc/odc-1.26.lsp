;; odc-1.26 -- Changes vs 1.25:
;;   DROP the scan-a-layer model entirely. O-DC no longer pre-scans the module
;;   layer, builds a record list, or depends on *ocfg-layer-modules* / entity
;;   type. You click a panel; AutoCAD already knows what entity is under the
;;   cursor, so we pick THAT entity live and use its center as the string node.
;;
;;   Why: the layer scan was the real fragility. v1.22-1.24 crashed parsing
;;   module geometry by hand ("numberp: nil"); v1.25 reported "none found on
;;   'MODULES'" because the panels are not on that layer / it is named
;;   differently. Either way the command dead-ended before the user could click.
;;
;;   New per-click flow (same getpoint UX -- Enter finishes, a miss re-prompts):
;;     1. getpoint -> UCS point (nil on Enter = done)
;;     2. (ssget pt) at the raw UCS point -> entity under the click (nil = miss)
;;     3. node = that entity's bbox center via _odc-ent-bbox (vla-getBoundingBox)
;;     4. dedup consecutive picks by entity name (clicking same panel twice)
;;   Arrowheads still orient to the picked entity's edge via _odc-ent-dir.
;;
;;   Removed: _odc-collect-modules, _odc-module-at, _odc-mlayer, the scanning
;;   prompt and the "none found" branch. The only config O-DC still uses is the
;;   OUTPUT layer (*ocfg-layer-dc* = E-STRINGING), which is not a fragility point.
;;
;;   Carried over unchanged from 1.25: _odc-ent-bbox / _odc-ent-dir (VLA),
;;   layer/linetype/lineweight setup, live LINE feedback, LWPOLYLINE join,
;;   _odc-box-arrow, aliases, *error* handler.
;; ============================================================

(vl-load-com)

;; --- DC line layer (config-driven) ---
(defun _odc-lname ()
  (if (and (boundp (quote *ocfg-layer-dc*)) *ocfg-layer-dc*)
    *ocfg-layer-dc*
    "E-STRINGING"))

;; --- DC layer linetype / lineweight (config-overridable) ---
(defun _odc-ltname ()
  (if (and (boundp (quote *ocfg-dc-linetype*)) *ocfg-dc-linetype*)
    *ocfg-dc-linetype*
    "Dash Style-13"))
(defun _odc-lweight ()
  (if (and (boundp (quote *ocfg-dc-lineweight*)) *ocfg-dc-lineweight*)
    *ocfg-dc-lineweight*
    50))                                  ; hundredths of mm -> 50 = 0.50mm

;; --- box arrowhead edge length for a bbox (minx miny maxx maxy) ---
;; 0.22 × short-side ≈ 17" at typical 77"-wide panel.
(defun _odc-asize (bb / w h s)
  (if (and (boundp (quote *ocfg-dc-arrow-size*)) *ocfg-dc-arrow-size* (> *ocfg-dc-arrow-size* 0))
    *ocfg-dc-arrow-size*
    (progn
      (setq w (- (nth 2 bb) (nth 0 bb))
            h (- (nth 3 bb) (nth 1 bb))
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

;; --- bbox center as a WCS point (x y 0) ---
(defun _odc-bbox-center (bb)
  (list (/ (+ (nth 0 bb) (nth 2 bb)) 2.0)
        (/ (+ (nth 1 bb) (nth 3 bb)) 2.0)
        0.0))

;; --- module edge direction (normalized 2D WCS vector) from the curve API.
;;     param 0 -> param 1 is the entity's first edge. Falls back to (1 0) on
;;     any error or degenerate edge (e.g. a non-curve entity). ---
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

;; --- entity under a point pick; nil if nothing there. pt is a raw UCS point
;;     (ssget point args use UCS). Returns the topmost entity at the point. ---
(defun _odc-pick-ent (pt / ss)
  (if (setq ss (ssget pt))
    (ssname ss 0)))

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

;; --- "Box filled" arrowhead: SOLID-filled square of edge sz, centered at cen,
;;     sides oriented along dir (entity edge direction vector). ---
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

(defun C:O-DC ( / old-err old-os old-ce lname prev hl pt ent bb cen e
                  path n fc lc segs fent lent prev-ent plpts c s)

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

  (setq lname (_odc-lname))
  (_odc-ensure-layer lname)

  (prompt "\nO-DC: click panels to string (Enter to finish).")
  (setq prev nil prev-ent nil hl '() path '() segs '() fent nil lent nil)
  (while (setq pt (if prev
                    (getpoint (trans prev 0 1) "\nNext panel: ")
                    (getpoint "\nFirst panel: ")))
    (setq ent (_odc-pick-ent pt))
    (cond
      ((null ent)
       (prompt "  -- nothing there, ignored."))
      ((eq ent prev-ent)
       (prompt "  -- same panel, ignored."))
      ((null (setq bb (_odc-ent-bbox ent)))
       (prompt "  -- can't measure that entity, ignored."))
      (T
       (setq cen (_odc-bbox-center bb))
       (redraw ent 3)
       (setq hl (cons ent hl))
       (setq path (cons cen path))
       (if (null fent) (setq fent ent))
       (setq lent ent)
       (if prev
         (setq segs
           (cons (entmakex (list '(0 . "LINE")
                                 (cons 8 lname)
                                 (cons 62 256)
                                 (cons 10 prev)
                                 (cons 11 cen)))
                 segs)))
       (setq prev cen prev-ent ent))))
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
  ;; --- arrowheads oriented to panel edge, not string direction ---
  (if path
    (progn
      (setq n  (length path)
            fc (car path)
            lc (nth (1- n) path))
      (_odc-box-arrow fc (_odc-ent-dir fent) (_odc-asize (_odc-ent-bbox fent)) lname)
      (if (> n 1)
        (_odc-box-arrow lc (_odc-ent-dir lent) (_odc-asize (_odc-ent-bbox lent)) lname))
      (prompt (strcat "\nO-DC: " (itoa n) " panels strung, "
                      (if (> n 1) "joined to 1 polyline, 2 box arrowheads"
                                  "1 box arrowhead") " placed."))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (prompt "\nO-DC: done.")
  (princ))

(defun C:ODC      () (C:O-DC))
(defun C:O-STRING () (C:O-DC))
(defun C:OSTRING  () (C:O-DC))

(prompt "\nO-DC v1.26 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
