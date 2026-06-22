;; ============================================================
;; ssm-1.0  --  SSM : Select modules -- select every real PV module in the drawing
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb SS (select) + noun M (module), drawing-wide (cf. SSA = one array).
;; Lives in opal-tools so it runs today, on the ogeo shared library.
;;
;; COMMAND  SSM
;;   No pick. Collects every real PV module (ogeo + the modal-footprint filter O-SET uses)
;;   and puts them in the active (gripped) selection set. Run any command next.
;;
;; COLLISION NOTE: acad.pgp aliases SSM -> *SHEETSET. A LISP-defined C:SSM is expected to
;;   shadow that pgp alias (command beats alias); acad.pgp is NOT edited (per VVN rule).
;;   VERIFY live: type SSM and confirm it selects rather than opening Sheet Set Manager.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Modules via shared _ogeo-all-modules (configured layer first; shape-gated fallback)
;;     then _ogeo-real-modules (modal-footprint gate) -- so clutter on the module layer is
;;     not selected. No geometry re-implemented.
;;   - Selection delivered with (sssetfirst nil ss); nothing is modified.
;; ============================================================

(vl-load-com)

;; ============================================================
;; SSM  --  select every real PV module, drawing-wide
;; ============================================================
(defun C:SSM ( / old-err recs ss r)
  (setq old-err *error*)
  (defun *error* (msg)
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nSSM error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-REAL-MODULES" (atoms-family 1 (list "_OGEO-REAL-MODULES"))))
     (prompt "\nSSM: ogeo library not loaded (need v1.02+) -- run OLOAD."))
    (T
     (setq recs (_ogeo-real-modules (_ogeo-all-modules)))
     (if (null recs)
       (prompt "\nSSM: no PV modules found.")
       (progn
         (setq ss (ssadd))
         (foreach r recs (ssadd (car r) ss))
         (sssetfirst nil ss)
         (prompt (strcat "\nSSM: selected " (itoa (sslength ss))
                         " modules (grips active -- run a command on them)."))))))

  (setq *error* old-err)
  (princ))

(prompt "\nSSM v1.0 loaded. Command: SSM  ->  select every real PV module in the drawing.")
(princ)
