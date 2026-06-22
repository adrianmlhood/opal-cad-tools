;; ogeo-1.0.lsp -- O-Suite shared geometry library  (no command; defines _ogeo-* only)
;;
;; One home for the module-reading + array-detection + spacing-pattern math shared by
;; O-GRID and O-ROWSPACE (and reusable by the future XDATA-IR port). Loaded as a normal
;; tool; callers invoke _ogeo-* at command runtime (after O-LOAD has loaded everything),
;; so load order is irrelevant. Config globals (*ocfg-modules* / *ocfg-patterns*) are
;; parsed by oconfig (loads first); this lib consumes them.
;;
;; Module record (the unit every consumer uses):
;;   (ent typ center ushort ulong short long nverts)
;;     center = WCS (x y) centroid;  ushort/ulong = unit vectors along the short/long edge;
;;     short/long = edge lengths;  nverts = geometry-vertex count.
;; v1.0
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

;; select all module polylines on the configured module layer -> records
(defun _ogeo-all-modules ( / ml ss)
  (setq ml (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
             *ocfg-layer-modules* nil))
  (setq ss (ssget "X" (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml))
                                (list (quote (0 . "*POLYLINE"))))))
  (if ss (_ogeo-recs-from ss) nil))

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

(prompt "\nogeo v1.0 loaded (shared geometry: module reader, flood-fill, pattern math).")
(princ)
