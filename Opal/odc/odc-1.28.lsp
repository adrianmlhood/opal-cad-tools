;; odc-1.28 -- Changes vs 1.27:
;;   RESTORE auto-centerpoint snap (the helpful bit 1.27 removed) -- but make it
;;   graceful so it can never break the command. At each click O-DC tries to snap
;;   the node to the center of the panel you clicked; if it can't, it uses the raw
;;   click point. Worst case == 1.27 (click-to-click), so this can't regress.
;;
;;   How it avoids the two failures we hit:
;;     - NO full-layer scan, NO layer-name dependency (v1.25 "none found on
;;       MODULES"). At each click we select only the polylines in a small box
;;       AROUND the click via (ssget "_C" ll ur ...) with two EXPLICIT corners --
;;       which, unlike the single-point (ssget pt), never drops into interactive
;;       "Specify opposite corner" mode (v1.26). Box size scales with the zoom
;;       (VIEWSIZE), so only entities near the click are considered -- fast, and
;;       no giant over-collection.
;;     - Among those candidates, pick the one whose bbox CONTAINS the click, with
;;       a nearest-center tiebreak -> that's the panel; snap to its center.
;;     - Every per-entity bbox is computed in a vl-catch-all-apply wrapper with
;;       numeric-validated vertex reads, so a malformed entity is SKIPPED, never
;;       a "numberp: nil" crash (v1.22-1.24). If nothing valid contains the
;;       click, fall back to the raw click point.
;;
;;   Output unchanged from 1.27: nodes join into one open LWPOLYLINE on
;;   *ocfg-layer-dc* (E-STRINGING); box arrowheads at first/last node oriented
;;   along the adjacent segment, auto-sized to that segment length.
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

;; --- is this VERTEX a real polyline corner? skip spline-frame / mesh vertices ---
(defun _odc-geom-vtx-p (vd / fl)
  (setq fl (cdr (assoc 70 vd)))
  (or (null fl)
      (and (= 0 (logand fl 16)) (= 0 (logand fl 64)) (= 0 (logand fl 128)))))

;; --- WCS corner points of an LWPOLYLINE or heavyweight POLYLINE.
;;     Numeric-validated: only points whose x AND y are numbers reach (trans). ---
(defun _odc-poly-pts (ent / ed et pts pr v vd raw)
  (setq ed (entget ent) et (cdr (assoc 0 ed)) pts '())
  (cond
    ((= et "LWPOLYLINE")
     (foreach pr ed
       (if (and (= (car pr) 10) (numberp (cadr pr)) (numberp (caddr pr)))
         (setq pts (cons (trans (list (cadr pr) (caddr pr) 0.0) ent 0) pts)))))
    ((= et "POLYLINE")
     (setq v (entnext ent))
     (while (and v (= (cdr (assoc 0 (setq vd (entget v)))) "VERTEX"))
       (setq raw (cdr (assoc 10 vd)))
       (if (and (_odc-geom-vtx-p vd)
                raw (numberp (car raw)) (numberp (cadr raw)))
         (setq pts (cons (trans (list (car raw) (cadr raw) 0.0) ent 0) pts)))
       (setq v (entnext v)))))
  pts)

;; --- WCS bbox (minx miny maxx maxy) from a poly's corners; nil if < 3 pts.
;;     Nil-safe min/max -- no nil can flow into a comparison. ---
(defun _odc-poly-bbox (ent / pts p xmin xmax ymin ymax)
  (setq pts (_odc-poly-pts ent))
  (if (>= (length pts) 3)
    (progn
      (foreach p pts
        (if (and (numberp (car p)) (numberp (cadr p)))
          (progn
            (if (or (null xmin) (< (car p) xmin)) (setq xmin (car p)))
            (if (or (null xmax) (> (car p) xmax)) (setq xmax (car p)))
            (if (or (null ymin) (< (cadr p) ymin)) (setq ymin (cadr p)))
            (if (or (null ymax) (> (cadr p) ymax)) (setq ymax (cadr p))))))
      (if (and xmin xmax ymin ymax) (list xmin ymin xmax ymax)))))

;; --- bbox of one entity, fully crash-proofed (catch-wrapped). nil on any failure. ---
(defun _odc-safe-bbox (ent / res)
  (setq res (vl-catch-all-apply (function (lambda () (_odc-poly-bbox ent)))))
  (if (vl-catch-all-error-p res) nil res))

;; --- polylines near a UCS click point (small crossing box scaled to the zoom).
;;     Two explicit corners -> never interactive. nil if none. ---
(defun _odc-candidates (pt / d ll ur)
  (setq d (/ (getvar "VIEWSIZE") 40.0))
  (if (or (null d) (<= d 1e-9)) (setq d 1.0))
  (setq ll (list (- (car pt) d) (- (cadr pt) d))
        ur (list (+ (car pt) d) (+ (cadr pt) d)))
  (ssget "_C" ll ur (list '(0 . "*POLYLINE"))))

;; --- center (WCS, z=0) of the panel under a UCS click, or nil if none found.
;;     Among nearby polylines whose bbox contains the click, nearest-center wins. ---
(defun _odc-snap-center (pt / wpt ss i e bb best bd cx cy d)
  (setq wpt (trans pt 1 0))
  (if (setq ss (_odc-candidates pt))
    (progn
      (setq i 0 best nil bd nil)
      (while (< i (sslength ss))
        (setq e (ssname ss i))
        (if (setq bb (_odc-safe-bbox e))
          (if (and (>= (car wpt)  (nth 0 bb)) (<= (car wpt)  (nth 2 bb))
                   (>= (cadr wpt) (nth 1 bb)) (<= (cadr wpt) (nth 3 bb)))
            (progn
              (setq cx (/ (+ (nth 0 bb) (nth 2 bb)) 2.0)
                    cy (/ (+ (nth 1 bb) (nth 3 bb)) 2.0)
                    d  (distance wpt (list cx cy 0.0)))
              (if (or (null bd) (< d bd)) (setq best (list cx cy 0.0) bd d)))))
        (setq i (1+ i)))))
  best)

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

(defun C:O-DC ( / old-err old-os old-ce lname prev pt snap wpt path segs
                  nsnap nraw n fc lc p1 pl plpts c s)

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

  (prompt "\nO-DC: click panels in order (snaps to panel center; Enter to finish).")
  (setq prev nil path '() segs '() nsnap 0 nraw 0)
  (while (setq pt (if prev
                    (getpoint (trans prev 0 1) "\nNext panel: ")
                    (getpoint "\nFirst panel: ")))
    (setq snap (_odc-snap-center pt)
          wpt  (if snap snap (trans pt 1 0)))
    (if snap (setq nsnap (1+ nsnap))
             (progn (setq nraw (1+ nraw))
                    (prompt "  -- no panel here, used click point.")))
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
      (prompt (strcat "\nO-DC: " (itoa n) " panels strung ("
                      (itoa nsnap) " centered, " (itoa nraw) " by click), "
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

(prompt "\nO-DC v1.28 loaded. Commands: O-DC / ODC / O-STRING / OSTRING")
(princ)
