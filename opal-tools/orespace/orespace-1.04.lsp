;; ============================================================
;; orespace-1.04  --  O-RESPACE / O-SPACE  : array row re-spacing
;; Companion: O-ROWS  (measure-only: report rows + inter-row spacing, no move)
;; Ocotillo Labs LLC  --  O-Suite (Opal Energy, Solesca exports)
;;
;; CHANGES vs 1.03
;;   - ABSOLUTE target distances instead of relative deltas. You now enter the
;;     desired inter-row spacing for the NORTH BAY (first gap) and the FIELD rows
;;     (every other gap). The tool sets every gap EXACTLY to its target -- so the
;;     result is even regardless of current irregularities (per-row anomalies and
;;     any uniform offset are both corrected in one pass).
;;       shift(0) = 0  (anchor row, fixed)
;;       shift(k) = shift(k-1) + (target_gap(k) - current_gap(k))      k >= 1
;;     Each gap independently lands on target; no error accumulates.
;;   - Because the MOVE now uses the measured edges, the module pick matters for
;;     the RESULT (not just the readout). If you skip it, O-RESPACE warns that
;;     spacing is measured from all selected entities (racking/strings included).
;;   - Plan table columns: row / ents / current / target / shift.
;;   - Defaults: north bay 13.5, field 14.5 (Unirac RM10 EVO).
;;
;; PURPOSE
;;   Re-space an array's rows to exact inter-row spacing (e.g. converting a layout
;;   to Unirac RM10 EVO). Anchor row stays put; every other row is repositioned so
;;   its gap to the previous row equals the target you set.
;;
;; WHY A DIRECTION VECTOR (not "south = -Y")
;;   Solesca exports modules ROTATED to the site/racking orientation. So the
;;   spacing direction is picked: click the row that STAYS FIXED, then click
;;   toward the rows that move. Every selected entity is projected onto that
;;   direction; entities at the same projected position = one row. Rows sort from
;;   the anchor (smallest projection) outward.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Grouping center: midpoint of each entity's projected extent (full selection).
;;   - Row edges (drive both the readout AND the move): true projected geometry via
;;     dual-path vertex read (LWPOLYLINE group 10 + heavyweight POLYLINE VERTEX
;;     walk, OCS->WCS by entity name); non-poly fall back to projected bbox corners.
;;     Optional module-layer filter so racking/strings are excluded. All wrapped in
;;     vl-catch-all-apply -- an unmeasurable entity is skipped, never fatal.
;;   - You SELECT the entities (ssget); details / SLDs / title blocks untouched.
;;     The MOVE acts on the FULL selection (everything in a row moves together).
;;   - Always prints the plan and requires explicit Yes (default No) before moving.
;;   - vla-move per entity; locked-layer failures caught + reported as a fail count.
;; ============================================================

(vl-load-com)

;; --- normalize a 2D vector; (1 0) if degenerate ---
(defun _ors-norm (v / len)
  (setq len (sqrt (+ (* (car v) (car v)) (* (cadr v) (cadr v)))))
  (if (> len 1e-9) (list (/ (car v) len) (/ (cadr v) len)) (list 1.0 0.0)))

;; --- unit WCS direction from UCS points a -> b ---
(defun _ors-dir (a b / aw bw)
  (setq aw (trans a 1 0) bw (trans b 1 0))
  (_ors-norm (list (- (car bw) (car aw)) (- (cadr bw) (cadr aw)))))

;; --- scalar projection of point p onto unit dir d ---
(defun _ors-proj (p d) (+ (* (car p) (car d)) (* (cadr p) (cadr d))))

;; --- right-pad string s to width w ---
(defun _ors-pad (s w / r) (setq r s) (while (< (strlen r) w) (setq r (strcat r " "))) r)

;; --- is this VERTEX a real polyline corner? (skip spline-frame / mesh vertices) ---
(defun _ors-geom-vtx-p (vd / fl)
  (setq fl (cdr (assoc 70 vd)))
  (or (null fl)
      (and (= 0 (logand fl 16)) (= 0 (logand fl 64)) (= 0 (logand fl 128)))))

;; --- WCS corner points of an LWPOLYLINE or heavyweight POLYLINE; nil otherwise.
;;     Numeric-validated: only points whose x AND y are numbers reach (trans). ---
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

;; --- WCS points that bound an entity along any direction: true polyline corners
;;     if available, else the four WCS bbox corners. nil if nothing measurable. ---
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

;; --- group ascending recs into rows by center gap > tol.
;;     Returns groups (ascending); each group = list of recs (ent center minp maxp layer). ---
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

;; --- (measuredCount nearEdge farEdge) of a row group along the direction.
;;     If mlayer is set, edges come from that layer only; a row with none of that
;;     layer falls back to all its entities. ---
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

;; --- prompt for spacing direction (two-point pick); unit WCS vector or nil ---
(defun _ors-get-dir ( / old-os p1 p2)
  (setq old-os (getvar "OSMODE"))
  (setvar "OSMODE" 0)
  (setq p1 (getpoint "\nPick a point AT the row that stays fixed: "))
  (if p1 (setq p2 (getpoint p1 "\nPick a point toward the rows that move: ")))
  (setvar "OSMODE" old-os)
  (if (and p1 p2) (_ors-dir p1 p2)))

;; --- prompt for an optional module layer (pick one module); nil = measure all ---
(defun _ors-get-mlayer ( / e ly)
  (setq e (entsel "\nPick ONE module to measure spacing from its layer (or Enter = all selected): "))
  (if e
    (progn
      (setq ly (cdr (assoc 8 (entget (car e)))))
      (prompt (strcat "\n  measuring inter-row spacing from layer: " ly))
      ly)))

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

;; ============================================================
;; O-RESPACE -- the re-spacing command (absolute target spacing)
;; ============================================================
(defun C:O-RESPACE ( / old-err old-os old-ce ss d mlayer tol north field groups
                       k g ext2 rmin rmax prevmax prevs cur tgt s shifts
                       dx dy ans nmoved nfail r)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-RESPACE error: " msg)))
    (princ))
  (setq old-os (getvar "OSMODE") old-ce (getvar "CMDECHO"))

  (prompt "\nO-RESPACE: select array entities to re-space (modules, racking, strings):")
  (setq ss (ssget))
  (cond
    ((null ss) (prompt "\nNothing selected."))
    ((null (setq d (_ors-get-dir)))
     (prompt "\nNo spacing direction given -- aborted."))
    (T
     (setq mlayer (_ors-get-mlayer))
     (if (null mlayer)
       (prompt "\n  WARNING: no module picked -- spacing measured from ALL selected entities (racking/strings can skew it). Check the 'current' column against O-ROWS before you confirm."))
     (setq north (getreal "\nNorth-bay inter-row spacing (first gap) <13.5>: "))
     (if (null north) (setq north 13.5))
     (setq field (getreal "\nField inter-row spacing (all other gaps) <14.5>: "))
     (if (null field) (setq field 14.5))
     (setq tol (getreal "\nRow grouping tolerance <3.0>: "))
     (if (null tol) (setq tol 3.0))

     (setq groups (_ors-rows ss d tol))
     (if (< (length groups) 2)
       (prompt "\nFewer than 2 rows detected -- nothing to move. Try a larger tolerance or recheck the direction (O-ROWS).")
       (progn
         ;; --- plan: compute per-row shift so each gap hits its target exactly ---
         (prompt (strcat "\n\nO-RESPACE plan -- " (itoa (length groups))
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
             (prompt (strcat "\nO-RESPACE: done -- " (itoa nmoved) " entities moved across "
                             (itoa (1- (length groups))) " rows. Re-run O-ROWS to confirm."))
             (if (> nfail 0)
               (prompt (strcat "\n  WARNING: " (itoa nfail)
                               " entities could not move (locked layer?). Unlock and re-run."))))
           (prompt "\nO-RESPACE: cancelled -- nothing moved."))))))
  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; ============================================================
;; O-ROWS -- measure-only: report detected rows + inter-row spacing, no move
;; ============================================================
(defun C:O-ROWS ( / ss d mlayer tol groups k g ext2 rmin rmax prevmax sp gaps mn mx sm)
  (vl-load-com)
  (prompt "\nO-ROWS: select array entities to analyze (no changes made):")
  (setq ss (ssget))
  (cond
    ((null ss) (prompt "\nNothing selected."))
    ((null (setq d (_ors-get-dir))) (prompt "\nNo spacing direction given -- aborted."))
    (T
     (setq mlayer (_ors-get-mlayer))
     (setq tol (getreal "\nRow grouping tolerance <3.0>: "))
     (if (null tol) (setq tol 3.0))
     (setq groups (_ors-rows ss d tol))
     (prompt (strcat "\nO-ROWS: " (itoa (length groups)) " rows detected."))
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
                         "   avg " (rtos (/ sm (length gaps)) 2 3)))
         (prompt "\n  (uniform spacing = clean detection; if it still varies, pick a module so racking/strings are excluded)")))))
  (princ))

;; --- aliases (O-Suite: dashed + undashed) ---
(defun C:ORESPACE () (C:O-RESPACE))
(defun C:O-SPACE  () (C:O-RESPACE))
(defun C:OSPACE   () (C:O-RESPACE))
(defun C:OROWS    () (C:O-ROWS))

(prompt "\nO-RESPACE v1.04 loaded. Commands: O-RESPACE / O-SPACE  (set spacing)  |  O-ROWS  (check only)")
(princ)
