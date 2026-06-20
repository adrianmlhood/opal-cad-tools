;; bootstrap.lsp -- Opal CAD Tools auto-loader (AutoCAD ApplicationPlugins)
;; Loaded automatically on AutoCAD startup via PackageContents.xml.
;; Self-locates the bundle under %APPDATA% (the deterministic install path),
;; sets the suite roots, then loads O-Suite and LayerKit quietly. No path is
;; baked in at install time -- the same file works on every machine.
;; ============================================================

(vl-load-com)

;; --- locate the bundle's Contents folder ---
(setq *opal-bundle*
  (strcat (getenv "APPDATA")
          "\\Autodesk\\ApplicationPlugins\\OpalTools.bundle\\Contents\\"))

;; Fallback: if that path is not present, derive it from this file's location.
(if (not (vl-file-directory-p *opal-bundle*))
  (if (findfile "bootstrap.lsp")
    (setq *opal-bundle*
      (strcat (vl-filename-directory (findfile "bootstrap.lsp")) "\\"))))

(setq *o-suite-root*  (strcat *opal-bundle* "opal-tools\\"))
(setq *lk-suite-root* (strcat *opal-bundle* "layer-kit\\"))

;; --- helper: ASCII string compare (a < b) ---
(defun _opal-str< (a b / i ca cb)
  (setq i 1)
  (while (and (<= i (strlen a)) (<= i (strlen b))
              (= (setq ca (ascii (substr a i 1)))
                 (setq cb (ascii (substr b i 1)))))
    (setq i (1+ i)))
  (cond ((> i (strlen a)) (< (strlen a) (strlen b)))
        ((> i (strlen b)) nil)
        (T (< ca cb))))

;; --- helper: load the highest-versioned .lsp in a folder ---
(defun _opal-latest (folder / files best f)
  (setq files (vl-directory-files folder "*.lsp" 1) best nil)
  (foreach f files
    (if (or (not best) (_opal-str< best f)) (setq best f)))
  (if best (load (strcat folder best)) nil))

;; --- load both suites quietly (quiet suppresses banners and the O-SET prompt) ---
(setq *oload-quiet* T *lkload-quiet* T)

(_opal-latest (strcat *o-suite-root*  "oload\\"))
(_opal-latest (strcat *lk-suite-root* "lkload\\"))

(if (not (null (atoms-family 1 (list "C:O-LOAD"))))  (C:O-LOAD))
(if (not (null (atoms-family 1 (list "C:LK-LOAD")))) (C:LK-LOAD))

(setq *oload-quiet* nil *lkload-quiet* nil)

(princ "\nOpal CAD Tools loaded. Type O for the toolbox, or OHELP for the command list.")
(princ)
