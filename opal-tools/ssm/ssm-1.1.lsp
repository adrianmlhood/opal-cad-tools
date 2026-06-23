;; ============================================================
;; ssm-1.1  --  SSM : Select + query modules -- select every real PV module AND report
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb SS (select) + noun M (module), drawing-wide (cf. QQA = one array).
;; Lives in opal-tools so it runs today, on the ogeo shared library.
;;
;; COMMAND  SSM
;;   No pick. Collects every real PV module (ogeo + the modal-footprint filter O-SET uses),
;;   puts them in the active (gripped) selection set, AND prints a drawing-wide readout
;;   (total modules, distinct arrays, module footprint). Run any command next.
;;
;; v1.1 -- fold the "query all modules" (QQM) readout into SSM: after selecting, report the
;;         total module count, the number of distinct arrays (flood-fill over the real set),
;;         and the module footprint. One command selects AND reports drawing-wide.
;;
;; COLLISION NOTE: acad.pgp aliases SSM -> *SHEETSET. A LISP-defined C:SSM is expected to
;;   shadow that pgp alias (command beats alias); acad.pgp is NOT edited (per VVN rule).
;;   VERIFY live: type SSM and confirm it selects rather than opening Sheet Set Manager.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Modules via the shared _ogeo-modules entry (ogeo 1.04: _ogeo-all-modules configured-layer
;;     scan + graceful fallback + viewport filter, then the _ogeo-real-modules footprint gate),
;;     so clutter on the module layer is not selected. No geometry re-implemented.
;;   - Array count = flood-fill (_ogeo-array-from) over the real set, marking visited enames
;;     (member test, no lambda). Footprint via _ogeo-module-dims. Selection via sssetfirst.
;; ============================================================

(vl-load-com)

;; ============================================================
;; SSM  --  select + query every real PV module, drawing-wide
;; ============================================================
(defun C:SSM ( / old-err recs ss r arrs visited arr a dims)
  (setq old-err *error*)
  (defun *error* (msg)
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nSSM error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-MODULES" (atoms-family 1 (list "_OGEO-MODULES"))))
     (prompt "\nSSM: ogeo library not loaded (need v1.04+) -- run OLOAD."))
    (T
     (setq recs (_ogeo-modules))
     (if (null recs)
       (prompt "\nSSM: no PV modules found.")
       (progn
         ;; select every real module
         (setq ss (ssadd))
         (foreach r recs (ssadd (car r) ss))
         (sssetfirst nil ss)
         ;; query: distinct arrays via flood-fill, marking visited enames (no lambda)
         (setq arrs 0  visited '())
         (foreach r recs
           (if (not (member (car r) visited))
             (progn
               (setq arr  (_ogeo-array-from (car r) recs)
                     arrs (1+ arrs))
               (foreach a arr (setq visited (cons (car a) visited))))))
         (setq dims (_ogeo-module-dims recs))
         (prompt (strcat "\n  MODULES   " (itoa (sslength ss)) " (grips active -- run a command on them)"))
         (prompt (strcat "\n  ARRAYS    " (itoa arrs)))
         (if dims
           (prompt (strcat "\n  MODULE    " (rtos (car dims) 2 2) " x " (rtos (cadr dims) 2 2))))))))

  (setq *error* old-err)
  (princ))

(prompt "\nSSM v1.1 loaded. Command: SSM  ->  select every real PV module + report (count/arrays/size).")
(princ)
