;; olaunch-1.15.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opal mark + grouped buttons.
;; v1.15 -- toolbox "Draw" button points at O-MODSPACE (was O-ROWSPACE); DCL button
;;          key OMODSPACE / label "Module Spacing". Part of the O-ROWSPACE -> O-MODSPACE
;;          rename (rows + columns).
;; v1.14 -- "Save Layers/Filters" moved out of the main DEV toolbox into a dev-only
;;          "Advanced >" submenu (opal_advanced) whose "< Back" returns to the main
;;          toolbox (done_dialog 2 -> reopen), same as the old Layer Tools back.
;;          New prod-test-only "Back to DEV" button (key MODEDEV -> omode:to-dev) via
;;          a third main variant opal_launcher_prodtest -- shown only in BUNDLE
;;          (prod-test), never in a real teammate BUNDLE install. Main variant is now
;;          a 3-way pick: dev / prodtest / bundle.
;; v1.13 -- layer actions in the main toolbox; gate is DEV vs BUNDLE (not OADMIN).
;; v1.11 -- "Switch to Bundle" (omode:to-bundle), reopens to teammate view.
;; v1.10 -- mode folded into the version line. v1.09 -- variant-by-mode.
;; v1.08 -- dropped Calibrate; Reload reopens. v1.07 -- "< Back" reliable.
;; ============================================================

(vl-load-com)

(setq *olaunch-ver* "1.1.1")   ;; keep in step with opal-cad-installer/VERSION

;; generic buttons: pick the command, close the toolbox, run it
(setq *olaunch-main*
  (list
    (cons "OMODSPACE" "C:O-MODSPACE")
    (cons "OHELP"     "C:OHELP")))

;; DEV-only "Save Layers/Filters": push this drawing's layer standard AND filters
;; up to the master CSVs (drawing -> master). Runs both saves in sequence.
(defun olaunch:save-master ( / )
  (if (_olaunch-have "lk:std-save")    (lk:std-save))
  (if (_olaunch-have "lk:filter-save") (lk:filter-save))
  (princ))

;; Current load mode, detected from the suite root (no dependency on the omode
;; tool, which is excluded from packaged releases).
(defun _olaunch-mode ( / r)
  (setq r (if (and (boundp (quote *o-suite-root*)) *o-suite-root*) *o-suite-root* ""))
  (cond
    ((vl-string-search "OpalTools-prodtest" r) "BUNDLE (prod-test)")
    ((vl-string-search "ApplicationPlugins" r) "BUNDLE")
    (T "DEV")))

(defun _olaunch-have (sym / n)
  (setq n (strcase sym))
  (and (member n (atoms-family 1 (list n))) T))

(defun _olaunch-call (sym)
  (if (_olaunch-have sym)
    (eval (list (read sym)))
    (prompt (strcat "\n" sym " is not available."))))

(defun _olaunch-dcl-path ( / root p)
  (setq root (if (and (boundp (quote *o-suite-root*)) *o-suite-root*)
               *o-suite-root*
               "C:\\Users\\adria\\CAD\\Automations\\opal-tools\\"))
  (setq p (strcat root "olaunch\\olaunch.dcl"))
  (if (findfile p) p (findfile "olaunch.dcl")))

(defun _olaunch-gl (x1 y1 x2 y2)
  (vector_image x1 y1 x2 y2 40))

(defun _olaunch-draw-mark ( / w h cx cy r rd yy hw bb sz)
  (setq w  (dimx_tile "logo") h (dimy_tile "logo")
        cx (/ w 2) cy (/ h 2)
        sz (min w h)
        r  (fix (* sz 0.373))
        rd (fix (* sz 0.194))
        bb (max 2 (fix (* rd 0.36))))
  (start_image "logo")
  (fill_image 0 0 w h 250)
  (setq ri 0)
  (while (< ri 8)
    (_olaunch-gl cx          (- cy r ri)  (+ cx r ri)  cy         )
    (_olaunch-gl (+ cx r ri) cy           cx           (+ cy r ri))
    (_olaunch-gl cx          (+ cy r ri)  (- cx r ri)  cy         )
    (_olaunch-gl (- cx r ri) cy           cx           (- cy r ri))
    (setq ri (1+ ri)))
  (setq yy (- rd))
  (while (<= yy rd)
    (setq hw (fix (sqrt (max 0 (- (* rd rd) (* yy yy))))))
    (if (> hw 0) (fill_image (- cx hw) (+ cy yy) (* 2 hw) 1 255))
    (setq yy (1+ yy)))
  (fill_image (- cx rd) (- (- cy (fix (* rd 0.33))) (/ bb 2)) (* 2 rd) bb 250)
  (fill_image (- cx rd) (- (+ cy (fix (* rd 0.33))) (/ bb 2)) (* 2 rd) bb 250)
  (end_image))

(defun _olaunch-wire (pairs / p)
  (foreach p pairs
    (if (_olaunch-have (cdr p))
      (action_tile (car p)
        (strcat "(setq *olaunch-go* \"" (cdr p) "\")(done_dialog 1)"))
      (mode_tile (car p) 1))))

(defun C:O ( / dcl id res r2 pick again md devp ptp dlg)
  (setq dcl (_olaunch-dcl-path))
  (if (not dcl)
    (progn
      (prompt "\nLauncher dialog file not found. Type OHELP for the command list.")
      (princ))
    (progn
      (setq id (load_dialog dcl))
      (if (< id 0)
        (progn
          (prompt "\nCould not open the launcher. Type OHELP for the command list.")
          (princ))
        (progn
          (setq pick nil again T)
          (while again
            (setq again nil)
            ;; recompute each pass so a mode switch + reopen shows the new variant
            (setq md   (_olaunch-mode)
                  devp (= md "DEV")
                  ptp  (= md "BUNDLE (prod-test)")
                  dlg  (cond (devp "opal_launcher_dev")
                             (ptp  "opal_launcher_prodtest")
                             (T    "opal_launcher")))
            (if (new_dialog dlg id)
              (progn
                (setq *olaunch-go* nil)
                (set_tile "ver" (strcat "v" *olaunch-ver* "  " (chr 183) "  " md))
                (_olaunch-draw-mark)
                (_olaunch-wire *olaunch-main*)
                (_olaunch-wire (list (cons "LKAPPLY" "C:LK-APPLY")))   ; Standardize, all variants
                (if devp (action_tile "ADV"     "(done_dialog 40)"))  ; Advanced > (dev)
                (if devp (action_tile "OLOAD"   "(done_dialog 20)"))
                (if devp (action_tile "MODESW"  "(done_dialog 30)"))
                (if ptp  (action_tile "MODEDEV" "(done_dialog 31)"))  ; Back to DEV (prod-test)
                (setq res (start_dialog))
                (cond
                  ((= res 1) (setq pick *olaunch-go*))
                  ;; Reload: close, reload tools, reopen the toolbox
                  ((= res 20)
                   (if (_olaunch-have "C:O-LOAD") (C:O-LOAD))
                   (setq again T))
                  ;; Switch to Bundle: flip to prod-test, reopen (teammate view)
                  ((= res 30)
                   (if (_olaunch-have "omode:to-bundle")
                     (omode:to-bundle)
                     (prompt "\nOMODE tool not loaded -- cannot switch mode."))
                   (setq again T))
                  ;; Back to DEV: flip prod-test back to the source tree, reopen
                  ((= res 31)
                   (if (_olaunch-have "omode:to-dev")
                     (omode:to-dev)
                     (prompt "\nOMODE tool not loaded -- cannot switch mode."))
                   (setq again T))
                  ;; Advanced submenu (dev): Save Layers/Filters; < Back -> main
                  ((= res 40)
                   (if (new_dialog "opal_advanced" id)
                     (progn
                       (setq *olaunch-go* nil)
                       (_olaunch-wire (list (cons "LKSAVE" "olaunch:save-master")))
                       (action_tile "back" "(done_dialog 2)")
                       (setq r2 (start_dialog))
                       ;; r2=1 -> save chosen (exit + run); else (2=Back,0=ESC) -> main
                       (if (= r2 1)
                         (setq pick *olaunch-go*)
                         (setq again T)))))))))
          (unload_dialog id)
          (if pick (_olaunch-call pick))
          (princ))))))

(defun C:OPAL   () (C:O))
(defun C:O-MENU () (C:O))

(prompt "\nO-LAUNCH v1.15 loaded. Type O to open the Opal toolbox.")
(princ)
