;; ============================================================
;; omodspace-1.0  --  O-MODSPACE : array module spacing (rows AND columns)
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; Supersedes O-ROWSPACE (orespace). Generalized from row-only spacing to BOTH axes,
;; and from "select the array then pick a module" to a single module pick that
;; flood-fills the whole connected array (shared ogeo neighbour detection).
;;
;; COMMAND  O-MODSPACE / OMODSPACE  ->  [Set/Measure]
;;   Pick ONE module; the whole array is detected from it (_ogeo-array-from). The
;;   module's own row AND column stay fixed; everything shifts relative to it.
;;
;; MODES
;;   Measure = report BOTH axes (rows = short edge, columns = long edge); no move.
;;   Set     = re-space, modules only. One run can correct rows AND columns:
;;               Rows    [Uniform/North-bay/Pattern/Skip]  (defaults from *ocfg-patterns*)
;;               Columns [Set/Skip]                        (default gap from *ocfg-modules*)
;;             Each axis is independent; Skip leaves it untouched. Plan prints; explicit Yes.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - All geometry via the shared ogeo library: module records (ent typ center ushort
;;     ulong short long nverts), flood-fill, axis grouping, pattern math, locked-safe move.
;;   - Rows step along the module SHORT edge (ushort); columns along the LONG edge (ulong).
;;     Row/col target positions reuse _ogeo-row-positions; movement is vla-move (no resize).
;;   - Anchor = the picked module's group on each axis (its row and column stay put). The two
;;     axes are orthogonal, so row shifts (along ushort) and column shifts (along ulong) are
;;     computed from the original record set and applied independently.
;;   - Modules only. Racking/strings/annotation are not moved (consistent with O-GRID).
;; ============================================================

(vl-load-com)

;; --- right-pad string s to width w ---
(defun _omsp-pad (s w / r) (setq r s) (while (< (strlen r) w) (setq r (strcat r " "))) r)

;; --- mean projection of a group's record centres onto unit axis u ---
(defun _omsp-group-mean (g u / s n r)
  (setq s 0.0 n 0)
  (foreach r g (setq s (+ s (_ogeo-dot (nth 2 r) u)) n (1+ n)))
  (if (> n 0) (/ s n) 0.0))

;; --- index of the ordered group that contains ENT (0 if not found) ---
(defun _omsp-anchor-idx (groups ent / i found g r)
  (setq i 0 found 0)
  (foreach g groups
    (foreach r g (if (eq (car r) ent) (setq found i)))
    (setq i (1+ i)))
  found)

;; --- per-group shift along u so every gap hits the pattern, anchor group AIDX fixed.
;;     ideal cumulative positions (_ogeo-row-positions) are offset so group AIDX lands on
;;     its current mean; shift[i] = ideal[i]+C - current[i]. ---
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

;; --- resolve the ROWS target -> (kind gaps endside) or nil (Skip). Defaults from the
;;     detected config pattern; Pattern opens the shared picker. ---
(defun _omsp-rows-target (arr short / cfg dk dn df endside pat g du dn2 df2)
  (setq cfg (_ogeo-detect-pattern arr short))
  (if cfg
    (setq dk (if (= (nth 1 cfg) "uniform") "Uniform" "North-bay")
          dn (car (nth 2 cfg)) df (cadr (nth 2 cfg)) endside (nth 3 cfg))
    (setq dk "North-bay" dn 13.5 df 14.5 endside "low"))
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
     (list "endbay" (list dn2 df2) (if endside endside "low")))))

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

;; ============================================================
;; O-MODSPACE  --  [Set/Measure]
;; ============================================================
(defun C:O-MODSPACE ( / old-err old-os old-ce mode e mens mlayer ss recs arr seed
                        us ul dims rgroups cgroups raidx caidx rtgt ctgt rshifts cshifts
                        ans res nok nfail cfg)
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

     (setq e (entsel "\nPick a module in the array: "))
     (if (null e)
       (prompt "\nNothing picked.")
       (progn
         (setq mens   (car e)
               mlayer (cdr (assoc 8 (entget mens))))
         ;; build records on the picked module's own layer, then flood-fill from it
         (setq ss   (ssget "X" (list (quote (0 . "*POLYLINE")) (cons 8 mlayer)))
               recs (if ss (_ogeo-recs-from ss) nil)
               arr  (if recs (_ogeo-array-from mens recs) nil))
         (if (or (null arr) (< (length arr) 2))
           (prompt "\nO-MODSPACE: could not detect an array from that module (pick a 4-corner module).")
           (progn
             (setq seed (_ogeo-find mens arr)
                   us   (nth 3 seed) ul (nth 4 seed)
                   dims (_ogeo-module-dims arr))
             (prompt (strcat "\nO-MODSPACE: array " (itoa (length arr)) " modules (layer " mlayer ")."))

             (cond
               ;; ---------------- MEASURE ----------------
               ((= mode "Measure")
                (_omsp-axis-report (_ogeo-axis-groups arr us (* 0.5 (nth 5 seed))) us (nth 5 seed) "ROWS")
                (_omsp-axis-report (_ogeo-axis-groups arr ul (* 0.5 (nth 6 seed))) ul (nth 6 seed) "COLUMNS")
                (setq cfg (_ogeo-detect-pattern arr (nth 5 seed)))
                (if cfg (prompt (strcat "\n  rows match config pattern: " (car cfg)))))

               ;; ---------------- SET ----------------
               (T
                (setq rtgt (_omsp-rows-target arr (nth 5 seed))
                      ctgt (_omsp-cols-target dims))
                (if (and (null rtgt) (null ctgt))
                  (prompt "\nO-MODSPACE Set: both axes skipped -- nothing to do.")
                  (progn
                    (setq rgroups (_ogeo-axis-groups arr us (* 0.5 (nth 5 seed)))
                          cgroups (_ogeo-axis-groups arr ul (* 0.5 (nth 6 seed)))
                          raidx   (_omsp-anchor-idx rgroups mens)
                          caidx   (_omsp-anchor-idx cgroups mens))
                    (if rtgt
                      (setq rshifts (_omsp-shifts rgroups us (nth 5 seed)
                                                  (car rtgt) (cadr rtgt) (caddr rtgt) raidx)))
                    (if ctgt
                      (setq cshifts (_omsp-shifts cgroups ul (nth 6 seed)
                                                  "uniform" (list ctgt) nil caidx)))
                    ;; --- plan ---
                    (prompt "\n\nO-MODSPACE Set plan (modules only):")
                    (if rtgt
                      (prompt (strcat "\n  rows: " (itoa (length rgroups)) " rows, "
                                      (if (= (car rtgt) "uniform")
                                        (strcat "uniform " (rtos (car (cadr rtgt)) 2 3))
                                        (strcat "north-bay " (rtos (car (cadr rtgt)) 2 3)
                                                " / field " (rtos (cadr (cadr rtgt)) 2 3)))
                                      "   (anchor row " (itoa (1+ raidx)) " fixed)")))
                    (if ctgt
                      (prompt (strcat "\n  cols: " (itoa (length cgroups)) " cols, uniform "
                                      (rtos ctgt 2 3) "   (anchor col " (itoa (1+ caidx)) " fixed)")))
                    (initget "Yes No")
                    (setq ans (getkword "\n\nApply? [Yes/No] <No>: "))
                    (if (= ans "Yes")
                      (progn
                        (setvar "CMDECHO" 0)
                        (setq nok 0 nfail 0)
                        (if rtgt
                          (progn (setq res (_omsp-apply rgroups rshifts us))
                                 (setq nok (+ nok (car res)) nfail (+ nfail (cadr res)))))
                        (if ctgt
                          (progn (setq res (_omsp-apply cgroups cshifts ul))
                                 (setq nok (+ nok (car res)) nfail (+ nfail (cadr res)))))
                        (setvar "CMDECHO" old-ce)
                        (prompt (strcat "\nO-MODSPACE Set: done -- " (itoa nok)
                                        " module-moves applied. Run O-MODSPACE Measure to confirm."))
                        (if (> nfail 0)
                          (prompt (strcat "\n  WARNING: " (itoa nfail)
                                          " moves failed (locked layer?). Unlock and re-run."))))
                      (prompt "\nO-MODSPACE Set: cancelled -- nothing moved."))))))))))))

  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

;; --- alias (O-Suite: dashed + undashed) ---
(defun C:OMODSPACE () (C:O-MODSPACE))

(prompt "\nO-MODSPACE v1.0 loaded. Command: O-MODSPACE / OMODSPACE  ->  [Set/Measure] (rows + columns)")
(princ)
