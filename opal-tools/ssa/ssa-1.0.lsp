;; ============================================================
;; ssa-1.0  --  SSA : Select array -- select every module in one array from a single click
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb SS (select) + noun A (array). A is a new noun extending the
;; VVN grammar -- it scopes selection to ONE contiguous module array, distinct from the
;; rostered SSM (select ALL modules, drawing-wide). Lives in opal-tools so it runs today,
;; on the ogeo shared library (the suite's geometry kernel).
;;
;; COMMAND  SSA
;;   Click one module. The whole connected array is put into the active (gripped)
;;   selection set -- no window-drag. Run any command next (ERASE, MOVE, CHPROP,
;;   layer change, PROPERTIES) and it acts on the entire array.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - All geometry via shared ogeo: records (_ogeo-all-modules, with graceful layer
;;     fallback) + proximity flood-fill (_ogeo-array-from). No geometry re-implemented.
;;   - Click-near, OSNAP OFF (read-only interaction, same as O-MODSPACE Measure): the
;;     seed = the module whose centre is nearest the click point. The click need not land
;;     exactly inside a module, and it is never snapped to a distant entity.
;;   - Selection is delivered with (sssetfirst nil ss) so the array shows grips and is the
;;     pickfirst set for the next command. Nothing is modified.
;; ============================================================

(vl-load-com)

;; --- record whose centre is nearest WCS point pt ---
(defun _ssa-nearest (recs pt / best bd r d)
  (setq best nil bd nil)
  (foreach r recs
    (setq d (distance (nth 2 r) pt))
    (if (or (null bd) (< d bd)) (setq bd d best r)))
  best)

;; ============================================================
;; SSA  --  click a module -> select the whole array
;; ============================================================
(defun C:SSA ( / old-err old-os pt recs seed arr ss r)
  (vl-load-com)
  (setq old-err *error* old-os (getvar "OSMODE"))
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nSSA error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-ARRAY-FROM" (atoms-family 1 (list "_OGEO-ARRAY-FROM"))))
     (prompt "\nSSA: ogeo library not loaded -- run OLOAD."))
    (T
     (setvar "OSMODE" 0)
     (setq pt (getpoint "\nClick a module in the array to select: "))
     (if (null pt)
       (prompt "\nNothing picked.")
       (progn
         (setq recs (_ogeo-all-modules))
         (if (null recs)
           (prompt "\nSSA: no modules found.")
           (progn
             (setq seed (_ssa-nearest recs (trans pt 1 0))
                   arr  (if seed (_ogeo-array-from (car seed) recs) nil))
             (if (null arr)
               (prompt "\nSSA: no array found near that point.")
               (progn
                 (setq ss (ssadd))
                 (foreach r arr (ssadd (car r) ss))
                 (sssetfirst nil ss)
                 (prompt (strcat "\nSSA: selected " (itoa (sslength ss))
                                 " modules in the array (grips active -- run a command on them)."))))))))))

  (setvar "OSMODE" old-os)
  (setq *error* old-err)
  (princ))

(prompt "\nSSA v1.0 loaded. Command: SSA  ->  click one module, select the whole array.")
(princ)
