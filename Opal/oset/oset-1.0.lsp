;; oset-1.0.lsp -- O-Suite Project Parameter Setup
;; Commands: O-SET (alias: OSET)
;; Box-select any 2x2+ grid of modules to derive width, height,
;; X-gap, and Y-gap. Results stored in *oset-* globals used by
;; all other O-Suite geometry tools.
;; v1.0
;; ============================================================

(if (not *oset-mod-w*)  (setq *oset-mod-w*  nil))
(if (not *oset-mod-h*)  (setq *oset-mod-h*  nil))
(if (not *oset-gap-x*)  (setq *oset-gap-x*  nil))
(if (not *oset-gap-y*)  (setq *oset-gap-y*  nil))


;; ============================================================
;; List min/max helpers (no apply 'min / apply 'max)
;; ============================================================

(defun _oset-lmin (lst / v r)
  (setq r (car lst))
  (foreach v (cdr lst) (if (< v r) (setq r v)))
  r)

(defun _oset-lmax (lst / v r)
  (setq r (car lst))
  (foreach v (cdr lst) (if (> v r) (setq r v)))
  r)


;; ============================================================
;; Denylist: return T if layer is a known non-module O-Suite layer.
;; Any 4-vertex LWPOLYLINE NOT on these layers is treated as a module.
;; Matches both Opal layer names and legacy Stringtag names for
;; compatibility on mixed or transitional drawings.
;; ============================================================

(defun _oset-non-module-layer (lyr / u)
  (setq u (strcase lyr))
  (or (vl-string-search "PV-STRINGING"   u)
      (vl-string-search "PV-DC-PATH"     u)
      (vl-string-search "PV-HOMERUN"     u)
      (vl-string-search "PV-CABLE-JUMP"  u)
      (vl-string-search "PV-TAGS"        u)
      (vl-string-search "PV-SCHEDULES"   u)
      (vl-string-search "PV-LAYOUT"      u)
      (vl-string-search "PV-XDATA"       u)
      (vl-string-search "E-CONDUIT"      u)
      (vl-string-search "G-ANNO-TEXT"    u)
      (vl-string-search "DC-ARROW"       u)
      (vl-string-search "STRING-BOUNDARY" u)
      (vl-string-search "STRING-FILL"    u)
      (vl-string-search "STRING-COUNT"   u)
      (vl-string-search "STRING-TAG"     u)
      (vl-string-search "STRING-LABEL"   u)
      (vl-string-search "XDATA-LABEL"    u)
      (vl-string-search "ROW-NUM"        u)
      (vl-string-search "GRIDLINE"       u)
      (vl-string-search "CONDUIT"        u)
      (vl-string-search "HOMERUN"        u)
      (vl-string-search "STRUCTURE"      u)
      (vl-string-search "CALLOUT"        u)
      (vl-string-search "LABEL"          u)
      (vl-string-search "TABLE"          u)))


;; ============================================================
;; Pick modules and derive geometry
;; ============================================================

(defun _oset-pick-module ( / ss i ent ed lyr wpts pair xvals yvals bboxes
                              cx cy w h all-cx all-cy sorted-cx sorted-cy
                              gx gy dup ins res tmp x y u r wp wp3)
  (vl-load-com)
  (prompt "\nO-SET: Select modules (box any 2x2 or larger -- non-module entities ignored): ")
  (setq ss (ssget (quote ((0 . "LWPOLYLINE")))))
  (if (not ss)
    (progn (prompt "\nNothing selected.") nil)
    (progn
      (setq bboxes (quote ())  i 0)
      (while (< i (sslength ss))
        (setq ent (ssname ss i)
              ed  (entget ent)
              lyr (cdr (assoc 8 ed)))
        (if (not (_oset-non-module-layer lyr))
          (progn
            (setq wpts (quote ()))
            (foreach pair ed
              (if (= (car pair) 10)
                (setq wpts (append wpts (list (cdr pair))))))
            (if (= (length wpts) 4)
              (progn
                (setq xvals (quote ())  yvals (quote ()))
                (foreach wp wpts
                  (setq wp3 (trans (list (car wp) (cadr wp) 0.0) 2 0))
                  (setq xvals (append xvals (list (car wp3))))
                  (setq yvals (append yvals (list (cadr wp3)))))
                (setq cx (/ (+ (_oset-lmin xvals) (_oset-lmax xvals)) 2.0)
                      cy (/ (+ (_oset-lmin yvals) (_oset-lmax yvals)) 2.0)
                      w  (- (_oset-lmax xvals) (_oset-lmin xvals))
                      h  (- (_oset-lmax yvals) (_oset-lmin yvals)))
                (setq bboxes (append bboxes (list (list cx cy w h))))))))
        (setq i (1+ i)))

      (if (< (length bboxes) 4)
        (progn
          (prompt (strcat "\nFound " (itoa (length bboxes))
                          " module(s) -- need at least 4 (a 2x2 grid)."))
          nil)
        (progn
          (setq all-cx (quote ())  all-cy (quote ()))
          (foreach bb bboxes
            (setq all-cx (append all-cx (list (car  bb))))
            (setq all-cy (append all-cy (list (cadr bb)))))

          (setq w (caddr  (car bboxes))
                h (cadddr (car bboxes)))

          ;; Deduplicate cx within tolerance 1.0
          (setq sorted-cx (quote ()))
          (foreach x all-cx
            (setq dup nil)
            (foreach u sorted-cx
              (if (< (abs (- x u)) 1.0) (setq dup T)))
            (if (not dup) (setq sorted-cx (append sorted-cx (list x)))))

          ;; Deduplicate cy within tolerance 1.0
          (setq sorted-cy (quote ()))
          (foreach y all-cy
            (setq dup nil)
            (foreach u sorted-cy
              (if (< (abs (- y u)) 1.0) (setq dup T)))
            (if (not dup) (setq sorted-cy (append sorted-cy (list y)))))

          ;; Sort cx ascending
          (setq tmp (quote ()))
          (foreach x sorted-cx
            (setq ins nil  res (quote ()))
            (foreach r tmp
              (if (and (not ins) (< x r))
                (progn (setq res (append res (list x r))  ins T))
                (setq res (append res (list r)))))
            (setq tmp (if ins res (append res (list x)))))
          (setq sorted-cx tmp)

          ;; Sort cy ascending
          (setq tmp (quote ()))
          (foreach y sorted-cy
            (setq ins nil  res (quote ()))
            (foreach r tmp
              (if (and (not ins) (< y r))
                (progn (setq res (append res (list y r))  ins T))
                (setq res (append res (list r)))))
            (setq tmp (if ins res (append res (list y)))))
          (setq sorted-cy tmp)

          (if (or (< (length sorted-cx) 2) (< (length sorted-cy) 2))
            (progn
              (prompt (strcat "\nFound " (itoa (length sorted-cx))
                              " unique X column(s) and " (itoa (length sorted-cy))
                              " unique Y row(s) -- need at least 2 of each."))
              nil)
            (progn
              (setq gx (abs (- (abs (- (cadr sorted-cx) (car sorted-cx))) w))
                    gy (abs (- (abs (- (cadr sorted-cy) (car sorted-cy))) h)))
              (prompt (strcat "\nFound " (itoa (length bboxes)) " modules ("
                              (itoa (length sorted-cx)) " cols x "
                              (itoa (length sorted-cy)) " rows)."))
              (list w h gx gy))))))))


;; ============================================================
;; Main command
;; ============================================================

(defun C:O-SET ( / measured)
  (vl-load-com)
  (prompt "\nO-SET -- Calibrate module grid geometry")
  (setq measured (_oset-pick-module))
  (if measured
    (progn
      (setq *oset-mod-w* (nth 0 measured)
            *oset-mod-h* (nth 1 measured)
            *oset-gap-x* (nth 2 measured)
            *oset-gap-y* (nth 3 measured))
      (prompt "\n--- O-SET parameters ---")
      (prompt (strcat "\n  Module W: " (rtos *oset-mod-w* 2 4)))
      (prompt (strcat "\n  Module H: " (rtos *oset-mod-h* 2 4)))
      (prompt (strcat "\n  Gap X:    " (rtos *oset-gap-x* 2 4)))
      (prompt (strcat "\n  Gap Y:    " (rtos *oset-gap-y* 2 4)))))
  (princ))

(defun C:OSET () (C:O-SET))

(prompt "\nO-SET v1.0 loaded. Type O-SET or OSET to calibrate module grid.")
(princ)
