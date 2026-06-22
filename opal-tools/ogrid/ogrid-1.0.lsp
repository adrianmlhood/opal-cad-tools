;; ogrid-1.0.lsp -- O-Suite: snap a module array to an ideal lattice
;; Commands: O-GRID (alias: OGRID)
;;
;; "Make this array perfect." Pick a reference module (its size becomes the target),
;; pick a fixed corner point (the grid origin -- nothing there moves), and O-GRID
;; auto-detects the row spacing pattern + within-row gap (confirm or override), then
;; RESIZES every module to the reference size AND repositions it to its ideal lattice
;; node. Modules only (PV-MODS); racking/strings/annotation untouched.
;;
;; Builds entirely on ogeo (flood-fill array detection, pattern math, place/resize) and
;; the config patterns (*ocfg-patterns*). Always prints a plan and needs an explicit Yes.
;; v1.0
;; ============================================================

(vl-load-com)

(defun _ogrid-fmt (v) (rtos v 2 2))

;; pick a named pattern from *ocfg-patterns*; returns (name kind gaps endside) or nil
(defun _ogrid-pick-pattern ( / lst i p sel)
  (setq lst (if (and (boundp (quote *ocfg-patterns*)) *ocfg-patterns*) *ocfg-patterns* nil))
  (if (null lst)
    (progn (prompt "\n  (no patterns in config)") nil)
    (progn
      (prompt "\n  Config patterns:")
      (setq i 1)
      (foreach p lst
        (prompt (strcat "\n    " (itoa i) ". " (car p) "  (" (cadr p) " "
                        (apply (function strcat)
                               (mapcar (function (lambda (x) (strcat (rtos x 2 2) " "))) (caddr p))) ")"))
        (setq i (1+ i)))
      (initget 7)
      (setq sel (getint (strcat "\n  Pick pattern [1-" (itoa (length lst)) "]: ")))
      (if (and sel (>= sel 1) (<= sel (length lst))) (nth (1- sel) lst) nil))))

(defun _ogrid-gaps-str (gaps / s g)
  (setq s "")
  (foreach g gaps (setq s (strcat s (rtos g 2 2) " ")))
  s)

;; ============================================================
(defun C:O-GRID ( / old-err old-os old-ce e refrec us ul refS refL refE
                    recs arr p0 o0 o0c sps lps rowC colC nr nc
                    rowpat rkind rgaps rend cgap kw pk
                    rpos cpos i0 j0 m sp lp i j du dv tc
                    nok nfail nskip)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (if old-os (setvar "OSMODE" old-os))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-GRID error: " msg)))
    (princ))
  (setq old-os (getvar "OSMODE") old-ce (getvar "CMDECHO"))

  (cond
    ((not (member "_OGEO-ARRAY-FROM" (atoms-family 1 (list "_OGEO-ARRAY-FROM"))))
     (prompt "\nO-GRID: ogeo library not loaded -- run OLOAD."))
    (T
     (setvar "OSMODE" 0)
     (setq e (entsel "\nPick the REFERENCE module (sets target size + the array): "))
     (if (null e)
       (prompt "\nO-GRID: nothing picked.")
       (progn
         (setq refrec (vl-catch-all-apply (function _ogeo-rec) (list (car e))))
         (if (or (vl-catch-all-error-p refrec) (null refrec))
           (prompt "\nO-GRID: that is not a readable 4-corner module.")
           (progn
             (setq us (nth 3 refrec) ul (nth 4 refrec)
                   refS (nth 5 refrec) refL (nth 6 refrec) refE (nth 0 refrec))
             (setq recs (_ogeo-all-modules)
                   arr  (_ogeo-array-from refE recs))
             (if (or (null arr) (< (length arr) 2))
               (prompt "\nO-GRID: could not flood-fill an array from that module.")
               (progn
                 ;; --- fixed anchor point -> origin module (nearest, stays put) ---
                 (setq p0 (getpoint "\nPick the FIXED corner point (origin -- stays put): "))
                 (if (null p0)
                   (prompt "\nO-GRID: no point picked.")
                   (progn
                     (setq p0 (trans p0 1 0) o0 nil)
                     (foreach m arr
                       (if (or (null o0) (< (distance (nth 2 m) p0) (distance o0 p0)))
                         (setq o0 (nth 2 m))))
                     (setq o0c o0)
                     ;; --- cluster rows (short axis) + cols (long axis) ---
                     (setq sps nil lps nil)
                     (foreach m arr
                       (setq sps (cons (_ogeo-dot (nth 2 m) us) sps)
                             lps (cons (_ogeo-dot (nth 2 m) ul) lps)))
                     (setq rowC (_ogeo-cluster1 sps (* 0.5 refS))
                           colC (_ogeo-cluster1 lps (* 0.5 refL))
                           nr (length rowC) nc (length colC))
                     ;; --- auto-detect row pattern + col gap ---
                     (setq rowpat (_ogeo-detect-pattern arr refS)
                           cgap   (_ogeo-col-gap arr refL))
                     (if (null cgap) (setq cgap 0.25))
                     (prompt (strcat "\nO-GRID: array of " (itoa (length arr)) " modules, "
                                     (itoa nr) " rows x " (itoa nc) " cols.  Module "
                                     (_ogrid-fmt refS) " x " (_ogrid-fmt refL) "."))
                     (prompt (strcat "\n  detected -> rows: "
                                     (if rowpat (strcat (car rowpat) " (" (cadr rowpat) " "
                                                        (_ogrid-gaps-str (caddr rowpat)) ")") "UNRECOGNIZED")
                                     "   cols gap: " (_ogrid-fmt cgap)))
                     (initget "Yes Pattern Type")
                     (setq kw (getkword "\n  Use detected? [Yes/Pattern/Type] <Yes>: "))
                     (if (and (null rowpat) (or (null kw) (= kw "Yes")))
                       (progn (prompt "\n  No pattern recognized -- choose one:") (setq kw "Pattern")))
                     (cond
                       ((= kw "Pattern")
                        (if (setq pk (_ogrid-pick-pattern))
                          (setq rkind (cadr pk) rgaps (caddr pk) rend (cadddr pk))
                          (setq rkind nil)))
                       ((= kw "Type")
                        (setq rgaps (list (getreal "\n  Row (between-row) gap <14.5>: ")))
                        (if (null (car rgaps)) (setq rgaps (list 14.5)))
                        (setq rkind "uniform" rend nil)
                        (setq cgap (cond ((getreal (strcat "\n  Col (within-row) gap <" (_ogrid-fmt cgap) ">: "))) (T cgap))))
                       (T (if rowpat (setq rkind (cadr rowpat) rgaps (caddr rowpat) rend (cadddr rowpat))
                                     (setq rkind nil))))
                     (if (null rkind)
                       (prompt "\nO-GRID: no spacing pattern -- aborted.")
                       (progn
                         ;; --- ideal positions along each axis ---
                         (setq rpos (_ogeo-row-positions rkind rgaps rend refS nr)
                               cpos (_ogeo-row-positions "uniform" (list cgap) nil refL nc)
                               i0 (_ogeo-nearest-idx (_ogeo-dot o0c us) rowC)
                               j0 (_ogeo-nearest-idx (_ogeo-dot o0c ul) colC))
                         (prompt (strcat "\n  PLAN: resize all to " (_ogrid-fmt refS) " x " (_ogrid-fmt refL)
                                         " and snap to a " (itoa nr) " x " (itoa nc)
                                         " lattice (rows " rkind " " (_ogrid-gaps-str rgaps)
                                         "/ cols " (_ogrid-fmt cgap) "), origin fixed."))
                         (initget "Yes No")
                         (if (/= (getkword "\n  Apply? [Yes/No] <No>: ") "Yes")
                           (prompt "\nO-GRID: cancelled -- nothing changed.")
                           (progn
                             (setvar "CMDECHO" 0)
                             (setq nok 0 nfail 0 nskip 0)
                             (foreach m arr
                               (setq sp (_ogeo-dot (nth 2 m) us) lp (_ogeo-dot (nth 2 m) ul)
                                     i  (_ogeo-nearest-idx sp rowC) j (_ogeo-nearest-idx lp colC)
                                     du (- (nth i rpos) (nth i0 rpos))
                                     dv (- (nth j cpos) (nth j0 cpos))
                                     tc (list (+ (car o0c) (* du (car us)) (* dv (car ul)))
                                              (+ (cadr o0c) (* du (cadr us)) (* dv (cadr ul)))))
                               (if (= (nth 7 m) 4)
                                 (if (_ogeo-place m tc us ul (* 0.5 refS) (* 0.5 refL))
                                   (setq nok (1+ nok)) (setq nfail (1+ nfail)))
                                 (setq nskip (1+ nskip))))
                             (vl-catch-all-apply
                               (function (lambda () (vla-regen (vla-get-activedocument (vlax-get-acad-object)) 1))))
                             (setvar "CMDECHO" old-ce)
                             (prompt (strcat "\nO-GRID: done -- " (itoa nok) " modules snapped"
                                             (if (> nfail 0) (strcat ", " (itoa nfail) " failed (locked?)") "")
                                             (if (> nskip 0) (strcat ", " (itoa nskip) " skipped (not 4-corner)") "")
                                             ".  Run O-SET / O-MODSIZE Report to confirm."))))))))))))))))
  (setvar "OSMODE" old-os)
  (setvar "CMDECHO" old-ce)
  (setq *error* old-err)
  (princ))

(defun C:OGRID () (C:O-GRID))

(prompt "\nO-GRID v1.0 loaded. Type O-GRID or OGRID to snap an array to an ideal lattice.")
(princ)
