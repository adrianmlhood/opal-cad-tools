;; oset-1.06.lsp -- O-Suite Project Parameter Setup
;; Commands: O-SET (alias: OSET)
;; Auto-calibrate: scan modules on the configured layer, derive module W/H and
;; the column/row gaps. No click.
;; v1.06 -- pitch selection now minimises |gap| (picks the supported pitch
;;          CLOSEST to the module size), not the smallest pitch. The old
;;          smallest-pitch rule latched onto degenerate sliver pairs (pitch
;;          -> 0) and reported a huge negative gap; smallest-|gap| rejects both
;;          slivers and 2-pitch jumps and lands on the true adjacent neighbour.
;; v1.05 -- robust spacing: sample nearest-neighbour pitch from EVERY module;
;;          module W/H from the median over all modules.
;; v1.04 -- defensive: skip any entity it cannot read as a 4-corner module
;;          (was crashing with numberp:nil on a bad/odd polyline).
;; ============================================================

(if (not *oset-mod-w*) (setq *oset-mod-w* nil))
(if (not *oset-mod-h*) (setq *oset-mod-h* nil))
(if (not *oset-gap-x*) (setq *oset-gap-x* nil))
(if (not *oset-gap-y*) (setq *oset-gap-y* nil))

(defun _oset-lmin (lst / v r) (setq r (car lst)) (foreach v (cdr lst) (if (< v r) (setq r v))) r)
(defun _oset-lmax (lst / v r) (setq r (car lst)) (foreach v (cdr lst) (if (> v r) (setq r v))) r)
(defun _oset-sum  (lst / v r) (setq r 0.0) (foreach v lst (setq r (+ r v))) r)
(defun _oset-sub  (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun _oset-len  (a)   (sqrt (+ (* (car a) (car a)) (* (cadr a) (cadr a)))))
(defun _oset-dot  (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))
(defun _oset-unit (a / l) (setq l (_oset-len a)) (if (> l 1e-9) (list (/ (car a) l) (/ (cadr a) l)) (list 1.0 0.0)))

(defun _oset-modlayer ()
  (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
    *ocfg-layer-modules* nil))

;; corners as WCS points (LWPOLYLINE group 10, or heavyweight POLYLINE VERTEX walk)
(defun _oset-poly-pts (ent / ed typ pts pr sub sd p)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)) pts nil)
  (cond
    ((= typ "LWPOLYLINE")
     (foreach pr ed
       (if (= (car pr) 10)
         (setq pts (cons (trans (list (cadr pr) (caddr pr) 0.0) ent 0) pts)))))
    ((= typ "POLYLINE")
     (setq sub (entnext ent))
     (while (and sub (setq sd (entget sub)) (= (cdr (assoc 0 sd)) "VERTEX"))
       (if (setq p (cdr (assoc 10 sd)))
         (setq pts (cons (trans p ent 0) pts)))
       (setq sub (entnext sub)))))
  (reverse pts))

;; T if p looks like a numeric 2D/3D point
(defun _oset-pt-ok (p) (and (listp p) (numberp (car p)) (numberp (cadr p))))

;; module record: (ent center la lb u v minx miny maxx maxy), or nil if unusable
(defun _oset-rec (ent / pts p0 p1 p2 p3 xs ys)
  (setq pts (_oset-poly-pts ent))
  (if (< (length pts) 4)
    nil
    (progn
      (setq p0 (nth 0 pts) p1 (nth 1 pts) p2 (nth 2 pts) p3 (nth 3 pts))
      (if (not (and (_oset-pt-ok p0) (_oset-pt-ok p1) (_oset-pt-ok p2) (_oset-pt-ok p3)))
        nil
        (progn
          (setq xs (list (car p0) (car p1) (car p2) (car p3))
                ys (list (cadr p0) (cadr p1) (cadr p2) (cadr p3)))
          (list ent
                (list (/ (_oset-sum xs) 4.0) (/ (_oset-sum ys) 4.0))
                (_oset-len  (_oset-sub p1 p0))
                (_oset-len  (_oset-sub p3 p0))
                (_oset-unit (_oset-sub p1 p0))
                (_oset-unit (_oset-sub p3 p0))
                (_oset-lmin xs) (_oset-lmin ys) (_oset-lmax xs) (_oset-lmax ys)))))))

;; build records from a selection set, skipping any entity that errors
(defun _oset-recs-from (ss / i ent r lst)
  (setq i 0 lst nil)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          r (vl-catch-all-apply (function _oset-rec) (list ent)))
    (if (and (not (vl-catch-all-error-p r)) r) (setq lst (cons r lst)))
    (setq i (1+ i)))
  lst)

;; numeric ascending sort that KEEPS duplicates (vl-sort drops equal elements)
(defun _oset-nsort (lst / out x done res r)
  (setq out nil)
  (foreach x lst
    (setq done nil res nil)
    (foreach r out
      (if (and (not done) (< x r))
        (setq res (append res (list x r)) done T)
        (setq res (append res (list r)))))
    (setq out (if done res (append res (list x)))))
  out)

(defun _oset-median (lst / s n)
  (setq s (_oset-nsort lst) n (length s))
  (cond
    ((= n 0) nil)
    ((= (rem n 2) 1) (nth (/ (1- n) 2) s))
    (T (/ (+ (nth (1- (/ n 2)) s) (nth (/ n 2) s)) 2.0))))

;; Among pitches supported by >= minc samples (within tol of each other), the
;; one CLOSEST to `size` -- i.e. the smallest |pitch - size| = smallest |gap| =
;; a true adjacent neighbour. Rejects degenerate slivers (pitch -> 0) AND
;; 2-pitch jumps (pitch -> ~2*size), both of which have large |gap|.
(defun _oset-pick-pitch (pitches size tol minc / p q cnt best bestd d)
  (foreach p pitches
    (setq cnt 0)
    (foreach q pitches (if (<= (abs (- q p)) tol) (setq cnt (1+ cnt))))
    (if (>= cnt minc)
      (progn
        (setq d (abs (- p size)))
        (if (or (not best) (< d bestd)) (setq best p bestd d)))))
  ;; fallback: nothing met the support threshold -> single closest to size
  (if (and (not best) pitches)
    (foreach p pitches
      (setq d (abs (- p size)))
      (if (or (not best) (< d bestd)) (setq best p bestd d))))
  best)

;; nearest in-band neighbour pitch from ONE module along each module axis.
;; A candidate must be at least half a module away (rejects overlap/duplicate
;; centres) and within half a module cross-axis (same row / same column band).
;; -> (pitu pitv), either may be nil if no neighbour in that band.
(defun _oset-pitch1 (pick recs / c u v la lb r rc dvec du dv pitu pitv)
  (setq c (nth 1 pick) la (nth 2 pick) lb (nth 3 pick) u (nth 4 pick) v (nth 5 pick))
  (foreach r recs
    (if (not (eq (car r) (car pick)))
      (progn
        (setq rc (nth 1 r)
              dvec (list (- (car rc) (car c)) (- (cadr rc) (cadr c)))
              du (_oset-dot dvec u) dv (_oset-dot dvec v))
        ;; same-row band -> candidate column pitch (distance along u)
        (if (and (< (abs dv) (* 0.5 lb)) (> (abs du) (* 0.5 la)))
          (if (or (not pitu) (< (abs du) pitu)) (setq pitu (abs du))))
        ;; same-column band -> candidate row pitch (distance along v)
        (if (and (< (abs du) (* 0.5 la)) (> (abs dv) (* 0.5 lb)))
          (if (or (not pitv) (< (abs dv) pitv)) (setq pitv (abs dv)))))))
  (list pitu pitv))

(defun C:O-SET ( / ml ss n recs las lbs pus pvs r p la lb pu pv e0 pts0)
  (vl-load-com)
  (setq ml (_oset-modlayer))
  (prompt (strcat "\nO-SET -- module layer: " (if ml ml "<none set>")))
  (setq ss (ssget "X" (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml)) (list (quote (0 . "*POLYLINE")))))
        n  (if ss (sslength ss) 0))
  (prompt (strcat "\nScanned " (itoa n) " polyline(s) on the layer."))
  (if (= n 0)
    (prompt "\nNo polylines found. Check the module layer name in oconfig (O-CONFIG).")
    (progn
      (setq recs (_oset-recs-from ss))
      (prompt (strcat "\nUsable 4-corner modules: " (itoa (length recs)) "."))
      (if (null recs)
        (progn
          (setq e0 (ssname ss 0) pts0 (_oset-poly-pts e0))
          (prompt (strcat "\nFirst entity: type=" (cdr (assoc 0 (entget e0)))
                          ", corners read=" (itoa (length pts0))))
          (prompt "\nModules are not 4-corner polylines as expected -- send me this readout."))
        (progn
          ;; module dimensions: median over all modules (robust to oddballs)
          (setq las nil lbs nil)
          (foreach r recs (setq las (cons (nth 2 r) las) lbs (cons (nth 3 r) lbs)))
          (setq la (_oset-median las) lb (_oset-median lbs))
          ;; nearest-neighbour pitch sampled from EVERY module, both axes
          (setq pus nil pvs nil)
          (foreach r recs
            (setq p (_oset-pitch1 r recs))
            (if (car p)  (setq pus (cons (car p)  pus)))
            (if (cadr p) (setq pvs (cons (cadr p) pvs))))
          ;; true pitch = supported pitch closest to the module size (min |gap|)
          (setq pu (_oset-pick-pitch pus la (* 0.10 la) 3)
                pv (_oset-pick-pitch pvs lb (* 0.10 lb) 3))
          (setq *oset-mod-w* la *oset-mod-h* lb
                *oset-gap-x* (if pu (- pu la) nil)
                *oset-gap-y* (if pv (- pv lb) nil))
          (prompt "\n--- O-SET parameters (auto) ---")
          (prompt (strcat "\n  Module W: " (rtos *oset-mod-w* 2 4)
                          "   Module H: " (rtos *oset-mod-h* 2 4)))
          (prompt (strcat "\n  Pitch X:  " (if pu (rtos pu 2 4) "(none)")
                          "   Gap X: " (if *oset-gap-x* (rtos *oset-gap-x* 2 4) "(no neighbour)")))
          (prompt (strcat "\n  Pitch Y:  " (if pv (rtos pv 2 4) "(none)")
                          "   Gap Y: " (if *oset-gap-y* (rtos *oset-gap-y* 2 4) "(no neighbour)")))
          (prompt (strcat "\n  Sampled " (itoa (length pus)) " X-neighbours, "
                          (itoa (length pvs)) " Y-neighbours."))))))
  (princ))

(defun C:OSET () (C:O-SET))

(prompt "\nO-SET v1.06 loaded. Type O-SET or OSET to auto-calibrate (no clicking).")
(princ)
