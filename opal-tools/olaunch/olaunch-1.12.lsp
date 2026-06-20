;; olaunch-1.12.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opal mark + grouped buttons; all layer actions under one "Layer Tools" panel.
;; v1.12 -- Layer Tools cleaned up. One everyday action "Standardize this drawing"
;;          (LK-APPLY already does cleanup + apply-standard + build-filters, so the
;;          old "Apply standard" / "Build filters" buttons were redundant -- dropped).
;;          The two master-rewrite actions (Save drawing -> master standard /
;;          filters) are ADMIN-only: shown via the opal_layers_admin variant when
;;          _olaunch-admin-p (DEV machine, or HKCU\..\OpalTools Admin=1 set by OADMIN).
;;          Labels read "drawing -> master" so the dangerous direction is obvious.
;;          (LK-STD / LK-FILTER stay typable for the dropped sub-actions.)
;; v1.11 -- "Switch to Bundle" button in the DEV toolbox (Setup) flips to a prod-test
;;          via omode:to-bundle, then reopens showing the teammate view.
;; v1.10 -- mode folded into the version line as "v1.0 <middot> DEV".
;; v1.09 -- picks DCL variant by mode: opal_launcher_dev vs opal_launcher.
;; v1.08 -- dropped Calibrate; Reload reopens the main toolbox.
;; v1.07 -- "< Back" reliably returns to the main toolbox.
;; ============================================================

(vl-load-com)

(setq *olaunch-ver* "1.0")

;; generic buttons: pick the command, close the toolbox, run it
(setq *olaunch-main*
  (list
    (cons "ORESPACE" "C:O-ROWSPACE")
    (cons "OHELP"    "C:OHELP")))

;; Layer Tools -- everyday: just the safe all-in-one (-> this drawing)
(setq *olaunch-layers*
  (list
    (cons "LKAPPLY" "C:LK-APPLY")))

;; Layer Tools -- admin: adds the two master-rewrite actions (drawing -> master)
(setq *olaunch-layers-admin*
  (list
    (cons "LKAPPLY" "C:LK-APPLY")
    (cons "STDSAVE" "lk:std-save")
    (cons "FILSAVE" "lk:filter-save")))

;; Current load mode, detected from the suite root (no dependency on the omode
;; tool, which is excluded from packaged releases).
(defun _olaunch-mode ( / r)
  (setq r (if (and (boundp (quote *o-suite-root*)) *o-suite-root*) *o-suite-root* ""))
  (cond
    ((vl-string-search "OpalTools-prodtest" r) "BUNDLE (prod-test)")
    ((vl-string-search "ApplicationPlugins" r) "BUNDLE")
    (T "DEV")))

;; Admin unlock: DEV machines are always admin; otherwise honour a per-machine
;; registry flag set by OADMIN (HKCU\Software\Ocotillo\OpalTools  Admin=1).
(defun _olaunch-admin-p ( / v)
  (cond
    ((= (_olaunch-mode) "DEV") T)
    ((setq v (vl-registry-read "HKEY_CURRENT_USER\\Software\\Ocotillo\\OpalTools" "Admin"))
     (= v "1"))
    (T nil)))

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

(defun C:O ( / dcl id res r2 pick again devp dlg ladmin ldlg)
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
            (setq devp (= (_olaunch-mode) "DEV")
                  dlg  (if devp "opal_launcher_dev" "opal_launcher"))
            (if (new_dialog dlg id)
              (progn
                (setq *olaunch-go* nil)
                (set_tile "ver"
                  (strcat "v" *olaunch-ver* "  " (chr 183) "  " (_olaunch-mode)))
                (_olaunch-draw-mark)
                (_olaunch-wire *olaunch-main*)
                (action_tile "LAYERS" "(done_dialog 10)")
                (if devp (action_tile "OLOAD"  "(done_dialog 20)"))
                (if devp (action_tile "MODESW" "(done_dialog 30)"))
                (setq res (start_dialog))
                (cond
                  ((= res 1) (setq pick *olaunch-go*))
                  ;; Reload: close the dialog, reload tools, reopen the toolbox
                  ((= res 20)
                   (if (_olaunch-have "C:O-LOAD") (C:O-LOAD))
                   (setq again T))
                  ;; Switch to Bundle: flip to a prod-test, reopen (teammate view)
                  ((= res 30)
                   (if (_olaunch-have "omode:to-bundle")
                     (omode:to-bundle)
                     (prompt "\nOMODE tool not loaded -- cannot switch mode."))
                   (setq again T))
                  ((= res 10)
                   (setq ladmin (_olaunch-admin-p)
                         ldlg   (if ladmin "opal_layers_admin" "opal_layers"))
                   (if (new_dialog ldlg id)
                     (progn
                       (setq *olaunch-go* nil)
                       (_olaunch-wire (if ladmin *olaunch-layers-admin* *olaunch-layers*))
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

(prompt "\nO-LAUNCH v1.12 loaded. Type O to open the Opal toolbox.")
(princ)
