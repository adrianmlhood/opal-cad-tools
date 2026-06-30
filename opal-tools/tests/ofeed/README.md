# O-FEED engine verification — tests/ofeed

Reproducible verification of the O-FEED conductor/breaker/conduit **sizing engine**
(`opal-tools/ofeed/ofeed-2.35.lsp`, `_ofeed-size-feeder`). 23,421 simulations across
resi / C&I / industrial ranges, checked against NEC-derived invariants. Latest run: 0 violations.

## Show the team
- **`verification-summary.html`** — open in a browser, print to PDF. One page, for circulation.
- **`VERIFICATION_REPORT.md`** — full methodology, NEC invariant table, coverage, scope/limits.
- **`verification-results.txt`** — the raw PASS table from the analyzer.

## Re-run it
Requires AutoCAD 2027 (`accoreconsole`). Run from **PowerShell**, not git-bash.

1. Sweep (regenerates the data):
   ```
   & "C:\Program Files\Autodesk\AutoCAD 2027\accoreconsole.exe" /i <scratch>.dwg /s "ofeed-sweep.scr"
   ```
   Writes `%TEMP%\ofeed-sweep-out.csv`. accoreconsole does not self-exit at `QUIT`; kill it once the
   CSV stops growing (~23,422 lines).
2. Analyze:
   ```
   .\analyze.ps1
   ```
   Prints the invariant PASS/FAIL table. With no fresh sweep in `%TEMP%`, it reads the committed
   `ofeed-sweep-results.csv` snapshot here — so the analysis reproduces on any machine, no AutoCAD
   needed.

## What is and isn't covered
- **Covered:** the sizing math and its NEC reference tables (`opal-tools/config/*.csv`).
- **Not covered here:** the AutoCAD native-table GUI/COM read-write path (column setup, formatting,
  regen) — COM-only, verified via the separate live-GUI pass.

## Files
| File | Purpose |
|---|---|
| `ofeed-sweep.lsp` | Sweep harness — loads the engine, calls it across the input grid, writes one CSV row per sim. Modifies no production code. |
| `ofeed-sweep.scr` | accoreconsole run script |
| `analyze.ps1` | Independent NEC-invariant analyzer (recomputes breaker / VD / ampacity from the NEC tables) |
| `ofeed-sweep-results.csv` | 23,421-row evidence snapshot |
| `verification-results.txt` | Captured analyzer output |
| `VERIFICATION_REPORT.md` | Full report |
| `verification-summary.html` | One-page printable summary |
