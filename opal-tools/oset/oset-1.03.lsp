;; oset-1.03.lsp -- O-Suite Project Parameter Setup
;; Commands: O-SET (alias: OSET)
;; FULLY AUTOMATIC: scans all modules on the configured module layer, picks a
;; reference module that has neighbours on both axes, and derives module W/H and
;; the column/row gaps. No clicking -- the module layer is known from oconfig.
;; v1.03 -- removed the click; auto-selects a reference module.
;; v1.02 -- module count readout. v1.01 -- neighbour auto-detect + POLYLINE fix.
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

(defun _oset-non-module-layer (lyr / u)
  (setq u (strcase lyr))
  (or (vl-string-search "STRINGING" u) (vl-string-search "DC-" u)
      (vl-string-search "HOMERUN" u)   (vl-string-search "JUMP" u)
      (vl-string-search "TAG" u)       (vl-string-search "SCHEDULE" u)
      (vl-string-search "CONDUIT" u)   (vl-string-search "LABEL" u)
      (vl-string-search "STRUCTURE" u) (vl-string-search "GRIDLINE" u)
      (vl-string-search "TABLE" u)     (vl-string-search "CALLOUT" u)
      (vl-string-search "BOUNDARY" u)  (vl-string-search "FILL" u)
      (vl-string-search "COUNT" u)     (vl-string-search "XDATA" u)))

(defun _oset-poly-pts (ent / ed typ pts pr sub sd)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)) pts nil)
  (cond
    ((= typ "LWPOLYLINE")
     (foreach pr ed
       (if (= (car pr) 10)
         (setq pts (cons (trans (list (cadr pr) (caddr pr) 0.0) ent 0) pts)))))
    ((= typ "POLYLINE")
     (setq sub (entnext ent))
     (while (and sub (setq sd (entget sub)) (= (cdr (assoc 0 sd)) "VERTEX"))
       (setq pts (cons (trans (cdr (assoc 10 sd)) ent 0) pts))
       (setq sub (entnext sub)))))
  (reverse pts))

(defun _oset-rec (ent / pts p0 p1 p3 xs ys)
  (setq pts (_oset-poly-pts ent))
  (if (< (length pts) 4)
    nil
    (progn
      (setq p0 (nth 0 pts) p1 (nth 1 pts) p3 (nth 3 pts)
            xs (mapcar (function car)  (list (nth 0 pts) (nth 1 pts) (nth 2 pts) (nth 3 pts)))
            ys (mapcar (function cadr) (list (nth 0 pts) (nth 1 pts) (nth 2 pts) (nth 3 pts))))
      (list ent
            (list (/ (_oset-sum xs) 4.0) (/ (_oset-sum ys) 4.0))
            (_oset-len  (_oset-sub p1 p0))
            (_oset-len  (_oset-sub p3 p0))
            (_oset-unit (_oset-sub p1 p0))
            (_oset-unit (_oset-sub p3 p0))
            (_oset-lmin xs) (_oset-lmin ys) (_oset-lmax xs) (_oset-lmax ys)))))

(defun _oset-collect ( / ml flt ss i ent rec lst)
  (setq ml (_oset-modlayer)
        flt (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml)) (list (quote (0 . "*POLYLINE"))))
        ss (ssget "X" flt) lst nil i 0)
  (if ss
    (while (< i (sslength ss))
      (setq ent (ssname ss i))
      (if (or ml (not (_oset-non-module-layer (cdr (assoc 8 (entget ent))))))
        (progn (setq rec (_oset-rec ent)) (if rec (setq lst (cons rec lst)))))
      (setq i (1+ i))))
  lst)

;; nearest neighbour pitch along each module axis -> (la lb gap-u gap-v)
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

;; pick a reference: first module with BOTH gaps; else one with any; else first
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

(defun C:O-SET ( / ml recs res)
  (vl-load-com)
  (setq ml (_oset-modlayer))
  (prompt (strcat "\nO-SET -- module layer: " (if ml ml "<none set; using denylist>")))
  (setq recs (_oset-collect))
  (prompt (strcat "\nFound " (itoa (length recs)) " module(s)."))
  (if (not recs)
    (prompt "\nNo modules found. Check the module layer name in oconfig (O-CONFIG).")
    (progn
      (setq res (_oset-reference recs)
            *oset-mod-w* (nth 0 res) *oset-mod-h* (nth 1 res)
            *oset-gap-x* (nth 2 res) *oset-gap-y* (nth 3 res))
      (prompt "\n--- O-SET parameters (auto) ---")
      (prompt (strcat "\n  Module W: " (rtos *oset-mod-w* 2 4)))
      (prompt (strcat "\n  Module H: " (rtos *oset-mod-h* 2 4)))
      (prompt (strcat "\n  Gap X:    " (if *oset-gap-x* (rtos *oset-gap-x* 2 4) "(no neighbour found)")))
      (prompt (strcat "\n  Gap Y:    " (if *oset-gap-y* (rtos *oset-gap-y* 2 4) "(no neighbour found)")))
      (if (or (not *oset-gap-x*) (not *oset-gap-y*))
        (prompt "\n  Note: only isolated modules found in one axis; gap may be incomplete."))))
  (princ))

(defun C:OSET () (C:O-SET))

(prompt "\nO-SET v1.03 loaded. Type O-SET or OSET to auto-calibrate (no clicking).")
(princ)
