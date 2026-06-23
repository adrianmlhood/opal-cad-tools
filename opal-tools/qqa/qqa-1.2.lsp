;; ============================================================
;; qqa-1.2  --  QQA : Query + select array -- click a module, report AND select the array
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb QQ (query) + noun A (array). Click one module; print a compact
;; readout of the array it belongs to AND grip-select the whole array. Combines the old
;; SSA (select array) into QQA -- one click does both. Nothing is drawn or modified.
;; Lives in opal-tools so it runs today, on the ogeo shared library.
;;
;; COMMAND  QQA
;;   Click near a module (OSNAP off, same click-near interaction as O-MODSPACE Measure).
;;   The connected array floods via _ogeo-array-from; QQA reports module count, rows x
;;   columns, module footprint, row gaps, column gap, and any matched config pattern, then
;;   puts the whole array into the active (gripped) selection set so the next command acts
;;   on it.
;;
;; v1.2 -- fold SSA into QQA: after the report, grip-select the array (ssadd + sssetfirst).
;;         The standalone SSA command is superseded (kept on disk but dropped from the O menu).
;; v1.1 -- count REAL modules only. Was flooding over the raw _ogeo-all-modules set, so the
;;         ARRAY count included footprint clutter (e.g. 84 incl. mismatched polys). Now filters
;;         through _ogeo-real-modules first (same gate as SSM / ZZA), so the seed, the flooded
;;         array, and the count are all real modules.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Every number comes from an existing ogeo helper -- no geometry/spacing math here.
;;   - Click-near, OSNAP off; seed = module whose centre is nearest the click point.
;; ============================================================

(vl-load-com)

;; --- record whose centre is nearest WCS point pt ---
(defun _qqa-nearest (recs pt / best bd r d)
  (setq best nil bd nil)
  (foreach r recs
    (setq d (distance (nth 2 r) pt))
    (if (or (null bd) (< d bd)) (setq bd d best r)))
  best)

;; --- render an ascending number list to a readable string, or "(none)" ---
(defun _qqa-nstr (lst / s v)
  (if (null lst)
    "(none)"
    (progn
      (setq s "")
      (foreach v lst (setq s (strcat s (if (= s "") "" "  ") (rtos v 2 3))))
      s)))

;; ============================================================
;; QQA  --  query the clicked array
;; ============================================================
(defun C:QQA ( / old-err old-os pt recs seed arr us ul short long
                 rgroups cgroups dims rgaps cgap pat ss r)
  (setq old-err *error* old-os (getvar "OSMODE"))
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nQQA error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-MODULES" (atoms-family 1 (list "_OGEO-MODULES"))))
     (prompt "\nQQA: ogeo library not loaded (need v1.04+) -- run OLOAD."))
    (T
     (setvar "OSMODE" 0)
     (setq pt (getpoint "\nClick a module in the array to query: "))
     (if (null pt)
       (prompt "\nNothing picked.")
       (progn
         (setq recs (_ogeo-modules))
         (if (null recs)
           (prompt "\nQQA: no modules found.")
           (progn
             (setq seed (_qqa-nearest recs (trans pt 1 0))
                   arr  (if seed (_ogeo-array-from (car seed) recs) nil))
             (if (or (null arr) (< (length arr) 1))
               (prompt "\nQQA: no array found near that point.")
               (progn
                 (setq us      (nth 3 seed) ul (nth 4 seed)
                       short   (nth 5 seed) long (nth 6 seed)
                       rgroups (_ogeo-axis-groups arr us (* 0.5 short))
                       cgroups (_ogeo-axis-groups arr ul (* 0.5 long))
                       dims    (_ogeo-module-dims arr)
                       rgaps   (_ogeo-row-gaps arr short)
                       cgap    (_ogeo-col-gap arr long)
                       pat     (_ogeo-detect-pattern arr short))
                 (prompt "\n")
                 (prompt (strcat "\n  ARRAY     " (itoa (length arr)) " modules"))
                 (prompt (strcat "\n  GRID      " (itoa (length rgroups)) " rows x "
                                 (itoa (length cgroups)) " cols"))
                 (if dims
                   (prompt (strcat "\n  MODULE    " (rtos (car dims) 2 2) " x "
                                   (rtos (cadr dims) 2 2))))
                 (prompt (strcat "\n  ROW GAP   " (_qqa-nstr rgaps)))
                 (prompt (strcat "\n  COL GAP   " (if cgap (rtos cgap 2 3) "(none)")))
                 (prompt (strcat "\n  PATTERN   " (if pat (car pat) "(no config match)")))
                 ;; grip-select the whole array (folds in the old SSA)
                 (setq ss (ssadd))
                 (foreach r arr (ssadd (car r) ss))
                 (sssetfirst nil ss)
                 (prompt (strcat "\n  SELECTED  " (itoa (sslength ss))
                                 " modules (grips active -- run a command on them)."))))))))))

  (setvar "OSMODE" old-os)
  (setq *error* old-err)
  (princ))

(prompt "\nQQA v1.2 loaded. Command: QQA  ->  click a module, report AND select its array.")
(princ)
