;; olaunch-1.05.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opal mark + grouped buttons; all layer actions under one "Layer Tools" panel.
;; v1.05 -- FIX: run the chosen command AFTER unload_dialog. Running an
;;          interactive command (getpoint/ssget, e.g. O-SET, O-ROWSPACE) while
;;          the dialog is only done_dialog'd (not unloaded) made the pending
;;          input cancel the pick immediately. Now the dialog is fully closed
;;          first, then the command runs.
;; ============================================================

(vl-load-com)

(setq *olaunch-ver* "1.0")

(setq *olaunch-main*
  (list
    (cons "ORESPACE" "C:O-ROWSPACE")
    (cons "OSET"     "C:O-SET")
    (cons "OLOAD"    "C:O-LOAD")
    (cons "OHELP"    "C:OHELP")))

(setq *olaunch-layers*
  (list
    (cons "LKAPPLY"  "C:LK-APPLY")
    (cons "STDSAVE"  "lk:std-save")
    (cons "STDSET"   "lk:std-set")
    (cons "FILBUILD" "lk:filter-set")
    (cons "FILSAVE"  "lk:filter-save")))

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

(defun C:O ( / dcl id res pick)
  (setq dcl (_olaunch-dcl-path))
  (if (not dcl)
    (progn
      (prompt "\nLauncher dialog file not found. Type OHELP for the command list.")
      (princ))
    (progn
      (setq id (load_dialog dcl))
      (if (or (< id 0) (not (new_dialog "opal_launcher" id)))
        (progn
          (if (>= id 0) (unload_dialog id))
          (prompt "\nCould not open the launcher. Type OHELP for the command list.")
          (princ))
        (progn
          (setq *olaunch-go* nil pick nil)
          (set_tile "ver" (strcat "v" *olaunch-ver*))
          (_olaunch-draw-mark)
          (_olaunch-wire *olaunch-main*)
          (action_tile "LAYERS" "(done_dialog 10)")
          (setq res (start_dialog))
          (cond
            ((= res 1) (setq pick *olaunch-go*))
            ((= res 10)
             (if (new_dialog "opal_layers" id)
               (progn
                 (setq *olaunch-go* nil)
                 (_olaunch-wire *olaunch-layers*)
                 (if (= (start_dialog) 1) (setq pick *olaunch-go*))))))
          (unload_dialog id)
          ;; run the chosen command only after the dialog is fully closed
          (if pick (_olaunch-call pick))
          (princ))))))

(defun C:OPAL   () (C:O))
(defun C:O-MENU () (C:O))

(prompt "\nO-LAUNCH v1.05 loaded. Type O to open the Opal toolbox.")
(princ)
