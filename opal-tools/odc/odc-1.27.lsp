;; odc-1.27 -- Changes vs 1.26:
;;   PURE CLICK-TO-CLICK. O-DC no longer identifies the panel entity at all --
;;   no ssget, no entsel, no vla-getBoundingBox, no layer, no COM. Each click
;;   drops a node at that point; the nodes are joined into the string. "I show
;;   it where" -- the clicks ARE the data.
;;
;;   Why: v1.26 used (ssget pt) to grab the entity under the click. On a real
;;   sheet that dropped into interactive window-select ("Specify opposite
;;   corner...") and then "can't measure that entity" when it grabbed a
;;   viewport/titleblock. Deeper problem: a closed UNFILLED polyline (the panel)
;;   is NOT selectable by clicking its interior -- only its edge -- so neither
;;   ssget-at-point nor entsel supports "click inside the panel". The old
;;   click-inside behavior only worked via a pre-scanned bbox containment test,
;;   which is exactly the layer-scan fragility we removed. Connecting the raw
;;   click points needs none of that and cannot throw.
;;
;;   Behavior:
;;     - getpoint loop, rubber-band from the previous node, Enter finishes.
;;     - Each click -> a node (WCS). Consecutive identical points are ignored.
;;     - Nodes join into one open LWPOLYLINE on the DC layer (*ocfg-layer-dc*).
;;     - Box arrowheads at the first/last node, oriented along the adjacent
;;       segment, auto-sized to that segment length (≈ panel pitch).
;;       *ocfg-dc-arrow-size* (>0) overrides the size.
;;
;;   Tradeoff vs the old tool: lines pass through your click points, not a
;;   computed panel center. Click near panel centers and it reads clean. An
;;   optional "snap each click to a panel center" can be added later WITHOUT
;;   reintroducing a layer scan if desired.
;;
;;   Carried over: layer/linetype/lineweight setup, live LINE feedback,
;;   LWPOLYLINE join, _odc-box-arrow, aliases, *error* handler.
;; ============================================================

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

;; --- normalized 2D direction from point a to point b; (1 0) if degenerate ---
(defun _odc-dir (a b / dx dy len)
  (setq dx  (- (car b)  (car a))
        dy  (- (cadr b) (cadr a))
        len (sqrt (+ (* dx dx) (* dy dy))))
  (if (> len 1e-9) (list (/ dx len) (/ dy len)) (list 1.0 0.0)))

;; --- arrowhead edge length: *ocfg-dc-arrow-size* (>0) wins; else 0.2 x the
;;     adjacent segment length (≈ panel pitch); else a 12-unit fallback. ---
(defun _odc-asize-len (seglen)
  (cond
    ((and (boundp (quote *ocfg-dc-arrow-size*)) *ocfg-dc-arrow-size* (> *ocfg-dc-arrow-size* 0))
     *ocfg-dc-arrow-size*)
    ((> seglen 1e-6) (* 0.2 seglen))
    (T 12.0)))

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
;;     sides oriented along dir. ---
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

(defun C:O-DC ( / old-err old-os old-ce lname prev pt wpt path segs
                  n fc lc p1 pl plpts c s)

  (setq old-err *error*)
  (defun *error* (msg)
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

  (prompt "\nO-DC: click panels in order to string them (Enter to finish).")
  (setq prev nil path '() segs '())
  (while (setq pt (if prev
                    (getpoint (trans prev 0 1) "\nNext panel: ")
                    (getpoint "\nFirst panel: ")))
    (setq wpt (trans pt 1 0))
    (if (and prev (<= (distance prev wpt) 1e-6))
      (prompt "  -- same point, ignored.")
      (progn
        (setq path (cons wpt path))
        (if prev
          (setq segs
            (cons (entmakex (list '(0 . "LINE")
                                  (cons 8 lname)
                                  (cons 62 256)
                                  (cons 10 prev)
                                  (cons 11 wpt)))
                  segs)))
        (setq prev wpt))))
  ;; --- join nodes into one open LWPOLYLINE ---
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
  ;; --- box arrowheads at the first/last node, oriented along the end segment ---
  (if path
    (progn
      (setq n  (length path)
            fc (car path)
            lc (nth (1- n) path))
      (if (> n 1)
        (progn
          (setq p1 (cadr path)
                pl (nth (- n 2) path))
          (_odc-box-arrow fc (_odc-dir fc p1) (_odc-asize-len (distance fc p1)) lname)
          (_odc-box-arrow lc (_odc-dir pl lc) (_odc-asize-len (distance pl lc)) lname))
        (_odc-box-arrow fc (list 1.0 0.0) (_odc-asize-len 0.0) lname))
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

(prompt "\nO-DC v1.27 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
