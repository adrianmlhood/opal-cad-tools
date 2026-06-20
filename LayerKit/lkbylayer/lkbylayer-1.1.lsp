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

;; --- EXCLUSIONS -------------------------------------------------------------------
;; Two kinds, both PERSISTENT:
;;   * Block names -> *lk-bylayer-skip* (wildcards, case-insensitive). Saved in the Windows
;;     registry (HKCU\Software\Ocotillo\LayerKit\BylayerSkipBlocks, "|"-joined) so they carry
;;     across drawings/sessions. Both the block DEFINITION and any INSERTs are preserved.
;;   * Individual elements -> tagged with "LKSKIP" XDATA, which is saved inside the DWG.
;; Build the lists by PICKING objects: LK-SKIPADD. View: LK-SKIPLIST. Clear: LK-SKIPCLEAR.

(defun lk:bl-regkey () "HKEY_CURRENT_USER\\Software\\Ocotillo\\LayerKit")

(defun lk:bl-split (s / pos out)            ; split on "|"
  (setq out '())
  (while (setq pos (vl-string-search "|" s))
    (setq out (cons (substr s 1 pos) out)  s (substr s (+ pos 2))))
  (if (> (strlen s) 0) (setq out (cons s out)))
  (reverse out))

(defun lk:bl-load-skip ( / s)
  (setq s (vl-registry-read (lk:bl-regkey) "BylayerSkipBlocks"))
  (if (and s (= (type s) 'STR) (> (strlen s) 0)) (lk:bl-split s) nil))

(defun lk:bl-save-skip (lst / s)
  (setq s "")
  (foreach x lst (setq s (if (= s "") x (strcat s "|" x))))
  (vl-registry-write (lk:bl-regkey) "BylayerSkipBlocks" s))

;; Restore the saved block list each session (authoritative); seed "*NORTH*" if none saved.
(if (not (boundp (quote *lk-bylayer-skip*))) (setq *lk-bylayer-skip* nil))
(setq *lk-bl-saved* (lk:bl-load-skip))
(cond (*lk-bl-saved* (setq *lk-bylayer-skip* *lk-bl-saved*))
      ((not *lk-bylayer-skip*) (setq *lk-bylayer-skip* (quote ("*NORTH*")))))

(defun lk:skip-block-p (name / hit)
  (setq hit nil)
  (foreach pat *lk-bylayer-skip*
    (if (wcmatch (strcase name) (strcase pat)) (setq hit T)))
  hit)

;; element-level skip: entity carries "LKSKIP" XDATA (saved in the drawing)
(defun lk:has-skip-xd (e)
  (assoc -3 (entget e (list "LKSKIP"))))

;; should this entity be left alone? (insert of an excluded block, or an XDATA-tagged element)
(defun lk:skip-ent-p (e et)
  (or (and (= "INSERT" (cdr (assoc 0 et))) (lk:skip-block-p (cdr (assoc 2 et))))
      (lk:has-skip-xd e)))

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

  ;; Part 1: every top-level entity in every space (model + all layouts).
  ;; Skip INSERTs of excluded blocks so those references keep their look.
  (if (setq ss (ssget "X"))
    (repeat (setq i (sslength ss))
      (setq i (1- i)  e (ssname ss i)  et (entget e))
      (if (not (lk:skip-ent-p e et))
        (if (lk:bylayer-ent e) (setq n (1+ n))))))

  ;; Part 2: entities INSIDE block definitions (skip layout blocks + xrefs)
  (setq brec (tblnext "BLOCK" T))
  (while brec
    (setq bname (cdr (assoc 2 brec))  f70 (cond ((cdr (assoc 70 brec)))(0)))
    (if (and (= 0 (logand f70 4))
             (not (wcmatch (strcase bname) "*MODEL_SPACE,*PAPER_SPACE*"))
             (not (lk:skip-block-p bname)))            ; preserve excluded blocks
      (progn
        (setq en (entnext (tblobjname "BLOCK" bname)))
        (while (and en (setq et (entget en)) (/= "ENDBLK" (cdr (assoc 0 et))))
          (if (not (lk:has-skip-xd en))
            (if (lk:bylayer-ent en) (setq n (1+ n))))
          (setq en (entnext en)))))
    (setq brec (tblnext "BLOCK")))

  (lk:restore-layers saved)
  (setvar "CMDECHO" old-ce)
  (princ (strcat "\n  Color set ByLayer on " (itoa n)
           " object(s) -- all spaces + block definitions."))
  (if *lk-bylayer-skip*
    (progn
      (princ "\n  Excluded blocks (colors preserved): ")
      (foreach p *lk-bylayer-skip* (princ (strcat p " ")))))
  (if saved
    (princ (strcat "\n  (temporarily cleared lock/freeze on " (itoa (length saved))
             " layer(s), restored.)")))
  (princ))

;;; ============================================================
;;; Build the persistent exclusion lists by PICKING objects
;;; ============================================================
(defun C:LK-SKIPADD ( / ss i e et typ name lst nblk nent old-ce)
  (princ "\nSelect blocks / elements to EXCLUDE from LK-BYLAYER (colors preserved):")
  (setq ss (ssget))
  (if (not ss)
    (princ "\n  Nothing selected.")
    (progn
      (setq old-ce (getvar "CMDECHO")) (setvar "CMDECHO" 0)
      (regapp "LKSKIP")
      (setq lst (if *lk-bylayer-skip* *lk-bylayer-skip* '())  nblk 0  nent 0  i 0)
      (repeat (sslength ss)
        (setq e (ssname ss i)  et (entget e)  typ (cdr (assoc 0 et))  i (1+ i))
        (if (= typ "INSERT")
          (progn                                   ; block -> add NAME to saved list
            (setq name (strcase (cdr (assoc 2 et))))
            (if (not (member name lst))
              (setq lst (cons name lst)  nblk (1+ nblk))))
          (if (not (lk:has-skip-xd e))             ; element -> tag with XDATA in the drawing
            (if (not (vl-catch-all-error-p
                       (vl-catch-all-apply (function (lambda ()
                         (entmod (append et (list (list -3 (list "LKSKIP" (cons 1000 "skip")))))))))))
              (setq nent (1+ nent))))))
      (setq *lk-bylayer-skip* lst)
      (lk:bl-save-skip lst)
      (setvar "CMDECHO" old-ce)
      (princ (strcat "\n  Added " (itoa nblk) " block name(s) (saved across sessions) and "
               (itoa nent) " element(s) (tagged in this drawing)."))
      (princ (strcat "\n  Block exclusions now: "))
      (foreach p *lk-bylayer-skip* (princ (strcat p " ")))))
  (princ))

(defun C:LK-SKIPLIST ( )
  (princ "\n  LK-BYLAYER block exclusions (saved):")
  (if *lk-bylayer-skip*
    (foreach p *lk-bylayer-skip* (princ (strcat "\n    " p)))
    (princ "\n    (none)"))
  (princ "\n  Individual elements are excluded by an LKSKIP tag stored in the drawing.")
  (princ))

(defun C:LK-SKIPCLEAR ( )
  (setq *lk-bylayer-skip* nil)
  (lk:bl-save-skip nil)
  (princ "\n  Cleared the saved block-exclusion list.")
  (princ "\n  (Element tags remain in the drawing; re-run LK-BYLAYER won't skip blocks now.)")
  (princ))

(princ "\n  LK-BYLAYER loaded. LK-BYLAYER (run) | LK-SKIPADD (pick exclusions) | LK-SKIPLIST | LK-SKIPCLEAR")
(princ)
