;; ============================================================
;; ssa-2.0  --  SSA : SELECT ARRAYS -- select every real PV module, report total + per-array breakdown
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb SS (select) + noun A (arrays), drawing-wide. SSA is now the ONE
;; select/query command for modules -- it folds in the old SSA (select one array), QQA
;; (query + select one array), SSM (select all modules) and the "QQM" (query all modules)
;; readout. One command: selects every REAL module across the drawing and prints a per-array
;; breakdown. Lives in opal-tools so it runs today, on the ogeo shared library.
;;
;; COMMAND  SSA  (SELECT ARRAYS)
;;   No pick. Collects every REAL PV module (ogeo: configured layer + footprint gate +
;;   viewport filter), grip-selects them all, and prints:
;;     - total REAL modules selected (never the raw PV-MODS element count)
;;     - number of distinct arrays (proximity flood-fill)
;;     - module footprint
;;     - a per-array breakdown line: modules + rows x cols, largest array first
;;   Run any command next (ERASE / MOVE / CHPROP / layer change / PROPERTIES) on the whole set.
;;
;; v2.0 -- REWRITE + fold. Was "click one module -> select its array" (superseded by QQA). Now the
;;         unified drawing-wide SELECT ARRAYS: total real modules + per-array breakdown. Built on
;;         the shared _ogeo-modules / _ogeo-array-from / _ogeo-axis-groups -- no geometry math here.
;;         Reports ONLY real modules; the PV-MODS raw element count is never shown (ogeo 1.07
;;         dropped that line from the shared collector, so no O-Suite tool prints it).
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Real-module set from the shared _ogeo-modules (layer + graceful fallback + footprint gate
;;     + viewport filter), so SSA counts exactly what O-SET counts.
;;   - Arrays via flood-fill (_ogeo-array-from) over the real set, marking visited enames with the
;;     built-in (member) (no lambda). Per-array rows/cols via _ogeo-axis-groups (rows step along
;;     the module SHORT edge, columns along the LONG edge -- same as QQA / O-MODSPACE).
;; ============================================================

(vl-load-com)

;; insertion-sort a list of arrays (each a record list) by module count, DESCENDING
(defun _ssa-by-size (arrs / out a ins tmp x)
  (setq out nil)
  (foreach a arrs
    (setq ins nil tmp nil)
    (foreach x out
      (if (and (not ins) (> (length a) (length x)))
        (progn (setq tmp (append tmp (list a x)) ins T))
        (setq tmp (append tmp (list x)))))
    (setq out (if ins tmp (append tmp (list a)))))
  out)

;; ============================================================
;; SSA  --  select every real PV module, drawing-wide, with a per-array breakdown
;; ============================================================
(defun C:SSA ( / old-err recs ss r arrs visited arr a dims total idx seed rgroups cgroups)
  (setq old-err *error*)
  (defun *error* (msg)
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nSSA error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-MODULES" (atoms-family 1 (list "_OGEO-MODULES"))))
     (prompt "\nSSA: ogeo library not loaded (need v1.07+) -- run OLOAD."))
    (T
     (setq recs (_ogeo-modules))
     (if (null recs)
       (prompt "\nSSA: no PV modules found.")
       (progn
         ;; select every real module
         (setq ss (ssadd))
         (foreach r recs (ssadd (car r) ss))
         (sssetfirst nil ss)
         ;; flood the real set into distinct arrays (visited ename list, member test, no lambda)
         (setq arrs nil visited nil)
         (foreach r recs
           (if (not (member (car r) visited))
             (progn
               (setq arr  (_ogeo-array-from (car r) recs)
                     arrs (cons arr arrs))
               (foreach a arr (setq visited (cons (car a) visited))))))
         (setq arrs  (_ssa-by-size arrs)
               total (length recs)
               dims  (_ogeo-module-dims recs))
         ;; ---- drawing-wide summary (real modules only) ----
         (prompt "\n")
         (prompt (strcat "\n  MODULES   " (itoa total)
                         " real modules selected (grips active -- run a command on them)"))
         (prompt (strcat "\n  ARRAYS    " (itoa (length arrs))))
         (if dims
           (prompt (strcat "\n  MODULE    " (rtos (car dims) 2 2) " x " (rtos (cadr dims) 2 2))))
         ;; ---- per-array breakdown (largest first) ----
         (prompt "\n")
         (setq idx 1)
         (foreach arr arrs
           (setq seed    (car arr)
                 rgroups (_ogeo-axis-groups arr (nth 3 seed) (* 0.5 (nth 5 seed)))
                 cgroups (_ogeo-axis-groups arr (nth 4 seed) (* 0.5 (nth 6 seed))))
           (prompt (strcat "\n    Array " (itoa idx) "   "
                           (itoa (length arr)) " modules   ("
                           (itoa (length rgroups)) " x " (itoa (length cgroups)) ")"))
           (setq idx (1+ idx)))))))

  (setq *error* old-err)
  (princ))

(prompt "\nSSA v2.0 loaded. Command: SSA (SELECT ARRAYS) -> select every real module + per-array breakdown.")
(princ)
