;; lkload-1.6.lsp -- LayerKit Master Loader
;; Commands: LK-LOAD (alias: LKLOAD)
;; Scans every tool subfolder in the LayerKit root and loads the
;; highest-versioned .lsp in each. Ship a fix by writing the next
;; version file -- no loader edit needed.
;; Set *lkload-quiet* T before loading to suppress per-tool [OK] lines.
;; Skipped folders: lkload, config, archive, test, tools.
;; v1.6 -- root is relocatable: returns *lk-suite-root* when bound (set by
;;         the plugin bootstrap), else the original hardcoded dev path.
;; ============================================================

(defun _lkload-root ()
  (if (and (boundp (quote *lk-suite-root*)) *lk-suite-root*)
    *lk-suite-root*
    "C:\\Users\\adria\\CAD\\Automations\\layer-kit\\"))

;; Folders excluded from the tool scan (loader, data, or non-tool dirs)
(defun _lkload-skip-p (d / u)
  (setq u (strcase d))
  (or (= d ".")
      (= d "..")
      (= u "LKLOAD")
      (= u "CONFIG")
      (= u "ARCHIVE")
      (= u "TEST")
      (= u "TOOLS")))

;; Collect all tool subfolders in root except skipped ones
(defun _lkload-tools (root / dirs tools d)
  (setq dirs (vl-directory-files root nil -1))
  (setq tools (quote ()))
  (foreach d dirs
    (if (and (not (_lkload-skip-p d))
             (vl-file-directory-p (strcat root d "\\")))
      (setq tools (append tools (list d)))))
  tools)

;; Char-by-char ASCII string comparison (a < b)
(defun _lkload-str< (a b / i ca cb)
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
(defun _lkload-sort-str (lst / sorted x inserted result r)
  (setq sorted (quote ()))
  (foreach x lst
    (setq inserted nil  result (quote ()))
    (foreach r sorted
      (if (and (not inserted) (_lkload-str< x r))
        (progn (setq result (append result (list x r))  inserted T))
        (setq result (append result (list r)))))
    (setq sorted (if inserted result (append result (list x)))))
  sorted)

;; Find highest-versioned .lsp in a folder
(defun _lkload-best-lsp (folder / files)
  (setq files (vl-directory-files folder "*.lsp" 1))
  (if files (car (reverse (_lkload-sort-str files))) nil))

;; Extract major.minor from filename e.g. "pvcleanup-1.0.lsp" -> "1.0"
(defun _lkload-major-minor (fname / base i c tok segs in-ver)
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

(if (not *lkload-versions*) (setq *lkload-versions* nil))
(if (not (boundp (quote *lkload-quiet*))) (setq *lkload-quiet* nil))


(defun C:LK-LOAD ( / root tools folder lspfile path
                     loaded skipped new-ver prev-ver is-update)
  (vl-load-com)
  (setq root (_lkload-root))

  ;; Load all tool folders
  (setq tools (_lkload-tools root))
  (setq loaded (quote ())  skipped (quote ()))
  (if (not *lkload-quiet*) (prompt "\nLoading LayerKit tools..."))

  (foreach tool tools
    (setq lspfile (_lkload-best-lsp (strcat root tool "\\")))
    (if (not lspfile)
      (progn
        (if (not *lkload-quiet*)
          (prompt (strcat "\n  [skip] No .lsp: " tool)))
        (setq skipped (append skipped (list tool))))
      (progn
        (setq path (strcat root tool "\\" lspfile))
        (load path)
        (setq new-ver  (_lkload-major-minor lspfile))
        (setq prev-ver (cdr (assoc tool *lkload-versions*)))
        (setq is-update (and prev-ver (/= prev-ver new-ver)))
        (if (assoc tool *lkload-versions*)
          (setq *lkload-versions*
            (subst (cons tool new-ver) (assoc tool *lkload-versions*) *lkload-versions*))
          (setq *lkload-versions* (cons (cons tool new-ver) *lkload-versions*)))
        (if (not *lkload-quiet*)
          (prompt (strcat "\n  [OK]   " lspfile
                          (if is-update "  ** UPDATE **" ""))))
        (setq loaded (append loaded (list lspfile))))))

  (if *lkload-quiet*
    (prompt (strcat "\nLayerKit loaded -- " (itoa (length loaded)) " tool(s)."))
    (progn
      (prompt "\n")
      (prompt "\n--- LayerKit ---")
      (prompt "\nLK-LOAD / LKLOAD   reload all tools")
      (prompt "\nLK-APPLY           do it all: cleanup + standards + filters")
      (prompt "\nLK-CLEANUP         classify + merge/purge layers (Full or Preview)")
      (prompt "\nLK-BYLAYER         force all colors ByLayer (everywhere)")
      (prompt "\nLK-SKIP            manage ByLayer exclusions [Add/Layer/List/Clear]")
      (prompt "\nLK-STD             layer standards [Save/Set/Config]")
      (prompt "\nLK-FILTER          layer group filters [Set/Save]")
      (prompt (strcat "\n" (itoa (length loaded)) " tool(s) loaded."))))

  (if skipped
    (progn
      (setq _lkload-skip-str "")
      (foreach _lkload-s skipped
        (setq _lkload-skip-str (strcat _lkload-skip-str _lkload-s " ")))
      (prompt (strcat "\nSkipped (no .lsp): " _lkload-skip-str))))
  (princ))

(defun C:LKLOAD () (C:LK-LOAD))

(prompt "\nLK-LOAD v1.6 loaded. Type LK-LOAD or LKLOAD to load all LayerKit tools.")
(princ)
