;; layerkit-load.lsp -- LayerKit auto-loader
;;
;; NOT named acad.lsp on purpose: AutoCAD auto-loads only the FIRST acad.lsp on the
;; Support File Search Path, which would collide with other suites (e.g. Opal\acad.lsp).
;;
;; To load LayerKit every session, do ONE of:
;;   - APPLOAD -> Startup Suite -> add this file, OR
;;   - add this line to your single real acad.lsp / acaddoc.lsp:
;;       (load "C:\\Users\\adria\\CAD\\Automations\\LayerKit\\layerkit-load.lsp")
;;
;; This file silently loads the whole LayerKit suite (quiet mode).

(setq *lkload-quiet* T)
(load "C:\\Users\\adria\\CAD\\Automations\\LayerKit\\lkload\\lkload-1.5.lsp")
(C:LK-LOAD)
(setq *lkload-quiet* nil)
