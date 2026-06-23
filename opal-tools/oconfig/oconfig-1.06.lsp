;; oconfig-1.06.lsp -- Opal Energy deployment configuration
;; Client-specific layer names + module footprints + row-spacing patterns.
;; Replace this file (and config\*.csv) to redeploy the O-Suite for a different client.
;; All tool logic reads from these globals -- nothing is hardcoded elsewhere.
;; v1.06: *ocfg-module-sheet* -- the layout (sheet) whose viewport defines the "real"
;;        modules. The shared collector (_ogeo-all-modules / _ogeo-vp-windows) keeps only
;;        modules shown on that sheet (default "E-1.0"); wildcard ok; nil = any layout
;;        (old behavior). Graceful fallback if the sheet is absent. O-ZONE overrides it.
;; v1.05: *ocfg-filter-viewport* behavior flag. When T (default), the shared module
;;        collector (_ogeo-all-modules) ignores module-shaped objects that are NOT shown
;;        inside any layout viewport -- template copies parked in model space, cutsheet/
;;        detail geometry, etc. Set nil to disable (e.g. drawings with no sheets set up).
;; v1.04: load config\modules.csv and config\patterns.csv into *ocfg-modules* /
;;        *ocfg-patterns* (CSV so the user can add modules/patterns in Excel). Parser
;;        lives here because oconfig loads before any tool (incl. ogeo). The kind->offset
;;        expander + geometry helpers live in ogeo and consume these globals at runtime.
;; v1.03: module SOURCE layer "PV-MODS" (confirmed against live drawing).
;; v1.02: DC string path layer "PV-DC-PATH" -> "E-STRINGING".
;; ============================================================

;; --- PV Geometry ---
(setq *ocfg-layer-stringing*     "PV-STRINGING")       ; string boundary polylines
(setq *ocfg-layer-fill*          "PV-STRINGING-FILL")  ; string solid fill hatches
(setq *ocfg-layer-count*         "PV-STRINGING-COUNT") ; module count labels per string
(setq *ocfg-layer-dc*            "E-STRINGING")         ; DC string path lines
(setq *ocfg-layer-homerun-n*     "PV-HOMERUN-N")       ; negative DC homerun cable lines
(setq *ocfg-layer-homerun-p*     "PV-HOMERUN-P")       ; positive DC homerun cable lines
(setq *ocfg-layer-jump*          "PV-CABLE-JUMP")      ; cable jump paths
(setq *ocfg-layer-modules*       "PV-MODS")            ; module geometry (source layer)

;; --- PV Annotations ---
(setq *ocfg-layer-pv-tags*       "PV-TAGS")            ; string/terminal/jump text labels
(setq *ocfg-layer-homerun-tags*  "PV-HOMERUN-TAGS")    ; homerun and row-jump callout labels
(setq *ocfg-layer-schedules*     "PV-SCHEDULES")       ; all schedule tables
(setq *ocfg-layer-nums*          "PV-LAYOUT-NUMS")     ; row and column number labels
(setq *ocfg-layer-grid*          "PV-LAYOUT-GRID")     ; gridlines
(setq *ocfg-layer-xdata-labels*  "PV-XDATA-LABELS")   ; XDATA visualization labels
(setq *ocfg-layer-pv-notes*      "PV-NOTES")           ; PV-specific notes

;; --- Electrical ---
(setq *ocfg-layer-conduit*       "E-CONDUIT RUN")      ; AC conduit routing lines
(setq *ocfg-layer-conduit-tags*  "E-PV-CONDUIT-TAGS") ; AC feeder/conduit callout labels

;; --- General ---
(setq *ocfg-layer-anno*          "G-ANNO-TEXT")        ; general annotation fallback

;; --- Behavior ---
;; Ignore module-shaped objects not shown in any layout viewport (template copies in
;; model space, cutsheet/detail geometry). T = filter on (default); nil = keep everything.
;; Consumed by _ogeo-all-modules at runtime; safe by design -- if a drawing has no
;; viewports, or the filter would drop ALL modules, the collector keeps everything.
(setq *ocfg-filter-viewport*     T)

;; The layout (sheet) whose viewport frames the "real" modules. The shared collector
;; keeps only modules shown on this sheet (default "E-1.0"); wcmatch wildcards allowed.
;; nil = use any layout viewport (the pre-1.06 behavior). Graceful fallback: if this sheet
;; is absent or frames nothing, the collector drops to any-viewport, then all modules.
;; O-ZONE (a picked rectangle) overrides this gate entirely.
(setq *ocfg-module-sheet*        "E-1.0")

;; ====================================================================
;; Module + pattern config (CSV-driven). Self-contained reader -- oconfig
;; loads before any tool, so it cannot rely on ogeo for parsing.
;; ====================================================================

(defun _ocfg-root ()
  (if (and (boundp (quote *o-suite-root*)) *o-suite-root*)
    *o-suite-root*
    "C:\\Users\\adria\\CAD\\Automations\\opal-tools\\"))

;; split string S on a single-char separator SEP -> list of fields (keeps empties)
(defun _ocfg-split (s sep / pos out)
  (setq out nil)
  (while (setq pos (vl-string-search sep s))
    (setq out (cons (substr s 1 pos) out)
          s   (substr s (+ pos 1 (strlen sep)))))
  (reverse (cons s out)))

;; read a CSV: skip the header, return list of field-lists (blank lines skipped)
(defun _ocfg-read-csv (path / f line rows)
  (setq rows nil)
  (if (setq f (open path "r"))
    (progn
      (read-line f)                                  ; header
      (while (setq line (read-line f))
        (if (> (strlen line) 0)
          (setq rows (cons (_ocfg-split line ",") rows))))
      (close f)))
  (reverse rows))

;; "13.5|14.5" -> (13.5 14.5)   ; empty -> nil
(defun _ocfg-nums (s / out)
  (setq out nil)
  (if (and s (> (strlen s) 0))
    (foreach tok (_ocfg-split s "|") (setq out (cons (atof tok) out))))
  (reverse out))

;; field N of row R as a non-empty string, or nil
(defun _ocfg-fld (r n / v) (setq v (nth n r)) (if (and v (> (strlen v) 0)) v nil))

;; ---- modules.csv -> *ocfg-modules* : ((name short long within-gap) ...) ----
(setq *ocfg-modules* nil)
(foreach r (_ocfg-read-csv (strcat (_ocfg-root) "config\\modules.csv"))
  (if (>= (length r) 3)
    (setq *ocfg-modules*
      (cons (list (nth 0 r) (atof (nth 1 r)) (atof (nth 2 r))
                  (if (_ocfg-fld r 3) (atof (nth 3 r)) 0.25))
            *ocfg-modules*))))
(setq *ocfg-modules* (reverse *ocfg-modules*))
(if (null *ocfg-modules*)                              ; fallback if CSV missing
  (setq *ocfg-modules* (list (list "solesca-default" 44.41 89.69 0.25))))

;; ---- patterns.csv -> *ocfg-patterns* : ((name kind (gaps...) end-side) ...) ----
(setq *ocfg-patterns* nil)
(foreach r (_ocfg-read-csv (strcat (_ocfg-root) "config\\patterns.csv"))
  (if (>= (length r) 3)
    (setq *ocfg-patterns*
      (cons (list (nth 0 r) (strcase (nth 1 r) T) (_ocfg-nums (nth 2 r)) (_ocfg-fld r 3))
            *ocfg-patterns*))))
(setq *ocfg-patterns* (reverse *ocfg-patterns*))
(if (null *ocfg-patterns*)                             ; fallback if CSV missing
  (setq *ocfg-patterns*
    (list (list "uniform" "uniform" (list 14.5) nil)
          (list "north-bay" "endbay" (list 13.5 14.5) "low"))))

(prompt (strcat "\noconfig v1.06 loaded -- Opal layer config + "
                (itoa (length *ocfg-modules*)) " module(s), "
                (itoa (length *ocfg-patterns*)) " pattern(s)."))
(princ)
