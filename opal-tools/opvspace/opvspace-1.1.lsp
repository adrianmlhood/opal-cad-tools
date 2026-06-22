;; ============================================================
;; opvspace-1.1  --  O-PVSPACE : batch array spacing (every array in a layout)
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; COMMAND  O-PVSPACE / OPVSPACE
;;   Re-space many arrays in a PV layout in TWO phases:
;;     1. BATCH-PICK every array's anchor point (OSNAP on, snap to a corner). Each point
;;        detects its array (nearest module) and fixes that array's anchor row/col. Re-picking
;;        the same array is ignored. Enter/Esc finishes picking.
;;     2. PROMPT ONCE for the spacing params (rows + columns), resolved against the first
;;        picked array as representative. North-bay asks for the odd-bay end exactly once and
;;        reuses it for every array (arrays in a layout share orientation).
;;   Then a single combined plan + one [Yes/No] applies that one param set to EVERY picked
;;   array at once. Each array keeps its own anchored row/col fixed.
;;
;;   v1.1 -- two-phase (batch-pick, then one prompt, then apply-all). Replaces the v1.0
;;           per-array interleaved [Same/Configure/Skip] + per-array confirm.
;;
;;   Pure wrapper around O-MODSPACE's engine (_omsp-array-at / _omsp-rows-target /
;;   _omsp-cols-target / _omsp-apply-one) -- no duplicated spacing math. Modules only.
;; ============================================================

(vl-load-com)

(defun C:O-PVSPACE ( / old-err old-os old-ce pt arr seed picks pent dup done
                       first-arr us rtgt ctgt ans res nok nfail nchanged p)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (foreach p picks (redraw (caar (cadr p)) 4))   ; clear array highlights (seed ent)
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-PVSPACE error: " msg)))
    (princ))
  (setq old-os (getvar "OSMODE") old-ce (getvar "CMDECHO"))

  (cond
    ((not (member "_OMSP-APPLY-ONE" (atoms-family 1 (list "_OMSP-APPLY-ONE"))))
     (prompt "\nO-PVSPACE: O-MODSPACE engine not loaded -- run OLOAD."))
    (T
     ;; ---------------- Phase 1: batch-pick anchor points ----------------
     (setq picks nil done nil)
     (prompt "\nO-PVSPACE: pick an anchor point per array (snap to a corner); Enter to finish.")
     (while (not done)
       (setvar "OSMODE" (logior old-os 1))
       (setq pt (getpoint "\nAnchor point for an array (Enter to finish): "))
       (setvar "OSMODE" old-os)
       (if (null pt)
         (setq done T)
         (progn
           (setq arr (_omsp-array-at (trans pt 1 0)))
           (if (or (null arr) (< (length arr) 2))
             (prompt "\n  No array found near that point -- try again.")
             (progn
               (setq pent (caar arr) dup nil)   ; seed entity name of this array
               (foreach p picks (if (eq (caar (cadr p)) pent) (setq dup T)))
               (if dup
                 (prompt "\n  That array is already selected -- skipped.")
                 (progn
                   (setq picks (cons (list (trans pt 1 0) arr) picks))
                   (redraw pent 3)
                   (prompt (strcat "\n  array " (itoa (length picks)) ": "
                                   (itoa (length arr)) " modules.")))))))))

     (cond
       ((null picks)
        (prompt "\nO-PVSPACE: no arrays picked -- nothing to do."))
       (T
        (setq picks (reverse picks))
        ;; ---------------- Phase 2: prompt the spacing params ONCE ----------------
        (setq first-arr (cadr (car picks)) seed (car first-arr) us (nth 3 seed))
        (prompt (strcat "\nO-PVSPACE: " (itoa (length picks))
                        " array(s) selected. Spacing applies to all."))
        (setq rtgt (_omsp-rows-target first-arr
                                      (_ogeo-axis-groups first-arr us (* 0.5 (nth 5 seed)))
                                      us (nth 5 seed))
              ctgt (_omsp-cols-target (_ogeo-module-dims first-arr)))
        (cond
          ((and (null rtgt) (null ctgt))
           (prompt "\nO-PVSPACE: both axes skipped -- nothing to do."))
          (T
           ;; ---------------- Phase 3: one combined plan + confirm + apply all ----------------
           (prompt (strcat "\n\nO-PVSPACE plan (modules only) -- " (itoa (length picks))
                           " array(s):"))
           (if rtgt
             (prompt (strcat "\n  rows: "
                             (if (= (car rtgt) "uniform")
                               (strcat "uniform " (rtos (car (cadr rtgt)) 2 3))
                               (strcat "north-bay " (rtos (car (cadr rtgt)) 2 3)
                                       " / field " (rtos (cadr (cadr rtgt)) 2 3)
                                       " (odd bay at " (caddr rtgt) " end)")))))
           (if ctgt
             (prompt (strcat "\n  cols: uniform " (rtos ctgt 2 3))))
           (prompt "\n  (each array's anchored row/col stays fixed)")
           (initget "Yes No")
           (setq ans (getkword "\n\nApply to all? [Yes/No] <No>: "))
           (if (= ans "Yes")
             (progn
               (setq nok 0 nfail 0 nchanged 0)
               (foreach p picks
                 (setq res (_omsp-apply-one (cadr p) (car p) rtgt ctgt))
                 (if (> (car res) 0) (setq nchanged (1+ nchanged)))
                 (setq nok (+ nok (car res)) nfail (+ nfail (cadr res))))
               (prompt (strcat "\nO-PVSPACE: done -- " (itoa nchanged) " array(s) re-spaced, "
                               (itoa nok) " module-moves applied."))
               (if (> nfail 0)
                 (prompt (strcat "\n  WARNING: " (itoa nfail)
                                 " moves failed (locked layer?). Unlock and re-run.")))
               (prompt "\n  Run O-MODSPACE Measure to confirm."))
             (prompt "\nO-PVSPACE: cancelled -- nothing moved.")))))

       )                                ; end (cond picks)
     (foreach p picks (redraw (caar (cadr p)) 4))))   ; clear highlights (seed ent)

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; --- alias (O-Suite: dashed + undashed) ---
(defun C:OPVSPACE () (C:O-PVSPACE))

(prompt "\nO-PVSPACE v1.1 loaded. Command: O-PVSPACE / OPVSPACE -- batch-pick anchors, prompt once, space all.")
(princ)
