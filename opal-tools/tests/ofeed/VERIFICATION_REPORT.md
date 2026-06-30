# O-FEED Sizing Engine — Verification Report

**Tool:** O-FEED (Ocotillo AC Feeder Schedule) — sizing engine
**Engine file:** `opal-tools/ofeed/ofeed-2.35.lsp`, function `_ofeed-size-feeder`
**Verified:** 2026-06-28
**Runner:** AutoCAD 2027 (R26.0) `accoreconsole`, headless
**Result:** 23,421 simulations, **0 invariant violations**

---

## 1. Purpose

Demonstrate, with reproducible evidence, that the O-FEED conductor/breaker/conduit sizing engine
produces NEC-consistent output across the full range of system sizes Ocotillo designs — residential,
commercial & industrial (C&I), and industrial — not just the handful of cases on the production sheet.

This verifies the **sizing engine** (the math that turns load + length + voltage + environment into a
feeder schedule row). It does not, by itself, verify the AutoCAD table read/write (GUI/COM) layer —
see Section 7, Scope & Limitations.

## 2. Method

A headless harness loads the production engine unchanged and calls `_ofeed-size-feeder` directly over
a swept grid of inputs, writing one CSV row per simulation. An independent analyzer
(`analyze.ps1`) then checks every row against a set of **NEC / logical invariants** — rules that must
hold for any correct sizing, derived from the code itself, *not* from the engine's own output. Where a
quantity has a single correct value (breaker rating, voltage drop, adjusted ampacity), the analyzer
**recomputes it independently** from the same NEC reference tables and compares.

Two layers of confidence:

1. **Invariants** — engine-independent truths (e.g. "corrected ampacity must be at least the breaker
   rating"). A violation is a real defect.
2. **Independent recompute** — the analyzer re-derives breaker size, voltage drop, and adjusted
   ampacity from first principles and the NEC tables; a mismatch is a real defect.

No production code was modified. The harness only loads the engine and reads the shared
`config/*.csv` reference tables (NEC 310.16 ampacity, 240.6 breaker sizes, 250.122 EGC, Chapter 9
conduit areas and resistance, 310.15(B)(1) ambient correction).

## 3. Coverage (input sweep)

| Parameter | Range swept | Spans |
|---|---|---|
| Circuit load | 10 – 1600 A | resi branch → industrial aggregation |
| Voltage | 120, 208, 240, 277, 480, 600 V | 1Ø and 3Ø service voltages |
| Phase | 1Ø, 3Ø | both |
| One-way length | 10 – 1000 ft | short runs → long site feeders |
| Design ambient | 10 – 85 °C | every 310.15(B)(1) correction band |
| Termination temp | 75 °C, 90 °C | both NEC 110.14(C) columns |
| Neutral counted as CCC | off / on | balanced wye vs harmonic/nonlinear |
| Per-run conductor cap | none / 350 / 500 KCMIL | paralleling behavior |

**23,421 simulations.** Capability boundary: load ≤ 1600 A, because 125% of 1600 = 2000 A is the
largest standard breaker in the table (NEC 240.6). Above this the engine correctly has no breaker to
select; the harness stops at the boundary.

Output range observed across the sweep: parallel sets 1–25, breaker 15–2000 A, base ampacity
25–8750 A, adjusted ampacity 25–2281 A, conduit fill 9.57–39.56 % (always under the 40 % limit),
voltage drop 0.02–102 %. Material split: 4,736 single-run copper, 18,655 parallel aluminum.

## 4. Invariants checked

| # | Invariant | NEC basis | Result |
|---|---|---|---|
| 1 | Breaker = smallest standard rating ≥ 125 % of load | 210.20(A), 215.3, 240.6(A) | PASS |
| 2 | Breaker ≥ 125 % of load | 210.20(A), 215.2 | PASS |
| 3 | **Adjusted (corrected) ampacity ≥ breaker rating** | **240.4** | PASS |
| 4 | Adjusted ampacity = ⌊sets × derate × table ampacity⌋ (independent recompute) | 310.15(B)(1), 310.15(C)(1) | PASS |
| 5 | Raw table ampacity ≥ breaker when derate ≤ 1 | 240.4, 110.14(C) | PASS |
| 6 | Single run → copper; parallel sets → aluminum (consistent wire string) | 310.10(G) | PASS |
| 7 | Phase-conductor count correct (2 for 1Ø, 3 for 3Ø) | — | PASS |
| 8 | Neutral present in output iff requested | 220.61 | PASS |
| 9 | Voltage drop V and % match independent recompute from conductor R | Ch. 9 Table 8 | PASS |
| 10 | Conduit fill < 40 % (or flagged as exceeding one 4 in EMT) | Ch. 9 Table 1 | PASS (0 over) |
| 11 | Breaker, adjusted ampacity, and sets are non-decreasing as load rises | internal consistency | PASS |
| 12 | "75 °C not permitted" fires exactly when term = 75 °C and ambient is above the band where the 75 °C factor reaches 0 (~70 °C) | 110.14(C), 310.15(B)(1) | PASS |

**Total invariant violations: 0 / 23,421.**

The single most important line is invariant 3 / 4: across every one of the 23,421 cases — every
ambient, every termination temperature, every paralleling scenario — the conductor's **corrected**
ampacity always carries its overcurrent device, which is the core NEC 240.4 protection guarantee. A
hot ambient or counted neutral upsizes the conductor or adds a set rather than silently undersizing.

## 5. Ground-truth anchor

The engine's built-in self-test (`O-FEEDTEST`) reproduces the stamped production sheet E-2.0:
432.9 A aggregation feeder → 600 A breaker → parallel aluminum sets; 144.3 A branch → 3/0 copper;
48.1 A inverter branch. Matching an issued drawing anchors the sweep to a real, reviewed design.

## 6. Notable, correctly-handled cases

- **Voltage drop > 3 %** occurred in 7,352 cases — all at extreme length / low voltage / high
  current. This is correct: the engine computes and **reports** the high drop (a design flag for the
  engineer to act on), it does not hide or error on it. VD > 3 % is an advisory threshold
  (210.19/215.2 Informational Note), not a sizing fault.
- **Not-permitted terminations** — 30 cases where a 75 °C termination is disallowed by the design
  ambient are reported cleanly as "75 °C termination not permitted at this ambient," never sized as
  if permitted.

## 7. Scope & limitations (state these to reviewers)

- This verifies the **sizing engine math** (`_ofeed-size-feeder`) and its NEC reference tables. It
  does **not** verify the AutoCAD native-table read/write path (column setup, cell formatting,
  regen handling), which is COM/GUI-only and cannot be exercised headless. That layer is on the
  O-Suite live-GUI test checklist and should get a separate live pass before "fully tested" is
  claimed end to end.
- Verification is against the engine's NEC reference CSVs. Those tables (especially aluminum
  resistance/area values) carry a "verify against your NEC copy" note in `conductors.csv`; the sweep
  confirms the engine *uses* the tables correctly, not that every published table value is transcribed
  perfectly. A one-time table audit against a current NEC handbook closes that gap.
- Load is bounded at 1600 A (the 2000 A top-breaker limit). Larger services are out of the current
  table's scope by design.

## 8. Reproduce

Requires AutoCAD 2027 (`accoreconsole`), run from PowerShell (not git-bash). From this folder:

1. `accoreconsole.exe /i <any scratch>.dwg /s ofeed-sweep.scr` — runs the 23,421-case sweep,
   writing `%TEMP%\ofeed-sweep-out.csv`. (accoreconsole does not self-exit at `QUIT`; kill it once
   the CSV is written.)
2. `.\analyze.ps1` — checks the results against all invariants and prints the PASS/FAIL table.
   With no fresh sweep present it reads the committed `ofeed-sweep-results.csv` snapshot in this
   folder, so the analysis reproduces on any machine without AutoCAD.

## 9. Files in this folder

| File | What it is |
|---|---|
| `VERIFICATION_REPORT.md` | This report |
| `verification-summary.html` | One-page printable summary (open in a browser, print to PDF) |
| `verification-results.txt` | Captured analyzer output (the PASS table) |
| `ofeed-sweep-results.csv` | The 23,421-row evidence snapshot (one row per simulation) |
| `ofeed-sweep.lsp` | The sweep harness (loads the engine, calls it across the grid) |
| `ofeed-sweep.scr` | accoreconsole run script |
| `analyze.ps1` | Independent NEC-invariant analyzer |
| `README.md` | Quick-start / reproduction notes |
