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

;; ---- EXPORT: current layers -> CSV ----
(defun C:LK-STDSAVE ( / path f trec rec name n)
  (setq path (lk:std-csv-path)  f (open path "w"))
  (if (not f)
    (progn (princ (strcat "\n  ** Cannot write: " path)) (princ))
    (progn
      (write-line "layer,color,linetype,lineweight,plot,vpfreeze" f)
      (setq n 0  trec (tblnext "LAYER" T))
      (while trec
        (setq name (cdr (assoc 2 trec)))
        ;; tblnext records OMIT lineweight(370)/plot(290) -- read the FULL record
        (setq rec (entget (tblobjname "LAYER" name)))
        (write-line
          (strcat name ","
                  (itoa (lk:lay-color rec)) ","
                  (lk:lay-ltype rec) ","
                  (itoa (lk:lay-lw rec)) ","
                  (itoa (lk:lay-plot rec)) ","
                  (itoa (lk:lay-vpf rec)))
          f)
        (setq n (1+ n)  trec (tblnext "LAYER")))
      (close f)
      (princ (strcat "\n  Saved " (itoa n) " layer standards -> " path))
      (princ))))

;; ---- ensure a linetype is loaded (from acad.lin) ----
(defun lk:ensure-ltype (lt)
  (cond
    ((or (null lt) (= (strlen lt) 0)) nil)
    ((tblsearch "LTYPE" lt) T)
    ((= (strcase lt) "CONTINUOUS") T)
    (T (vl-catch-all-apply
         (function (lambda () (command "._-LINETYPE" "_LOAD" lt "acad.lin" ""))))
       (and (tblsearch "LTYPE" lt) T))))

;; ---- APPLY: CSV -> matching layers. Returns count applied, or -1 if no CSV ----
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
            (if (and (/= (strcase name) "0")
                     (setq en (tblobjname "LAYER" name)))
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
                  (setq n (1+ n))))))))
      n)))

(defun C:LK-STDSET ( / n old-ce)
  (setq old-ce (getvar "CMDECHO")) (setvar "CMDECHO" 0)
  (setq n (lk:std-apply))
  (setvar "CMDECHO" old-ce)
  (if (< n 0)
    (princ (strcat "\n  No standards file. Run LK-STDSAVE first (" (lk:std-csv-path) ")."))
    (princ (strcat "\n  Applied standards to " (itoa n) " layer(s).")))
  (princ))

(princ "\n  LK-STD loaded. Commands: LK-STDSAVE (export) | LK-STDSET (apply)")
(princ)
