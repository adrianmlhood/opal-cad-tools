;; olaunch-1.08.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opal mark + grouped buttons; all layer actions under one "Layer Tools" panel.
;; v1.09 -- shows the load mode (DEV / BUNDLE / BUNDLE prod-test) at the top of the
;;          toolbox. Detection is self-contained (reads *o-suite-root*) so it works
;;          even in a packaged install where the omode tool is absent. Picks the DCL
;;          variant by mode: opal_launcher_dev (DEV -- adds Reload Tools) vs
;;          opal_launcher (BUNDLE/teammate -- no Reload Tools); OLOAD wired dev-only.
;; v1.08 -- dropped the "Calibrate" (OSET) button (OLOAD auto-calibrates anyway).
;;          "Reload Tools" now runs the reload and REOPENS the main toolbox
;;          instead of closing (done_dialog 20 -> run C:O-LOAD -> loop).
;; v1.07 -- "< Back" reliably returns to the main toolbox (explicit done_dialog 2).
;; v1.06 -- "Back" returns to the main toolbox (launcher runs in a loop).
;; ============================================================

(vl-load-com)

(setq *olaunch-ver* "1.0")

;; generic buttons: pick the command, close the toolbox, run it
(setq *olaunch-main*
  (list
    (cons "ORESPACE" "C:O-ROWSPACE")
    (cons "OHELP"    "C:OHELP")))

(setq *olaunch-layers*
  (list
    (cons "LKAPPLY"  "C:LK-APPLY")
    (cons "STDSAVE"  "lk:std-save")
    (cons "STDSET"   "lk:std-set")
    (cons "FILBUILD" "lk:filter-set")
    (cons "FILSAVE"  "lk:filter-save")))

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
        r  (fix (* sz 0.46))
        rd (fix (* sz 0.24))
        bb (max 2 (fix (* rd 0.36))))
  (start_image "logo")
  (fill_image 0 0 w h 250)
  (_olaunch-gl cx (- cy r) (+ cx r) cy)
  (_olaunch-gl (+ cx r) cy cx (+ cy r))
  (_olaunch-gl cx (+ cy r) (- cx r) cy)
  (_olaunch-gl (- cx r) cy cx (- cy r))
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

(defun C:O ( / dcl id res r2 pick again devp dlg)
  (setq dcl (_olaunch-dcl-path))
  (setq devp (= (_olaunch-mode) "DEV")
        dlg  (if devp "opal_launcher_dev" "opal_launcher"))
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
            (if (new_dialog dlg id)
              (progn
                (setq *olaunch-go* nil)
                (set_tile "ver" (strcat "v" *olaunch-ver*))
                (set_tile "mode" (strcat "Mode: " (_olaunch-mode)))
                (_olaunch-draw-mark)
                (_olaunch-wire *olaunch-main*)
                (action_tile "LAYERS" "(done_dialog 10)")
                (if devp (action_tile "OLOAD" "(done_dialog 20)"))
                (setq res (start_dialog))
                (cond
                  ((= res 1) (setq pick *olaunch-go*))
                  ;; Reload: close the dialog, reload tools, reopen the toolbox
                  ((= res 20)
                   (if (_olaunch-have "C:O-LOAD") (C:O-LOAD))
                   (setq again T))
                  ((= res 10)
                   (if (new_dialog "opal_layers" id)
                     (progn
                       (setq *olaunch-go* nil)
                       (_olaunch-wire *olaunch-layers*)
                       (action_tile "back" "(done_dialog 2)")
                       (setq r2 (start_dialog))
                       ;; r2=1 -> action picked; else (2=Back, 0=ESC) -> main
                       (if (= r2 1)
                         (setq pick *olaunch-go*)
                         (setq again T)))))))))
          (unload_dialog id)
          (if pick (_olaunch-call pick))
          (princ))))))

(defun C:OPAL   () (C:O))
(defun C:O-MENU () (C:O))

(prompt "\nO-LAUNCH v1.09 loaded. Type O to open the Opal toolbox.")
(princ)
