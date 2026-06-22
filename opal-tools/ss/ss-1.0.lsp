;; ============================================================
;; ss-1.0  --  SS : Select layer -- select every object on the picked entity's layer
;; Opal CAD Tools  --  O-Suite (Opal Energy, Solesca exports)
;;
;; VVN nomenclature: bare SS = the SELECT verb at full breadth -- pick one object, get
;; everything on its layer. (Reassigned from the roster's planned "master tile menu"; no
;; menu is built yet, so the bare name is free.) Generic: any layer, any object type.
;; Lives in opal-tools; no ogeo dependency.
;;
;; COMMAND  SS
;;   Pick one object. Every object on that object's layer is put in the active (gripped)
;;   selection set. Run any command next (ERASE, MOVE, CHPROP, layer change, PROPERTIES).
;;
;; DESIGN NOTES
;;   - Layer read from the picked entity's DXF group 8; ssget "X" filters drawing-wide.
;;   - Selection delivered with (sssetfirst nil ss); nothing is modified.
;; ============================================================

(vl-load-com)

;; ============================================================
;; SS  --  select all objects on the picked entity's layer
;; ============================================================
(defun C:SS ( / old-err pk ent lay ss)
  (setq old-err *error*)
  (defun *error* (msg)
    (setq *error* old-err)
    (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
      (prompt (strcat "\nSS error: " msg)))
    (princ))

  (setq pk (entsel "\nPick an object on the target layer: "))
  (if (null pk)
    (prompt "\nNothing picked.")
    (progn
      (setq ent (car pk)
            lay (cdr (assoc 8 (entget ent)))
            ss  (ssget "X" (list (cons 8 lay))))
      (if (null ss)
        (prompt (strcat "\nSS: nothing found on layer " lay "."))
        (progn
          (sssetfirst nil ss)
          (prompt (strcat "\nSS: selected " (itoa (sslength ss))
                          " objects on layer " lay " (grips active)."))))))

  (setq *error* old-err)
  (princ))

(prompt "\nSS v1.0 loaded. Command: SS  ->  select all objects on the picked entity's layer.")
(princ)
