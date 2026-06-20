;; olaunch-1.0.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opens a DCL dialog: faceted gem logo + grouped buttons that run each tool.
;; Buttons whose command is not loaded are shown disabled, so the toolbox
;; never offers a tool that is not installed.
;; v1.0
;; ============================================================

(vl-load-com)

(setq *olaunch-ver* "1.0")

;; dialog button key -> actual command name
(setq *olaunch-map*
  (list
    (cons "ODC"       "O-DC")
    (cons "ORESPACE"  "O-ROWSPACE")
    (cons "LKAPPLY"   "LK-APPLY")
    (cons "LKCLEANUP" "LK-CLEANUP")
    (cons "LKBYLAYER" "LK-BYLAYER")
    (cons "LKSTD"     "LK-STD")
    (cons "LKFILTER"  "LK-FILTER")
    (cons "OSET"      "O-SET")
    (cons "OLOAD"     "O-LOAD")
    (cons "OHELP"     "OHELP")))

(defun _olaunch-loaded-p (cmd / n)
  (setq n (strcat "C:" (strcase cmd)))
  (and (member n (atoms-family 1 (list n))) T))

(defun _olaunch-dcl-path ( / root p)
  (setq root (if (and (boundp (quote *o-suite-root*)) *o-suite-root*)
               *o-suite-root*
               "C:\\Users\\adria\\CAD\\Automations\\Opal\\"))
  (setq p (strcat root "olaunch\\olaunch.dcl"))
  (if (findfile p) p (findfile "olaunch.dcl")))

;; thin gold line (lineweight-0 look; corners meet sharp)
(defun _olaunch-gl (x1 y1 x2 y2)
  (vector_image x1 y1 x2 y2 40))

;; draw the Opal mark (gold diamond + split disc on charcoal) into "logo"
(defun _olaunch-draw-mark ( / w h cx cy dx dy s top bb band)
  (setq w  (dimx_tile "logo") h (dimy_tile "logo")
        cx (/ w 2) cy (/ h 2)
        dx (fix (* w 0.40)) dy (fix (* h 0.42))
        s  (fix (* h 0.21)))
  (setq top  (- cy s)
        bb   (max 2 (fix (* s 0.42)))
        band (fix (/ (- (* 2 s) (* 2 bb)) 3)))
  (start_image "logo")
  (fill_image 0 0 w h 250)                 ; charcoal badge background
  ;; thin gold diamond, sharp corners
  (_olaunch-gl cx (- cy dy) (+ cx dx) cy)
  (_olaunch-gl (+ cx dx) cy cx (+ cy dy))
  (_olaunch-gl cx (+ cy dy) (- cx dx) cy)
  (_olaunch-gl (- cx dx) cy cx (- cy dy))
  ;; cream disc body, split into equal thirds by two charcoal bars
  (fill_image (- cx s) top (* 2 s) (* 2 s) 7)
  (fill_image (- cx s) (+ top band) (* 2 s) bb 250)
  (fill_image (- cx s) (+ top band bb band) (* 2 s) bb 250)
  (end_image))

(defun C:O ( / dcl dcl-id chosen pair key cmd)
  (setq dcl (_olaunch-dcl-path))
  (if (not dcl)
    (progn
      (prompt "\nLauncher dialog file not found. Type OHELP for the command list.")
      (princ))
    (progn
      (setq dcl-id (load_dialog dcl))
      (if (or (< dcl-id 0) (not (new_dialog "opal_launcher" dcl-id)))
        (progn
          (if (>= dcl-id 0) (unload_dialog dcl-id))
          (prompt "\nCould not open the launcher. Type OHELP for the command list.")
          (princ))
        (progn
          (setq *olaunch-cmd* nil)
          (set_tile "ver" (strcat "v" *olaunch-ver*))
          (_olaunch-draw-mark)
          (foreach pair *olaunch-map*
            (setq key (car pair) cmd (cdr pair))
            (if (_olaunch-loaded-p cmd)
              (action_tile key
                (strcat "(setq *olaunch-cmd* \"" cmd "\")(done_dialog 1)"))
              (mode_tile key 1)))
          (setq chosen (start_dialog))
          (unload_dialog dcl-id)
          ;; run the chosen command after the dialog has fully closed
          (if (and (= chosen 1) *olaunch-cmd*)
            (eval (list (read (strcat "C:" *olaunch-cmd*)))))
          (princ))))))

(defun C:OPAL   () (C:O))
(defun C:O-MENU () (C:O))

(prompt "\nO-LAUNCH v1.0 loaded. Type O to open the Opal toolbox.")
(princ)
