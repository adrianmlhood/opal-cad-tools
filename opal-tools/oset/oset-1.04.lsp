;; oset-1.04.lsp -- O-Suite Project Parameter Setup
;; Commands: O-SET (alias: OSET)
;; Auto-calibrate: scan modules on the configured layer, pick a reference module
;; with neighbours on both axes, derive module W/H and column/row gaps. No click.
;; v1.04 -- defensive: skip any entity it cannot read as a 4-corner module
;;          (was crashing with numberp:nil on a bad/odd polyline). Reports raw
;;          polyline count, usable module count, and the first entity's shape
;;          when nothing is usable, to diagnose unexpected geometry.
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

;; nearest-neighbour pitch along each module axis -> (la lb gap-u gap-v)
(defun _oset-gaps (pick recs / c u v la lb r rc dvec du dv pitu pitv)
  (setq c (nth 1 pick) la (nth 2 pick) lb (nth 3 pick) u (nth 4 pick) v (nth 5 pick))
  (foreach r recs
    (if (not (eq (car r) (car pick)))
      (progn
        (setq rc (nth 1 r)
              dvec (list (- (car rc) (car c)) (- (cadr rc) (cadr c)))
              du (_oset-dot dvec u) dv (_oset-dot dvec v))
        (if (< (abs dv) (* 0.5 lb))
          (if (> (abs du) (* 0.05 la))
            (if (or (not pitu) (< (abs du) pitu)) (setq pitu (abs du)))))
        (if (< (abs du) (* 0.5 la))
          (if (> (abs dv) (* 0.05 lb))
            (if (or (not pitv) (< (abs dv) pitv)) (setq pitv (abs dv))))))))
  (list la lb (if pitu (- pitu la) nil) (if pitv (- pitv lb) nil)))

(defun _oset-reference (recs / r res found)
  (foreach r recs
    (if (not found)
      (progn (setq res (_oset-gaps r recs))
             (if (and (nth 2 res) (nth 3 res)) (setq found res)))))
  (if (not found)
    (foreach r recs
      (if (not found)
        (progn (setq res (_oset-gaps r recs))
               (if (or (nth 2 res) (nth 3 res)) (setq found res))))))
  (if (not found) (setq found (_oset-gaps (car recs) recs)))
  found)

(defun C:O-SET ( / ml ss n recs res e0 pts0)
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
          (setq res (_oset-reference recs)
                *oset-mod-w* (nth 0 res) *oset-mod-h* (nth 1 res)
                *oset-gap-x* (nth 2 res) *oset-gap-y* (nth 3 res))
          (prompt "\n--- O-SET parameters (auto) ---")
          (prompt (strcat "\n  Module W: " (rtos *oset-mod-w* 2 4)))
          (prompt (strcat "\n  Module H: " (rtos *oset-mod-h* 2 4)))
          (prompt (strcat "\n  Gap X:    " (if *oset-gap-x* (rtos *oset-gap-x* 2 4) "(no neighbour found)")))
          (prompt (strcat "\n  Gap Y:    " (if *oset-gap-y* (rtos *oset-gap-y* 2 4) "(no neighbour found)")))))))
  (princ))

(defun C:OSET () (C:O-SET))

(prompt "\nO-SET v1.04 loaded. Type O-SET or OSET to auto-calibrate (no clicking).")
(princ)
