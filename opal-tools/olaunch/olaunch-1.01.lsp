;; olaunch-1.01.lsp -- Opal CAD Tools launcher dialog (the "toolbox")
;; Commands: O (aliases: OPAL, O-MENU)
;; Opens a DCL dialog: Opal mark + grouped buttons that run each tool.
;; Buttons whose command is not loaded are shown disabled.
;; v1.01 -- logo polish: symmetric gold diamond + real cream disc (filled
;;          circle) split into thirds by two charcoal bars. Cream now uses a
;;          light ACI so it renders on the dark badge (1.0 used ACI 7 = black).
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
               "C:\\Users\\adria\\CAD\\Automations\\opal-tools\\"))
  (setq p (strcat root "olaunch\\olaunch.dcl"))
  (if (findfile p) p (findfile "olaunch.dcl")))

;; thin gold line (lineweight-0 look; corners meet sharp)
(defun _olaunch-gl (x1 y1 x2 y2)
  (vector_image x1 y1 x2 y2 40))

;; draw the Opal mark (gold diamond + cream disc split by 2 charcoal bars)
(defun _olaunch-draw-mark ( / w h cx cy r rd yy hw bb sz)
  (setq w  (dimx_tile "logo") h (dimy_tile "logo")
        cx (/ w 2) cy (/ h 2)
        sz (min w h)
        r  (fix (* sz 0.46))                 ; diamond half-size (symmetric)
        rd (fix (* sz 0.24))                 ; disc radius
        bb (max 2 (fix (* rd 0.36))))        ; charcoal bar thickness
  (start_image "logo")
  (fill_image 0 0 w h 250)                   ; charcoal badge background
  ;; gold diamond, sharp corners
  (_olaunch-gl cx (- cy r) (+ cx r) cy)
  (_olaunch-gl (+ cx r) cy cx (+ cy r))
  (_olaunch-gl cx (+ cy r) (- cx r) cy)
  (_olaunch-gl (- cx r) cy cx (- cy r))
  ;; cream disc -- filled circle drawn as horizontal rows (ACI 255 = light)
  (setq yy (- rd))
  (while (<= yy rd)
    (setq hw (fix (sqrt (max 0 (- (* rd rd) (* yy yy))))))
    (if (> hw 0) (fill_image (- cx hw) (+ cy yy) (* 2 hw) 1 255))
    (setq yy (1+ yy)))
  ;; two charcoal bars split the disc into thirds (overflow sits on the
  ;; same-coloured badge bg, so it reads as gaps in the circle)
  (fill_image (- cx rd) (- (- cy (fix (* rd 0.33))) (/ bb 2)) (* 2 rd) bb 250)
  (fill_image (- cx rd) (- (+ cy (fix (* rd 0.33))) (/ bb 2)) (* 2 rd) bb 250)
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
          (if (and (= chosen 1) *olaunch-cmd*)
            (eval (list (read (strcat "C:" *olaunch-cmd*)))))
          (princ))))))

(defun C:OPAL   () (C:O))
(defun C:O-MENU () (C:O))

(prompt "\nO-LAUNCH v1.01 loaded. Type O to open the Opal toolbox.")
(princ)
