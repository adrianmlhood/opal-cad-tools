;; ============================================================
;; zza-1.1  --  ZZA : Zoom arrays -- zoom window to the extent of all PV arrays
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: verb ZZ (zoom, new verb) + noun A (array). Frames every PV module
;; in the drawing in one view -- the combined boundary of all arrays. Lives in opal-tools
;; so it runs today, on the ogeo shared library (the suite's geometry kernel).
;;
;; COMMAND  ZZA
;;   No pick. Collects every PV module (ogeo, with graceful layer fallback), filters to the
;;   REAL modules (the modal-footprint set O-SET counts), accumulates the WCS bounding box,
;;   and ZOOM-windows to it with a small margin.
;;
;; v1.1 -- frame only REAL modules. Was accumulating the bbox over EVERY polyline
;;         _ogeo-all-modules returned, so stray clutter on the module layer (mismatched
;;         footprints) stretched the window. Now passes through _ogeo-real-modules first,
;;         so the zoom matches O-SET's module count.
;;
;; DESIGN NOTES (per O-Suite CLAUDE.md)
;;   - Modules via shared _ogeo-all-modules (configured module layer first; shape-gated
;;     all-layer fallback) then _ogeo-real-modules (modal-footprint gate). No geometry
;;     assumptions re-implemented here.
;;   - Per-module WCS extent via vla-getboundingbox (correct for rotated Solesca modules --
;;     the box is the axis-aligned WCS envelope, which is exactly what a zoom window needs).
;;   - View-only: nothing in the drawing is modified. Zoom via vla-ZoomWindow.
;; ============================================================

(vl-load-com)

;; ============================================================
;; ZZA  --  zoom window to all PV array boundaries
;; ============================================================
(defun C:ZZA ( / old-err recs r o mn mx minx miny maxx maxy dx dy mar p1 p2)
  (vl-load-com)
  (setq old-err *error*)
  (defun *error* (msg)
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nZZA error: " msg)))
    (princ))

  (cond
    ((not (member "_OGEO-ALL-MODULES" (atoms-family 1 (list "_OGEO-ALL-MODULES"))))
     (prompt "\nZZA: ogeo library not loaded -- run OLOAD."))
    (T
     (setq recs (_ogeo-real-modules (_ogeo-all-modules)))
     (if (null recs)
       (prompt "\nZZA: no PV modules found.")
       (progn
         ;; accumulate the WCS bounding box over every module
         (foreach r recs
           (setq o (vlax-ename->vla-object (car r)))
           (vla-getboundingbox o 'mn 'mx)
           (setq mn (vlax-safearray->list mn) mx (vlax-safearray->list mx))
           (if (null minx)
             (setq minx (car mn) miny (cadr mn) maxx (car mx) maxy (cadr mx))
             (setq minx (min minx (car mn)) miny (min miny (cadr mn))
                   maxx (max maxx (car mx)) maxy (max maxy (cadr mx)))))
         ;; 5% margin so the outermost arrays are not flush to the screen edge
         (setq dx (- maxx minx) dy (- maxy miny)
               mar (* 0.05 (max dx dy 1.0))
               p1 (list (- minx mar) (- miny mar) 0.0)
               p2 (list (+ maxx mar) (+ maxy mar) 0.0))
         (vla-ZoomWindow (vlax-get-acad-object) (vlax-3d-point p1) (vlax-3d-point p2))
         (prompt (strcat "\nZZA: zoomed to " (itoa (length recs))
                         " real modules across all arrays."))))))

  (setq *error* old-err)
  (princ))

(prompt "\nZZA v1.1 loaded. Command: ZZA  ->  zoom window to all PV array boundaries.")
(princ)
