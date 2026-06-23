;; ============================================================
;; ssa-1.1  --  SSA : Select array -- select every module in one array from a single click
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb SS (select) + noun A (array). A is a new noun extending the
;; VVN grammar -- it scopes selection to ONE contiguous module array, distinct from the
;; rostered SSM (select ALL modules, drawing-wide). Lives in opal-tools so it runs today,
;; on the ogeo shared library (the suite's geometry kernel).
;;
;; NOTE: superseded by QQA (which reports AND selects the array). Kept on disk; migrated
;; to the shared primitive so its seeding matches the rest of the suite if reactivated.
;;
;; COMMAND  SSA
;;   Click one module. The whole connected array is put into the active (gripped)
;;   selection set -- no window-drag. Run any command next (ERASE, MOVE, CHPROP,
;;   layer change, PROPERTIES) and it acts on the entire array.
;;
;; v1.1 -- click->array resolution now via the shared _ogeo-array-at (ogeo 1.05); dropped the
;;         local _ssa-nearest + inline scan. Seeds from the REAL-module set (was the raw
;;         _ogeo-all-modules), so SSA resolves the same array as QQA/O-MODSPACE for a click.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Click->array via shared _ogeo-array-at (real-module-seeded nearest + flood-fill).
;;   - Click-near, OSNAP OFF (the click need not land inside a module; never snapped to a
;;     distant entity). Selection delivered with (sssetfirst nil ss); nothing is modified.
;; ============================================================

(vl-load-com)

;; ============================================================
;; SSA  --  click a module -> select the whole array
;; ============================================================
(defun C:SSA ( / old-err old-os pt arr ss r)
  (vl-load-com)
  (setq old-err *error* old-os (getvar "OSMODE"))
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nSSA error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-ARRAY-AT" (atoms-family 1 (list "_OGEO-ARRAY-AT"))))
     (prompt "\nSSA: ogeo library not loaded (need v1.05+) -- run OLOAD."))
    (T
     (setvar "OSMODE" 0)
     (setq pt (getpoint "\nClick a module in the array to select: "))
     (if (null pt)
       (prompt "\nNothing picked.")
       (progn
         (setq arr (_ogeo-array-at (trans pt 1 0)))
         (if (null arr)
           (prompt "\nSSA: no array found near that point.")
           (progn
             (setq ss (ssadd))
             (foreach r arr (ssadd (car r) ss))
             (sssetfirst nil ss)
             (prompt (strcat "\nSSA: selected " (itoa (sslength ss))
                             " modules in the array (grips active -- run a command on them)."))))))))

  (setvar "OSMODE" old-os)
  (setq *error* old-err)
  (princ))

(prompt "\nSSA v1.1 loaded. Command: SSA  ->  click one module, select the whole array.")
(princ)
