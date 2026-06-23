;; ogeo-1.04.lsp -- O-Suite shared geometry library  (no command; defines _ogeo-* only)
;;
;; One home for the module-reading + array-detection + spacing-pattern math shared by
;; O-GRID and O-MODSPACE (and reusable by the future XDATA-IR port). Loaded as a normal
;; tool; callers invoke _ogeo-* at command runtime (after O-LOAD has loaded everything),
;; so load order is irrelevant. Config globals (*ocfg-modules* / *ocfg-patterns*) are
;; parsed by oconfig (loads first); this lib consumes them.
;;
;; Module record (the unit every consumer uses):
;;   (ent typ center ushort ulong short long nverts)
;;     center = WCS (x y) centroid;  ushort/ulong = unit vectors along the short/long edge;
;;     short/long = edge lengths;  nverts = geometry-vertex count.
;;
;; CHANGES vs 1.0
;;   - _ogeo-all-modules: graceful layer fallback. Try the configured module layer first;
;;     if it finds nothing, scan ALL layers and keep only module-SHAPED polylines (4-corner,
;;     footprint within tol of a *ocfg-modules* entry). Shape-gated, NOT a denylist.
;;   - _ogeo-pick-pattern: shared config-pattern picker (lifted from ogrid's _ogrid-pick-pattern).
;;   - _ogeo-axis-groups: cluster a record list along a unit axis into ordered groups (the
;;     row/column grouping primitive used by O-MODSPACE for either axis).
;;   - _ogeo-move: locked-safe vla-move of one entity (shared; was orespace's _ors-move).
;; v1.01
;; CHANGES vs 1.01
;;   - _ogeo-all-modules now ends with a VIEWPORT-VISIBILITY filter (_ogeo-filter-shown):
;;     module-shaped objects NOT shown inside any layout viewport are ignored (template
;;     copies parked in model space, cutsheet/detail geometry). Locks every tool onto the
;;     ONE documented concentration of modules. Safe by design: no viewports in the drawing,
;;     or a filter that would drop ALL modules, falls back to keeping everything. Gated by
;;     *ocfg-filter-viewport* (oconfig, default T). Plan-view, non-paper-background, twist-
;;     aware rectangular windows; clipped/3D viewports are treated permissively (kept).
;; v1.02
;; CHANGES vs 1.02
;;   - _ogeo-real-modules (recs): the single home for "what counts as a module". Keeps only
;;     records matching the dominant (modal) footprint -- the "real modules" O-SET counts --
;;     so clutter on the module layer (mismatched footprints, half panels, frames) is dropped.
;;     Mirrors oset's _oset-match-mods tolerances; orientation-agnostic; returns recs unchanged
;;     if the footprint is indeterminate. Referenced by SSM and ZZA.
;; v1.03
;; CHANGES vs 1.03
;;   - _ogeo-modules: the ONE high-level entry for "the real modules in the drawing" --
;;     composes _ogeo-all-modules (scan + viewport filter) with _ogeo-real-modules (footprint
;;     gate). SSM / ZZA / QQA all call this instead of repeating the two-step inline, so the
;;     definition of the working module set lives in exactly one place.
;; v1.04
;; ============================================================

(vl-load-com)

;; ---- small vector helpers ----
(defun _ogeo-sum  (l / v r) (setq r 0.0) (foreach v l (setq r (+ r v))) r)
(defun _ogeo-sub  (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun _ogeo-len  (a)   (sqrt (+ (* (car a) (car a)) (* (cadr a) (cadr a)))))
(defun _ogeo-unit (a / l) (setq l (_ogeo-len a)) (if (> l 1e-9) (list (/ (car a) l) (/ (cadr a) l)) (list 1.0 0.0)))
(defun _ogeo-dot  (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

;; ---- module reader (dual-path: heavyweight POLYLINE VERTEX walk + LWPOLYLINE) ----
(defun _ogeo-geom-vtx-p (vd / fl)
  (setq fl (cdr (assoc 70 vd)))
  (or (null fl)
      (and (= 0 (logand fl 16)) (= 0 (logand fl 64)) (= 0 (logand fl 128)))))

(defun _ogeo-poly-pts (ent / ed typ pts pr sub sd raw)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)) pts nil)
  (cond
    ((= typ "LWPOLYLINE")
     (foreach pr ed
       (if (and (= (car pr) 10) (numberp (cadr pr)) (numberp (caddr pr)))
         (setq pts (cons (trans (list (cadr pr) (caddr pr) 0.0) ent 0) pts)))))
    ((= typ "POLYLINE")
     (setq sub (entnext ent))
     (while (and sub (= (cdr (assoc 0 (setq sd (entget sub)))) "VERTEX"))
       (setq raw (cdr (assoc 10 sd)))
       (if (and (_ogeo-geom-vtx-p sd) raw (numberp (car raw)) (numberp (cadr raw)))
         (setq pts (cons (trans (list (car raw) (cadr raw) 0.0) ent 0) pts)))
       (setq sub (entnext sub)))))
  (reverse pts))

(defun _ogeo-pt-ok (p) (and (listp p) (numberp (car p)) (numberp (cadr p))))

;; -> (ent typ center ushort ulong short long nverts) or nil
(defun _ogeo-rec (ent / pts typ p0 p1 p3 e1 e2 l1 l2 xs ys cen)
  (setq pts (_ogeo-poly-pts ent) typ (cdr (assoc 0 (entget ent))))
  (if (< (length pts) 4)
    nil
    (progn
      (setq p0 (nth 0 pts) p1 (nth 1 pts) p3 (nth 3 pts))
      (if (not (and (_ogeo-pt-ok p0) (_ogeo-pt-ok p1) (_ogeo-pt-ok p3)))
        nil
        (progn
          (setq xs  (list (car p0) (car p1) (car (nth 2 pts)) (car p3))
                ys  (list (cadr p0) (cadr p1) (cadr (nth 2 pts)) (cadr p3))
                cen (list (/ (_ogeo-sum xs) 4.0) (/ (_ogeo-sum ys) 4.0))
                e1  (_ogeo-sub p1 p0) e2 (_ogeo-sub p3 p0)
                l1  (_ogeo-len e1)    l2 (_ogeo-len e2))
          (if (<= l1 l2)
            (list ent typ cen (_ogeo-unit e1) (_ogeo-unit e2) l1 l2 (length pts))
            (list ent typ cen (_ogeo-unit e2) (_ogeo-unit e1) l2 l1 (length pts))))))))

;; build records from a selection set, skipping any entity that errors
(defun _ogeo-recs-from (ss / i ent r lst)
  (setq i 0 lst nil)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          r (vl-catch-all-apply (function _ogeo-rec) (list ent)))
    (if (and (not (vl-catch-all-error-p r)) r) (setq lst (cons r lst)))
    (setq i (1+ i)))
  lst)

;; is REC a module-shaped record? 4-corner AND footprint within tol of a config module.
;; Used by the all-layer fallback so we never over-collect (no denylist).
(defun _ogeo-shape-match-p (rec / s l hit cs cl m)
  (if (and (= (nth 7 rec) 4) (boundp (quote *ocfg-modules*)) *ocfg-modules*)
    (progn
      (setq s (nth 5 rec) l (nth 6 rec) hit nil)
      (foreach m *ocfg-modules*
        (setq cs (nth 1 m) cl (nth 2 m))
        (if (and (<= (abs (- cs s)) 2.0) (<= (abs (- cl l)) 3.0)) (setq hit T)))
      hit)
    nil))

;; ---- viewport-visibility filter ----------------------------------------------------
;; A real module is shown inside a layout viewport. Module-shaped objects that no sheet
;; viewport frames (template copies parked in model space, cutsheet/detail geometry) are
;; ignored, so every tool locks onto the ONE documented concentration of modules.

;; Model-space view windows of all usable layout viewports. Each window:
;;   (cx cy hw hh cs sn)  -- WCS view centre, half-width, half-height (MS units),
;;                           cos/sin of the view twist. Plan-view, non-paper-background
;;                           (DXF id 1 skipped) viewports only. nil if none.
;; Geometry comes from the VLA AcadPViewport properties (ViewCenter/ViewHeight/Width/
;; Height/TwistAngle) -- documented in model-space terms, unlike the DCS-relative raw DXF.
(defun _ogeo-vp-windows ( / ss i en vp id dir r out)
  (setq ss (ssget "X" (list (quote (0 . "VIEWPORT")))) out nil)
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (setq en (ssname ss i) vp (entget en) i (1+ i)
              id (cdr (assoc 69 vp)) dir (cdr (assoc 16 vp)))
        (if (and (/= 1 id)                                ; skip paper-background vp (id 1)
                 (or (null dir)                            ; plan view only
                     (and (< (abs (car dir)) 1e-6) (< (abs (cadr dir)) 1e-6))))
          (progn
            (setq r (vl-catch-all-apply
                      (function (lambda ( / o vc vh pw ph tw)
                        (setq o  (vlax-ename->vla-object en)
                              vc (vlax-safearray->list
                                   (vlax-variant-value (vla-get-ViewCenter o)))
                              vh (vla-get-ViewHeight o)
                              pw (vla-get-Width o)
                              ph (vla-get-Height o)
                              tw (vla-get-TwistAngle o))
                        (if (and vh (> vh 0.0) ph (> ph 1e-9))
                          (list (car vc) (cadr vc) (* 0.5 pw (/ vh ph)) (* 0.5 vh)
                                (cos tw) (sin tw)))))))
            (if (and (not (vl-catch-all-error-p r)) r) (setq out (cons r out))))))
      out)
    nil))

;; is WCS point P inside any view window (twist-aware)?
(defun _ogeo-pt-shown-p (p wins / hit w dx dy rx ry)
  (setq hit nil)
  (foreach w wins
    (if (not hit)
      (progn
        (setq dx (- (car p) (car w)) dy (- (cadr p) (cadr w))
              rx (+ (* dx (nth 4 w)) (* dy (nth 5 w)))     ; rotate delta by -twist
              ry (- (* dy (nth 4 w)) (* dx (nth 5 w))))
        (if (and (<= (abs rx) (nth 2 w)) (<= (abs ry) (nth 3 w))) (setq hit T)))))
  hit)

;; drop records whose centre is not shown in any viewport. Safe: filter off, no viewports,
;; or a filter that would drop EVERYTHING -> keep all (never strand real modules). Reports.
(defun _ogeo-filter-shown (recs / wins kept dropped r)
  (if (and recs
           (or (not (boundp (quote *ocfg-filter-viewport*))) *ocfg-filter-viewport*)
           (setq wins (_ogeo-vp-windows)))
    (progn
      (setq kept nil dropped 0)
      (foreach r recs
        (if (_ogeo-pt-shown-p (nth 2 r) wins)
          (setq kept (cons r kept))
          (setq dropped (1+ dropped))))
      (cond
        ((null kept)                                       ; would drop all -> keep all
         (prompt "\n  [modules] viewport filter would drop ALL -- keeping all (check sheet viewports).")
         recs)
        ((> dropped 0)
         (prompt (strcat "\n  [modules] ignored " (itoa dropped)
                         " outlier(s) not shown in any layout viewport."))
         (reverse kept))
        (T recs)))
    recs))

;; select module polylines -> records. Try the configured module layer first; if that
;; finds nothing, fall back to a shape-gated scan of ALL layers (graceful degradation,
;; so a tool never dead-ends just because the layer was renamed). Then ignore objects not
;; shown in any layout viewport. Prints which path won + any outliers ignored.
(defun _ogeo-all-modules ( / ml ss recs all r kept base)
  (setq ml (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
             *ocfg-layer-modules* nil))
  (setq ss (ssget "X" (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml))
                                (list (quote (0 . "*POLYLINE"))))))
  (setq recs (if ss (_ogeo-recs-from ss) nil))
  (if recs
    (progn
      (prompt (strcat "\n  [modules] " (itoa (length recs)) " on layer "
                      (if ml ml "*") "."))
      (setq base recs))
    (progn
      (setq all (ssget "X" (list (quote (0 . "*POLYLINE")))) kept nil)
      (setq recs (if all (_ogeo-recs-from all) nil))
      (foreach r recs (if (_ogeo-shape-match-p r) (setq kept (cons r kept))))
      (if kept
        (prompt (strcat "\n  [modules] layer " (if ml ml "(none)")
                        " empty -- fell back to " (itoa (length kept))
                        " module-shaped polylines across all layers."))
        (prompt "\n  [modules] none found (layer empty; no module-shaped polylines)."))
      (setq base kept)))
  (_ogeo-filter-shown base))

;; ---- modal footprint + module-dims resolution ----
(defun _ogeo-round (v bin) (* bin (fix (+ 0.5 (/ v bin)))))
(defun _ogeo-mode (vals bin / tbl best bestc cell k sum n q)
  (setq tbl nil)
  (foreach v vals
    (setq k (_ogeo-round v bin) cell (assoc k tbl))
    (if cell (setq tbl (subst (cons k (1+ (cdr cell))) cell tbl))
             (setq tbl (cons (cons k 1) tbl))))
  (setq best nil bestc -1)
  (foreach cell tbl (if (> (cdr cell) bestc) (setq best (car cell) bestc (cdr cell))))
  (if (null best) nil
    (progn (setq sum 0.0 n 0)
      (foreach q vals (if (<= (abs (- q best)) bin) (setq sum (+ sum q) n (1+ n))))
      (if (> n 0) (/ sum n) best))))

;; dominant (short long) over a record list
(defun _ogeo-dominant (recs / ss ls r)
  (setq ss nil ls nil)
  (foreach r recs (setq ss (cons (nth 5 r) ss) ls (cons (nth 6 r) ls)))
  (list (_ogeo-mode ss 0.5) (_ogeo-mode ls 0.5)))

;; Keep only records matching the dominant (modal) footprint -- the "real modules"
;; O-SET counts -- so clutter on the module layer (mismatched footprints, half panels,
;; shorter frames) is dropped. The single home for "what counts as a module"; used by
;; SSM and ZZA. Mirrors oset's _oset-match-mods tolerances: the LONG side (panel length)
;; is matched TIGHTLY (the stable dimension that separates real modules from shorter
;; clutter), the SHORT side gets more slack. Orientation-agnostic (record short=nth 5,
;; long=nth 6 are already min/max-ordered by _ogeo-rec). Returns RECS unchanged if the
;; dominant footprint is indeterminate (never strands real modules).
(defun _ogeo-real-modules (recs / dom mshort mlong tol-s tol-l out r rs rl)
  (setq dom (_ogeo-dominant recs) mshort (car dom) mlong (cadr dom))
  (if (and recs mshort mlong)
    (progn
      (setq tol-s (max 4.0 (* 0.10 mshort))
            tol-l (max 2.0 (* 0.02 mlong))
            out   nil)
      (foreach r recs
        (setq rs (min (nth 5 r) (nth 6 r))
              rl (max (nth 5 r) (nth 6 r)))
        (if (and (<= (abs (- rl mlong))  tol-l)
                 (<= (abs (- rs mshort)) tol-s))
          (setq out (cons r out))))
      (reverse out))
    recs))

;; THE high-level entry: the real modules in the drawing. Composes the raw scan
;; (_ogeo-all-modules: layer + graceful fallback + viewport filter) with the footprint gate
;; (_ogeo-real-modules). Tools that want "the modules" call THIS -- one definition of the
;; working set, shared by SSM, ZZA, QQA (and any future module-wide tool).
(defun _ogeo-modules ( / )
  (_ogeo-real-modules (_ogeo-all-modules)))

;; resolve module dims: nearest *ocfg-modules* entry to the detected dominant
;; (snap to canonical), else the dominant itself. Returns (short long within-gap).
(defun _ogeo-module-dims (recs / dom ds dl best bestd m cs cl cg d)
  (setq dom (_ogeo-dominant recs) ds (car dom) dl (cadr dom) best nil bestd nil)
  (if (and (boundp (quote *ocfg-modules*)) *ocfg-modules* ds dl)
    (foreach m *ocfg-modules*
      (setq cs (nth 1 m) cl (nth 2 m) cg (nth 3 m)
            d  (+ (abs (- cs ds)) (abs (- cl dl))))
      (if (and (<= (abs (- cs ds)) 2.0) (<= (abs (- cl dl)) 3.0)
               (or (null bestd) (< d bestd)))
        (setq best (list cs cl (if cg cg 0.25)) bestd d))))
  (cond (best best)
        ((and ds dl) (list ds dl 0.25))
        (T nil)))

;; ---- flood-fill: the array containing a seed module ----
(defun _ogeo-ename-in (ent lst / hit r)
  (setq hit nil)
  (foreach r lst (if (eq (car r) ent) (setq hit T)))
  hit)

(defun _ogeo-find (ent recs / r hit)
  (foreach r recs (if (eq (car r) ent) (setq hit r)))
  hit)

;; From a seed module ename, return the connected subset of RECS (by proximity).
;; Two modules connect when their centres are within THR = 1.4 x long-dim, which
;; exceeds an in-array orthogonal neighbour but not a real cross-array aisle.
;; Iterative BFS; 4-connectivity is enough (transitive).
(defun _ogeo-array-from (seed recs / sr thr result frontier cur c0 r)
  (setq sr (_ogeo-find seed recs))
  (if (null sr)
    nil
    (progn
      (setq thr (* 1.4 (nth 6 sr))
            result (list sr) frontier (list sr))
      (while frontier
        (setq cur (car frontier) frontier (cdr frontier) c0 (nth 2 cur))
        (foreach r recs
          (if (and (not (_ogeo-ename-in (car r) result))
                   (<= (distance c0 (nth 2 r)) thr))
            (setq result (cons r result) frontier (cons r frontier)))))
      result)))

;; ---- axis grouping (rows or columns) ----
;; insertion sort of (proj . rec) pairs ascending by proj
(defun _ogeo-isort-pairs (lst / out v ins tmp r)
  (setq out nil)
  (foreach v lst
    (setq ins nil tmp nil)
    (foreach r out
      (if (and (not ins) (< (car v) (car r))) (progn (setq tmp (append tmp (list v r)) ins T))
                                              (setq tmp (append tmp (list r)))))
    (setq out (if ins tmp (append tmp (list v)))))
  out)

;; cluster RECS along unit axis U into ascending ordered groups (gap in projected centre
;; > TOL starts a new group). Returns a list of groups, each a list of records. The
;; row/column grouping primitive for O-MODSPACE: pass ushort for rows, ulong for columns.
(defun _ogeo-axis-groups (recs u tol / pr p sorted prev out grp)
  (setq pr nil)
  (foreach p recs (setq pr (cons (cons (_ogeo-dot (nth 2 p) u) p) pr)))
  (setq sorted (_ogeo-isort-pairs pr) prev nil out nil grp nil)
  (foreach p sorted
    (if (and prev (> (- (car p) prev) tol))
      (setq out (cons (reverse grp) out) grp nil))
    (setq grp (cons (cdr p) grp) prev (car p)))
  (if grp (setq out (cons (reverse grp) out)))
  (reverse out))

;; ---- spacing-pattern math ----
;; gap between row i-1 and row i (i = 1..nrows-1) for a pattern kind.
(defun _ogeo-gap-at (i kind gaps endside nrows)
  (cond
    ((= kind "uniform")     (car gaps))
    ((= kind "endbay")
       (if (and endside (= (strcase endside T) "high"))
         (if (= i (1- nrows)) (car gaps) (cadr gaps))
         (if (= i 1)          (car gaps) (cadr gaps))))
    ((= kind "alternating") (if (= (rem i 2) 1) (car gaps) (cadr gaps)))
    ((= kind "sequence")    (nth (rem (1- i) (length gaps)) gaps))
    (T (car gaps))))

;; cumulative axis positions for NROWS rows (row 0 at 0), pitch = modsize + gap.
;; Pass the module size of the edge spanning that axis (short for between-row,
;; long for within-row uniform via kind "uniform").
(defun _ogeo-row-positions (kind gaps endside modsize nrows / i pos out)
  (setq out (list 0.0) pos 0.0 i 1)
  (while (< i nrows)
    (setq pos (+ pos modsize (_ogeo-gap-at i kind gaps endside nrows))
          out (cons pos out) i (1+ i)))
  (reverse out))

;; cluster a list of scalars into ascending groups separated by gaps > tol;
;; returns the per-group means, ascending.
(defun _ogeo-cluster1 (vals tol / sorted v prev cur out grp)
  (setq sorted (_ogeo-isort vals) prev nil grp nil out nil)
  (foreach v sorted
    (if (and prev (> (- v prev) tol))
      (setq out (cons (/ (_ogeo-sum grp) (length grp)) out) grp nil))
    (setq grp (cons v grp) prev v))
  (if grp (setq out (cons (/ (_ogeo-sum grp) (length grp)) out)))
  (reverse out))

;; insertion sort ascending (numbers)
(defun _ogeo-isort (lst / out v ins tmp r)
  (setq out nil)
  (foreach v lst
    (setq ins nil tmp nil)
    (foreach r out
      (if (and (not ins) (< v r)) (progn (setq tmp (append tmp (list v r)) ins T))
                                  (setq tmp (append tmp (list r)))))
    (setq out (if ins tmp (append tmp (list v)))))
  out)

;; Measure the between-row edge gaps of an array (centres projected on the short
;; axis, clustered into rows; consecutive row pitches minus modshort).
;; Returns the ascending list of distinct edge gaps, or nil.
(defun _ogeo-row-gaps (recs modshort / u projs rows i j gaps)
  (if (or (null recs) (< (length recs) 2))
    nil
    (progn
      (setq u (nth 3 (car recs)) projs nil)
      (foreach r recs (setq projs (cons (_ogeo-dot (nth 2 r) u) projs)))
      (setq rows (_ogeo-cluster1 projs (* 0.5 modshort)))   ; row centre positions on u
      (if (< (length rows) 2)
        nil
        (progn
          (setq gaps nil i 0)
          (while (< (1+ i) (length rows))
            (setq gaps (cons (- (- (nth (1+ i) rows) (nth i rows)) modshort) gaps)
                  i (1+ i)))
          (_ogeo-cluster1 gaps 0.4))))))   ; distinct edge gaps

;; Match an array's measured row gaps to a *ocfg-patterns* entry.
;; Returns the matched pattern (name kind gaps endside) or nil.
(defun _ogeo-detect-pattern (recs modshort / meas best bestscore p pg score g m mindiff)
  (setq meas (_ogeo-row-gaps recs modshort))
  (if (or (null meas) (null (and (boundp (quote *ocfg-patterns*)) *ocfg-patterns*)))
    nil
    (progn
      (foreach p *ocfg-patterns*
        (setq pg (nth 2 p) score 0)
        ;; score = number of pattern gaps that appear (within 0.4) in the measured set
        (foreach g pg
          (setq mindiff nil)
          (foreach m meas
            (if (or (null mindiff) (< (abs (- g m)) mindiff)) (setq mindiff (abs (- g m)))))
          (if (and mindiff (<= mindiff 0.4)) (setq score (1+ score))))
        ;; require all pattern gaps matched AND same count of distinct gaps
        (if (and (= score (length pg)) (= (length pg) (length meas))
                 (or (null bestscore) (> score bestscore)))
          (setq best p bestscore score)))
      best)))

;; dominant within-row (long-axis) gap of an array, or nil
(defun _ogeo-col-gap (recs modlong / u projs cols i gaps)
  (if (or (null recs) (< (length recs) 2))
    nil
    (progn
      (setq u (nth 4 (car recs)) projs nil)
      (foreach r recs (setq projs (cons (_ogeo-dot (nth 2 r) u) projs)))
      (setq cols (_ogeo-cluster1 projs (* 0.5 modlong)))
      (if (< (length cols) 2)
        nil
        (progn
          (setq gaps nil i 0)
          (while (< (1+ i) (length cols))
            (setq gaps (cons (- (- (nth (1+ i) cols) (nth i cols)) modlong) gaps) i (1+ i)))
          (_ogeo-mode gaps 0.5))))))

;; index of the nearest value in an ascending list of cluster centres
(defun _ogeo-nearest-idx (v centers / i best bd k)
  (setq i 0 best 0 bd nil)
  (foreach k centers
    (if (or (null bd) (< (abs (- v k)) bd)) (setq bd (abs (- v k)) best i))
    (setq i (1+ i)))
  best)

;; ---- config-pattern picker (shared by O-GRID + O-MODSPACE) ----
;; list *ocfg-patterns* and let the user pick one by number; returns (name kind gaps endside) or nil
(defun _ogeo-pick-pattern ( / lst i p sel)
  (setq lst (if (and (boundp (quote *ocfg-patterns*)) *ocfg-patterns*) *ocfg-patterns* nil))
  (if (null lst)
    (progn (prompt "\n  (no patterns in config)") nil)
    (progn
      (prompt "\n  Config patterns:")
      (setq i 1)
      (foreach p lst
        (prompt (strcat "\n    " (itoa i) ". " (car p) "  (" (cadr p) " "
                        (apply (function strcat)
                               (mapcar (function (lambda (x) (strcat (rtos x 2 2) " "))) (caddr p))) ")"))
        (setq i (1+ i)))
      (initget 7)
      (setq sel (getint (strcat "\n  Pick pattern [1-" (itoa (length lst)) "]: ")))
      (if (and sel (>= sel 1) (<= sel (length lst))) (nth (1- sel) lst) nil))))

;; ---- entity move (locked-safe; shared) ----
(defun _ogeo-move (ent dx dy / res o)
  (setq res (vl-catch-all-apply
              (function (lambda ()
                (setq o (vlax-ename->vla-object ent))
                (vla-move o (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point dx dy 0.0))))))
  (if (vl-catch-all-error-p res) nil T))

;; write WCS corners back to a polyline IN VERTEX ORDER (entmod; no entupd -- caller regens)
(defun _ogeo-write-corners (ent typ wpts / ed out i pr sub sd ocs)
  (cond
    ((= typ "LWPOLYLINE")
     (setq ed (entget ent) out nil i 0)
     (foreach pr ed
       (if (= (car pr) 10)
         (progn (setq ocs (trans (nth i wpts) 0 ent))
                (setq out (cons (list 10 (car ocs) (cadr ocs)) out) i (1+ i)))
         (setq out (cons pr out))))
     (entmod (reverse out)))
    ((= typ "POLYLINE")
     (setq sub (entnext ent) i 0)
     (while (and sub (< i (length wpts)) (= (cdr (assoc 0 (setq sd (entget sub)))) "VERTEX"))
       (if (_ogeo-geom-vtx-p sd)
         (progn (setq ocs (trans (nth i wpts) 0 ent))
                (entmod (subst (cons 10 ocs) (assoc 10 sd) sd))
                (setq i (1+ i))))
       (setq sub (entnext sub))))))

;; Resize a module to (2*hs x 2*hl) along axes us/ul AND move its centre to TC.
;; Vertices keep their winding via the sign of each vertex's projection (rel. to its
;; own current centre) on us/ul. Returns T on success.
(defun _ogeo-place (rec tc us ul hs hl / ent typ cen pts newpts p d a b sa sb res)
  (setq ent (nth 0 rec) typ (nth 1 rec) cen (nth 2 rec))
  (setq res (vl-catch-all-apply (function (lambda ( / )
    (setq pts (_ogeo-poly-pts ent) newpts nil)
    (foreach p pts
      (setq d  (list (- (car p) (car cen)) (- (cadr p) (cadr cen)))
            a  (+ (* (car d) (car us)) (* (cadr d) (cadr us)))
            b  (+ (* (car d) (car ul)) (* (cadr d) (cadr ul)))
            sa (if (>= a 0) 1.0 -1.0) sb (if (>= b 0) 1.0 -1.0))
      (setq newpts (cons (list (+ (car tc) (* sa hs (car us)) (* sb hl (car ul)))
                               (+ (cadr tc) (* sa hs (cadr us)) (* sb hl (cadr ul))) 0.0)
                         newpts)))
    (_ogeo-write-corners ent typ (reverse newpts))))))
  (if (vl-catch-all-error-p res) nil T))

(prompt "\nogeo v1.04 loaded (shared geometry: module reader, real-module gate + _ogeo-modules entry, flood-fill, axis groups, pattern math, viewport filter).")
(princ)
