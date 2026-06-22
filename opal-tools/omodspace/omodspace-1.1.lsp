;; ============================================================
;; omodspace-1.1  --  O-MODSPACE : array module spacing (rows AND columns)
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; COMMAND  O-MODSPACE / OMODSPACE  ->  [Set/Measure]
;;
;; v1.1 -- ANCHOR-POINT model (replaces the module pick):
;;   Set     = pick an ANCHOR POINT (OSNAP on, snap to a corner). The array is the one
;;             whose NEAREST module is to that point; the point also selects the FIXED
;;             row + column (the row/col groups nearest the point stay put). Works even
;;             when there is no module exactly at the corner -- we anchor on the point and
;;             the nearest existing group, never on a module-at-corner.
;;   Measure = click anywhere near the array (OSNAP off); nearest module identifies it.
;;   North-bay pattern (and only North-bay) additionally asks you to pick a module in the
;;   NORTH-END row (re-prompts if it is not an end row) to set which end gets the odd bay.
;;   The Set engine is factored into _omsp-set-one so O-PVSPACE can batch many arrays.
;; v1.0 -- single-pick flood-fill; rows + columns; config-driven defaults.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - All geometry via shared ogeo: records, flood-fill, axis grouping, pattern math, move.
;;   - Rows step along the module SHORT edge (ushort); columns along the LONG edge (ulong).
;;   - Anchor = the row/col groups nearest the anchor point stay fixed; the two axes are
;;     orthogonal, so row + column shifts are computed from the original set and applied
;;     independently. Modules only (racking/strings not moved -- consistent with O-GRID).
;; ============================================================

(vl-load-com)

;; --- right-pad string s to width w ---
(defun _omsp-pad (s w / r) (setq r s) (while (< (strlen r) w) (setq r (strcat r " "))) r)

;; --- mean projection of a group's record centres onto unit axis u ---
(defun _omsp-group-mean (g u / s n r)
  (setq s 0.0 n 0)
  (foreach r g (setq s (+ s (_ogeo-dot (nth 2 r) u)) n (1+ n)))
  (if (> n 0) (/ s n) 0.0))

;; --- record whose centre is nearest WCS point pt ---
(defun _omsp-nearest-rec (recs pt / best bd r d)
  (setq best nil bd nil)
  (foreach r recs
    (setq d (distance (nth 2 r) pt))
    (if (or (null bd) (< d bd)) (setq bd d best r)))
  best)

;; --- the array (record list) whose nearest module is at WCS pt, or nil ---
(defun _omsp-array-at (pt / recs seed)
  (setq recs (_ogeo-all-modules))
  (if (null recs)
    nil
    (progn
      (setq seed (_omsp-nearest-rec recs pt))
      (if seed (_ogeo-array-from (car seed) recs) nil))))

;; --- index of the ordered group whose mean projection on u is nearest proj
;;     (the anchor/fixed row or column selected by the anchor point) ---
(defun _omsp-group-idx-at (groups u proj / i best bd g m)
  (setq i 0 best 0 bd nil)
  (foreach g groups
    (setq m (_omsp-group-mean g u))
    (if (or (null bd) (< (abs (- m proj)) bd)) (setq bd (abs (- m proj)) best i))
    (setq i (1+ i)))
  best)

;; --- index of the ordered group that contains ENT, or nil if not in the array ---
(defun _omsp-ent-row-idx (groups ent / i found g r)
  (setq i 0 found nil)
  (foreach g groups
    (foreach r g (if (eq (car r) ent) (setq found i)))
    (setq i (1+ i)))
  found)

;; --- North-bay only: pick a module in the NORTH-END row; re-prompt if it is not an end
;;     row. Returns endside ("low" if it is group 0, "high" if it is the last group),
;;     or nil if the user cancels. ---
(defun _omsp-pick-north (rgroups us / n done e ent idx)
  (setq n (length rgroups) done nil idx nil)
  (while (not done)
    (setq e (entsel "\n  Pick a module in the NORTH-end row: "))
    (if (null e)
      (setq done T idx nil)
      (progn
        (setq ent (car e) idx (_omsp-ent-row-idx rgroups ent))
        (cond
          ((null idx) (prompt "\n  That module is not in this array -- try again."))
          ((or (= idx 0) (= idx (1- n))) (setq done T))
          (T (prompt "\n  That is not an END row -- pick a module in the north-END row."))))))
  (if (null idx) nil (if (= idx 0) "low" "high")))

;; --- per-group shift along u so every gap hits the pattern, anchor group AIDX fixed ---
(defun _omsp-shifts (groups u modsize kind gaps endside aidx / n plist g ideal c i out)
  (setq n (length groups) plist nil)
  (foreach g groups (setq plist (cons (_omsp-group-mean g u) plist)))
  (setq plist  (reverse plist)
        ideal  (_ogeo-row-positions kind gaps endside modsize n)
        c      (- (nth aidx plist) (nth aidx ideal))
        out nil i 0)
  (while (< i n)
    (setq out (cons (- (+ (nth i ideal) c) (nth i plist)) out) i (1+ i)))
  (reverse out))

;; --- move every member of each group by its shift along u; returns (nmoved nfail) ---
(defun _omsp-apply (groups shifts u / i g s dx dy r nok nfail)
  (setq i 0 nok 0 nfail 0)
  (foreach g groups
    (setq s (nth i shifts))
    (if (> (abs s) 1e-9)
      (progn
        (setq dx (* s (car u)) dy (* s (cadr u)))
        (foreach r g
          (if (_ogeo-move (car r) dx dy) (setq nok (1+ nok)) (setq nfail (1+ nfail))))))
    (setq i (1+ i)))
  (list nok nfail))

;; --- Measure: print one axis (rows or cols) + min/max/avg edge-to-edge gap ---
(defun _omsp-axis-report (groups u modsize label / n plist g i gap gaps mn mx sm)
  (setq n (length groups) plist nil)
  (foreach g groups (setq plist (cons (_omsp-group-mean g u) plist)))
  (setq plist (reverse plist))
  (prompt (strcat "\n  " label ": " (itoa n) (if (= label "ROWS") " rows" " cols")))
  (setq i 1 gaps nil)
  (while (< i n)
    (setq gap  (- (- (nth i plist) (nth (1- i) plist)) modsize)
          gaps (cons gap gaps))
    (prompt (strcat "\n    " (_omsp-pad (itoa i) 3) " -> " (_omsp-pad (itoa (1+ i)) 3)
                    "   gap " (rtos gap 2 3)))
    (setq i (1+ i)))
  (setq gaps (reverse gaps))
  (if gaps
    (progn
      (setq mn (car gaps) mx (car gaps) sm 0.0)
      (foreach gap gaps
        (if (< gap mn) (setq mn gap))
        (if (> gap mx) (setq mx gap))
        (setq sm (+ sm gap)))
      (prompt (strcat "\n    min " (rtos mn 2 3) "   max " (rtos mx 2 3)
                      "   avg " (rtos (/ sm (length gaps)) 2 3))))))

;; --- resolve the ROWS target -> (kind gaps endside) or nil (Skip). North-bay also
;;     edge-validates a north-row module pick to set endside. ---
(defun _omsp-rows-target (arr rgroups us short / cfg dk dn df pat g du dn2 df2 endside)
  (setq cfg (_ogeo-detect-pattern arr short))
  (if cfg
    (setq dk (if (= (nth 1 cfg) "uniform") "Uniform" "North-bay")
          dn (car (nth 2 cfg)) df (cadr (nth 2 cfg)))
    (setq dk "North-bay" dn 13.5 df 14.5))
  (if (null df) (setq df dn))
  (initget "Uniform North-bay Pattern Skip")
  (setq pat (getkword (strcat "\nRows spacing [Uniform/North-bay/Pattern/Skip] <" dk ">: ")))
  (if (null pat) (setq pat dk))
  (cond
    ((= pat "Skip") nil)
    ((= pat "Pattern")
     (setq g (_ogeo-pick-pattern))
     (if g (list (nth 1 g) (nth 2 g) (nth 3 g)) nil))
    ((= pat "Uniform")
     (setq du (getreal (strcat "\n  Uniform inter-row gap <"
                               (rtos (if (and cfg (= (nth 1 cfg) "uniform")) dn 14.5) 2 3) ">: ")))
     (if (null du) (setq du (if (and cfg (= (nth 1 cfg) "uniform")) dn 14.5)))
     (list "uniform" (list du) nil))
    (T  ; North-bay
     (setq dn2 (getreal (strcat "\n  North-bay (odd/end) gap <" (rtos dn 2 3) ">: ")))
     (if (null dn2) (setq dn2 dn))
     (setq df2 (getreal (strcat "\n  Field gap (all other rows) <" (rtos df 2 3) ">: ")))
     (if (null df2) (setq df2 df))
     (setq endside (_omsp-pick-north rgroups us))
     (if (null endside)
       (progn (prompt "\n  North-end row not chosen -- rows skipped.") nil)
       (list "endbay" (list dn2 df2) endside)))))

;; --- resolve the COLUMNS target -> gap value or nil (Skip). Default = config within-gap. ---
(defun _omsp-cols-target (dims / dc kw g)
  (setq dc (if (and dims (caddr dims)) (caddr dims) 0.25))
  (initget "Set Skip")
  (setq kw (getkword "\nColumns spacing [Set/Skip] <Set>: "))
  (if (= kw "Skip")
    nil
    (progn
      (setq g (getreal (strcat "\n  Within-row (column) gap <" (rtos dc 2 3) ">: ")))
      (if (null g) (setq g dc))
      g)))

;; --- apply a resolved (rtgt ctgt) to ONE array, anchored at WCS anchorpt. Plan + Yes +
;;     move. Returns T if applied, nil if cancelled/nothing. Reused by O-PVSPACE. ---
(defun _omsp-set-one (arr anchorpt rtgt ctgt / seed us ul short long rgroups cgroups
                        raidx caidx rshifts cshifts ans res nok nfail oce)
  (setq seed (car arr)
        us (nth 3 seed) ul (nth 4 seed) short (nth 5 seed) long (nth 6 seed)
        rgroups (_ogeo-axis-groups arr us (* 0.5 short))
        cgroups (_ogeo-axis-groups arr ul (* 0.5 long))
        raidx   (_omsp-group-idx-at rgroups us (_ogeo-dot anchorpt us))
        caidx   (_omsp-group-idx-at cgroups ul (_ogeo-dot anchorpt ul)))
  (if rtgt (setq rshifts (_omsp-shifts rgroups us short (car rtgt) (cadr rtgt) (caddr rtgt) raidx)))
  (if ctgt (setq cshifts (_omsp-shifts cgroups ul long "uniform" (list ctgt) nil caidx)))
  (prompt "\n\nO-MODSPACE plan (modules only):")
  (if rtgt
    (prompt (strcat "\n  rows: " (itoa (length rgroups)) " rows, "
                    (if (= (car rtgt) "uniform")
                      (strcat "uniform " (rtos (car (cadr rtgt)) 2 3))
                      (strcat "north-bay " (rtos (car (cadr rtgt)) 2 3)
                              " / field " (rtos (cadr (cadr rtgt)) 2 3)
                              " (odd bay at " (caddr rtgt) " end)"))
                    "   (anchor row " (itoa (1+ raidx)) " fixed)")))
  (if ctgt
    (prompt (strcat "\n  cols: " (itoa (length cgroups)) " cols, uniform " (rtos ctgt 2 3)
                    "   (anchor col " (itoa (1+ caidx)) " fixed)")))
  (initget "Yes No")
  (setq ans (getkword "\n\nApply? [Yes/No] <No>: "))
  (if (= ans "Yes")
    (progn
      (setq oce (getvar "CMDECHO")) (setvar "CMDECHO" 0)
      (setq nok 0 nfail 0)
      (if rtgt
        (progn (setq res (_omsp-apply rgroups rshifts us))
               (setq nok (+ nok (car res)) nfail (+ nfail (cadr res)))))
      (if ctgt
        (progn (setq res (_omsp-apply cgroups cshifts ul))
               (setq nok (+ nok (car res)) nfail (+ nfail (cadr res)))))
      (setvar "CMDECHO" oce)
      (prompt (strcat "\nO-MODSPACE: done -- " (itoa nok) " module-moves applied."))
      (if (> nfail 0)
        (prompt (strcat "\n  WARNING: " (itoa nfail) " moves failed (locked layer?). Unlock and re-run.")))
      T)
    (progn (prompt "\nO-MODSPACE: cancelled -- nothing moved.") nil)))

;; ============================================================
;; O-MODSPACE  --  [Set/Measure]
;; ============================================================
(defun C:O-MODSPACE ( / old-err old-os old-ce mode pt arr seed us ul dims rtgt ctgt cfg)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-MODSPACE error: " msg)))
    (princ))
  (setq old-os (getvar "OSMODE") old-ce (getvar "CMDECHO"))

  (cond
    ((not (member "_OGEO-ARRAY-FROM" (atoms-family 1 (list "_OGEO-ARRAY-FROM"))))
     (prompt "\nO-MODSPACE: ogeo library not loaded -- run OLOAD."))
    (T
     (initget "Set Measure")
     (setq mode (getkword "\nO-MODSPACE [Set/Measure] <Set>: "))
     (if (null mode) (setq mode "Set"))

     (cond
       ;; ---------------- MEASURE (click anywhere near the array) ----------------
       ((= mode "Measure")
        (setvar "OSMODE" 0)
        (setq pt (getpoint "\nClick anywhere near the array: "))
        (if (null pt)
          (prompt "\nNothing picked.")
          (progn
            (setq arr (_omsp-array-at (trans pt 1 0)))
            (if (or (null arr) (< (length arr) 2))
              (prompt "\nO-MODSPACE: no array found near that point.")
              (progn
                (setq seed (car arr))
                (prompt (strcat "\nO-MODSPACE: array " (itoa (length arr)) " modules."))
                (_omsp-axis-report (_ogeo-axis-groups arr (nth 3 seed) (* 0.5 (nth 5 seed)))
                                   (nth 3 seed) (nth 5 seed) "ROWS")
                (_omsp-axis-report (_ogeo-axis-groups arr (nth 4 seed) (* 0.5 (nth 6 seed)))
                                   (nth 4 seed) (nth 6 seed) "COLUMNS")
                (setq cfg (_ogeo-detect-pattern arr (nth 5 seed)))
                (if cfg (prompt (strcat "\n  rows match config pattern: " (car cfg)))))))))

       ;; ---------------- SET (anchor point, OSNAP on) ----------------
       (T
        (setvar "OSMODE" (logior old-os 1))
        (setq pt (getpoint "\nPick the array ANCHOR point (snap to a corner): "))
        (setvar "OSMODE" old-os)
        (if (null pt)
          (prompt "\nNothing picked.")
          (progn
            (setq arr (_omsp-array-at (trans pt 1 0)))
            (if (or (null arr) (< (length arr) 2))
              (prompt "\nO-MODSPACE: no array found near that point.")
              (progn
                (setq seed (car arr) us (nth 3 seed) ul (nth 4 seed)
                      dims (_ogeo-module-dims arr))
                (prompt (strcat "\nO-MODSPACE: array " (itoa (length arr)) " modules."))
                (setq rtgt (_omsp-rows-target arr (_ogeo-axis-groups arr us (* 0.5 (nth 5 seed)))
                                              us (nth 5 seed))
                      ctgt (_omsp-cols-target dims))
                (if (and (null rtgt) (null ctgt))
                  (prompt "\nO-MODSPACE: both axes skipped -- nothing to do.")
                  (_omsp-set-one arr (trans pt 1 0) rtgt ctgt))))))))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; --- alias (O-Suite: dashed + undashed) ---
(defun C:OMODSPACE () (C:O-MODSPACE))

(prompt "\nO-MODSPACE v1.1 loaded. Command: O-MODSPACE / OMODSPACE  ->  [Set/Measure] (anchor-point; rows + columns)")
(princ)
