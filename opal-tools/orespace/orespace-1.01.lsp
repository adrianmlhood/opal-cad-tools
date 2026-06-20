;; ============================================================
;; orespace-1.01  --  O-RESPACE / O-SPACE  : array row re-spacing
;; Companion: O-RSCHK  (measure-only: report rows + current pitch, no move)
;; Ocotillo Labs LLC  --  O-Suite (Opal Energy, Solesca exports)
;;
;; CHANGES vs 1.0
;;   - Dropped the X / Y axis direction options. Direction is ALWAYS the
;;     two-point pick now (click the fixed row, then click toward the moving
;;     rows) -- no keyword prompt. Removed the unused _ors-ucs-axis helper.
;;
;; PURPOSE
;;   Re-space an array's rows when the racking system changes (e.g. Unirac
;;   GridFlex 10 -> RM10 EVO). Keeps the anchor row fixed and pushes every
;;   subsequent row away from it by a cumulative gap change, so all inter-row
;;   gaps grow (or shrink) by the amounts you specify.
;;
;; WHY A DIRECTION VECTOR (not "south = -Y")
;;   Solesca exports modules ROTATED to the site/racking orientation -- they are
;;   NOT axis-aligned to WCS, and on this drawing the rows step left-right, not
;;   up-down. So the spacing direction is picked, not assumed: click the row
;;   that STAYS FIXED, then click toward the rows that should move. Works at ANY
;;   rotation. Every selected entity's WCS bbox center is projected onto that
;;   direction; entities at the same projected position = one row. Rows are
;;   sorted from the anchor (smallest projection) outward. Row k (0 = anchor)
;;   shifts by
;;       0                         for the anchor row
;;       dlt1 + (k-1)*dlt2         for k >= 1
;;   along the spacing direction (positive = gaps grow). For RM10 EVO from a
;;   13" GridFlex baseline: dlt1 = 0.5 (north bay 13->13.5), dlt2 = 1.5 (others
;;   13->14.5). Negative deltas shrink gaps.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Bbox via native vla-getBoundingBox wrapped in vl-catch-all-apply -- works
;;     for heavyweight POLYLINE, LWPOLYLINE, INSERT, ARC, CIRCLE, TEXT, MTEXT,
;;     DIMENSION; a single unmeasurable entity is skipped, never fatal.
;;   - You SELECT the entities (ssget) so detail views / SLDs / title blocks are
;;     never touched. No layer filter -- you control scope via the selection.
;;   - Always prints the plan (rows / pitch / shift) and requires explicit Yes
;;     before moving. Default answer is No.
;;   - vla-move per entity; entities on locked layers fail gracefully and are
;;     reported as a fail count (unlock and re-run if needed).
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

;; --- WCS bbox (minpt maxpt) of ANY entity via native VLA; nil on failure ---
(defun _ors-bbox (ent / res mn mx o)
  (setq res (vl-catch-all-apply
              (function (lambda ()
                (setq o (vlax-ename->vla-object ent))
                (vla-getboundingbox o 'mn 'mx)
                (list (vlax-safearray->list mn) (vlax-safearray->list mx))))))
  (if (vl-catch-all-error-p res) nil res))

;; --- WCS center (x y) of an entity, or nil ---
(defun _ors-center (ent / bb)
  (if (setq bb (_ors-bbox ent))
    (list (/ (+ (car  (car bb)) (car  (cadr bb))) 2.0)
          (/ (+ (cadr (car bb)) (cadr (cadr bb))) 2.0))))

;; --- scalar projection of point p onto unit dir d ---
(defun _ors-proj (p d) (+ (* (car p) (car d)) (* (cadr p) (cadr d))))

;; --- right-pad string s to width w ---
(defun _ors-pad (s w / r) (setq r s) (while (< (strlen r) w) (setq r (strcat r " "))) r)

;; --- insertion sort of records ((ent proj) ...) ascending by proj ---
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

;; --- group ascending recs into rows by projection gap > tol.
;;     Returns groups (ascending coord); each group = list of recs (ent proj). ---
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

;; --- shared: build sorted, grouped rows from a selection set + direction ---
(defun _ors-rows (ss d tol / recs i n en ctr nbad)
  (setq recs '() nbad 0 i 0 n (sslength ss))
  (while (< i n)
    (setq en (ssname ss i) ctr (_ors-center en))
    (if ctr
      (setq recs (cons (list en (_ors-proj ctr d)) recs))
      (setq nbad (1+ nbad)))
    (setq i (1+ i)))
  (if (> nbad 0)
    (prompt (strcat "\n  (" (itoa nbad) " entit" (if (= nbad 1) "y" "ies")
                    " skipped -- no measurable bounding box.)")))
  (_ors-group (_ors-sort recs) tol))

;; ============================================================
;; O-RESPACE -- the re-spacing command
;; ============================================================
(defun C:O-RESPACE ( / old-err old-os old-ce ss d tol dlt1 dlt2 groups
                       k g coord prevcoord m dx dy ans nmoved nfail r)
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
     (setq dlt1 (getreal "\nFirst-gap spacing change (north bay) <0.5>: "))
     (if (null dlt1) (setq dlt1 0.5))
     (setq dlt2 (getreal "\nEach subsequent gap spacing change <1.5>: "))
     (if (null dlt2) (setq dlt2 1.5))
     (setq tol (getreal "\nRow grouping tolerance <3.0>: "))
     (if (null tol) (setq tol 3.0))

     (setq groups (_ors-rows ss d tol))
     (if (< (length groups) 2)
       (prompt "\nFewer than 2 rows detected -- nothing to move. Try a larger tolerance or recheck the direction (O-RSCHK).")
       (progn
         ;; --- plan ---
         (prompt (strcat "\n\nO-RESPACE plan -- " (itoa (length groups))
                         " rows along the spacing direction (row 1 = anchor, fixed):"))
         (prompt "\n  row   ents   pitch(prev)   shift")
         (setq k 0 prevcoord nil)
         (foreach g groups
           (setq coord (cadr (car g))
                 m     (if (= k 0) 0.0 (+ dlt1 (* (- k 1) dlt2))))
           (prompt (strcat "\n  "
                           (_ors-pad (itoa (1+ k)) 6)
                           (_ors-pad (itoa (length g)) 7)
                           (_ors-pad (if prevcoord (rtos (- coord prevcoord) 2 2) "--") 14)
                           (rtos m 2 3) "\""))
           (setq prevcoord coord k (1+ k)))
         ;; --- confirm ---
         (initget "Yes No")
         (setq ans (getkword "\n\nApply this re-spacing? [Yes/No] <No>: "))
         (if (= ans "Yes")
           (progn
             (setq k 0 nmoved 0 nfail 0)
             (foreach g groups
               (setq m (if (= k 0) 0.0 (+ dlt1 (* (- k 1) dlt2))))
               (if (> (abs m) 1e-9)
                 (progn
                   (setq dx (* m (car d)) dy (* m (cadr d)))
                   (foreach r g
                     (if (_ors-move (car r) dx dy)
                       (setq nmoved (1+ nmoved))
                       (setq nfail (1+ nfail))))))
               (setq k (1+ k)))
             (prompt (strcat "\nO-RESPACE: done -- " (itoa nmoved) " entities moved across "
                             (itoa (1- (length groups))) " shifted rows."))
             (if (> nfail 0)
               (prompt (strcat "\n  WARNING: " (itoa nfail)
                               " entities could not move (locked layer?). Unlock and re-run."))))
           (prompt "\nO-RESPACE: cancelled -- nothing moved."))))))
  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; ============================================================
;; O-RSCHK -- measure-only: report detected rows + current pitch, no move
;; ============================================================
(defun C:O-RSCHK ( / ss d tol groups k g coord prevcoord pitches mn mx sm p)
  (vl-load-com)
  (prompt "\nO-RSCHK: select array entities to analyze (no changes made):")
  (setq ss (ssget))
  (cond
    ((null ss) (prompt "\nNothing selected."))
    ((null (setq d (_ors-get-dir))) (prompt "\nNo spacing direction given -- aborted."))
    (T
     (setq tol (getreal "\nRow grouping tolerance <3.0>: "))
     (if (null tol) (setq tol 3.0))
     (setq groups (_ors-rows ss d tol))
     (prompt (strcat "\nO-RSCHK: " (itoa (length groups)) " rows detected."))
     (setq k 0 prevcoord nil pitches '())
     (foreach g groups
       (setq coord (cadr (car g)))
       (prompt (strcat "\n  row " (_ors-pad (itoa (1+ k)) 5)
                       " ents " (_ors-pad (itoa (length g)) 6)
                       " pitch(prev) " (if prevcoord (rtos (- coord prevcoord) 2 3) "--")))
       (if prevcoord (setq pitches (cons (- coord prevcoord) pitches)))
       (setq prevcoord coord k (1+ k)))
     (if pitches
       (progn
         (setq mn (car pitches) mx (car pitches) sm 0.0)
         (foreach p pitches
           (if (< p mn) (setq mn p))
           (if (> p mx) (setq mx p))
           (setq sm (+ sm p)))
         (prompt (strcat "\n  pitch center-to-center:  min " (rtos mn 2 3)
                         "   max " (rtos mx 2 3)
                         "   avg " (rtos (/ sm (length pitches)) 2 3)))
         (prompt "\n  (uniform pitch = clean row detection; a tiny pitch = two rows merged -> lower the tolerance)")))))
  (princ))

;; --- aliases (O-Suite: dashed + undashed) ---
(defun C:ORESPACE () (C:O-RESPACE))
(defun C:O-SPACE  () (C:O-RESPACE))
(defun C:OSPACE   () (C:O-RESPACE))
(defun C:ORSCHK   () (C:O-RSCHK))

(prompt "\nO-RESPACE v1.01 loaded. Commands: O-RESPACE / O-SPACE  (re-space)  |  O-RSCHK  (check only)")
(princ)
