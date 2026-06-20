;; lkbylayer-1.0.lsp -- LayerKit: force entity color to ByLayer EVERYWHERE
;; Command: LK-BYLAYER
;; Sets every entity's color to ByLayer (group 62 = 256) and removes any true-color
;; override (group 420), across ALL spaces (model + every layout) AND inside ALL block
;; definitions. The native SETBYLAYER can't do this in one pass -- it only touches the
;; CURRENT space and only optionally blocks, so objects in other layouts / paper space /
;; block definitions get left behind.
;; Method (pure DXF + entmod -- cross-space, no COM):
;;   Part 1: (ssget "X") returns every TOP-LEVEL entity in every space -> entmod ByLayer.
;;   Part 2: walk every block DEFINITION's internal entities via
;;           (entnext (tblobjname "BLOCK" name)) ... to ENDBLK -> entmod ByLayer.
;;           (tblnext's group -2 is unreliable -- it's omitted for layout blocks.)
;;   Layout blocks (*Model_Space/*Paper_Space*) are skipped in Part 2 (done by Part 1);
;;   xref block defs are skipped (their contents can't be edited).
;; Locked AND frozen layers are temporarily cleared (entmod is blocked on both) and restored.
;; v1.0
;; ============================================================

;; --- set ONE entity's color ByLayer (strip true-color); return T if it changed ---
(defun lk:bylayer-ent (en / d changed)
  (setq d (entget en)  changed nil)
  (if d
    (progn
      (if (assoc 420 d) (setq d (vl-remove (assoc 420 d) d)  changed T))   ; drop true-color
      (cond
        ((not (assoc 62 d)) nil)                                           ; already ByLayer
        ((/= 256 (cdr (assoc 62 d)))
         (setq d (subst (cons 62 256) (assoc 62 d) d)  changed T)))
      (if changed (vl-catch-all-apply (function (lambda () (entmod d)))))))
  changed)

;; --- clear lock(4)+freeze(1) on all layers that have them; return ((name . origflags)...) ---
(defun lk:prep-all ( / rec saved en d f)
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
(defun lk:restore-layers (saved / en d f want)
  (foreach pr saved
    (setq en (tblobjname "LAYER" (car pr))  d (entget en)
          f (cdr (assoc 70 d))  want (cdr pr))
    (if (and (= 4 (logand want 4)) (= 0 (logand f 4))) (setq f (+ f 4)))
    (if (and (= 1 (logand want 1)) (= 0 (logand f 1))) (setq f (+ f 1)))
    (vl-catch-all-apply (function (lambda () (entmod (subst (cons 70 f) (assoc 70 d) d)))))))

(defun C:LK-BYLAYER ( / old-ce saved ss i e n brec bname f70 en et)
  (setq old-ce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (setq saved (lk:prep-all)  n 0)

  ;; Part 1: every top-level entity in every space (model + all layouts)
  (if (setq ss (ssget "X"))
    (repeat (setq i (sslength ss))
      (setq i (1- i)  e (ssname ss i))
      (if (lk:bylayer-ent e) (setq n (1+ n)))))

  ;; Part 2: entities INSIDE block definitions (skip layout blocks + xrefs)
  (setq brec (tblnext "BLOCK" T))
  (while brec
    (setq bname (cdr (assoc 2 brec))  f70 (cond ((cdr (assoc 70 brec)))(0)))
    (if (and (= 0 (logand f70 4))
             (not (wcmatch (strcase bname) "*MODEL_SPACE,*PAPER_SPACE*")))
      (progn
        (setq en (entnext (tblobjname "BLOCK" bname)))
        (while (and en (setq et (entget en)) (/= "ENDBLK" (cdr (assoc 0 et))))
          (if (lk:bylayer-ent en) (setq n (1+ n)))
          (setq en (entnext en)))))
    (setq brec (tblnext "BLOCK")))

  (lk:restore-layers saved)
  (setvar "CMDECHO" old-ce)
  (princ (strcat "\n  Color set ByLayer on " (itoa n)
           " object(s) -- all spaces + block definitions."))
  (if saved
    (princ (strcat "\n  (temporarily cleared lock/freeze on " (itoa (length saved))
             " layer(s), restored.)")))
  (princ))

(princ "\n  LK-BYLAYER loaded. Forces all entity colors ByLayer (all spaces + blocks).")
(princ)
