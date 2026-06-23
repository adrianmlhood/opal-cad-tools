;; lkzeroblock-1.0.lsp -- LayerKit: push a block's nested geometry onto layer 0
;; Command: LK-ZEROBLOCK (alias: LK-ZB)
;; Pick ONE block reference; every entity nested inside it -- through ALL levels of
;; nested blocks -- is moved onto layer "0". The point is the standard AutoCAD idiom:
;; geometry on layer 0 inside a block inherits the block's INSERTION layer, so the block
;; draws cleanly per wherever it's placed.
;; Method (pure DXF + entmod -- cross-space, no COM, accoreconsole-safe):
;;   Resolve the picked INSERT's block name, then walk that block DEFINITION's internal
;;   entities via (entnext (tblobjname "BLOCK" name)) ... to ENDBLK, moving each to "0".
;;   For every nested INSERT found, recurse into its definition (depth-first).
;; Notes:
;;   * Edits SHARED block definitions: all insertions of each block name update (this is
;;     inherent to how blocks store geometry, and is the intended behavior).
;;   * The clicked reference itself is left on its own layer (contents only).
;;   * Each block name is walked once (visited-list guards self-reference / re-walks).
;;   * xref block defs are skipped (their contents can't be edited).
;;   * Locked AND frozen layers are temporarily cleared (entmod is blocked on both) and
;;     restored -- nested entities on such layers still get moved.
;; v1.0
;; ============================================================

;; --- clear lock(4)+freeze(1) on all layers that have them; return ((name . origflags)...) ---
(defun lk:zb-prep ( / rec saved en d f)
  (setq saved '()  rec (tblnext "LAYER" T))
  (while rec
    (setq f (cond ((cdr (assoc 70 rec)))(0)))
    (if (/= 0 (logand f 5))
      (setq saved (cons (cons (cdr (assoc 2 rec)) f) saved)))
    (setq rec (tblnext "LAYER")))
  (foreach pr saved
    (setq en (tblobjname "LAYER" (car pr))  d (entget en)  f (cdr (assoc 70 d)))
    (if (= 1 (logand f 1)) (setq f (- f 1)))
    (if (= 4 (logand f 4)) (setq f (- f 4)))
    (vl-catch-all-apply (function (lambda () (entmod (subst (cons 70 f) (assoc 70 d) d))))))
  saved)

;; --- restore original lock/freeze bits ---
(defun lk:zb-restore (saved / en d f want)
  (foreach pr saved
    (setq en (tblobjname "LAYER" (car pr))  d (entget en)
          f (cdr (assoc 70 d))  want (cdr pr))
    (if (and (= 4 (logand want 4)) (= 0 (logand f 4))) (setq f (+ f 4)))
    (if (and (= 1 (logand want 1)) (= 0 (logand f 1))) (setq f (+ f 1)))
    (vl-catch-all-apply (function (lambda () (entmod (subst (cons 70 f) (assoc 70 d) d)))))))

;; --- is this block definition an xref? (flag-70 bit 4) ---
(defun lk:zb-xref-p (bname / brec)
  (and (setq brec (tblsearch "BLOCK" bname))
       (/= 0 (logand (cond ((cdr (assoc 70 brec)))(0)) 4))))

;; --- recursive walker: move a block def's entities to "0", recurse into nested INSERTs.
;;     Accumulates into *lk-zb-moved* / *lk-zb-visited* (set by the command). ---
(defun lk:zb-walk (bname / en et)
  (setq bname (strcase bname))
  (if (and (not (member bname *lk-zb-visited*))
           (not (lk:zb-xref-p bname)))
    (progn
      (setq *lk-zb-visited* (cons bname *lk-zb-visited*))
      (setq en (entnext (tblobjname "BLOCK" bname)))
      (while (and en (setq et (entget en)) (/= "ENDBLK" (cdr (assoc 0 et))))
        (if (/= "0" (cdr (assoc 8 et)))
          (if (not (vl-catch-all-error-p
                     (vl-catch-all-apply 'entmod
                       (list (subst (cons 8 "0") (assoc 8 et) et)))))
            (setq *lk-zb-moved* (1+ *lk-zb-moved*))))
        (if (= "INSERT" (cdr (assoc 0 et)))
          (lk:zb-walk (cdr (assoc 2 et))))
        (setq en (entnext en))))))

(defun C:LK-ZEROBLOCK ( / old-err old-ce ent edata bname saved)
  (setq old-err *error*)
  (defun *error* (msg)
    (if (and msg (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*")))
      (princ (strcat "\nError: " msg)))
    (if saved (lk:zb-restore saved))
    (if old-ce (setvar "CMDECHO" old-ce))
    (setq *error* old-err)
    (princ))

  (setq ent (car (entsel "\nSelect a block reference: ")))
  (cond
    ((null ent)
     (princ "\n  Cancelled."))
    ((/= "INSERT" (cdr (assoc 0 (setq edata (entget ent)))))
     (princ "\n  ** Not a block reference."))
    ((lk:zb-xref-p (setq bname (cdr (assoc 2 edata))))
     (princ "\n  ** That is an xref -- its contents can't be edited."))
    (T
     (setq *lk-zb-visited* nil  *lk-zb-moved* 0)
     (setq old-ce (getvar "CMDECHO"))
     (setvar "CMDECHO" 0)
     (setq saved (lk:zb-prep))
     (lk:zb-walk bname)
     (lk:zb-restore saved)
     (setq saved nil)
     (entupd ent)
     (setvar "CMDECHO" old-ce)
     (princ (strcat "\n  Moved " (itoa *lk-zb-moved*) " nested entity(ies) to layer 0  ["
                    (itoa (length *lk-zb-visited*)) " block definition(s) walked]."))
     (if saved (princ))))
  (setq *error* old-err)
  (princ))

(defun C:LK-ZB () (C:LK-ZEROBLOCK))

(princ "\n  LK-ZEROBLOCK loaded. LK-ZEROBLOCK (alias LK-ZB) -- pick a block, push nested geometry to layer 0.")
(princ)
