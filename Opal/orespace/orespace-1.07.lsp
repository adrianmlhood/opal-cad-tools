;; ============================================================
;; orespace-1.07  --  O-ROWSPACE : array row spacing (Set / Measure)
;; Ocotillo Labs LLC  --  O-Suite (Opal Energy, Solesca exports)
;;
;; CHANGES vs 1.06
;;   - Tighter UI. Both modes are now: select the array, then pick ONE module.
;;     The single module pick does everything:
;;       * measure layer        (its layer)
;;       * row direction         (its SHORT edge = stepping axis; exact, no
;;                                cosine error from hand-picked direction points)
;;       * anchor / fixed row    (Set: the row that module sits in stays fixed)
;;       * direction sign        (Set: auto-oriented so the array steps AWAY from
;;                                the fixed row -> that row becomes row 1)
;;   - Dropped the separate two-point direction pick and the separate measure-
;;     layer pick (the module pick replaces both).
;;   - No longer "assumes north": you designate the fixed row by picking a module
;;     in it (the north / first-bay row). Warns if that module isn't in an end row.
;;
;; MODES (O-ROWSPACE opens with [Set/Measure] <Set>)
;;   Set     = set absolute north-bay / field spacing and MOVE rows.
;;             Anchor row fixed; shift(0)=0, shift(k)=shift(k-1)+(target-current),
;;             so every gap lands on target exactly (corrects irregularities).
;;   Measure = report rows + current edge-to-edge inter-row spacing, NO move.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Direction from the module's SHORT edge (_ors-mod-stepdir): rotation-correct
;;     for landscape modules whose rows step along the short edge. If an array's
;;     rows step along the LONG edge the row count/spacing will look wrong in the
;;     plan (caught before any move) -- flag it and we add axis auto-detect.
;;   - Grouping center: midpoint of each entity's projected extent (full selection).
;;   - Row edges (readout + the Set move): true projected geometry via dual-path
;;     vertex read (LWPOLYLINE group 10 + heavyweight POLYLINE VERTEX walk,
;;     OCS->WCS by entity name); non-poly fall back to projected bbox corners.
;;     Module-layer filter excludes racking/strings. vl-catch-all-apply everywhere.
;;   - You SELECT the entities (ssget); details / SLDs / title blocks untouched.
;;     The MOVE acts on the FULL selection (everything in a row moves together).
;;   - Set always prints the plan and needs explicit Yes (default No) before moving.
;;   - vla-move per entity; locked-layer failures caught + reported as a fail count.
;; ============================================================

(vl-load-com)

;; --- normalize a 2D vector; (1 0) if degenerate ---
(defun _ors-norm (v / len)
  (setq len (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v)))))
  (if (> len 1e-9) (list (/ (car v) len) (/ (cadr v) len)) (list 1.0 0.0)))

;; --- scalar projection of point p onto unit dir d ---
(defun _ors-proj (p d) (+ (* (car p) (car d)) (* (cadr p) (cadr d))))

;; --- right-pad string s to width w ---
(defun _ors-pad (s w / r) (setq r s) (while (< (strlen r) w) (setq r (strcat r " "))) r)

;; --- is this VERTEX a real polyline corner? (skip spline-frame / mesh vertices) ---
(defun _ors-geom-vtx-p (vd / fl)
  (setq fl (cdr (assoc 70 vd)))
  (or (null fl)
      (and (= 0 (logand fl 16)) (= 0 (logand fl 64)) (= 0 (logand fl 128)))))

;; --- WCS corner points of an LWPOLYLINE or heavyweight POLYLINE; nil otherwise. ---
(defun _ors-poly-pts (ent / ed et pts pr v vd raw)
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
       (if (and (_ors-geom-vtx-p vd) raw (numberp (car raw)) (numberp (cadr raw)))
         (setq pts (cons (trans (list (car raw) (cadr raw) 0.0) ent 0) pts)))
       (setq v (entnext v)))))
  pts)

;; --- WCS bbox (minpt maxpt) of ANY entity via native VLA; nil on failure ---
(defun _ors-bbox (ent / res mn mx o)
  (setq res (vl-catch-all-apply
              (function (lambda ()
                (setq o (vlax-ename->vla-object ent))
                (vla-getboundingbox o 'mn 'mx)
                (list (vlax-safearray->list mn) (vlax-safearray->list mx))))))
  (if (vl-catch-all-error-p res) nil res))

;; --- WCS points bounding an entity: true poly corners else WCS bbox corners ---
(defun _ors-points (ent / pts bb)
  (setq pts (vl-catch-all-apply (function (lambda () (_ors-poly-pts ent)))))
  (if (vl-catch-all-error-p pts) (setq pts nil))
  (if (and pts (>= (length pts) 2))
    pts
    (if (setq bb (_ors-bbox ent))
      (list (list (car  (car bb)) (cadr (car  bb)))
            (list (car  (cadr bb)) (cadr (car  bb)))
            (list (car  (cadr bb)) (cadr (cadr bb)))
            (list (car  (car bb)) (cadr (cadr bb)))))))

;; --- projected extent of an entity onto dir d: (minproj maxproj center) or nil ---
(defun _ors-extent (ent d / pts p tp mn mx)
  (if (setq pts (_ors-points ent))
    (progn
      (foreach p pts
        (setq tp (_ors-proj p d))
        (if (or (null mn) (< tp mn)) (setq mn tp))
        (if (or (null mx) (> tp mx)) (setq mx tp)))
      (if (and mn mx) (list mn mx (/ (+ mn mx) 2.0))))))

;; --- row-stepping direction from a module: the SHORTER of two adjacent edges. ---
(defun _ors-mod-stepdir (ent / pts p0 p1 p2 e1 e2 l1 l2)
  (setq pts (_ors-points ent))
  (if (>= (length pts) 3)
    (progn
      (setq p0 (car pts) p1 (cadr pts) p2 (caddr pts)
            e1 (list (- (car p1) (car p0)) (- (cadr p1) (cadr p0)))
            e2 (list (- (car p2) (car p1)) (- (cadr p2) (cadr p1)))
            l1 (sqrt (+ (* (car e1) (car e1)) (* (cadr e1) (cadr e1))))
            l2 (sqrt (+ (* (car e2) (car e2)) (* (cadr e2) (cadr e2)))))
      (if (< l1 l2) (_ors-norm e1) (_ors-norm e2)))))

;; --- insertion sort of records (ent center minp maxp layer) ascending by center ---
(defun _ors-sort (lst / sorted xp tmp r inserted)
  (setq sorted '())
  (foreach xp lst
    (setq inserted nil tmp '())
    (foreach r sorted
      (if (and (not inserted) (< (cadr xp) (cadr r)))
        (progn (setq tmp (append tmp (list xp r))) (setq inserted T))
        (setq tmp (append tmp (list r)))))
    (setq sorted (if inserted tmp (append tmp (list xp)))))
  sorted)

;; --- group ascending recs into rows by center gap > tol. ---
(defun _ors-group (recs tol / groups cur prevp r p)
  (setq groups '() cur '() prevp nil)
  (foreach r recs
    (setq p (cadr r))
    (if (and prevp (> (- p prevp) tol))
      (progn (setq groups (cons (reverse cur) groups)) (setq cur '())))
    (setq cur (cons r cur))
    (setq prevp p))
  (if cur (setq groups (cons (reverse cur) groups)))
  (reverse groups))

;; --- (measuredCount nearEdge farEdge) of a row group; module layer preferred ---
(defun _ors-rowext (g mlayer / r mn mx cnt)
  (setq cnt 0)
  (foreach r g
    (if (or (null mlayer) (= (nth 4 r) mlayer))
      (progn
        (if (or (null mn) (< (caddr r)  mn)) (setq mn (caddr r)))
        (if (or (null mx) (> (cadddr r) mx)) (setq mx (cadddr r)))
        (setq cnt (1+ cnt)))))
  (if (and mlayer (= cnt 0))
    (progn
      (foreach r g
        (if (or (null mn) (< (caddr r)  mn)) (setq mn (caddr r)))
        (if (or (null mx) (> (cadddr r) mx)) (setq mx (cadddr r))))
      (setq cnt (length g))))
  (list cnt mn mx))

;; --- move one entity by (dx dy); T on success, nil on failure (e.g. locked) ---
(defun _ors-move (ent dx dy / res o)
  (setq res (vl-catch-all-apply
              (function (lambda ()
                (setq o (vlax-ename->vla-object ent))
                (vla-move o (vlax-3d-point 0.0 0.0 0.0) (vlax-3d-point dx dy 0.0))))))
  (if (vl-catch-all-error-p res) nil T))

;; --- build sorted, grouped rows from a selection set + direction ---
(defun _ors-rows (ss d tol / recs i n en ext nbad)
  (setq recs '() nbad 0 i 0 n (sslength ss))
  (while (< i n)
    (setq en (ssname ss i) ext (_ors-extent en d))
    (if ext
      (setq recs (cons (list en (caddr ext) (car ext) (cadr ext)
                             (cdr (assoc 8 (entget en)))) recs))
      (setq nbad (1+ nbad)))
    (setq i (1+ i)))
  (if (> nbad 0)
    (prompt (strcat "\n  (" (itoa nbad) " entit" (if (= nbad 1) "y" "ies")
                    " skipped -- no measurable geometry.)")))
  (_ors-group (_ors-sort recs) tol))

;; --- pick ONE module; return (mens mlayer dir) or nil. The module sets the
;;     measure layer and the row direction (its short edge). When orientp is T
;;     the direction is flipped so the module's end of the array is the LOW end
;;     (-> that row becomes row 1, the anchor). ---
(defun _ors-pick-setup (ss promptstr orientp / e mens mlayer d0 sumc cnt i n en ext pm mean)
  (setq e (entsel promptstr))
  (if e
    (progn
      (setq mens   (car e)
            mlayer (cdr (assoc 8 (entget mens)))
            d0     (_ors-mod-stepdir mens))
      (if d0
        (progn
          (if orientp
            (progn
              (setq sumc 0.0 cnt 0 i 0 n (sslength ss))
              (while (< i n)
                (setq en (ssname ss i) ext (_ors-extent en d0))
                (if ext (setq sumc (+ sumc (caddr ext)) cnt (1+ cnt)))
                (setq i (1+ i)))
              (setq ext  (_ors-extent mens d0)
                    pm   (if ext (caddr ext) 0.0)
                    mean (if (> cnt 0) (/ sumc cnt) pm))
              (if (< mean pm) (setq d0 (list (- (car d0)) (- (cadr d0)))))))
          (list mens mlayer d0))))))

;; --- is ent a member of group g (list of recs whose car is the ename)? ---
(defun _ors-in-group (ent g / found r)
  (setq found nil)
  (foreach r g (if (equal (car r) ent) (setq found T)))
  found)

;; --- Measure report: rows + current inter-row spacing (no move) ---
(defun _ors-report (groups mlayer / k g ext2 rmin rmax prevmax sp gaps mn mx sm)
  (prompt (strcat "\nO-ROWSPACE Measure: " (itoa (length groups)) " rows detected."))
  (setq k 0 prevmax nil gaps '())
  (foreach g groups
    (setq ext2 (_ors-rowext g mlayer)
          rmin (cadr ext2)
          rmax (caddr ext2)
          sp   (if prevmax (- rmin prevmax) nil))
    (prompt (strcat "\n  row " (_ors-pad (itoa (1+ k)) 5)
                    " ents " (_ors-pad (itoa (car ext2)) 6)
                    " inter-row spacing(prev) " (if sp (rtos sp 2 3) "--")))
    (if sp (setq gaps (cons sp gaps)))
    (setq prevmax rmax k (1+ k)))
  (if gaps
    (progn
      (setq mn (car gaps) mx (car gaps) sm 0.0)
      (foreach sp gaps
        (if (< sp mn) (setq mn sp))
        (if (> sp mx) (setq mx sp))
        (setq sm (+ sm sp)))
      (prompt (strcat "\n  inter-row spacing (edge-to-edge):  min " (rtos mn 2 3)
                      "   max " (rtos mx 2 3)
                      "   avg " (rtos (/ sm (length gaps)) 2 3))))))

;; ============================================================
;; O-ROWSPACE  --  [Set/Measure]
;; ============================================================
(defun C:O-ROWSPACE ( / old-err old-os old-ce mode ss setup mens d mlayer tol north field
                        groups k g ext2 rmin rmax prevmax prevs cur tgt s shifts
                        dx dy ans nmoved nfail r)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-ROWSPACE error: " msg)))
    (princ))
  (setq old-os (getvar "OSMODE") old-ce (getvar "CMDECHO"))

  (initget "Set Measure")
  (setq mode (getkword "\nO-ROWSPACE [Set/Measure] <Set>: "))
  (if (null mode) (setq mode "Set"))

  (cond
    ;; ---------------- MEASURE ----------------
    ((= mode "Measure")
     (prompt "\nO-ROWSPACE Measure: select array entities to analyze (no changes made):")
     (setq ss (ssget))
     (if (null ss)
       (prompt "\nNothing selected.")
       (progn
         (setq setup (_ors-pick-setup ss "\nPick ONE module (sets the layer + row direction): " nil))
         (if (null setup)
           (prompt "\nNo module picked (or its orientation couldn't be read) -- aborted.")
           (progn
             (setq mens (car setup) mlayer (cadr setup) d (caddr setup))
             (prompt (strcat "\n  measuring from layer: " mlayer
                             "  (direction from module short edge)"))
             (setq tol (getreal "\nRow grouping tolerance <3.0>: "))
             (if (null tol) (setq tol 3.0))
             (_ors-report (_ors-rows ss d tol) mlayer))))))

    ;; ---------------- SET ----------------
    (T
     (prompt "\nO-ROWSPACE Set: select array entities to re-space (modules, racking, strings):")
     (setq ss (ssget))
     (if (null ss)
       (prompt "\nNothing selected.")
       (progn
         (setq setup (_ors-pick-setup ss "\nPick a module in the row that stays FIXED (north / first-bay row): " T))
         (if (null setup)
           (prompt "\nNo module picked (or its orientation couldn't be read) -- aborted.")
           (progn
             (setq mens (car setup) mlayer (cadr setup) d (caddr setup))
             (prompt (strcat "\n  fixed row + spacing layer: " mlayer))
             (setq north (getreal "\nNorth-bay inter-row spacing (first gap) <13.5>: "))
             (if (null north) (setq north 13.5))
             (setq field (getreal "\nField inter-row spacing (all other gaps) <14.5>: "))
             (if (null field) (setq field 14.5))
             (setq tol (getreal "\nRow grouping tolerance <3.0>: "))
             (if (null tol) (setq tol 3.0))

             (setq groups (_ors-rows ss d tol))
             (if (< (length groups) 2)
               (prompt "\nFewer than 2 rows detected -- nothing to move. Try a larger tolerance, or the rows may step along the module's long edge (Measure to check).")
               (progn
                 (if (not (_ors-in-group mens (car groups)))
                   (prompt "\n  NOTE: the module you picked is NOT in an end row. The fixed/north row should be an end row -- row 1 below is treated as the anchor; re-pick if that's wrong."))
                 ;; --- plan: per-row shift so each gap hits its target exactly ---
                 (prompt (strcat "\n\nO-ROWSPACE Set plan -- " (itoa (length groups))
                                 " rows; targets: north bay " (rtos north 2 3)
                                 ", field " (rtos field 2 3) " (row 1 = anchor, fixed):"))
                 (prompt "\n  row   ents   current    target     shift")
                 (setq k 0 prevmax nil prevs 0.0 shifts '())
                 (foreach g groups
                   (setq ext2 (_ors-rowext g mlayer)
                         rmin (cadr ext2)
                         rmax (caddr ext2))
                   (if (= k 0)
                     (setq s 0.0 cur nil tgt nil)
                     (setq cur (- rmin prevmax)
                           tgt (if (= k 1) north field)
                           s   (+ prevs (- tgt cur))))
                   (setq shifts (cons s shifts))
                   (prompt (strcat "\n  "
                                   (_ors-pad (itoa (1+ k)) 6)
                                   (_ors-pad (itoa (car ext2)) 7)
                                   (_ors-pad (if cur (rtos cur 2 3) "--") 11)
                                   (_ors-pad (if tgt (rtos tgt 2 3) "--") 11)
                                   (rtos s 2 3) "\""))
                   (setq prevmax rmax prevs s k (1+ k)))
                 (setq shifts (reverse shifts))
                 ;; --- confirm ---
                 (initget "Yes No")
                 (setq ans (getkword "\n\nApply this re-spacing? [Yes/No] <No>: "))
                 (if (= ans "Yes")
                   (progn
                     (setq k 0 nmoved 0 nfail 0)
                     (foreach g groups
                       (setq s (nth k shifts))
                       (if (> (abs s) 1e-9)
                         (progn
                           (setq dx (* s (car d)) dy (* s (cadr d)))
                           (foreach r g
                             (if (_ors-move (car r) dx dy)
                               (setq nmoved (1+ nmoved))
                               (setq nfail (1+ nfail))))))
                       (setq k (1+ k)))
                     (prompt (strcat "\nO-ROWSPACE Set: done -- " (itoa nmoved) " entities moved across "
                                     (itoa (1- (length groups))) " rows. Run O-ROWSPACE Measure to confirm."))
                     (if (> nfail 0)
                       (prompt (strcat "\n  WARNING: " (itoa nfail)
                                       " entities could not move (locked layer?). Unlock and re-run."))))
                   (prompt "\nO-ROWSPACE Set: cancelled -- nothing moved."))))))))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; --- alias (O-Suite: dashed + undashed) ---
(defun C:OROWSPACE () (C:O-ROWSPACE))

(prompt "\nO-ROWSPACE v1.07 loaded. Command: O-ROWSPACE / OROWSPACE  ->  [Set/Measure]")
(princ)
