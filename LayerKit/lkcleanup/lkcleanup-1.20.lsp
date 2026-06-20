;;; ============================================================
;;; LK-CLEANUP.lsp — Layer Cleanup Tool for PV Design
;;; ============================================================
;;; 
;;; SETUP:
;;;   1. Place PV_static_mappings.csv and PV_keywords.csv
;;;      in the same folder as your DWG (or set *lk-config-dir*)
;;;   2. APPLOAD this file in AutoCAD
;;;   3. Type LK-CLEANUP at the command line
;;;
;;; CLASSIFICATION ORDER:
;;;   1. Static  — exact match from PV_static_mappings.csv
;;;   2. PDF     — layers matching PDF#_* pattern → grouped
;;;   3. Keyword — tokens matched against PV_keywords.csv
;;;   4. Unmatched — reported for manual / LLM assignment
;;;
;;; ASSIGNMENT TYPES:
;;;   Hard = permanent, written to static CSV for future use
;;;   Soft = this session only, not saved
;;;
;;; ============================================================

;;; --- Global config ---
;;; The CSV directory is REMEMBERED across sessions in the Windows registry and
;;; restored automatically on load. LK-CONFIG sets and persists it.
;;; If nothing is saved, the tool falls back to the drawing's folder (DWGPREFIX).
(vl-load-com)

(defun lk:reg-key ( ) "HKEY_CURRENT_USER\\Software\\Ocotillo\\LayerKit")

(defun lk:get-saved-dir ( / v)
  ;; Return the persisted CSV directory string, or nil if none/invalid
  (setq v (vl-registry-read (lk:reg-key) "ConfigDir"))
  (if (and v (= (type v) 'STR) (> (strlen v) 0)) v nil)
)

(defun lk:save-dir (dir / )
  ;; Persist the CSV directory across sessions
  (vl-registry-write (lk:reg-key) "ConfigDir" dir)
)

;;; Restore the remembered directory on load (keep any value already set this session)
(if (not *lk-config-dir*)
  (setq *lk-config-dir* (lk:get-saved-dir))
)

;;; ============================================================
;;; UTILITY FUNCTIONS
;;; ============================================================

(defun lk:get-config-dir ( / )
  (if *lk-config-dir*
    *lk-config-dir*
    (getvar "DWGPREFIX")
  )
)

(defun lk:str-trim (str)
  (if (and str (= (type str) 'STR))
    (vl-string-trim " \t\r\n" str)
    ""
  )
)

(defun lk:str-split (str delim / pos result)
  ;; Split string by single-character delimiter string
  (setq result '())
  (while (setq pos (vl-string-search delim str))
    (setq result (append result (list (substr str 1 pos))))
    (setq str (substr str (+ pos 2)))
  )
  (append result (list str))
)

(defun lk:tokenize (layer-name / str tokens)
  ;; Split layer name into lowercase tokens on - _ ( ) space
  (setq str (strcase layer-name T)) ; lowercase
  (setq str (vl-string-translate "-_()" "    " str))
  (setq tokens (lk:str-split str " "))
  ;; Remove empty strings and very short tokens (single chars)
  (vl-remove-if
    '(lambda (x) (<= (strlen (lk:str-trim x)) 0))
    (mapcar 'lk:str-trim tokens)
  )
)

(defun lk:today-str ( / d)
  (setq d (rtos (getvar "CDATE") 2 0))
  (strcat (substr d 1 4) "-" (substr d 5 2) "-" (substr d 7 2))
)

;;; ============================================================
;;; CSV READING / WRITING
;;; ============================================================

(defun lk:read-csv (filepath / f line result row)
  ;; Read CSV, skip header, return list of row-lists
  (setq result '())
  (if (findfile filepath)
    (progn
      (setq f (open filepath "r"))
      (if f
        (progn
          (read-line f) ; skip header
          (while (setq line (read-line f))
            (setq line (lk:str-trim line))
            (if (> (strlen line) 0)
              (progn
                (setq row (mapcar 'lk:str-trim (lk:str-split line ",")))
                (setq result (append result (list row)))
              )
            )
          )
          (close f)
        )
      )
    )
    (princ (strcat "\n  ** File not found: " filepath))
  )
  result
)

(defun lk:csv-append (filepath row / f line)
  ;; Append one row to a CSV file
  (setq f (open filepath "a"))
  (if f
    (progn
      (setq line (car row))
      (foreach item (cdr row)
        (setq line (strcat line "," item))
      )
      (write-line line f)
      (close f)
    )
    (princ (strcat "\n  ** Cannot write to: " filepath))
  )
)

;;; ============================================================
;;; STATIC MAPPING (Level 1)
;;; ============================================================

(defun lk:load-static-map (filepath / data result)
  ;; Returns assoc list: (("SOURCE_UPPER" . "Target") ...)
  (setq data (lk:read-csv filepath))
  (setq result '())
  (foreach row data
    (if (>= (length row) 2)
      (setq result
        (cons
          (cons (strcase (car row)) (cadr row))
          result
        )
      )
    )
  )
  (reverse result)
)

(defun lk:static-lookup (name smap / )
  ;; Case-insensitive exact match
  (cdr (assoc (strcase name) smap))
)

;;; ============================================================
;;; PDF DETECTION (Level 2)
;;; ============================================================

(defun lk:is-pdf-layer (name / )
  ;; Match PDF#_* or PDF_* patterns
  (wcmatch (strcase name) "PDF*_*")
)

(defun lk:get-pdf-group (name / pos)
  ;; Extract group prefix: "PDF2" from "PDF2_Geometry"
  (setq pos (vl-string-search "_" name))
  (if pos
    (substr name 1 pos)
    "PDF"
  )
)

;;; ============================================================
;;; KEYWORD MATCHING (Level 3)
;;; ============================================================

(defun lk:load-keywords (filepath / data result)
  ;; Returns list: (("keyword" "TARGET") ...)
  (setq data (lk:read-csv filepath))
  (setq result '())
  (foreach row data
    (if (>= (length row) 2)
      (setq result
        (cons (list (strcase (car row) T) (cadr row)) result)
      )
    )
  )
  (reverse result)
)

(defun lk:keyword-match (layer-name kw-list / tokens match)
  ;; Try to match tokens against keyword dictionary
  ;; Returns (target-layer matched-keyword) or nil
  (setq tokens (lk:tokenize layer-name))
  (setq match nil)
  ;; Check single-word tokens first
  (foreach token tokens
    (if (not match)
      (foreach kw-pair kw-list
        (if (and (not match)
                 (= (strcase token T) (car kw-pair)))
          (setq match (list (cadr kw-pair) (car kw-pair)))
        )
      )
    )
  )
  ;; Check multi-word keywords (substring in full name)
  (if (not match)
    (foreach kw-pair kw-list
      (if (and (not match)
               (vl-string-search " " (car kw-pair))
               (vl-string-search (car kw-pair) (strcase layer-name T)))
        (setq match (list (cadr kw-pair) (car kw-pair)))
      )
    )
  )
  match
)

;;; ============================================================
;;; LAYER OPERATIONS
;;; ============================================================

(defun lk:get-all-layers ( / layer-data result)
  ;; Get list of all layer names
  (setq result '())
  (setq layer-data (tblnext "LAYER" T))
  (while layer-data
    (setq result (cons (cdr (assoc 2 layer-data)) result))
    (setq layer-data (tblnext "LAYER"))
  )
  (reverse result)
)

(defun lk:count-on-layer (name / ss)
  ;; Count entities on a layer
  (setq ss (ssget "X" (list (cons 8 name))))
  (if ss (sslength ss) 0)
)

;;; --- Remap entities inside block definitions (SINGLE PASS, batched) ---
;; *lk-blkmap* accumulates ((UPPER-OLD . NEW) ...) during do-rename; lk:remap-blocks-run
;; then walks every real block definition ONCE and remaps all queued layers together.
;; This replaces the old per-layer walk (a full COM scan of all blocks PER renamed layer
;; = O(layers x block-entities) — what made a cleanup take minutes).
;; ssget "X" already covers model/paper space, so we SKIP layout & xref blocks and only
;; touch reusable block definitions, where the hidden layer refs that block PURGE live.
(defun lk:blk-add (old new)
  (setq *lk-blkmap* (cons (cons (strcase old) new) *lk-blkmap*)))

(defun lk:remap-blocks-run ( / blocks cnt hit)
  (setq cnt 0)
  (if *lk-blkmap*
    (progn
      ;; Guard the COM acquisition so a missing acad-object can never abort cleanup
      (setq blocks (vl-catch-all-apply
        (function (lambda ()
          (vla-get-blocks (vla-get-activedocument (vlax-get-acad-object)))))))
      (if (vl-catch-all-error-p blocks) (setq blocks nil))
      (if blocks
        (vlax-for blk blocks
          (if (and (= (vla-get-IsLayout blk) :vlax-false)
                   (= (vla-get-IsXRef blk) :vlax-false))
            (vlax-for ent blk
              (if (vlax-property-available-p ent 'Layer)
                (progn
                  (setq hit (assoc (strcase (vla-get-layer ent)) *lk-blkmap*))
                  (if hit
                    (progn
                      (vl-catch-all-apply 'vla-put-layer (list ent (cdr hit)))
                      (setq cnt (1+ cnt))
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
  cnt
)

;;; --- Make a layer modifiable so its entities can be moved/deleted (then purged) ---
;; A LOCKED or FROZEN source layer makes entmod/entdel silently FAIL -- the entities
;; never leave, so the layer stays referenced and PURGE can't remove it. This was the
;; "N moved but nothing purged" bug: the count is sslength (selected), not actual moves.
;; We thaw (70-bit 1), unlock (70-bit 4), and turn on (62 positive) the layer first.
;; (Only ever CLEARS the freeze bit -- thawing the current layer is legal; freezing it
;; is not, and we never do that.)
(defun lk:prep-layer (name / en ed f70 c62)
  (if (setq en (tblobjname "LAYER" name))
    (progn
      (setq ed (entget en)  f70 (cdr (assoc 70 ed)))
      (if (= 1 (logand f70 1)) (setq f70 (- f70 1)))   ; thaw
      (if (= 4 (logand f70 4)) (setq f70 (- f70 4)))   ; unlock
      (setq ed (subst (cons 70 f70) (assoc 70 ed) ed))
      (setq c62 (cdr (assoc 62 ed)))
      (if (and c62 (< c62 0))                          ; turn on
        (setq ed (subst (cons 62 (abs c62)) (assoc 62 ed) ed)))
      (vl-catch-all-apply 'entmod (list ed))
    )
  )
)

(defun lk:do-rename (old-name new-name / ss i ent ed cnt)
  ;; Rename / merge / delete a layer. Block-internal entities are NOT walked here -- the
  ;; (old -> new) pair is QUEUED via lk:blk-add and remapped in ONE pass afterwards
  ;; (lk:remap-blocks-run). Model/paper-space entities are handled inline via ssget "X".
  (cond
    ;; Same name, skip
    ((= (strcase old-name) (strcase new-name))
     (princ (strcat "\n  [=] " old-name " (already correct)"))
    )
    ;; Target is "Purge": delete model/paper entities, queue block remap to "0"
    ((= (strcase new-name) "PURGE")
     (if (= (strcase (getvar "CLAYER")) (strcase old-name))
       (setvar "CLAYER" "0")
     )
     (lk:prep-layer old-name)
     (setq ss (ssget "X" (list (cons 8 old-name))))
     (if ss
       (progn (setq cnt (sslength ss)) (command "._ERASE" ss ""))
       (setq cnt 0)
     )
     (lk:blk-add old-name "0")
     (princ (strcat "\n  [DELETE] " old-name " (" (itoa cnt) " erased)"))
    )
    ;; Target doesn't exist yet: simple rename. Renaming the layer record makes ALL
    ;; references (including block-internal) follow automatically -- no walk needed.
    ((not (tblsearch "LAYER" new-name))
     (command "._-RENAME" "_LA" old-name new-name)
     (princ (strcat "\n  [RENAME] " old-name " -> " new-name))
    )
    ;; Target exists: move model/paper entities, queue block remap, leave old for purge
    (T
     (if (= (strcase (getvar "CLAYER")) (strcase old-name))
       (setvar "CLAYER" new-name)
     )
     (lk:prep-layer old-name)
     (setq ss (ssget "X" (list (cons 8 old-name))))
     (if ss
       (progn (setq cnt (sslength ss)) (command "._CHPROP" ss "" "_LA" new-name ""))
       (setq cnt 0)
     )
     (lk:blk-add old-name new-name)
     (princ (strcat "\n  [MERGE] " old-name " -> " new-name " (" (itoa cnt) " moved)"))
    )
  )
)

;;; --- Auto-purge empty layers ---
(defun lk:purge-empty-layers ( / )
  ;; Purge blocks FIRST (releases layer refs from unused block defs), then layers, then
  ;; everything else. Two passes each covers the usual nesting -- far lighter than the
  ;; old 13-pass version.
  (princ "\n\n  Purging...")
  (repeat 2 (command "._-PURGE" "_BL" "*" "_N"))
  (repeat 2 (command "._-PURGE" "_LA" "*" "_N"))
  (command "._-PURGE" "_ALL" "*" "_N")
  (princ " done.")
)

;;; ============================================================
;;; MAIN COMMAND
;;; ============================================================

(defun C:LK-CLEANUP ( / config-dir static-csv keyword-csv log-csv
                        static-map kw-list
                        all-layers layer-name target
                        kw-result choice
                        static-assigns hard-assigns soft-assigns
                        pdf-groups unmatched
                        old-error exec-choice)

  ;; Custom error handler for clean abort
  (setq old-error *error*)
  (defun *error* (msg)
    (if (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*"))
      (princ (strcat "\nError: " msg))
    )
    (setvar "CMDECHO" 1)
    (princ "\nLK-CLEANUP aborted.")
    (setq *error* old-error)
    (princ)
  )

  ;; ---- 1. CONFIG ----
  (setq config-dir (lk:get-config-dir))
  (setq static-csv (strcat config-dir "PV_static_mappings.csv"))
  (setq keyword-csv (strcat config-dir "PV_keywords.csv"))
  (setq log-csv (strcat config-dir "PV_mapping_log.csv"))

  (princ "\n====================================")
  (princ "\n  LK-CLEANUP — Layer Cleanup Tool")
  (princ "\n====================================")
  (princ (strcat "\n  Config: " config-dir))

  ;; ---- 2. LOAD CONFIGS ----
  (princ "\n\n  Loading static mappings...")
  (setq static-map (lk:load-static-map static-csv))
  (princ (strcat " " (itoa (length static-map)) " entries"))

  (princ "\n  Loading keywords...")
  (setq kw-list (lk:load-keywords keyword-csv))
  (princ (strcat " " (itoa (length kw-list)) " entries"))

  ;; ---- 3. SCAN LAYERS ----
  (setq all-layers (lk:get-all-layers))
  (princ (strcat "\n\n  Scanning " (itoa (length all-layers)) " layers...\n"))

  ;; ---- 4. CLASSIFY ----
  (setq static-assigns '())
  (setq hard-assigns '())
  (setq soft-assigns '())
  (setq pdf-groups '())
  (setq unmatched '())

  (foreach layer-name all-layers
    (cond

      ;; --- System layers: skip ---
      ((member (strcase layer-name) '("0" "DEFPOINTS"))
       (princ (strcat "\n  [SYSTEM]  " layer-name))
      )

      ;; --- Level 1: Static mapping ---
      ((setq target (lk:static-lookup layer-name static-map))
       (if (= (strcase layer-name) (strcase target))
         ;; Already matches its target name
         (princ (strcat "\n  [OK]      " layer-name))
         ;; Needs rename
         (progn
           (princ (strcat "\n  [STATIC]  " layer-name
                    " -> " target))
           (setq static-assigns
             (cons (list layer-name target) static-assigns))
         )
       )
      )

      ;; --- Level 2: PDF pattern ---
      ((lk:is-pdf-layer layer-name)
       (princ (strcat "\n  [PDF]     " layer-name
                " (group: " (lk:get-pdf-group layer-name) ")"))
       (setq pdf-groups
         (cons (list layer-name (lk:get-pdf-group layer-name))
               pdf-groups))
      )

      ;; --- Level 3: Keyword match ---
      ((setq kw-result (lk:keyword-match layer-name kw-list))
       (princ (strcat "\n  [KEYWORD] " layer-name
                " -> suggests " (car kw-result)
                "  (matched: \"" (cadr kw-result) "\")"))

       ;; Prompt for assignment type
       (initget "Hard Soft Other Skip")
       (setq choice
         (getkword
           (strcat "\n            Accept " (car kw-result)
             "? [Hard/Soft/Other/Skip] <Skip>: ")
         )
       )

       (cond
         ;; HARD: apply + save to static CSV
         ((= choice "Hard")
          (setq hard-assigns
            (cons (list layer-name (car kw-result)) hard-assigns))
          (lk:csv-append static-csv
            (list layer-name (car kw-result) (lk:today-str)))
          (princ (strcat "\n            -> HARD: "
                   (car kw-result) " (saved to CSV)"))
         )

         ;; SOFT: apply this session only
         ((= choice "Soft")
          (setq soft-assigns
            (cons (list layer-name (car kw-result)) soft-assigns))
          (princ (strcat "\n            -> SOFT: "
                   (car kw-result) " (session only)"))
         )

         ;; OTHER: user types custom target
         ((= choice "Other")
          (setq target
            (getstring T "\n            Enter target layer: "))
          (if (and target (> (strlen target) 0))
            (progn
              (initget "Hard Soft")
              (setq choice
                (getkword
                  "\n            Save as [Hard/Soft] <Soft>: "))
              (if (= choice "Hard")
                (progn
                  (setq hard-assigns
                    (cons (list layer-name target) hard-assigns))
                  (lk:csv-append static-csv
                    (list layer-name target (lk:today-str)))
                  (princ (strcat "\n            -> HARD: "
                           target " (saved to CSV)"))
                )
                (progn
                  (setq soft-assigns
                    (cons (list layer-name target) soft-assigns))
                  (princ (strcat "\n            -> SOFT: " target))
                )
              )
            )
            (progn
              (setq unmatched (cons layer-name unmatched))
              (princ "\n            -> SKIPPED")
            )
          )
         )

         ;; SKIP (default)
         (T
          (setq unmatched (cons layer-name unmatched))
          (princ "\n            -> SKIPPED")
         )
       )
      )

      ;; --- Level 4: Unmatched ---
      (T
       (princ (strcat "\n  [???]     " layer-name
                "  (" (itoa (lk:count-on-layer layer-name))
                " entities)"))
       (setq unmatched (cons layer-name unmatched))
      )
    )
  ) ; end foreach

  ;; ---- 5. SUMMARY ----
  (princ "\n\n====================================")
  (princ "\n  SUMMARY")
  (princ "\n====================================")
  (princ (strcat "\n  Static assignments:  "
           (itoa (length static-assigns))))
  (princ (strcat "\n  Hard assignments:    "
           (itoa (length hard-assigns))))
  (princ (strcat "\n  Soft assignments:    "
           (itoa (length soft-assigns))))
  (princ (strcat "\n  PDF groups:          "
           (itoa (length pdf-groups))))
  (princ (strcat "\n  Unmatched/skipped:   "
           (itoa (length unmatched))))

  (setq total-assigns
    (+ (length static-assigns)
       (length hard-assigns)
       (length soft-assigns)))

  (if (> total-assigns 0)
    (progn
      ;; ---- 6. EXECUTE ----
      (princ (strcat "\n\n  " (itoa total-assigns)
               " layers ready to rename/merge."))
      (initget "Yes No")
      (setq exec-choice
        (getkword "\n  Execute now? [Yes/No] <No>: "))

      (if (= exec-choice "Yes")
        (progn
          (princ "\n\n  Executing renames...")
          (setq *lk-cmdecho* (getvar "CMDECHO"))
          (setvar "CMDECHO" 0)
          (setq *lk-blkmap* nil)

          ;; Static assignments
          (foreach a (reverse static-assigns)
            (lk:do-rename (car a) (cadr a))
          )
          ;; Hard assignments
          (foreach a (reverse hard-assigns)
            (lk:do-rename (car a) (cadr a))
          )
          ;; Soft assignments
          (foreach a (reverse soft-assigns)
            (lk:do-rename (car a) (cadr a))
          )

          ;; ONE block-definition pass for every queued merge/purge (was per-layer)
          (princ (strcat "\n\n  Remapping block-internal layers... "
                   (itoa (lk:remap-blocks-run)) " refs."))

          ;; Log all actions
          (if (not (findfile log-csv))
            (progn
              (setq f (open log-csv "w"))
              (write-line "timestamp,source_layer,target_layer,method" f)
              (close f)
            )
          )
          (foreach a (reverse static-assigns)
            (lk:csv-append log-csv
              (list (lk:today-str) (car a) (cadr a) "static"))
          )
          (foreach a (reverse hard-assigns)
            (lk:csv-append log-csv
              (list (lk:today-str) (car a) (cadr a) "hard"))
          )
          (foreach a (reverse soft-assigns)
            (lk:csv-append log-csv
              (list (lk:today-str) (car a) (cadr a) "soft"))
          )

          ;; Auto-purge empty layers and unused objects
          (lk:purge-empty-layers)
          (setvar "CMDECHO" *lk-cmdecho*)

          ;; Honest verification: which source layers did NOT get removed, and why?
          (setq *lk-stuck* nil)
          (foreach a (append static-assigns hard-assigns soft-assigns)
            (if (and (/= (strcase (car a)) (strcase (cadr a)))
                     (tblsearch "LAYER" (car a)))
              (progn
                (setq _s (ssget "X" (list (cons 8 (car a)))))
                (setq *lk-stuck*
                  (cons (list (car a) (if _s (sslength _s) 0)) *lk-stuck*)))))
          (if *lk-stuck*
            (progn
              (princ "\n\n  ** STILL PRESENT (could not remove): **")
              (foreach s *lk-stuck*
                (princ (strcat "\n    " (car s) " -- "
                  (if (> (cadr s) 0)
                    (strcat (itoa (cadr s)) " object(s) remain on it")
                    "empty but won't purge (VP-freeze / layer state / underlay ref)"))))
              (princ (strcat "\n  " (itoa (length *lk-stuck*)) " layer(s) need manual attention.")))
            (princ "\n\n  All matched source layers were removed."))

          (princ "\n\n  Done.")
          (princ "\n  Log written to PV_mapping_log.csv")
        )
        (princ "\n\n  Aborted. No changes made.")
      )
    )
    (princ "\n\n  Nothing to rename.")
  )

  ;; Report unmatched for LLM assignment
  (if (> (length unmatched) 0)
    (progn
      (princ "\n\n  UNMATCHED LAYERS (paste into Claude):")
      (princ "\n  ------------------------------------")
      (foreach u (reverse unmatched)
        (princ (strcat "\n    " u
                 "  (" (itoa (lk:count-on-layer u)) " entities)"))
      )
    )
  )

  ;; Report PDF groups
  (if (> (length pdf-groups) 0)
    (progn
      (princ "\n\n  PDF GROUPS (contained references):")
      (princ "\n  ------------------------------------")
      (foreach pg (reverse pdf-groups)
        (princ (strcat "\n    " (cadr pg) " : " (car pg)))
      )
    )
  )

  (princ "\n")
  (setq *error* old-error)
  (princ)
)

;;; ============================================================
;;; HELPER: Set config directory
;;; ============================================================
(defun C:LK-CONFIG ( / dir)
  (setq dir (getstring T
    (strcat "\nCSV directory [" (lk:get-config-dir) "]: ")))
  (if (and dir (> (strlen dir) 0))
    (progn
      ;; Ensure trailing backslash
      (if (not (wcmatch dir "*\\"))
        (setq dir (strcat dir "\\"))
      )
      (setq *lk-config-dir* dir)
      (lk:save-dir dir)
      (princ (strcat "\n  Config dir set to: " dir))
      (princ "\n  Remembered -- loads automatically every session until changed.")
    )
    (princ (strcat "\n  Keeping: " (lk:get-config-dir)))
  )
  (princ)
)

;;; ============================================================
;;; HELPER: Quick report without executing
;;; ============================================================
(defun C:LK-REPORT ( / config-dir static-csv keyword-csv
                       static-map kw-list all-layers layer-name
                       target kw-result
                       ct-static ct-pdf ct-kw ct-ok ct-unk)

  (setq config-dir (lk:get-config-dir))
  (setq static-csv (strcat config-dir "PV_static_mappings.csv"))
  (setq keyword-csv (strcat config-dir "PV_keywords.csv"))

  (setq static-map (lk:load-static-map static-csv))
  (setq kw-list (lk:load-keywords keyword-csv))
  (setq all-layers (lk:get-all-layers))

  (setq ct-static 0 ct-pdf 0 ct-kw 0 ct-ok 0 ct-unk 0)

  (princ "\n\n  LK-REPORT — Classification Preview")
  (princ "\n  ===================================\n")

  (foreach layer-name all-layers
    (cond
      ((member (strcase layer-name) '("0" "DEFPOINTS"))
       (setq ct-ok (1+ ct-ok))
      )
      ((setq target (lk:static-lookup layer-name static-map))
       (if (= (strcase layer-name) (strcase target))
         (setq ct-ok (1+ ct-ok))
         (progn
           (princ (strcat "\n  STATIC  " layer-name " -> " target))
           (setq ct-static (1+ ct-static))
         )
       )
      )
      ((lk:is-pdf-layer layer-name)
       (princ (strcat "\n  PDF     " layer-name))
       (setq ct-pdf (1+ ct-pdf))
      )
      ((setq kw-result (lk:keyword-match layer-name kw-list))
       (princ (strcat "\n  KEYWRD  " layer-name
                " -> " (car kw-result)
                "  [" (cadr kw-result) "]"))
       (setq ct-kw (1+ ct-kw))
      )
      (T
       (princ (strcat "\n  ???     " layer-name))
       (setq ct-unk (1+ ct-unk))
      )
    )
  )

  (princ "\n\n  -----------------------------------")
  (princ (strcat "\n  Already correct:  " (itoa ct-ok)))
  (princ (strcat "\n  Static renames:   " (itoa ct-static)))
  (princ (strcat "\n  PDF groups:       " (itoa ct-pdf)))
  (princ (strcat "\n  Keyword matches:  " (itoa ct-kw)))
  (princ (strcat "\n  Unmatched:        " (itoa ct-unk)))
  (princ "\n")
  (princ)
)

(princ "\n  LK-CLEANUP loaded.")
(princ "\n  Commands: LK-CLEANUP | LK-REPORT | LK-CONFIG")
(if *lk-config-dir*
  (princ (strcat "\n  CSV dir (remembered): " *lk-config-dir*)))
(princ "\n")
