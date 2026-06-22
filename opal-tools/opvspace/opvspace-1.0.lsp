;; ============================================================
;; opvspace-1.0  --  O-PVSPACE : batch array spacing (every array in a layout)
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; COMMAND  O-PVSPACE / OPVSPACE
;;   Re-space EVERY array in a PV layout. Pick an anchor point per array (OSNAP on,
;;   snap to a corner); the array is detected from the nearest module, and its rows +
;;   columns are corrected with that corner's row/col held fixed. Enter/Esc finishes.
;;
;;   The FIRST array you pick is configured (rows pattern + column gap). For each later
;;   array: [Same/Configure/Skip] -- Same reuses the previous settings (endside is the
;;   same physical end across a layout, since arrays share orientation), Configure asks
;;   again (re-picks the north row for North-bay), Skip leaves that array untouched.
;;
;;   Pure wrapper around O-MODSPACE's engine (_omsp-array-at / _omsp-rows-target /
;;   _omsp-cols-target / _omsp-set-one) -- no duplicated spacing math. Modules only.
;; ============================================================

(vl-load-com)

(defun C:O-PVSPACE ( / old-err old-os old-ce pt arr seed us kw rtgt ctgt
                       lastr lastc first done nchanged)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-PVSPACE error: " msg)))
    (princ))
  (setq old-os (getvar "OSMODE") old-ce (getvar "CMDECHO"))

  (cond
    ((not (member "_OMSP-SET-ONE" (atoms-family 1 (list "_OMSP-SET-ONE"))))
     (prompt "\nO-PVSPACE: O-MODSPACE engine not loaded -- run OLOAD."))
    (T
     (setq nchanged 0 lastr nil lastc nil first T done nil)
     (prompt "\nO-PVSPACE: re-space every array. Pick an anchor point per array; Enter to finish.")
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
               (setq seed (car arr) us (nth 3 seed))
               (prompt (strcat "\n  Array: " (itoa (length arr)) " modules."))
               (if first
                 (progn
                   (setq rtgt (_omsp-rows-target arr (_ogeo-axis-groups arr us (* 0.5 (nth 5 seed)))
                                                 us (nth 5 seed))
                         ctgt (_omsp-cols-target (_ogeo-module-dims arr))
                         lastr rtgt lastc ctgt first nil))
                 (progn
                   (initget "Same Configure Skip")
                   (setq kw (getkword "\n  Spacing for this array? [Same/Configure/Skip] <Same>: "))
                   (cond
                     ((= kw "Skip") (setq rtgt (quote skip) ctgt nil))
                     ((= kw "Configure")
                      (setq rtgt (_omsp-rows-target arr (_ogeo-axis-groups arr us (* 0.5 (nth 5 seed)))
                                                    us (nth 5 seed))
                            ctgt (_omsp-cols-target (_ogeo-module-dims arr))
                            lastr rtgt lastc ctgt))
                     (T (setq rtgt lastr ctgt lastc)))))    ; Same / Enter
               (cond
                 ((eq rtgt (quote skip)) (prompt "\n  Skipped."))
                 ((and (null rtgt) (null ctgt)) (prompt "\n  Both axes skipped for this array."))
                 (T (if (_omsp-set-one arr (trans pt 1 0) rtgt ctgt)
                      (setq nchanged (1+ nchanged))))))))))
     (prompt (strcat "\nO-PVSPACE: done -- " (itoa nchanged) " array(s) re-spaced. Run O-MODSPACE Measure to confirm."))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; --- alias (O-Suite: dashed + undashed) ---
(defun C:OPVSPACE () (C:O-PVSPACE))

(prompt "\nO-PVSPACE v1.0 loaded. Command: O-PVSPACE / OPVSPACE -- batch-space every array.")
(princ)
