;; ohelp-1.08.lsp -- Opal CAD Tools command reference (text)
;; Commands: OHELP (alias: O-HELP)
;; Prints a grouped, plain-language list of the loaded commands. Plain-text
;; fallback for the O launcher dialog; works in headless/script sessions too.
;; v1.08 -- add LK-ZEROBLOCK (Layers) -- push nested block geometry to layer 0; and
;;          O-ZONE (Setup) -- limit module tools to a picked area (E-1.0 sheet fallback).
;; v1.07 -- new "Select" group: SSA (SELECT ARRAYS) -- select every real module and report
;;          the total + per-array breakdown. SSA is the unified select/query tool (folds in
;;          the old QQA / SSM / SSA / "QQM").
;; v1.06 -- add O-PVSPACE (Draw) -- batch-space every array in a layout.
;; v1.05 -- O-ROWSPACE renamed to O-MODSPACE (spaces rows AND columns).
;; v1.04 -- add O-GRID (Draw) -- snap an array to an ideal grid.
;; v1.03 -- add O-MODSIZE (Draw) -- normalize module sizes.
;; v1.02 -- author credit line (Adrian Hood, 2026) at the top of the help.
;; ============================================================

(setq *ohelp-cmds*
  (list
    ;; group     command        description
    (list "Draw"   "O-MODSPACE" "Space one array's rows and columns")
    (list "Draw"   "O-PVSPACE"  "Space rows and columns of every array")
    (list "Draw"   "O-MODSIZE"  "Normalize all module sizes to one footprint")
    (list "Draw"   "O-GRID"     "Snap a module array to an ideal grid")
    (list "Select" "SSA"        "Select every module + per-array breakdown")
    (list "Layers" "LK-APPLY"   "Clean up + standardize layers (all in one)")
    (list "Layers" "LK-STD"     "Layer standards - Save / Set / Config")
    (list "Layers" "LK-FILTER"  "Layer group filters - Set / Save")
    (list "Layers" "LK-ZEROBLOCK" "Push nested block geometry to layer 0")
    (list "Setup"  "O"          "Open the Opal toolbox dialog")
    (list "Setup"  "O-SET"      "Calibrate the module grid")
    (list "Setup"  "O-ZONE"     "Limit module tools to a picked area")
    (list "Setup"  "O-LOAD"     "Reload all tools")
    (list "Setup"  "OHELP"      "Show this list")))

(defun _ohelp-loaded-p (cmd / n)
  (setq n (strcat "C:" (strcase cmd)))
  (and (member n (atoms-family 1 (list n))) T))

(defun _ohelp-pad (s n / r)
  (setq r s)
  (while (< (strlen r) n) (setq r (strcat r " ")))
  r)

(defun C:OHELP ( / groups g rec shown)
  (setq groups (list "Draw" "Select" "Layers" "Setup"))
  (prompt "\n==================================================")
  (prompt "\n  OPAL CAD TOOLS - type any command name")
  (prompt "\n")
  (prompt "\n  --  by Adrian Hood, 2026  --")
  (prompt "\n==================================================")
  (foreach g groups
    (setq shown nil)
    (foreach rec *ohelp-cmds*
      (if (and (= (car rec) g) (_ohelp-loaded-p (cadr rec)))
        (progn
          (if (not shown)
            (progn (prompt (strcat "\n " g ":")) (setq shown T)))
          (prompt (strcat "\n   " (_ohelp-pad (cadr rec) 12) (caddr rec)))))))
  (prompt "\n--------------------------------------------------")
  (prompt "\n Tip: type O for the clickable toolbox.")
  (princ))

(defun C:O-HELP () (C:OHELP))

(prompt "\nOHELP v1.08 loaded. Type OHELP for the command list.")
(princ)
