;; lkstd-1.0.lsp -- LayerKit Layer Standards
;; Commands: LK-STDSAVE  (export current drawing's layer properties -> CSV)
;;           LK-STDSET   (apply CSV standards to matching layers in current drawing)
;; Per-layer standard captured: color(ACI), linetype, lineweight(1/100mm), plot flag,
;; and New-VP-Freeze (group 70 bit 2 = frozen by default in NEW viewports).
;; CSV: PV_layer_standards.csv in the LK config dir (lk:get-config-dir).
;; Pure DXF (entget/entmod on LAYER records) -- no COM. Reuses lk:get-config-dir /
;; lk:read-csv from lkcleanup (same suite, loaded together; only called at runtime).
;; LK-CLEANUP auto-applies these at the end of a run via lk:std-apply (if a CSV exists).
;; v1.0
;; ============================================================

(defun lk:std-csv-path ()
  (strcat (lk:get-config-dir) "PV_layer_standards.csv"))

;; ---- read one property from a LAYER record (entget of tblobjname) ----
(defun lk:lay-color (rec) (abs (cond ((cdr (assoc 62 rec)))(7))))
(defun lk:lay-ltype (rec) (cond ((cdr (assoc 6 rec)))("Continuous")))
(defun lk:lay-lw    (rec) (cond ((cdr (assoc 370 rec)))(-3)))
(defun lk:lay-plot  (rec) (cond ((cdr (assoc 290 rec)))(1)))
(defun lk:lay-vpf   (rec) (if (= 2 (logand (cond ((cdr (assoc 70 rec)))(0)) 2)) 1 0))

;; ---- build one CSV row string from a layer name + its full DXF record ----
(defun lk:std-row (name rec)
  (strcat name ","
          (itoa (lk:lay-color rec)) ","
          (lk:lay-ltype rec) ","
          (itoa (lk:lay-lw rec)) ","
          (itoa (lk:lay-plot rec)) ","
          (itoa (lk:lay-vpf rec))))

;; ---- EXPORT: current layers -> CSV. Layers ALREADY in the standards list (and "0") are
;; written as-is. A layer NOT yet listed is CONFIRMED first (lk:confirm-new-layer:
;; Yes/No/Reject) so junk layers don't silently enter the standards; "Reject" remembers it
;; permanently. Permanently-rejected layers are DROPPED even if currently listed (so a Save
;; purges them). First-ever Save (no CSV) writes everything -- nothing to protect yet. ----
(defun lk:std-save ( / path existing gate f trec rec name rows newct addct dropct)
  (setq path (lk:std-csv-path)  existing '()  gate (and (findfile path) T))
  ;; collect the names already in the standards list (UPPER)
  (if gate
    (foreach row (lk:read-csv path)
      (if (and (car row) (> (strlen (car row)) 0))
        (setq existing (cons (strcase (car row)) existing)))))
  ;; walk drawing layers; gate any that aren't already standards
  (setq rows '()  newct 0  addct 0  dropct 0  trec (tblnext "LAYER" T))
  (while trec
    (setq name (cdr (assoc 2 trec))
          ;; tblnext records OMIT lineweight(370)/plot(290) -- read the FULL record
          rec  (entget (tblobjname "LAYER" name)))
    (cond
      ;; permanently rejected -> drop it (even if currently listed)
      ((and (boundp (quote lk:rejected-p)) (lk:rejected-p name))
       (setq dropct (1+ dropct)))
      ;; layer 0 or an existing standard -> keep as-is
      ((or (= (strcase name) "0") (member (strcase name) existing))
       (setq rows (cons (lk:std-row name rec) rows)))
      ;; NEW layer -> confirm before adding to the standards list
      (T
       (setq newct (1+ newct))
       (if (or (not gate)
               (if (boundp (quote lk:confirm-new-layer))
                 (lk:confirm-new-layer name "standards")
                 T))
         (setq rows (cons (lk:std-row name rec) rows)  addct (1+ addct)))))
    (setq trec (tblnext "LAYER")))
  ;; write the curated list
  (setq f (open path "w"))
  (if (not f)
    (princ (strcat "\n  ** Cannot write: " path))
    (progn
      (write-line "layer,color,linetype,lineweight,plot,vpfreeze" f)
      (foreach ln (reverse rows) (write-line ln f))
      (close f)
      (princ (strcat "\n  Saved " (itoa (length rows)) " layer standard(s) -> " path))
      (if (> newct 0)
        (princ (strcat "\n  New layers: " (itoa addct) " added, "
                 (itoa (- newct addct)) " declined.")))
      (if (> dropct 0)
        (princ (strcat "\n  Dropped " (itoa dropct) " permanently-rejected layer(s).")))))
  (princ))

;; ---- ensure a linetype is loaded (from acad.lin) ----
(defun lk:ensure-ltype (lt)
  (cond
    ((or (null lt) (= (strlen lt) 0)) nil)
    ((tblsearch "LTYPE" lt) T)
    ((= (strcase lt) "CONTINUOUS") T)
    (T (vl-catch-all-apply
         (function (lambda () (command "._-LINETYPE" "_LOAD" lt "acad.lin" ""))))
       (and (tblsearch "LTYPE" lt) T))))

;; ---- APPLY: CSV -> layers. CREATES any standard layer that doesn't exist yet (so the
;; standard set populates), then sets its props. Returns count applied, or -1 if no CSV ----
(defun lk:std-apply ( / path data n name color lt lw plot vpf en rec cur62 c62 f70)
  (setq path (lk:std-csv-path))
  (if (not (findfile path))
    -1
    (progn
      (setq data (lk:read-csv path)  n 0)
      (foreach row data
        (if (>= (length row) 2)
          (progn
            (setq name  (nth 0 row)
                  color (atoi (nth 1 row))
                  lt    (if (> (length row) 2) (nth 2 row) "")
                  lw    (if (> (length row) 3) (atoi (nth 3 row)) -3)
                  plot  (if (> (length row) 4) (atoi (nth 4 row)) 1)
                  vpf   (if (> (length row) 5) (atoi (nth 5 row)) 0))
            (if (/= (strcase name) "0")
              (progn
                ;; create the standard layer if it doesn't exist yet -- these are curated
                ;; CSV layers, so no prompt; just skip any permanently-rejected name.
                (if (and (not (tblobjname "LAYER" name))
                         (not (and (boundp (quote lk:rejected-p)) (lk:rejected-p name))))
                  (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                                  '(100 . "AcDbLayerTableRecord") (cons 2 name)
                                  '(70 . 0) '(62 . 7) '(6 . "Continuous"))))
                ;; style only if the layer now exists (pre-existing, or creation confirmed)
                (if (setq en (tblobjname "LAYER" name))
                  (progn
                    (setq rec (entget en))
                    ;; color (preserve current on/off sign)
                    (setq cur62 (cond ((cdr (assoc 62 rec)))(7)))
                    (setq c62 (if (< cur62 0) (- (abs color)) (abs color)))
                    (setq rec (subst (cons 62 c62) (assoc 62 rec) rec))
                    ;; linetype
                    (if (lk:ensure-ltype lt)
                      (if (assoc 6 rec)
                        (setq rec (subst (cons 6 lt) (assoc 6 rec) rec))
                        (setq rec (append rec (list (cons 6 lt))))))
                    ;; lineweight
                    (if (assoc 370 rec)
                      (setq rec (subst (cons 370 lw) (assoc 370 rec) rec))
                      (setq rec (append rec (list (cons 370 lw)))))
                    ;; plot flag
                    (if (assoc 290 rec)
                      (setq rec (subst (cons 290 plot) (assoc 290 rec) rec))
                      (setq rec (append rec (list (cons 290 plot)))))
                    ;; new-vp-freeze (bit 2 of group 70)
                    (setq f70 (cond ((cdr (assoc 70 rec)))(0)))
                    (setq f70 (if (= vpf 1)
                                (logior f70 2)
                                (if (= 2 (logand f70 2)) (- f70 2) f70)))
                    (setq rec (subst (cons 70 f70) (assoc 70 rec) rec))
                    (if (not (vl-catch-all-error-p (vl-catch-all-apply 'entmod (list rec))))
                      (setq n (1+ n))))))))))
      n)))

(defun lk:std-set ( / n old-ce)
  (setq old-ce (getvar "CMDECHO")) (setvar "CMDECHO" 0)
  (setq n (lk:std-apply))
  (setvar "CMDECHO" old-ce)
  (if (< n 0)
    (princ (strcat "\n  No standards file (" (lk:std-csv-path) "). Use LK-STD > Save first."))
    (princ (strcat "\n  Applied standards to " (itoa n) " layer(s).")))
  (princ))

;; One command: Save (export look) | Set (apply look) | Config (set the CSV directory)
(defun C:LK-STD ( / opt)
  (initget "Save Set Config Rejects")
  (setq opt (getkword "\nLayer standards [Save/Set/Config/Rejects] <Set>: "))
  (cond
    ((= opt "Save") (lk:std-save))
    ((= opt "Config")
     (if (boundp (quote lk:set-config-dir)) (lk:set-config-dir)
       (princ "\n  (config helper not loaded)")))
    ((= opt "Rejects")
     (if (boundp (quote lk:reject-manage)) (lk:reject-manage)
       (princ "\n  (reject helper not loaded)")))
    (T (lk:std-set)))
  (princ))

(princ "\n  LK-STD loaded. LK-STD [Save/Set/Config/Rejects]")
(princ)
