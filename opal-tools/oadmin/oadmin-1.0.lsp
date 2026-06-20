;; oadmin-1.0.lsp -- O-Suite admin unlock (per machine)
;; Commands: OADMIN, O-ADMIN
;; The admin unlock reveals the master-rewrite actions ("Save drawing -> master
;; standard" / "... master filters") in the O > Layer Tools panel. Those rewrite
;; the shared standard/filter CSVs from the current drawing, so they are hidden by
;; default. A DEV machine is always admin; on any other machine you opt in here.
;; Persisted in HKCU\Software\Ocotillo\OpalTools  Admin = "1"/"0" (the hive omode
;; uses). To grant a teammate, have them run OADMIN On once on their machine.
;; v1.0
;; ============================================================

(vl-load-com)

(defun _oadmin-reg () "HKEY_CURRENT_USER\\Software\\Ocotillo\\OpalTools")

(defun _oadmin-on-p ( / v)
  (setq v (vl-registry-read (_oadmin-reg) "Admin"))
  (and v (= v "1")))

(defun C:OADMIN ( / cur opt)
  (setq cur (_oadmin-on-p))
  (initget "On Off")
  (setq opt (getkword
              (strcat "\nAdmin unlock is " (if cur "ON" "OFF")
                      " on this machine. [On/Off] <" (if cur "Off" "On") ">: ")))
  (if (not opt) (setq opt (if cur "Off" "On")))   ; Enter toggles
  (vl-registry-write (_oadmin-reg) "Admin" (if (= opt "On") "1" "0"))
  (prompt (strcat "\nAdmin unlock now " (strcase opt) " for this machine."))
  (if (= opt "On")
    (prompt "\n  The O > Layer Tools panel now shows the Save -> master actions.")
    (prompt "\n  The Save -> master actions are hidden again."))
  (prompt "\n  Re-open the toolbox (type O) to see the change.")
  (princ))

(defun C:O-ADMIN () (C:OADMIN))

(prompt "\nOADMIN loaded. Type OADMIN to toggle the admin unlock.")
(princ)
