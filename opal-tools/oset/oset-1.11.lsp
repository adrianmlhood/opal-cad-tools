;; oset-1.11.lsp -- O-Suite Project Parameter Setup
;; Commands: O-SET (alias: OSET)
;; Auto-calibrate: scan modules on the configured layer, derive module W/H and
;; the column/row gaps. No click.
;; v1.11 -- readout reorganised for fast scanning: scan counts / neighbour
;;          sampling / pitch clusters print first (context), then a compact
;;          aligned summary block (MODULE w x h, GAP X, GAP Y) at the bottom.
;;          Gaps shown to 2 decimals.
;; v1.10 -- detect 1 OR 2 spacings per axis (distinct-but-close mode groups);
;;          secondary stored in *oset-gap-x2* / *oset-gap-y2*.
;; v1.09 -- spacing = most common pitch. v1.08 -- modal footprint + layer filter.
;; v1.04 -- defensive 4-corner read.
;; ============================================================

(if (not *oset-mod-w*)  (setq *oset-mod-w*  nil))
(if (not *oset-mod-h*)  (setq *oset-mod-h*  nil))
(if (not *oset-gap-x*)  (setq *oset-gap-x*  nil))
(if (not *oset-gap-y*)  (setq *oset-gap-y*  nil))
(if (not *oset-gap-x2*) (setq *oset-gap-x2* nil))
(if (not *oset-gap-y2*) (setq *oset-gap-y2* nil))

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

;; ---- histogram / cluster helpers -------------------------------------------
(defun _oset-round (v bin) (* bin (fix (+ 0.5 (/ v bin)))))

;; -> list of (binCentre . count)
(defun _oset-hist (vals bin / v k cell tbl)
  (setq tbl nil)
  (foreach v vals
    (setq k (_oset-round v bin) cell (assoc k tbl))
    (if cell
      (setq tbl (subst (cons k (1+ (cdr cell))) cell tbl))
      (setq tbl (cons (cons k 1) tbl))))
  tbl)

;; precise mean of the values within tol of a centre (nil-safe -> centre)
(defun _oset-cluster-mean (vals centre tol / q sum n)
  (setq sum 0.0 n 0)
  (foreach q vals (if (<= (abs (- q centre)) tol) (setq sum (+ sum q) n (1+ n))))
  (if (> n 0) (/ sum n) centre))

;; modal value: mean of the most-populated cluster (windowed +/- bin)
(defun _oset-mode (vals bin / tbl best bestc cell)
  (setq tbl (_oset-hist vals bin) best nil bestc -1)
  (foreach cell tbl (if (> (cdr cell) bestc) (setq best (car cell) bestc (cdr cell))))
  (if best (_oset-cluster-mean vals best bin) nil))

;; top n (binCentre . count) pairs by count, descending
(defun _oset-topn (tbl nmax / out best bestc c)
  (setq out nil)
  (while (and tbl (< (length out) nmax))
    (setq best nil bestc -1)
    (foreach c tbl (if (> (cdr c) bestc) (setq best c bestc (cdr c))))
    (setq out (append out (list best)) tbl (vl-remove best tbl)))
  out)

(defun _oset-hist-str (vals bin nmax / s c)
  (setq s "")
  (foreach c (_oset-topn (_oset-hist vals bin) nmax)
    (setq s (strcat s (rtos (car c) 2 1) "x" (itoa (cdr c)) "  ")))
  (if (= s "") "(none)" s))

;; Detect the dominant spacing(s). Returns ((pitch . count) ...), biggest first.
;; A second entry is added only when a cluster is well-supported (>= max(8,8%)),
;; distinct from the first (refined means >= 0.75 apart) and close (<= 1.6 apart).
(defun _oset-spacings (vals / total tbl tops minc c0 m0 out c1 m1)
  (setq out nil total (length vals))
  (if (> total 0)
    (progn
      (setq tbl  (_oset-hist vals 1.0)
            tops (_oset-topn tbl 4)
            minc (max 8 (fix (* 0.08 total)))
            c0   (car tops)
            m0   (_oset-cluster-mean vals (car c0) 0.5)
            out  (list (cons m0 (cdr c0))))
      (foreach c1 (cdr tops)
        (if (and (= (length out) 1)
                 (>= (cdr c1) minc)
                 (<= (abs (- (car c1) (car c0))) 1.6))
          (progn
            (setq m1 (_oset-cluster-mean vals (car c1) 0.5))
            (if (>= (abs (- m1 m0)) 0.75)
              (setq out (append out (list (cons m1 (cdr c1)))))))))))
  out)

;; compact gap readout for an axis (one or two spacings), 2 decimals
(defun _oset-gaps-str (spacings modsize / txt first s)
  (if (null spacings)
    "(no neighbour)"
    (progn
      (setq txt "" first T)
      (foreach s spacings
        (setq txt (strcat txt (if first "" "  and  ")
                          (rtos (- (car s) modsize) 2 2) " (x" (itoa (cdr s)) ")")
              first nil))
      (if (> (length spacings) 1)
        (strcat txt "   [2 spacings, "
                (rtos (abs (- (car (car spacings)) (car (cadr spacings)))) 2 2) " apart]")
        txt))))
;; -----------------------------------------------------------------------------

;; nearest in-band neighbour pitch from ONE module along each module axis.
(defun _oset-pitch1 (pick recs / c u v la lb r rc dvec du dv pitu pitv)
  (setq c (nth 1 pick) la (nth 2 pick) lb (nth 3 pick) u (nth 4 pick) v (nth 5 pick))
  (foreach r recs
    (if (not (eq (car r) (car pick)))
      (progn
        (setq rc (nth 1 r)
              dvec (list (- (car rc) (car c)) (- (cadr rc) (cadr c)))
              du (_oset-dot dvec u) dv (_oset-dot dvec v))
        (if (and (< (abs dv) (* 0.5 lb)) (> (abs du) (* 0.5 la)))
          (if (or (not pitu) (< (abs du) pitu)) (setq pitu (abs du))))
        (if (and (< (abs du) (* 0.5 la)) (> (abs dv) (* 0.5 lb)))
          (if (or (not pitv) (< (abs dv) pitv)) (setq pitv (abs dv)))))))
  (list pitu pitv))

;; keep only records whose footprint matches the dominant module (modw x modh)
(defun _oset-match-mods (recs modw modh / tw th out r)
  (setq tw (max 1.0 (* 0.05 modw)) th (max 1.0 (* 0.05 modh)) out nil)
  (foreach r recs
    (if (and (<= (abs (- (nth 2 r) modw)) tw) (<= (abs (- (nth 3 r) modh)) th))
      (setq out (cons r out))))
  out)

(defun C:O-SET ( / ml ss n recs las lbs modw modh mods nmod pus pvs r p sx sy e0 pts0)
  (vl-load-com)
  (setq ml (_oset-modlayer))
  (setq ss (ssget "X" (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml)) (list (quote (0 . "*POLYLINE")))))
        n  (if ss (sslength ss) 0))
  (if (= n 0)
    (prompt (strcat "\nO-SET -- layer " (if ml ml "<none set>")
                    ": no polylines found. Check the module layer in oconfig (O-CONFIG)."))
    (progn
      (setq recs (_oset-recs-from ss))
      (if (null recs)
        (progn
          (setq e0 (ssname ss 0) pts0 (_oset-poly-pts e0))
          (prompt (strcat "\nO-SET -- layer " (if ml ml "<none set>") ": " (itoa n)
                          " polylines but none are 4-corner modules."))
          (prompt (strcat "\nFirst entity: type=" (cdr (assoc 0 (entget e0)))
                          ", corners read=" (itoa (length pts0)) " -- send me this readout.")))
        (progn
          ;; dominant module footprint = MODE of W and H over all 4-corner polys
          (setq las nil lbs nil)
          (foreach r recs (setq las (cons (nth 2 r) las) lbs (cons (nth 3 r) lbs)))
          (setq modw (_oset-mode las 2.0) modh (_oset-mode lbs 2.0))
          ;; keep only polylines matching that footprint (ignore layer clutter)
          (setq mods (_oset-match-mods recs modw modh) nmod (length mods))
          ;; pitch sampled from matched modules only
          (setq pus nil pvs nil)
          (foreach r mods
            (setq p (_oset-pitch1 r mods))
            (if (car p)  (setq pus (cons (car p)  pus)))
            (if (cadr p) (setq pvs (cons (cadr p) pvs))))
          ;; one or two spacings per axis
          (setq sx (_oset-spacings pus) sy (_oset-spacings pvs))
          (setq *oset-mod-w*  modw *oset-mod-h* modh
                *oset-gap-x*  (if sx (- (car (car sx)) modw) nil)
                *oset-gap-y*  (if sy (- (car (car sy)) modh) nil)
                *oset-gap-x2* (if (cdr sx) (- (car (cadr sx)) modw) nil)
                *oset-gap-y2* (if (cdr sy) (- (car (cadr sy)) modh) nil))
          ;; ---- context first (fast-scroll-past) ----
          (prompt (strcat "\nO-SET -- layer " ml "   " (itoa n) " polylines  ->  "
                          (itoa (length recs)) " 4-corner  ->  " (itoa nmod)
                          " modules (ignored " (itoa (- (length recs) nmod)) ")"))
          (prompt (strcat "\n  X clusters: " (_oset-hist-str pus 1.0 6)))
          (prompt (strcat "\n  Y clusters: " (_oset-hist-str pvs 1.0 6)))
          ;; ---- fast-scan summary last ----
          (prompt "\n")
          (prompt (strcat "\n  MODULE   " (rtos modw 2 2) " x " (rtos modh 2 2)))
          (prompt (strcat "\n  GAP X    " (_oset-gaps-str sx modw)))
          (prompt (strcat "\n  GAP Y    " (_oset-gaps-str sy modh)))))))
  (princ))

(defun C:OSET () (C:O-SET))

(prompt "\nO-SET v1.11 loaded. Type O-SET or OSET to auto-calibrate (no clicking).")
(princ)
