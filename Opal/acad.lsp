;; acad.lsp -- O-Suite auto-loader
;; Drop this file in your AutoCAD support path (Tools > Options > Files > Support File Search Path)
;; OR use APPLOAD Startup Suite to load oload-1.02.lsp directly.
;; This file silently loads the O-Suite on every AutoCAD session.

(setq *oload-quiet* T)
(load "C:\\Users\\adria\\CAD\\Automations\\Opal\\oload\\oload-1.02.lsp")
(C:O-LOAD)
(setq *oload-quiet* nil)
