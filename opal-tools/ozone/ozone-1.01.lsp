;; ozone-1.01.lsp -- O-Suite active module zone
;; Commands: O-ZONE (alias: OZONE)
;; Rough-drag a rectangle around the array you care about; the working zone becomes the
;; bounding box of the modules you grabbed (padded by one module, then scaled
;; *ozone-margin* -- default 2.0 -- about its centre). While a zone is set, the module
;; tools that route through ogeo (O-MODSIZE, SSA/SSM, click->array) AND O-SET see ONLY
;; modules whose centre is inside it. This is the MANUAL fallback for when the default
;; "module = visible on sheet E-1.0" rule (oconfig *ocfg-module-sheet*) isn't framing the
;; right array; an active zone OVERRIDES that sheet rule (see ogeo _ogeo-all-modules).
;; O-ZONE Clear releases it and restores the sheet default.
;;   *ozone-bounds*  (xmin ymin xmax ymax) WCS, or nil = no active zone
;;   *ozone-margin*  expansion factor about the grabbed-system centre (default 2.0)
;; v1.01 -- _ozone-bbox-of tracks min/max during the walk; dropped (apply 'min/'max ...)
;;          per the house rule (apply over a long list can exceed the arg limit).
;; v1.0
;; ============================================================

(if (not (boundp (quote *ozone-bounds*))) (setq *ozone-bounds* nil))
(if (not (boundp (quote *ozone-margin*))) (setq *ozone-margin* 2.0))

;; module layer from oconfig (nil -> any layer)
(defun _ozone-modlayer ()
  (if (and (boundp (quote *ocfg-layer-modules*)) *ocfg-layer-modules*)
    *ocfg-layer-modules* nil))

;; half a module's long side, used to pad the centre-bbox out to the panels' real extents
;; (so even a one-module grab yields a sensible zone). Falls back to 90 if no config.
(defun _ozone-modpad ( / l)
  (setq l (if (and (boundp (quote *ocfg-modules*)) *ocfg-modules*
                   (nth 2 (car *ocfg-modules*)))
            (nth 2 (car *ocfg-modules*)) 90.0))
  (* 0.5 l))

;; (xmin ymin xmax ymax) from a list of ogeo records (centre = nth 2). Tracks min/max in
;; the walk -- no (apply 'min ...) over a long list (house rule: it can blow the arg limit).
(defun _ozone-bbox-of (recs / x y xmin ymin xmax ymax)
  (foreach r recs
    (setq x (car (nth 2 r)) y (cadr (nth 2 r)))
    (if (null xmin)
      (setq xmin x ymin y xmax x ymax y)
      (setq xmin (min xmin x) ymin (min ymin y)
            xmax (max xmax x) ymax (max ymax y))))
  (if xmin (list xmin ymin xmax ymax) nil))

;; grow a box outward by d on every side
(defun _ozone-pad-box (b d)
  (list (- (car b) d) (- (cadr b) d) (+ (caddr b) d) (+ (cadddr b) d)))

;; scale a box about its own centre by factor f
(defun _ozone-scale-box (b f / cx cy hx hy)
  (setq cx (* 0.5 (+ (car b) (caddr b)))  cy (* 0.5 (+ (cadr b) (cadddr b)))
        hx (* 0.5 f (- (caddr b) (car b))) hy (* 0.5 f (- (cadddr b) (cadr b))))
  (list (- cx hx) (- cy hy) (+ cx hx) (+ cy hy)))

;; modules currently inside the active zone (uses ogeo's already-zone-filtered set);
;; highlight them and report. Returns the count.
(defun _ozone-show ( / recs ss n)
  (if (null *ozone-bounds*)
    (progn
      (sssetfirst nil nil)
      (prompt "\n  O-ZONE: no active zone -- module tools use the E-1.0 sheet default.")
      0)
    (progn
      (setq recs (if (member "_OGEO-MODULES" (atoms-family 1 (list "_OGEO-MODULES")))
                   (_ogeo-modules) nil))
      (setq ss (ssadd) n 0)
      (foreach r recs (setq ss (ssadd (nth 0 r) ss) n (1+ n)))
      (sssetfirst nil (if (> n 0) ss nil))
      (prompt (strcat "\n  O-ZONE active: " (itoa n) " module(s) inside  ("
                      (rtos (car   *ozone-bounds*) 2 1) ", " (rtos (cadr  *ozone-bounds*) 2 1)
                      ") .. (" (rtos (caddr *ozone-bounds*) 2 1) ", "
                      (rtos (cadddr *ozone-bounds*) 2 1) ").  O-ZONE Clear to release."))
      n)))

;; Set: rough-drag a rectangle, derive the padded + scaled zone from the modules grabbed.
(defun _ozone-set ( / ml p1 p2 ss recs box)
  (setq ml (_ozone-modlayer))
  (setq p1 (getpoint "\n  Drag a rectangle around the array -- first corner: "))
  (if p1 (setq p2 (getcorner p1 "\n  Opposite corner: ")))
  (if (and p1 p2)
    (progn
      (setq ss (ssget "_C" p1 p2
                      (if ml (list (quote (0 . "*POLYLINE")) (cons 8 ml))
                             (list (quote (0 . "*POLYLINE"))))))
      (setq recs (if ss (_ogeo-recs-from ss) nil)
            box  (_ozone-bbox-of recs))
      (if (null box)
        (prompt "\n  No modules in that rectangle -- zone unchanged.")
        (progn
          (setq *ozone-bounds*
                (_ozone-scale-box (_ozone-pad-box box (_ozone-modpad)) *ozone-margin*))
          (_ozone-show))))
    (prompt "\n  Cancelled -- zone unchanged."))
  (princ))

(defun C:O-ZONE ( / old-err old-ce opt)
  (vl-load-com)
  (setq old-err *error* old-ce (getvar "CMDECHO"))
  (defun *error* (msg)
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nO-ZONE error: " msg)))
    (princ))
  (if (not (member "_OGEO-RECS-FROM" (atoms-family 1 (list "_OGEO-RECS-FROM"))))
    (prompt "\nO-ZONE: ogeo library not loaded -- run OLOAD.")
    (progn
      (initget "Set Clear Show")
      (setq opt (getkword "\nO-ZONE [Set/Clear/Show] <Set>: "))
      (cond
        ((= opt "Clear")
         (setq *ozone-bounds* nil)
         (sssetfirst nil nil)
         (prompt "\n  O-ZONE cleared -- module tools use the E-1.0 sheet default again."))
        ((= opt "Show") (_ozone-show))
        (T (_ozone-set)))))
  (setq *error* old-err)
  (princ))

(defun C:OZONE () (C:O-ZONE))

(prompt "\nO-ZONE loaded. O-ZONE [Set/Clear/Show] -- limit module tools to a picked area (fallback for the E-1.0 sheet rule).")
(princ)
