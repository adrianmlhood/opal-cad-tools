;; ofeed-sweep.lsp -- headless verification harness for the O-FEED sizing engine.
;; Loads the active ofeed, then sweeps inputs across resi / C&I / industrial ranges
;; and writes one CSV row per simulation. NO production code is modified.
;; Engine entry: (_ofeed-size-feeder id load phase volts length neutral capsize)
;; Globals the engine reads (set per sim here): *term-temp* *ofeed-ambient-temp*
;;   *ofeed-neutral-is-ccc* *ofeed-parallel-material* *ofeed-max-cond* *vd-coeff*

(setq *ofeed-trace* nil) ; silence the trace log during the sweep

(defun _swp-num (x prec)
  (cond ((null x) "NA")
        ((= (type x) (quote INT)) (itoa x))
        ((= (type x) (quote REAL)) (rtos x 2 prec))
        (T (vl-princ-to-string x))))

;; write one simulation: inputs + outputs. NP (not-permitted) rows carry NP in the output fields.
(defun _swp-row (f suite ld ph vt ln nu amb tt nc cap / rr fill sets)
  (setq rr (_ofeed-size-feeder "X" ld ph vt ln nu cap))
  (if (assoc "NOTPERMITTED" rr)
    (write-line
      (strcat suite "," (_swp-num ld 1) "," (itoa ph) "," (itoa vt) "," (itoa ln) ","
              (if nu "1" "0") "," (_swp-num amb 0) "," (itoa tt) ","
              (if nc "1" "0") "," (if cap cap "none") ","
              "NP,NP,NP,NP,NP,NP,NP,NP,NOTPERMITTED")
      f)
    (progn
      (setq fill (cdr (assoc "FILL" rr))) ; "33.21%"
      (setq fill (substr fill 1 (1- (strlen fill))))
      (write-line
        (strcat suite "," (_swp-num ld 1) "," (itoa ph) "," (itoa vt) "," (itoa ln) ","
                (if nu "1" "0") "," (_swp-num amb 0) "," (itoa tt) ","
                (if nc "1" "0") "," (if cap cap "none") ","
                (itoa (cdr (assoc "SETS" rr))) ","
                (itoa (cdr (assoc "OCP" rr))) ","
                (itoa (cdr (assoc "BASEDAMP" rr))) ","
                (itoa (cdr (assoc "ADJAMP" rr))) ","
                (_swp-num (cdr (assoc "VDV" rr)) 4) ","
                (_swp-num (cdr (assoc "VDP" rr)) 4) ","
                fill ","
                (cdr (assoc "NEUTRAL" rr)) ","
                (cdr (assoc "WIRE" rr)))
        f))))

(defun c:OFSWEEP ( / f path n ld volts lengths amb amblist ttlist tt nc cap caplist ldlist)
  (_ofeed-load-refs)
  (setq *vd-coeff* 2.0)
  (setq path (strcat (getenv "TEMP") "\\ofeed-sweep-out.csv"))
  (setq f (open path "w"))
  (write-line "suite,load,phase,volts,length,neutral,ambient,term,nccc,cap,sets,ocp,basedamp,adjamp,vdv,vdp,fillpct,neut_out,wire" f)
  (setq n 0)

  ;; ---- SUITE A: structural grid (material/sets/breaker/conduit/VD logic) ----
  ;; nominal environment: ambient 30C, term 90C, neutral-not-ccc, cap 500KCMIL
  (setq *ofeed-ambient-temp* 30.0 *term-temp* 90 *ofeed-neutral-is-ccc* nil
        *ofeed-parallel-material* "AL" *ofeed-max-cond* "500KCMIL")
  (setq volts (list 120 208 240 277 480 600)
        lengths (list 10 50 100 250 500 1000))
  (foreach vt volts
    (foreach ln lengths
      (foreach ph (list 1 3)
        (foreach nu (list T nil)
          (setq ld 10)
          (while (<= ld 1600)
            (_swp-row f "A" ld ph vt ln nu 30 90 nil "500KCMIL")
            (setq n (1+ n) ld (+ ld 10)))))))

  ;; ---- SUITE B: environmental sweep (ambient temp correction + term-temp + neutral-ccc) ----
  ;; representative resi/C&I/industrial loads; volts 480, phase 3, length 100, neutral on
  (setq ldlist (list 30 150 433 800 1500)
        amblist (list 10 15 20 25 30 33 35 40 42 45 50 55 60 65 70 75 80 85))
  (foreach tt (list 75 90)
    (foreach nc (list nil T)
      (foreach ld ldlist
        (foreach amb amblist
          (setq *term-temp* tt *ofeed-ambient-temp* (float amb) *ofeed-neutral-is-ccc* nc)
          (_swp-row f "B" ld 3 480 100 T amb tt nc "500KCMIL")
          (setq n (1+ n))))))
  ;; restore nominal env
  (setq *term-temp* 90 *ofeed-ambient-temp* 30.0 *ofeed-neutral-is-ccc* nil)

  ;; ---- SUITE C: per-run cap sweep (paralleling logic: nil vs 350 vs 500 KCMIL) ----
  (setq caplist (list nil "350KCMIL" "500KCMIL"))
  (foreach cap caplist
    (setq *ofeed-max-cond* cap)
    (foreach ld (list 100 200 400 600 900 1200 1500)
      (_swp-row f "C" ld 3 480 200 T 30 90 nil cap)
      (setq n (1+ n))))
  (setq *ofeed-max-cond* "500KCMIL")

  (close f)
  (prompt (strcat "\nOFSWEEP DONE n=" (itoa n) " -> " path))
  (princ))
(princ)
