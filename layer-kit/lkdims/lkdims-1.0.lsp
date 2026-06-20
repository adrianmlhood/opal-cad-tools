;; lkdims-1.0.lsp -- LayerKit: bring all DIMENSIONs to draw-order FRONT and
;; apply a background text mask (DIMTFILL = 1) to every dimension.
;; Command: LK-DIMS  [Both/Front/Mask]  (default Both)
;;
;; FRONT: DRAWORDER only acts on the CURRENT space, so we loop Model + every
;;        layout: set CTAB, select that tab's DIMENSIONs (group 410), DRAWORDER _F.
;; MASK:  a dimension's "background" text fill = dimvar DIMTFILL 1 (fills the dim
;;        text box with the drawing background color). We first VERIFY each dim's
;;        effective DIMTFILL -- the entity DSTYLE override (XDATA code 69) if
;;        present, else its dimstyle record's 69 -- and report how many already
;;        have a fill, then DIMOVERRIDE DIMTFILL=1 across all dims (idempotent).
;;        DIMOVERRIDE (not raw XDATA entmod) merges cleanly with any existing
;;        per-dim overrides; like DRAWORDER it acts per current space.
;; v1.0
;; ============================================================

;; --- effective DIMTFILL for one dimension (entity override first, then its style)
(defun lk:dim-tfill (ent / ed app a sub found val stylename sed)
  (setq ed    (entget ent '("ACAD"))
        found nil
        val   nil
        app   (cdr (assoc -3 ed)))               ; ((appname (1070 . 69) ...) ...)
  (if app
    (foreach a app
      (if (and (= (car a) "ACAD") (not found))
        (progn
          (setq sub (cdr a))                     ; flat list of (code . value) pairs
          (while (and sub (not found))
            (if (and (= (caar sub) 1070)
                     (= (cdar sub) 69)
                     (cdr sub)
                     (= (car (cadr sub)) 1070))
              (setq val (cdr (cadr sub)) found T))
            (setq sub (cdr sub)))))))
  (cond
    (found val)
    (T                                            ; fall back to the dimstyle record
     (setq stylename (cdr (assoc 3 ed)))
     (if (and stylename (tblobjname "DIMSTYLE" stylename))
       (progn
         (setq sed (entget (tblobjname "DIMSTYLE" stylename)))
         (if (assoc 69 sed) (cdr (assoc 69 sed)) 0))
       0))))

;; --- engine (no interactive prompts) -- do-front / do-mask are booleans.
;; Returns a list (found verifiedmask frontcnt appliedcnt); found = total dims.
(defun lk:dims-run (do-front do-mask / cmde ctab allss n i ent tf
                                       verifiedmask spaces sp ss frontcnt appliedcnt)
  (setq cmde (getvar "CMDECHO")
        ctab (getvar "CTAB"))
  (setvar "CMDECHO" 0)
  (setq allss (ssget "_X" '((0 . "DIMENSION")))
        verifiedmask 0
        frontcnt 0
        appliedcnt 0)
  (if (null allss)
    (progn
      (prompt "\nLK-DIMS: no DIMENSION objects found.")
      (setvar "CMDECHO" cmde)
      (list 0 0 0 0))
    (progn
      (setq n (sslength allss))
      (prompt (strcat "\nLK-DIMS: " (itoa n) " dimension(s) found."))

      ;; MASK -- verify current state before applying
      (if do-mask
        (progn
          (setq i 0)
          (while (< i n)
            (setq ent (ssname allss i)
                  tf  (lk:dim-tfill ent))
            (if (and tf (numberp tf) (> tf 0)) (setq verifiedmask (1+ verifiedmask)))
            (setq i (1+ i)))
          (prompt (strcat "\n  Mask check: " (itoa verifiedmask) " of " (itoa n)
                          " already have a background fill."))))

      ;; per-space pass: DRAWORDER front + DIMOVERRIDE mask (both are current-space only)
      (setq spaces (cons "Model" (layoutlist)))
      (foreach sp spaces
        (vl-catch-all-apply 'setvar (list "CTAB" sp))
        (setq ss (ssget "_X" (list '(0 . "DIMENSION") (cons 410 sp))))
        (if ss
          (progn
            (if do-front
              (progn
                (command "._DRAWORDER" ss "" "_F")
                (setq frontcnt (+ frontcnt (sslength ss)))))
            (if do-mask
              (progn
                (command "._DIMOVERRIDE" "DIMTFILL" "1" "" ss "")
                (setq appliedcnt (+ appliedcnt (sslength ss))))))))
      (vl-catch-all-apply 'setvar (list "CTAB" ctab))

      (if do-front
        (prompt (strcat "\n  Front: " (itoa frontcnt)
                        " dimension(s) brought to draw-order front.")))
      (if do-mask
        (prompt (strcat "\n  Mask: DIMTFILL=1 (background) applied across "
                        (itoa appliedcnt) " dimension(s).")))
      (prompt "\nLK-DIMS: done.")
      (setvar "CMDECHO" cmde)
      (list n verifiedmask frontcnt appliedcnt))))

(defun C:LK-DIMS ( / olderr opt do-front do-mask)
  (vl-load-com)
  (setq olderr *error*)
  (defun *error* (msg)
    (setq *error* olderr)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nLK-DIMS error: " msg)))
    (princ))
  (initget "Both Front Mask")
  (setq opt (getkword "\nLK-DIMS [Both/Front/Mask] <Both>: "))
  (if (not opt) (setq opt "Both"))
  (setq do-front (and (member opt '("Both" "Front")) T)
        do-mask  (and (member opt '("Both" "Mask"))  T))
  (lk:dims-run do-front do-mask)
  (setq *error* olderr)
  (princ))

(defun C:LKDIMS () (C:LK-DIMS))

(prompt "\nLK-DIMS loaded -- bring DIMENSIONs to front + DIMTFILL background mask.")
(princ)
