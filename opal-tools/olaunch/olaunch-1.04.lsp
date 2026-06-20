;; olaunch-1.04.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opal mark + grouped buttons. All layer actions live under one "Layer Tools"
;; sub-panel (no more Standardize-vs-Standards name clash). Sub-buttons call the
;; commands/functions directly, so no command-line prompt.
;; v1.04 -- collapsed the Layers group into a single "Layer Tools >" sub-menu
;;          (Clean up + standardize / Save standard / Apply standard /
;;           Build filters / Save filters).
;; ============================================================

(vl-load-com)

(setq *olaunch-ver* "1.0")

;; main direct buttons: dialog key -> full callable symbol name
(setq *olaunch-main*
  (list
    (cons "ORESPACE" "C:O-ROWSPACE")
    (cons "OSET"     "C:O-SET")
    (cons "OLOAD"    "C:O-LOAD")
    (cons "OHELP"    "C:OHELP")))

;; "Layer Tools" sub-panel: dialog key -> callable symbol
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

;; thin gold line
(defun _olaunch-gl (x1 y1 x2 y2)
  (vector_image x1 y1 x2 y2 40))

;; Opal mark: gold diamond + cream disc split by 2 charcoal bars
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

;; wire (key . symbol) buttons: pick sets *olaunch-go* and closes; disable missing
(defun _olaunch-wire (pairs / p)
  (foreach p pairs
    (if (_olaunch-have (cdr p))
      (action_tile (car p)
        (strcat "(setq *olaunch-go* \"" (cdr p) "\")(done_dialog 1)"))
      (mode_tile (car p) 1))))

;; open a sub-panel; run the chosen symbol after it closes
(defun _olaunch-submenu (id dlg pairs)
  (if (new_dialog dlg id)
    (progn
      (setq *olaunch-go* nil)
      (_olaunch-wire pairs)
      (if (and (= (start_dialog) 1) *olaunch-go*)
        (_olaunch-call *olaunch-go*)))))

(defun C:O ( / dcl id res)
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
          (setq *olaunch-go* nil)
          (set_tile "ver" (strcat "v" *olaunch-ver*))
          (_olaunch-draw-mark)
          (_olaunch-wire *olaunch-main*)
          (action_tile "LAYERS" "(done_dialog 10)")
          (setq res (start_dialog))
          (cond
            ((= res 1)  (if *olaunch-go* (_olaunch-call *olaunch-go*)))
            ((= res 10) (_olaunch-submenu id "opal_layers" *olaunch-layers*)))
          (unload_dialog id)
          (princ))))))

(defun C:OPAL   () (C:O))
(defun C:O-MENU () (C:O))

(prompt "\nO-LAUNCH v1.04 loaded. Type O to open the Opal toolbox.")
(princ)
