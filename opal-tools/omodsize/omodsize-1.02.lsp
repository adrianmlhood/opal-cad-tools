;; omodsize-1.02.lsp -- O-Suite module size normalizer + size report
;; Commands: O-MODSIZE (alias: OMODSIZE)
;;
;; Two modes [Report/Normalize] <Report>:
;;   Report    = read-only footprint distribution (buckets + counts, min/max + spread,
;;               count off the TARGET). Run before/after a normalize to verify.
;;   Normalize = resize every matched module to ONE target footprint.
;;
;; v1.02 -- shares ogeo (detection, records, module-dims). Fixes:
;;   * off-target now measured vs the chosen TARGET (config/last-used/custom), so a
;;     uniform array reads off=0 (was: vs a stale modal -> always non-zero).
;;   * target sources: [Yes] default (last-used remembered in registry, else config
;;     dims) / [List] pick a named module from *ocfg-modules* / [Custom] type W,H
;;     (each defaulting to last-used). Last-used persisted in HKCU\...\OpalTools.
;;   * resize is winding-proof: each vertex is placed by the SIGN of its projection on
;;     the module's own short/long axes (no p0..p3 order assumption).
;;   * quiet: CMDECHO 0 during the batch; no per-entity entupd; one vla-regen at the
;;     end (kills the 227x "Viewport is view-locked / Switching to Paper space" spam).
;; v1.0/1.01 -- original engine + Report mode.
;; ============================================================

(vl-load-com)

(defun _oms-fmt (v) (rtos v 2 2))
(defun _oms-pad (s n / r) (setq r s) (while (< (strlen r) n) (setq r (strcat r " "))) r)
(defun _oms-reg () "HKEY_CURRENT_USER\\Software\\Ocotillo\\OpalTools")

(defun _oms-reg-read (key / v)
  (if (setq v (vl-registry-read (_oms-reg) key)) (atof v) nil))
(defun _oms-reg-write (key val)
  (vl-registry-write (_oms-reg) key (rtos val 2 4)))

(defun _oms-regen ( / )
  (vl-catch-all-apply
    (function (lambda ()
      (vla-regen (vla-get-activedocument (vlax-get-acad-object)) 1)))))   ; 1 = acAllViewports

;; keep recs whose footprint matches (short long) -- orientation-agnostic, long tight.
(defun _oms-match (recs short long / ts tl out r)
  (setq ts (max 4.0 (* 0.10 short)) tl (max 2.0 (* 0.02 long)) out nil)
  (foreach r recs
    (if (and (<= (abs (- (nth 6 r) long)) tl) (<= (abs (- (nth 5 r) short)) ts))
      (setq out (cons r out))))
  out)

;; write WCS corners back to the polyline IN VERTEX ORDER (no entupd; caller regens)
(defun _oms-write (ent typ wpts / ed out i pr sub sd ocs)
  (cond
    ((= typ "LWPOLYLINE")
     (setq ed (entget ent) out nil i 0)
     (foreach pr ed
       (if (= (car pr) 10)
         (progn (setq ocs (trans (nth i wpts) 0 ent))
                (setq out (cons (list 10 (car ocs) (cadr ocs)) out) i (1+ i)))
         (setq out (cons pr out))))
     (entmod (reverse out)))
    ((= typ "POLYLINE")
     (setq sub (entnext ent) i 0)
     (while (and sub (< i (length wpts)) (= (cdr (assoc 0 (setq sd (entget sub)))) "VERTEX"))
       (if (_ogeo-geom-vtx-p sd)
         (progn (setq ocs (trans (nth i wpts) 0 ent))
                (entmod (subst (cons 10 ocs) (assoc 10 sd) sd))
                (setq i (1+ i))))
       (setq sub (entnext sub))))))

;; resize a module to tshort x tlong about its centre, preserving rotation.
;; Each vertex goes to centre + sgn(proj on ushort)*ths*ushort + sgn(proj on ulong)*thl*ulong.
(defun _oms-resize (rec tshort tlong / ent typ cen us ul ths thl pts newpts p d a b sa sb res)
  (setq ent (nth 0 rec) typ (nth 1 rec) cen (nth 2 rec)
        us (nth 3 rec) ul (nth 4 rec) ths (* 0.5 tshort) thl (* 0.5 tlong))
  (setq res (vl-catch-all-apply (function (lambda ( / )
    (setq pts (_ogeo-poly-pts ent) newpts nil)
    (foreach p pts
      (setq d  (list (- (car p) (car cen)) (- (cadr p) (cadr cen)))
            a  (+ (* (car d) (car us)) (* (cadr d) (cadr us)))
            b  (+ (* (car d) (car ul)) (* (cadr d) (cadr ul)))
            sa (if (>= a 0) 1.0 -1.0) sb (if (>= b 0) 1.0 -1.0))
      (setq newpts (cons (list (+ (car cen) (* sa ths (car us)) (* sb thl (car ul)))
                               (+ (cadr cen) (* sa ths (cadr us)) (* sb thl (cadr ul))) 0.0)
                         newpts)))
    (_oms-write ent typ (reverse newpts))))))
  (if (vl-catch-all-error-p res) nil T))

;; ---- Report (read-only) ----
;; Uniformity is measured vs the array's OWN dominant footprint (so a uniform array
;; always reads off=0, regardless of the config canonical). config/last-used only set
;; the normalize TARGET, not this reference.
(defun _oms-report (mods / ts tl ss ls off buckets r sks lks smin smax lmin lmax key cell pair)
  (setq off 0 buckets nil)
  (if (null mods)
    (prompt "\nO-MODSIZE Report: no modules matched the footprint.")
    (progn
      (setq ss nil ls nil)
      (foreach r mods (setq ss (cons (nth 5 r) ss) ls (cons (nth 6 r) ls)))
      (setq ts (_ogeo-mode ss 0.5) tl (_ogeo-mode ls 0.5))
      (foreach r mods
        (setq sks (nth 5 r) lks (nth 6 r))
        (if (or (null smin) (< sks smin)) (setq smin sks))
        (if (or (null smax) (> sks smax)) (setq smax sks))
        (if (or (null lmin) (< lks lmin)) (setq lmin lks))
        (if (or (null lmax) (> lks lmax)) (setq lmax lks))
        (if (or (> (abs (- sks ts)) 0.01) (> (abs (- lks tl)) 0.01)) (setq off (1+ off)))
        (setq key (strcat (_oms-pad (rtos sks 2 2) 7) " x " (rtos lks 2 2)) cell (assoc key buckets))
        (if cell (setq buckets (subst (cons key (1+ (cdr cell))) cell buckets))
                 (setq buckets (cons (cons key 1) buckets))))
      (prompt (strcat "\nO-MODSIZE Report: " (itoa (length mods)) " modules."))
      (prompt (strcat "\n  dominant footprint: " (_oms-fmt ts) " x " (_oms-fmt tl)
                      "   (uniformity measured vs this)"))
      (prompt "\n  footprint (short x long  ->  count):")
      (foreach pair (reverse buckets)
        (prompt (strcat "\n    " (_oms-pad (car pair) 18) " x" (itoa (cdr pair)))))
      (prompt (strcat "\n  short side: min " (_oms-fmt smin) "  max " (_oms-fmt smax)
                      "   spread " (_oms-fmt (- smax smin))))
      (prompt (strcat "\n  long  side: min " (_oms-fmt lmin) "  max " (_oms-fmt lmax)
                      "   spread " (_oms-fmt (- lmax lmin))))
      (prompt (strcat "\n  off target (> 0.01): " (itoa off)
                      (if (= off 0) "   -- ALL UNIFORM" "")))))
  (princ))

;; pick a named module from *ocfg-modules*; returns (short long) or nil
(defun _oms-pick-from-list ( / lst i m sel)
  (setq lst (if (and (boundp (quote *ocfg-modules*)) *ocfg-modules*) *ocfg-modules* nil))
  (if (null lst)
    (progn (prompt "\n  (no modules in config)") nil)
    (progn
      (prompt "\n  Config modules:")
      (setq i 1)
      (foreach m lst
        (prompt (strcat "\n    " (itoa i) ". " (_oms-pad (car m) 18)
                        (_oms-fmt (nth 1 m)) " x " (_oms-fmt (nth 2 m))))
        (setq i (1+ i)))
      (initget 7)
      (setq sel (getint (strcat "\n  Pick module [1-" (itoa (length lst)) "]: ")))
      (if (and sel (>= sel 1) (<= sel (length lst)))
        (progn (setq m (nth (1- sel) lst)) (list (nth 1 m) (nth 2 m)))
        (progn (prompt "\n  out of range.") nil)))))

;; ============================================================
(defun C:O-MODSIZE ( / old-err old-ce mode recs dims short long mods
                       tshort tlong lastw lasth deftw defth kw sel
                       off r nchg nsame nfail)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-MODSIZE error: " msg)))
    (princ))

  (if (not (member "_OGEO-ALL-MODULES" (atoms-family 1 (list "_OGEO-ALL-MODULES"))))
    (prompt "\nO-MODSIZE: ogeo library not loaded -- run OLOAD.")
    (progn
      (initget "Report Normalize")
      (setq mode (getkword "\nO-MODSIZE [Report/Normalize] <Report>: "))
      (if (null mode) (setq mode "Report"))

      (setq recs (_ogeo-all-modules))
      (if (null recs)
        (prompt "\nO-MODSIZE: no module polylines on the module layer (check O-CONFIG).")
        (progn
          (setq dims  (_ogeo-module-dims recs)
                short (car dims) long (cadr dims)
                mods  (_oms-match recs short long))
          (cond
            ;; ---------------- REPORT ----------------
            ((= mode "Report")
             (_oms-report mods))

            ((null mods)
             (prompt "\nO-MODSIZE: no modules matched the footprint -- nothing to normalize."))

            ;; ---------------- NORMALIZE ----------------
            (T
             (setq lastw (_oms-reg-read "LastModW") lasth (_oms-reg-read "LastModH")
                   deftw (if lastw lastw short) defth (if lasth lasth long))
             (prompt (strcat "\nO-MODSIZE: " (itoa (length mods)) " modules.  Detected footprint "
                             (_oms-fmt short) " x " (_oms-fmt long) "."))
             (initget "Yes List Custom")
             (setq kw (getkword (strcat "\nNormalize to " (_oms-fmt deftw) " x " (_oms-fmt defth)
                                        "? [Yes/List/Custom] <Yes>: ")))
             (cond
               ((= kw "List")
                (if (setq sel (_oms-pick-from-list))
                  (setq tshort (car sel) tlong (cadr sel))
                  (setq tshort nil)))
               ((= kw "Custom")
                (setq tshort (getreal (strcat "\nTarget WIDTH (short side) <" (_oms-fmt deftw) ">: ")))
                (if (null tshort) (setq tshort deftw))
                (setq tlong (getreal (strcat "\nTarget HEIGHT (long side) <" (_oms-fmt defth) ">: ")))
                (if (null tlong) (setq tlong defth)))
               (T (setq tshort deftw tlong defth)))    ; Yes / Enter

             (if (null tshort)
               (prompt "\nO-MODSIZE: cancelled -- nothing changed.")
               (progn
                 ;; normalize so tshort <= tlong (short vs long)
                 (if (> tshort tlong) (progn (setq r tshort tshort tlong tlong r)))
                 (setq off 0)
                 (foreach r mods
                   (if (or (> (abs (- (nth 5 r) tshort)) 0.01) (> (abs (- (nth 6 r) tlong)) 0.01))
                     (setq off (1+ off))))
                 (prompt (strcat "\n  target " (_oms-fmt tshort) " x " (_oms-fmt tlong)
                                 "   |   off-size (will change): " (itoa off)
                                 "   already on size: " (itoa (- (length mods) off))))
                 (if (= off 0)
                   (prompt "\n  Every module already matches -- nothing to do.")
                   (progn
                     (initget "Yes No")
                     (if (/= (getkword (strcat "\nResize " (itoa off) " module(s)? [Yes/No] <No>: ")) "Yes")
                       (prompt "\nO-MODSIZE: cancelled -- nothing changed.")
                       (progn
                         (setq old-ce (getvar "CMDECHO")) (setvar "CMDECHO" 0)
                         (setq nchg 0 nsame 0 nfail 0)
                         (foreach r mods
                           (if (or (> (abs (- (nth 5 r) tshort)) 0.01) (> (abs (- (nth 6 r) tlong)) 0.01))
                             (if (and (= (nth 7 r) 4) (_oms-resize r tshort tlong))
                               (setq nchg (1+ nchg)) (setq nfail (1+ nfail)))
                             (setq nsame (1+ nsame))))
                         (_oms-regen)
                         (setvar "CMDECHO" old-ce)
                         (_oms-reg-write "LastModW" tshort) (_oms-reg-write "LastModH" tlong)
                         (prompt (strcat "\nO-MODSIZE: done -- " (itoa nchg) " resized, "
                                         (itoa nsame) " already on size"
                                         (if (> nfail 0) (strcat ", " (itoa nfail)
                                           " could not change (locked layer or not 4-corner)") "")
                                         "."))
                         (prompt "\n  Re-run O-MODSIZE Report (or O-SET) to confirm.")))))))))))))
  (setq *error* old-err)
  (princ))

(defun C:OMODSIZE () (C:O-MODSIZE))

(prompt "\nO-MODSIZE v1.02 loaded. Type O-MODSIZE -> [Report/Normalize]. Report is read-only.")
(princ)
