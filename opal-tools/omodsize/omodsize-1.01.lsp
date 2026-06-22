;; omodsize-1.01.lsp -- O-Suite module size normalizer + size report
;; Commands: O-MODSIZE (alias: OMODSIZE)
;;
;; Two modes (opens with [Report/Normalize] <Report>):
;;   Report    = read-only. Prints the module footprint distribution (size buckets
;;               + counts, min/max short & long side, count off the modal footprint).
;;               Run it BEFORE and AFTER a normalize to verify the change. No edits.
;;   Normalize = resize every matched module to ONE target footprint.
;;
;; Detects the module set exactly like O-SET (heavyweight POLYLINE / LWPOLYLINE on
;; the configured module layer, modal footprint, orientation-agnostic long-side
;; match) -- so it sees the same modules O-SET reports.
;;
;; Normalize rebuilds each module about its OWN centre along its OWN edge axes, so
;; rotation and position are preserved and only side lengths change. Orientation-
;; agnostic: the target's long side lands on whichever edge is currently the long one.
;; MODULES ONLY -- racking / strings / annotation are never touched. Edits in place
;; (entmod on the polyline's own vertices + entupd); entity identity / XDATA preserved.
;; Always prints a plan and needs an explicit Yes before changing anything.
;; v1.01 -- add Report mode (verify before/after); detection refactored into
;;          _oms-detect, shared by both modes.
;; v1.0
;; ============================================================

(vl-load-com)

;; ---- vector helpers ----
(defun _oms-sum  (lst / v r) (setq r 0.0) (foreach v lst (setq r (+ r v))) r)
(defun _oms-sub  (a b) (list (- (car a) (car b)) (- (cadr a) (cadr b))))
(defun _oms-len  (a)   (sqrt (+ (* (car a) (car a)) (* (cadr a) (cadr a)))))
(defun _oms-unit (a / l) (setq l (_oms-len a)) (if (> l 1e-9) (list (/ (car a) l) (/ (cadr a) l)) (list 1.0 0.0)))

(defun _oms-pad (s n / r) (setq r s) (while (< (strlen r) n) (setq r (strcat r " "))) r)

(defun _oms-modlayer ()
  (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
    *ocfg-layer-modules* nil))

;; T if a VERTEX sub-entity is a real polyline corner (skip spline-frame/mesh)
(defun _oms-geom-vtx-p (vd / fl)
  (setq fl (cdr (assoc 70 vd)))
  (or (null fl)
      (and (= 0 (logand fl 16)) (= 0 (logand fl 64)) (= 0 (logand fl 128)))))

;; Ordered WCS corner points of an LWPOLYLINE or heavyweight POLYLINE (geometry
;; vertices only), in the entity's own vertex order. Same dual-path reader as O-SET.
(defun _oms-poly-pts (ent / ed typ pts pr sub sd raw)
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
       (if (and (_oms-geom-vtx-p sd) raw (numberp (car raw)) (numberp (cadr raw)))
         (setq pts (cons (trans (list (car raw) (cadr raw) 0.0) ent 0) pts)))
       (setq sub (entnext sub)))))
  (reverse pts))

(defun _oms-pt-ok (p) (and (listp p) (numberp (car p)) (numberp (cadr p))))

;; module record: (ent typ center u v la lb nverts) or nil if unusable.
(defun _oms-rec (ent / pts typ p0 p1 p3 xs ys)
  (setq pts (_oms-poly-pts ent) typ (cdr (assoc 0 (entget ent))))
  (if (< (length pts) 4)
    nil
    (progn
      (setq p0 (nth 0 pts) p1 (nth 1 pts) p3 (nth 3 pts))
      (if (not (and (_oms-pt-ok p0) (_oms-pt-ok p1) (_oms-pt-ok p3)))
        nil
        (progn
          (setq xs (list (car p0) (car p1) (car (nth 2 pts)) (car p3))
                ys (list (cadr p0) (cadr p1) (cadr (nth 2 pts)) (cadr p3)))
          (list ent typ
                (list (/ (_oms-sum xs) 4.0) (/ (_oms-sum ys) 4.0))
                (_oms-unit (_oms-sub p1 p0))
                (_oms-unit (_oms-sub p3 p0))
                (_oms-len  (_oms-sub p1 p0))
                (_oms-len  (_oms-sub p3 p0))
                (length pts)))))))

(defun _oms-recs-from (ss / i ent r lst)
  (setq i 0 lst nil)
  (while (< i (sslength ss))
    (setq ent (ssname ss i)
          r (vl-catch-all-apply (function _oms-rec) (list ent)))
    (if (and (not (vl-catch-all-error-p r)) r) (setq lst (cons r lst)))
    (setq i (1+ i)))
  lst)

;; ---- modal footprint (mode of all 4-corner edge lengths), same as O-SET ----
(defun _oms-round (v bin) (* bin (fix (+ 0.5 (/ v bin)))))
(defun _oms-mode (vals bin / tbl best bestc cell k sum n q)
  (setq tbl nil)
  (foreach v vals
    (setq k (_oms-round v bin) cell (assoc k tbl))
    (if cell (setq tbl (subst (cons k (1+ (cdr cell))) cell tbl))
             (setq tbl (cons (cons k 1) tbl))))
  (setq best nil bestc -1)
  (foreach cell tbl (if (> (cdr cell) bestc) (setq best (car cell) bestc (cdr cell))))
  (if (null best)
    nil
    (progn
      (setq sum 0.0 n 0)
      (foreach q vals (if (<= (abs (- q best)) bin) (setq sum (+ sum q) n (1+ n))))
      (if (> n 0) (/ sum n) best))))

;; top n (key . count) pairs by count, descending
(defun _oms-topn (tbl nmax / out best bestc c)
  (setq out nil)
  (while (and tbl (< (length out) nmax))
    (setq best nil bestc -1)
    (foreach c tbl (if (> (cdr c) bestc) (setq best c bestc (cdr c))))
    (setq out (append out (list best)) tbl (vl-remove best tbl)))
  out)

;; keep only records whose footprint matches the dominant module (orientation-
;; agnostic: long side tight, short side loose -- identical to O-SET 1.12).
(defun _oms-match-mods (recs modw modh / mshort mlong tol-s tol-l out r rs rl)
  (setq mshort (min modw modh) mlong (max modw modh)
        tol-s (max 4.0 (* 0.10 mshort)) tol-l (max 2.0 (* 0.02 mlong)) out nil)
  (foreach r recs
    (setq rs (min (nth 5 r) (nth 6 r)) rl (max (nth 5 r) (nth 6 r)))
    (if (and (<= (abs (- rl mlong)) tol-l) (<= (abs (- rs mshort)) tol-s))
      (setq out (cons r out))))
  out)

;; Detect the module set. Returns (mods modw modh layer nrecs) or nil.
(defun _oms-detect ( / ml ss recs las lbs modw modh r)
  (setq ml (_oms-modlayer))
  (setq ss (ssget "X" (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml))
                                (list (quote (0 . "*POLYLINE"))))))
  (if (null ss)
    nil
    (progn
      (setq recs (_oms-recs-from ss))
      (if (null recs)
        nil
        (progn
          (setq las nil lbs nil)
          (foreach r recs (setq las (cons (nth 5 r) las) lbs (cons (nth 6 r) lbs)))
          (setq modw (_oms-mode las 2.0) modh (_oms-mode lbs 2.0))
          (if (and (boundp (quote *oset-mod-w*)) *oset-mod-w* (> *oset-mod-w* 0)) (setq modw *oset-mod-w*))
          (if (and (boundp (quote *oset-mod-h*)) *oset-mod-h* (> *oset-mod-h* 0)) (setq modh *oset-mod-h*))
          (list (_oms-match-mods recs modw modh) modw modh (if ml ml "<none>") (length recs)))))))

(defun _oms-fmt (v) (rtos v 2 2))

;; ---- resize one module to wu (along u) x wv (along v), centre fixed ----
(defun _oms-set-rect (rec wu wv / ent typ cen u v hu hv n0 n1 n2 n3 res)
  (setq ent (nth 0 rec) typ (nth 1 rec) cen (nth 2 rec) u (nth 3 rec) v (nth 4 rec)
        hu (* 0.5 wu) hv (* 0.5 wv))
  (setq n0 (list (- (car cen) (* hu (car u)) (* hv (car v)))
                 (- (cadr cen) (* hu (cadr u)) (* hv (cadr v))) 0.0)
        n1 (list (+ (- (car cen) (* hv (car v))) (* hu (car u)))
                 (+ (- (cadr cen) (* hv (cadr v))) (* hu (cadr u))) 0.0)
        n2 (list (+ (car cen) (* hu (car u)) (* hv (car v)))
                 (+ (cadr cen) (* hu (cadr u)) (* hv (cadr v))) 0.0)
        n3 (list (+ (- (car cen) (* hu (car u))) (* hv (car v)))
                 (+ (- (cadr cen) (* hu (cadr u))) (* hv (cadr v))) 0.0))
  (setq res (vl-catch-all-apply (function _oms-write-corners)
              (list ent typ (list n0 n1 n2 n3))))
  (if (vl-catch-all-error-p res) nil T))

;; write four WCS corners (in vertex order) back to the polyline
(defun _oms-write-corners (ent typ wpts / ed out i pr sub sd ocs)
  (cond
    ((= typ "LWPOLYLINE")
     (setq ed (entget ent) out nil i 0)
     (foreach pr ed
       (if (= (car pr) 10)
         (progn
           (setq ocs (trans (nth i wpts) 0 ent))
           (setq out (cons (list 10 (car ocs) (cadr ocs)) out) i (1+ i)))
         (setq out (cons pr out))))
     (entmod (reverse out)))
    ((= typ "POLYLINE")
     (setq sub (entnext ent) i 0)
     (while (and sub (< i 4) (= (cdr (assoc 0 (setq sd (entget sub)))) "VERTEX"))
       (if (_oms-geom-vtx-p sd)
         (progn
           (setq ocs (trans (nth i wpts) 0 ent))
           (entmod (subst (cons 10 ocs) (assoc 10 sd) sd))
           (setq i (1+ i))))
       (setq sub (entnext sub)))
     (entupd ent))))

;; ---- Report: footprint distribution, read-only ----
(defun _oms-report (mods modw modh ml nrecs / mshort mlong tol off buckets r sks lks
                    smin smax lmin lmax key cell pair)
  (setq mshort (min modw modh) mlong (max modw modh) tol 0.01 off 0 buckets nil)
  (if (null mods)
    (prompt (strcat "\nO-MODSIZE Report -- layer " ml ": no modules matched the footprint ("
                    (itoa nrecs) " 4-corner polylines scanned)."))
    (progn
      (foreach r mods
        (setq sks (min (nth 5 r) (nth 6 r)) lks (max (nth 5 r) (nth 6 r)))
        (if (or (null smin) (< sks smin)) (setq smin sks))
        (if (or (null smax) (> sks smax)) (setq smax sks))
        (if (or (null lmin) (< lks lmin)) (setq lmin lks))
        (if (or (null lmax) (> lks lmax)) (setq lmax lks))
        (if (or (> (abs (- sks mshort)) tol) (> (abs (- lks mlong)) tol)) (setq off (1+ off)))
        (setq key (strcat (_oms-pad (rtos sks 2 2) 7) " x " (rtos lks 2 2))
              cell (assoc key buckets))
        (if cell (setq buckets (subst (cons key (1+ (cdr cell))) cell buckets))
                 (setq buckets (cons (cons key 1) buckets))))
      (prompt (strcat "\nO-MODSIZE Report -- layer " ml ": " (itoa (length mods))
                      " modules (" (itoa nrecs) " 4-corner scanned)."))
      (prompt (strcat "\n  target/modal footprint: " (_oms-fmt mshort) " x " (_oms-fmt mlong)))
      (prompt "\n  footprint (short x long  ->  count):")
      (foreach pair (_oms-topn buckets 12)
        (prompt (strcat "\n    " (_oms-pad (car pair) 18) " x" (itoa (cdr pair)))))
      (prompt (strcat "\n  short side: min " (_oms-fmt smin) "  max " (_oms-fmt smax)
                      "   spread " (_oms-fmt (- smax smin))))
      (prompt (strcat "\n  long  side: min " (_oms-fmt lmin) "  max " (_oms-fmt lmax)
                      "   spread " (_oms-fmt (- lmax lmin))))
      (prompt (strcat "\n  off target (> 0.01): " (itoa off)
                      (if (= off 0) "   -- ALL UNIFORM" "")))))
  (princ))

;; ============================================================
;; O-MODSIZE  --  [Report/Normalize]
;; ============================================================
(defun C:O-MODSIZE ( / old-err mode det mods modw modh ml nrecs tgtw tgth mshort mlong
                       kw off same r rs rl wu wv tol nchg nsame nfail ans)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-MODSIZE error: " msg)))
    (princ))

  (initget "Report Normalize")
  (setq mode (getkword "\nO-MODSIZE [Report/Normalize] <Report>: "))
  (if (null mode) (setq mode "Report"))

  (setq det (_oms-detect))
  (if (null det)
    (prompt (strcat "\nO-MODSIZE -- no modules found on the module layer (check O-CONFIG)."))
    (progn
      (setq mods (car det) modw (cadr det) modh (caddr det) ml (nth 3 det) nrecs (nth 4 det))
      (cond
        ;; ---------------- REPORT ----------------
        ((= mode "Report")
         (_oms-report mods modw modh ml nrecs))

        ;; ---------------- NORMALIZE ----------------
        ((null mods)
         (prompt "\nO-MODSIZE: no modules matched the footprint -- nothing to normalize."))
        (T
         (setq tgtw modw tgth modh)
         (prompt (strcat "\nO-MODSIZE -- layer " ml ": " (itoa (length mods))
                         " modules.  Modal footprint " (_oms-fmt modw) " x " (_oms-fmt modh) "."))
         (initget "Yes No Custom")
         (setq kw (getkword (strcat "\nNormalize all to " (_oms-fmt tgtw) " x " (_oms-fmt tgth)
                                    "? [Yes/No/Custom] <Yes>: ")))
         (cond
           ((= kw "No") (setq tgtw nil))
           ((= kw "Custom")
            (setq tgtw (getreal (strcat "\nTarget WIDTH (short side) <" (_oms-fmt (min modw modh)) ">: ")))
            (if (null tgtw) (setq tgtw (min modw modh)))
            (setq tgth (getreal (strcat "\nTarget HEIGHT (long side) <" (_oms-fmt (max modw modh)) ">: ")))
            (if (null tgth) (setq tgth (max modw modh)))))
         (if (null tgtw)
           (prompt "\nO-MODSIZE: cancelled -- nothing changed.")
           (progn
             (setq mshort (min tgtw tgth) mlong (max tgtw tgth) tol 0.01 off 0 same 0)
             (foreach r mods
               (setq rs (min (nth 5 r) (nth 6 r)) rl (max (nth 5 r) (nth 6 r)))
               (if (or (> (abs (- rs mshort)) tol) (> (abs (- rl mlong)) tol))
                 (setq off (1+ off)) (setq same (1+ same))))
             (prompt (strcat "\n  target " (_oms-fmt mshort) " x " (_oms-fmt mlong)
                             "   |   off-size (will change): " (itoa off)
                             "   already on size: " (itoa same)))
             (if (= off 0)
               (prompt "\n  Every module already matches -- nothing to do.")
               (progn
                 (initget "Yes No")
                 (setq ans (getkword (strcat "\nResize " (itoa off) " module(s)? [Yes/No] <No>: ")))
                 (if (/= ans "Yes")
                   (prompt "\nO-MODSIZE: cancelled -- nothing changed.")
                   (progn
                     (setq nchg 0 nsame 0 nfail 0)
                     (foreach r mods
                       (setq rs (min (nth 5 r) (nth 6 r)) rl (max (nth 5 r) (nth 6 r)))
                       (if (or (> (abs (- rs mshort)) tol) (> (abs (- rl mlong)) tol))
                         (progn
                           (setq wu (if (>= (nth 5 r) (nth 6 r)) mlong mshort)
                                 wv (if (>= (nth 5 r) (nth 6 r)) mshort mlong))
                           (if (and (= (nth 7 r) 4) (_oms-set-rect r wu wv))
                             (setq nchg (1+ nchg))
                             (setq nfail (1+ nfail))))
                         (setq nsame (1+ nsame))))
                     (prompt (strcat "\nO-MODSIZE: done -- " (itoa nchg) " resized, "
                                     (itoa nsame) " already on size"
                                     (if (> nfail 0) (strcat ", " (itoa nfail)
                                       " could not change (locked layer or not 4-corner)") "")
                                     "."))
                     (prompt "\n  Re-run O-MODSIZE Report (or O-SET) to confirm.")))))))))))
  (setq *error* old-err)
  (princ))

(defun C:OMODSIZE () (C:O-MODSIZE))

(prompt "\nO-MODSIZE v1.01 loaded. Type O-MODSIZE -> [Report/Normalize]. Report is read-only.")
(princ)
