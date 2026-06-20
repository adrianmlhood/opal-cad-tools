;; oconfig-1.03.lsp -- Opal Energy deployment configuration
;; Client-specific layer name constants ONLY.
;; Replace this file to redeploy the O-Suite for a different client.
;; All tool logic reads from these globals -- no layer strings are
;; hardcoded anywhere else in the suite.
;; v1.01: module SOURCE layer corrected to "MODULES" (was "PV-MODULES LAYOUT")
;; v1.02: DC string path layer repointed "PV-DC-PATH" -> "E-STRINGING"
;; v1.03: module SOURCE layer corrected to "PV-MODS" (confirmed against live
;;        drawing; "MODULES" matched nothing).
;; ============================================================

;; --- PV Geometry ---
(setq *ocfg-layer-stringing*     "PV-STRINGING")       ; string boundary polylines
(setq *ocfg-layer-fill*          "PV-STRINGING-FILL")  ; string solid fill hatches
(setq *ocfg-layer-count*         "PV-STRINGING-COUNT") ; module count labels per string
(setq *ocfg-layer-dc*            "E-STRINGING")         ; DC string path lines (was "PV-DC-PATH")
(setq *ocfg-layer-homerun-n*     "PV-HOMERUN-N")       ; negative DC homerun cable lines
(setq *ocfg-layer-homerun-p*     "PV-HOMERUN-P")       ; positive DC homerun cable lines
(setq *ocfg-layer-jump*          "PV-CABLE-JUMP")      ; cable jump paths
(setq *ocfg-layer-modules*       "PV-MODS")            ; module geometry (source layer)

;; --- PV Annotations ---
(setq *ocfg-layer-pv-tags*       "PV-TAGS")            ; string/terminal/jump text labels
(setq *ocfg-layer-homerun-tags*  "PV-HOMERUN-TAGS")    ; homerun and row-jump callout labels
(setq *ocfg-layer-schedules*     "PV-SCHEDULES")       ; all schedule tables (string/HR/conduit/BOM)
(setq *ocfg-layer-nums*          "PV-LAYOUT-NUMS")     ; row and column number labels
(setq *ocfg-layer-grid*          "PV-LAYOUT-GRID")     ; gridlines
(setq *ocfg-layer-xdata-labels*  "PV-XDATA-LABELS")   ; XDATA visualization labels (O-XVIEW)
(setq *ocfg-layer-pv-notes*      "PV-NOTES")           ; PV-specific notes (BOM notes section)

;; --- Electrical ---
(setq *ocfg-layer-conduit*       "E-CONDUIT RUN")      ; AC conduit routing lines
(setq *ocfg-layer-conduit-tags*  "E-PV-CONDUIT-TAGS") ; AC feeder/conduit callout labels

;; --- General ---
(setq *ocfg-layer-anno*          "G-ANNO-TEXT")        ; general annotation fallback

(prompt "\noconfig v1.03 loaded -- Opal Energy layer config active.")
(princ)
