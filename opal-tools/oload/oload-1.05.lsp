;; oload-1.04.lsp -- O-Suite Master Loader
;; Commands: O-LOAD (alias: OLOAD)
;; Loads oconfig first, then all tool subfolders in the suite root.
;; Set *oload-quiet* T before loading to suppress per-tool [OK] lines.
;; Tools in dormant/ are excluded from scan. Move to root to activate.
;; v1.05 -- author credit line ("by Adrian Hood, 2026") in the load banner and at
;;          the top of the O-LOAD summary (both quiet and verbose).
;; v1.04 -- root is relocatable: returns *o-suite-root* when bound (set by
;;          the plugin bootstrap), else the original hardcoded dev path.
;; ============================================================

(defun _oload-root ()
  (if (and (boundp (quote *o-suite-root*)) *o-suite-root*)
    *o-suite-root*
    "C:\\Users\\adria\\CAD\\Automations\\opal-tools\\"))

;; Folders excluded from tool scan (loaded separately, not tools, or OS entries)
(defun _oload-skip-p (d / u)
  (setq u (strcase d))
  (or (= d ".")
      (= d "..")
      (= u "OLOAD")
      (= u "OCONFIG")
      (= u "DORMANT")
      (= u "TEST")
      (= u "TOOLS")))

;; Collect all tool subfolders in root except skipped ones
(defun _oload-tools (root / dirs tools d)
  (setq dirs (vl-directory-files root nil -1))
  (setq tools (quote ()))
  (foreach d dirs
    (if (and (not (_oload-skip-p d))
             (vl-file-directory-p (strcat root d "\\")))
      (setq tools (append tools (list d)))))
  tools)

;; Char-by-char ASCII string comparison (a < b)
(defun _oload-str< (a b / i ca cb)
  (setq i 1)
  (while (and (<= i (strlen a)) (<= i (strlen b))
              (= (setq ca (ascii (substr a i 1)))
                 (setq cb (ascii (substr b i 1)))))
    (setq i (1+ i)))
  (cond
    ((> i (strlen a)) (< (strlen a) (strlen b)))
    ((> i (strlen b)) nil)
    (T (< ca cb))))

;; Insertion sort ascending
(defun _oload-sort-str (lst / sorted x inserted result r)
  (setq sorted (quote ()))
  (foreach x lst
    (setq inserted nil  result (quote ()))
    (foreach r sorted
      (if (and (not inserted) (_oload-str< x r))
        (progn (setq result (append result (list x r))  inserted T))
        (setq result (append result (list r)))))
    (setq sorted (if inserted result (append result (list x)))))
  sorted)

;; Find highest-versioned .lsp in a folder
(defun _oload-best-lsp (folder / files)
  (setq files (vl-directory-files folder "*.lsp" 1))
  (if files (car (reverse (_oload-sort-str files))) nil))

;; Extract major.minor from filename e.g. "obound-1.2.3.lsp" -> "1.2"
(defun _oload-major-minor (fname / base i c tok segs in-ver)
  (setq base (vl-filename-base fname))
  (setq i 1  tok ""  segs (quote ())  in-ver nil)
  (while (<= i (strlen base))
    (setq c (substr base i 1))
    (cond
      ((and (not in-ver) (= c "-"))
       (setq in-ver T))
      ((and in-ver (= c "."))
       (setq segs (append segs (list tok))  tok ""))
      (in-ver
       (setq tok (strcat tok c))))
    (setq i (1+ i)))
  (if (/= tok "") (setq segs (append segs (list tok))))
  (if (>= (length segs) 2)
    (strcat (nth 0 segs) "." (nth 1 segs))
    (if (= (length segs) 1) (nth 0 segs) "0.0")))

(if (not *oload-versions*) (setq *oload-versions* nil))
(if (not (boundp (quote *oload-quiet*))) (setq *oload-quiet* nil))


(defun C:O-LOAD ( / root cfg-lsp tools folder lspfile path
                    loaded skipped new-ver prev-ver is-update)
  (vl-load-com)
  (setq root (_oload-root))

  ;; Load oconfig first -- sets all *ocfg-layer-* globals
  (setq cfg-lsp (_oload-best-lsp (strcat root "oconfig\\")))
  (if cfg-lsp
    (progn
      (load (strcat root "oconfig\\" cfg-lsp))
      (if (not *oload-quiet*) (prompt (strcat "\n[cfg]  " cfg-lsp))))
    (prompt "\nO-LOAD: WARNING -- oconfig not found. Layer names may be undefined."))

  ;; Load all tool folders
  (setq tools (_oload-tools root))
  (setq loaded (quote ())  skipped (quote ()))
  (if (not *oload-quiet*) (prompt "\nLoading O-Suite tools..."))

  (foreach tool tools
    (setq lspfile (_oload-best-lsp (strcat root tool "\\")))
    (if (not lspfile)
      (progn
        (if (not *oload-quiet*)
          (prompt (strcat "\n  [skip] No .lsp: " tool)))
        (setq skipped (append skipped (list tool))))
      (progn
        (setq path (strcat root tool "\\" lspfile))
        (load path)
        (setq new-ver  (_oload-major-minor lspfile))
        (setq prev-ver (cdr (assoc tool *oload-versions*)))
        (setq is-update (and prev-ver (/= prev-ver new-ver)))
        (if (assoc tool *oload-versions*)
          (setq *oload-versions*
            (subst (cons tool new-ver) (assoc tool *oload-versions*) *oload-versions*))
          (setq *oload-versions* (cons (cons tool new-ver) *oload-versions*)))
        (if (not *oload-quiet*)
          (prompt (strcat "\n  [OK]   " lspfile
                          (if is-update "  ** UPDATE **" ""))))
        (setq loaded (append loaded (list lspfile))))))

  (if *oload-quiet*
    (prompt (strcat "\nOpal CAD Tools by Adrian Hood, 2026 -- "
                    (itoa (length loaded)) " tool(s) loaded. Type OHELP for the command list."))
    (progn
      (prompt "\n")
      (prompt "\n===  Opal CAD Tools  --  by Adrian Hood, 2026  ===")
      (prompt "\n--- O-Suite ---")
      (prompt "\nO       / OPAL      open the Opal toolbox dialog")
      (prompt "\nO-LOAD  / OLOAD     reload all tools")
      (prompt "\nO-SET   / OSET      calibrate module grid geometry")
      (prompt "\nO-DC    / ODC       draw DC string path between modules")
      (prompt "\nO-ROWSPACE / OROWSPACE  evenly space selected module rows")
      (prompt "\nOHELP   / O-HELP    full command list")
      (prompt (strcat "\n" (itoa (length loaded)) " tool(s) loaded."))))

  (if skipped
    (progn
      (setq _oload-skip-str "")
      (foreach _oload-s skipped
        (setq _oload-skip-str (strcat _oload-skip-str _oload-s " ")))
      (prompt (strcat "\nSkipped (no .lsp): " _oload-skip-str))))

  ;; Auto-run O-SET if geometry not calibrated -- ONLY on a manual (non-quiet)
  ;; load. On silent startup (bootstrap sets *oload-quiet*) we must never hijack
  ;; the session with a calibration prompt.
  (if (not *oload-quiet*)
    (if (not (null (atoms-family 1 (list "C:O-SET"))))
      (C:O-SET)
      (prompt "\nO-SET not loaded -- run manually to calibrate module geometry.")))
  (princ))

(defun C:OLOAD () (C:O-LOAD))

(prompt "\nO-LOAD v1.05 (by Adrian Hood, 2026) loaded. Type O-LOAD or OLOAD to load all O-Suite tools.")
(princ)
