;; oset-1.02.lsp -- O-Suite Project Parameter Setup
;; Commands: O-SET (alias: OSET)
;; Click ONE module; O-SET reads its oriented width/height and auto-detects the
;; nearest neighbours along the module's own axes to derive column/row gaps.
;; v1.02 -- reports how many modules were found (and on which layer) before the
;;          pick, so a wrong module layer / empty selection is obvious.
;; v1.01 -- one-module pick + neighbour auto-detect; heavyweight POLYLINE fix.
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

(defun _oset-pick-rec (recs wp / best bd r c dx dy d inb)
  (foreach r recs
    (setq c (nth 1 r)
          inb (and (>= (car wp) (nth 6 r)) (<= (car wp) (nth 8 r))
                   (>= (cadr wp) (nth 7 r)) (<= (cadr wp) (nth 9 r)))
          dx (- (car wp) (car c)) dy (- (cadr wp) (cadr c)) d (+ (* dx dx) (* dy dy)))
    (if inb (if (or (not best) (< d bd)) (setq best r bd d))))
  (if (not best)
    (foreach r recs
      (setq c (nth 1 r) dx (- (car wp) (car c)) dy (- (cadr wp) (cadr c)) d (+ (* dx dx) (* dy dy)))
      (if (or (not best) (< d bd)) (setq best r bd d))))
  best)

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

(defun C:O-SET ( / recs wp pick res ml)
  (vl-load-com)
  (setq ml (_oset-modlayer))
  (prompt (strcat "\nO-SET -- module layer: " (if ml ml "<none set; using denylist>")))
  (setq recs (_oset-collect))
  (prompt (strcat "\nFound " (itoa (length recs)) " module(s)."))
  (if (not recs)
    (progn
      (prompt "\nNo modules found. Check the module layer name in oconfig (O-CONFIG).")
      (princ))
    (progn
      (setq wp (getpoint "\nClick a module to calibrate: "))
      (if (not wp)
        (progn (prompt "\nCancelled (no point picked).") (princ))
        (progn
          (setq wp (trans wp 1 0)
                pick (_oset-pick-rec recs wp))
          (if (not pick)
            (progn (prompt "\nNo module at that point.") (princ))
            (progn
              (setq res (_oset-gaps pick recs)
                    *oset-mod-w* (nth 0 res) *oset-mod-h* (nth 1 res)
                    *oset-gap-x* (nth 2 res) *oset-gap-y* (nth 3 res))
              (prompt "\n--- O-SET parameters ---")
              (prompt (strcat "\n  Module W: " (rtos *oset-mod-w* 2 4)))
              (prompt (strcat "\n  Module H: " (rtos *oset-mod-h* 2 4)))
              (prompt (strcat "\n  Gap X:    " (if *oset-gap-x* (rtos *oset-gap-x* 2 4) "(no neighbour found)")))
              (prompt (strcat "\n  Gap Y:    " (if *oset-gap-y* (rtos *oset-gap-y* 2 4) "(no neighbour found)")))
              (if (or (not *oset-gap-x*) (not *oset-gap-y*))
                (prompt "\n  Tip: click a module with neighbours on both sides for full spacing."))
              (princ)))))))
  (princ))

(defun C:OSET () (C:O-SET))

(prompt "\nO-SET v1.02 loaded. Type O-SET or OSET to calibrate (click one module).")
(princ)
