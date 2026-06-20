# Snapshot-Bundle.ps1 -- build a local "prod-test" copy of Opal CAD Tools and
# report what is not yet on GitHub. Driven by the in-AutoCAD OMODE command to
# flip from DEV (load from source) to a BUNDLE prod-test (load from a frozen copy).
#
#   powershell -ExecutionPolicy Bypass -NoProfile -File Snapshot-Bundle.ps1
#
# Self-locating (lives in opal-cad-installer\). Copies opal-tools + layer-kit into
# %LOCALAPPDATA%\Autodesk\OpalTools-prodtest using the SAME file selection as
# Package.ps1. Writes a human summary to %TEMP%\omode-status.txt and, last of all,
# %TEMP%\omode-done.flag so the caller can poll for completion.
#
# It NEVER commits or pushes -- the GitHub section is informational only.

$ErrorActionPreference = "Stop"
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path   # opal-cad-installer
$auto   = Split-Path -Parent $here                          # ...\Automations
$dest   = Join-Path $env:LOCALAPPDATA "Autodesk\OpalTools-prodtest"
$status = Join-Path $env:TEMP "omode-status.txt"
$flag   = Join-Path $env:TEMP "omode-done.flag"

if (Test-Path $flag) { Remove-Item $flag -Force }

function Get-GitLines {
    param($repo)
    $out = @()
    try {
        $dirty = & git -C $repo status --porcelain 2>$null
        $nDirty = @($dirty | Where-Object { $_ -ne "" }).Count
        $ahead = (& git -C $repo rev-list --count "@{u}..HEAD" 2>$null)
        if (-not $ahead) { $ahead = "?" }
        if ($nDirty -gt 0 -or ($ahead -ne "0" -and $ahead -ne "?")) {
            $out += "  NOT ON GITHUB:"
            $out += ("    uncommitted changes : {0} file(s)" -f $nDirty)
            $out += ("    commits not pushed  : {0}" -f $ahead)
            $out += "    -> commit + push from a terminal before teammates rely on this build."
        } else {
            $out += "  GitHub: up to date (nothing uncommitted, nothing unpushed)."
        }
    } catch {
        $out += "  GitHub: status unavailable (git not found, or not a repo)."
    }
    return $out
}

$lines = @()
$lines += "OMODE prod-test snapshot"
$lines += ("  source: " + $auto)
$lines += ("  copy:   " + $dest)
$lines += ""
$lines += (Get-GitLines $auto)
$lines += ""

# Build the frozen copy -- same exclusions as Package.ps1, plus omode (dev-only).
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
New-Item -ItemType Directory $dest -Force | Out-Null
robocopy (Join-Path $auto "opal-tools") (Join-Path $dest "opal-tools") /E /XD dormant archive test tools omode .git /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
robocopy (Join-Path $auto "layer-kit") (Join-Path $dest "layer-kit") /E /XD archive test tools .git /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null

if ($LASTEXITCODE -ge 8) {
    $lines += ("ERROR: robocopy failed (exit " + $LASTEXITCODE + ")")
    $ok = $false
} else {
    $lines += "Copy complete -- BUNDLE prod-test ready."
    $ok = $true
}

Set-Content -Path $status -Value $lines -Encoding utf8
if ($ok) { "ok" | Set-Content -Path $flag -Encoding utf8 }
else     { "err" | Set-Content -Path $flag -Encoding utf8 }

# robocopy exit codes 1-7 are success but leak as a nonzero process code -- normalize.
if ($ok) { exit 0 } else { exit 1 }
