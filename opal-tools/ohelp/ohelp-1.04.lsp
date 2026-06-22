;; ohelp-1.04.lsp -- Opal CAD Tools command reference (text)
;; Commands: OHELP (alias: O-HELP)
;; Prints a grouped, plain-language list of the loaded commands. Plain-text
;; fallback for the O launcher dialog; works in headless/script sessions too.
;; v1.04 -- add O-GRID (Draw) -- snap an array to an ideal grid.
;; v1.03 -- add O-MODSIZE (Draw) -- normalize module sizes.
;; v1.02 -- author credit line (Adrian Hood, 2026) at the top of the help.
;; ============================================================

(setq *ohelp-cmds*
  (list
    ;; group     command        description
    (list "Draw"   "O-ROWSPACE" "Evenly space the selected module rows")
    (list "Draw"   "O-MODSIZE"  "Normalize all module sizes to one footprint")
    (list "Draw"   "O-GRID"     "Snap a module array to an ideal grid")
    (list "Layers" "LK-APPLY"   "Clean up + standardize layers (all in one)")
    (list "Layers" "LK-STD"     "Layer standards - Save / Set / Config")
    (list "Layers" "LK-FILTER"  "Layer group filters - Set / Save")
    (list "Setup"  "O"          "Open the Opal toolbox dialog")
    (list "Setup"  "O-SET"      "Calibrate the module grid")
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
  (setq groups (list "Draw" "Layers" "Setup"))
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

(prompt "\nOHELP v1.04 loaded. Type OHELP for the command list.")
(princ)
