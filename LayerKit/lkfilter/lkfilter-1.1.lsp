;; lkfilter-1.0.lsp -- LayerKit: layer GROUP filters from a CSV
;; Commands: LK-FILTERSET  (CSV -> create/refresh group filters)
;;           LK-FILTERSAVE (existing group filters -> CSV)
;; Modern AutoCAD (2008+) stores the layer-filter tree in the LAYER table's extension
;; dictionary under key "ACLYDICTIONARY" (the legacy "ACAD_LAYERFILTERS" dict is vestigial).
;; A group filter is an XRECORD:
;;   (100 . "AcDbXrecord")(280 . 1)(1 . "AcLyLayerGroup")(90 . 1)(300 . <name>)
;;   (330 . <layer ename>) * one per member layer
;; CSV: PV_layer_filters.csv in the config dir -- one row per filter: name,layer1,layer2,...
;; Reuses lk:get-config-dir / lk:read-csv from lkcleanup (loaded together; called at runtime).
;; v1.0
;; ============================================================

(defun lk:filter-csv () (strcat (lk:get-config-dir) "PV_layer_filters.csv"))

;; ACLYDICTIONARY ename (layer-table xdict). Creates it (VLA) if missing; nil if it can't.
(defun lk:acly-dict ( / lt xd d r)
  (setq lt (cdr (assoc 330 (entget (tblobjname "LAYER" "0")))))
  (setq xd (cdr (assoc 360 (entget lt))))
  (if (and xd (setq d (dictsearch xd "ACLYDICTIONARY")))
    (cdr (assoc -1 d))
    (progn
      (setq r (vl-catch-all-apply
        (function (lambda ( / doc lyrs xdo)
          (setq doc  (vla-get-activedocument (vlax-get-acad-object))
                lyrs (vla-get-layers doc)
                xdo  (vla-getextensiondictionary lyrs))
          (if (vl-catch-all-error-p (vl-catch-all-apply 'vla-item (list xdo "ACLYDICTIONARY")))
            (vla-addobject xdo "ACLYDICTIONARY" "AcDbDictionary"))
          (vlax-vla-object->ename (vla-item xdo "ACLYDICTIONARY"))))))
      (if (vl-catch-all-error-p r) nil r))))

;; remove any existing group filter whose display name (300) matches `name`
(defun lk:filter-remove (ad name / nm rem)
  (setq nm nil  rem '())
  (foreach pr (entget ad)
    (cond
      ((= (car pr) 3) (setq nm (cdr pr)))
      ((member (car pr) '(350 360))
       (if (= (strcase (cond ((cdr (assoc 300 (entget (cdr pr)))))("")))
              (strcase name))
         (setq rem (cons (cons nm (cdr pr)) rem))))))
  (foreach r rem
    (dictremove ad (car r))
    (vl-catch-all-apply 'entdel (list (cdr r)))))

;; ensure a layer exists; CREATE it (white / Continuous) if missing; return its ename.
;; Counts new layers in *lk-filt-new* (reset by C:LK-FILTERSET).
(if (not (boundp (quote *lk-filt-new*))) (setq *lk-filt-new* 0))
(defun lk:filt-ensure-layer (name / en)
  (cond
    ((setq en (tblobjname "LAYER" name)) en)
    (T (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                       '(100 . "AcDbLayerTableRecord") (cons 2 name)
                       '(70 . 0) '(62 . 7) '(6 . "Continuous")))
       (setq *lk-filt-new* (1+ *lk-filt-new*))
       (tblobjname "LAYER" name))))

;; write/refresh one group filter (name + list of layer names) into dict `ad`. T if written.
;; Missing layers are CREATED (so they become members of the filter).
(defun lk:filter-write (ad name layers / members en xr)
  (setq members '())
  (foreach lname layers
    (if (and lname (> (strlen lname) 0) (setq en (lk:filt-ensure-layer lname)))
      (setq members (cons (cons 330 en) members))))
  (lk:filter-remove ad name)
  (setq xr (entmakex
    (append (list '(0 . "XRECORD") '(100 . "AcDbXrecord") '(280 . 1)
                  '(1 . "AcLyLayerGroup") '(90 . 1) (cons 300 name))
            (reverse members))))
  (if xr (progn (dictadd ad name xr) T) nil))

(defun C:LK-FILTERSET ( / path data ad n row)
  (setq path (lk:filter-csv))
  (cond
    ((not (findfile path)) (princ (strcat "\n  No filter CSV: " path)))
    ((not (setq ad (lk:acly-dict)))
     (princ "\n  No layer-filter dictionary, and couldn't create one (needs a GUI session)."))
    (T
     (setq data (lk:read-csv path)  n 0  *lk-filt-new* 0)
     (foreach row data
       (if (and (>= (length row) 1) (> (strlen (car row)) 0))
         (if (lk:filter-write ad (car row) (cdr row)) (setq n (1+ n)))))
     (princ (strcat "\n  Set " (itoa n) " layer group filter(s) from " path "."))
     (if (> *lk-filt-new* 0)
       (princ (strcat "\n  Created " (itoa *lk-filt-new*)
                " missing layer(s) (white/Continuous -- run LK-STDSET to style them).")))
     (princ "\n  ** SAVE and REOPEN the drawing to see the filters ** (AutoCAD reads the")
     (princ "\n  filter tree at open time; the palette won't refresh until reload).")))
  (princ))

(defun C:LK-FILTERSAVE ( / ad path f nm d line n le)
  (setq ad (lk:acly-dict))
  (cond
    ((not ad) (princ "\n  No layer-filter dictionary to read."))
    ((not (setq f (open (setq path (lk:filter-csv)) "w")))
     (princ (strcat "\n  Cannot write: " path)))
    (T
     (write-line "filter,layers" f)
     (setq nm nil  n 0)
     (foreach pr (entget ad)
       (cond
         ((= (car pr) 3) (setq nm (cdr pr)))
         ((member (car pr) '(350 360))
          (setq d (entget (cdr pr)))
          (if (= (cdr (assoc 1 d)) "AcLyLayerGroup")
            (progn
              (setq line (cdr (assoc 300 d)))
              (foreach p2 d
                (if (= (car p2) 330)
                  (if (and (setq le (entget (cdr p2))) (= (cdr (assoc 0 le)) "LAYER"))
                    (setq line (strcat line "," (cdr (assoc 2 le)))))))
              (write-line line f)
              (setq n (1+ n)))))))
     (close f)
     (princ (strcat "\n  Saved " (itoa n) " group filter(s) -> " path "."))))
  (princ))

(princ "\n  LK-FILTER loaded. LK-FILTERSET (CSV->filters) | LK-FILTERSAVE (filters->CSV)")
(princ)
