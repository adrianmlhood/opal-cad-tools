# Verify O-FEED engine outputs against NEC / logical invariants (PowerShell port).
$ErrorActionPreference = "Stop"
$CFG = "C:\Users\adria\CAD\Automations\opal-tools\config"
# Prefer the results CSV sitting next to this script (the committed evidence snapshot);
# fall back to a fresh sweep written to %TEMP% by ofeed-sweep.lsp.
$local = Join-Path $PSScriptRoot "ofeed-sweep-results.csv"
$OUT = if (Test-Path $local) { $local } else { Join-Path $env:TEMP "ofeed-sweep-out.csv" }

function Read-RefRows($name) {
    $rows = @()
    $seen = $false
    foreach ($line in (Get-Content (Join-Path $CFG $name))) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        if (-not $seen) { $seen = $true; continue }
        $rows += ,($t.Split(",") | ForEach-Object { $_.Trim() })
    }
    return $rows
}

# reference tables
$COND = @{}   # "size|MAT" -> @(amp75,amp90,r,area)
foreach ($r in (Read-RefRows "conductors.csv")) {
    if ($r.Count -ge 7) {
        $COND["$($r[0])|$($r[1].ToUpper())"] = @([int]$r[3], [int]$r[4], [double]$r[5], [double]$r[6])
    }
}
$OCPD = @(); $seenO = $false
foreach ($line in (Get-Content (Join-Path $CFG "ocpd.csv"))) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    if (-not $seenO) { $seenO = $true; continue }
    $OCPD += [int]($t.Split(",")[0])
}
$OCPD = $OCPD | Sort-Object
$CORR = @()   # @(ub,f75,f90)
foreach ($r in (Read-RefRows "ambient_correction.csv")) {
    if ($r.Count -ge 3) { $CORR += ,@([double]$r[0], [double]$r[1], [double]$r[2]) }
}

function Temp-Factor($term, $amb) {
    $f = $null; $last = $null
    foreach ($b in $CORR) {
        $last = $(if ($term -eq 90) { $b[2] } else { $b[1] })
        if ($null -eq $f -and $amb -le $b[0]) { $f = $last }
    }
    if ($null -ne $f) { return $f }
    if ($null -ne $last) { return $last }
    return 1.0
}
function Bundle-Factor($ccc) {
    if ($ccc -le 3) { return 1.0 }
    if ($ccc -le 6) { return 0.80 }
    if ($ccc -le 9) { return 0.70 }
    if ($ccc -le 20) { return 0.50 }
    if ($ccc -le 30) { return 0.45 }
    if ($ccc -le 40) { return 0.40 }
    return 0.35
}
function Ocp-Pick($i125) {
    foreach ($s in $OCPD) { if ($s -ge $i125 - 1e-9) { return $s } }
    return $null
}
function Parse-Wire($w) {
    $sets = 1; $s = $w
    if ($s -match "SETS OF") {
        $parts = $s -split "SETS OF", 2
        $sets = [int]($parts[0].Trim())
        $s = $parts[1].Trim()
    }
    $rp = $s.IndexOf(")")
    $np = [int]$s.Substring(1, $rp - 1)
    $rest = ($s.Substring($rp + 1).Trim()) -split "\s+"
    $mi = -1
    for ($i = 0; $i -lt $rest.Count; $i++) { if ($rest[$i] -eq "CU" -or $rest[$i] -eq "AL") { $mi = $i; break } }
    $size = ($rest[0..($mi-1)] -join " ")
    $mat = $rest[$mi]
    return @($sets, $np, $size, $mat)
}

if (-not (Test-Path $OUT)) { Write-Output "NO OUTPUT CSV"; exit 1 }
$rows = Import-Csv $OUT

$counts = @{}
$samples = @{}
function Add-Fail($inv, $row, $msg) {
    if (-not $counts.ContainsKey($inv)) { $counts[$inv] = 0; $samples[$inv] = @() }
    $counts[$inv]++
    if ($samples[$inv].Count -lt 6) { $samples[$inv] += ,@($msg, $row) }
}

$n = 0; $npRows = 0; $overflow = 0
foreach ($row in $rows) {
    $n++
    $term = [int]$row.term; $amb = [double]$row.ambient
    $nccc = $row.nccc -eq "1"; $neutral = $row.neutral -eq "1"
    $phase = [int]$row.phase; $volts = [int]$row.volts
    $length = [int]$row.length; $load = [double]$row.load
    if ($row.wire -eq "NOTPERMITTED" -or $row.sets -eq "NP") {
        $npRows++
        if (-not ($term -eq 75 -and (Temp-Factor 75 $amb) -eq 0.0)) {
            Add-Fail "NP_boundary_wrong" $row "NP but term=$term f75=$(Temp-Factor 75 $amb)"
        }
        continue
    }
    $sets = [int]$row.sets; $ocp = [int]$row.ocp
    $basedamp = [int]$row.basedamp; $adjamp = [int]$row.adjamp
    $vdv = [double]$row.vdv; $vdp = [double]$row.vdp; $fill = [double]$row.fillpct
    $neut = $row.neut_out; $wire = $row.wire
    $i125 = $load * 1.25
    $npc = $(if ($phase -eq 1) { 2 } else { 3 })
    $ccc = $npc + $(if ($neutral -and $nccc) { 1 } else { 0 })
    $derate = [Math]::Max(0.01, (Temp-Factor $term $amb) * (Bundle-Factor $ccc))

    $expOcp = Ocp-Pick $i125
    if ($expOcp -ne $ocp) { Add-Fail "ocp_exact" $row "ocp=$ocp expected=$expOcp i125=$([Math]::Round($i125,2))" }
    if ($ocp + 1e-9 -lt $i125) { Add-Fail "ocp_ge_i125" $row "ocp=$ocp < i125=$([Math]::Round($i125,2))" }
    if ($adjamp + 1e-9 -lt $ocp) { Add-Fail "adjamp_ge_ocp" $row "adjamp=$adjamp < ocp=$ocp" }
    if ($derate -le 1.0 + 1e-9 -and $basedamp + 1e-9 -lt $ocp) {
        Add-Fail "basedamp_ge_ocp_hot" $row "basedamp=$basedamp < ocp=$ocp derate=$([Math]::Round($derate,3))"
    }
    if ($fill -ge 40.0 + 1e-6) { $overflow++ }

    $pw = Parse-Wire $wire
    $psets = $pw[0]; $pnp = $pw[1]; $psize = $pw[2]; $pmat = $pw[3]
    if ($psets -ne $sets) { Add-Fail "wire_sets_mismatch" $row "wire sets=$psets col sets=$sets" }
    if ($pnp -ne $npc) { Add-Fail "wire_np_mismatch" $row "wire np=$pnp expected=$npc" }
    if ($sets -eq 1 -and $pmat -ne "CU") { Add-Fail "single_run_not_CU" $row "sets=1 material=$pmat" }
    if ($sets -ge 2 -and $pmat -ne "AL") { Add-Fail "parallel_not_AL" $row "sets=$sets material=$pmat" }
    if ($neutral -and $neut -eq "-") { Add-Fail "neutral_missing" $row "neutral requested but '-'" }
    if ((-not $neutral) -and $neut -ne "-") { Add-Fail "neutral_present_unwanted" $row "no neutral but neut=$neut" }

    $key = "$psize|$pmat"
    if ($COND.ContainsKey($key)) {
        $R = $COND[$key][2]
        $expVdv = 2.0 * $length * ($load / $sets) * $R / 1000.0
        $expVdp = 100.0 * $expVdv / $volts
        if ([Math]::Abs($expVdv - $vdv) -gt [Math]::Max(0.01, 0.01 * [Math]::Abs($expVdv))) {
            Add-Fail "vd_volts_formula" $row "vdv=$vdv expected=$([Math]::Round($expVdv,4)) R=$R"
        }
        if ([Math]::Abs($expVdp - $vdp) -gt [Math]::Max(0.01, 0.01 * [Math]::Abs($expVdp))) {
            Add-Fail "vd_pct_formula" $row "vdp=$vdp expected=$([Math]::Round($expVdp,4))"
        }
        $amp = $(if ($term -eq 90) { $COND[$key][1] } else { $COND[$key][0] })
        $expAdj = [Math]::Floor($sets * $derate * $amp)
        if ($expAdj -ne $adjamp) {
            Add-Fail "adjamp_recompute" $row "adjamp=$adjamp expected=$expAdj (sets=$sets derate=$([Math]::Round($derate,4)) amp=$amp)"
        }
    } else {
        Add-Fail "unknown_conductor" $row "$key not in table"
    }
    if ($vdv -lt 0 -or $vdp -lt 0) { Add-Fail "vd_negative" $row "vdv=$vdv vdp=$vdp" }
}

# monotonicity within suite A
$groups = @{}
foreach ($row in $rows) {
    if ($row.suite -ne "A" -or $row.sets -eq "NP") { continue }
    $k = "$($row.volts)|$($row.phase)|$($row.length)|$($row.neutral)"
    if (-not $groups.ContainsKey($k)) { $groups[$k] = @() }
    $groups[$k] += $row
}
$monoFail = 0; $monoSamples = @()
foreach ($k in $groups.Keys) {
    $g = $groups[$k] | Sort-Object { [double]$_.load }
    foreach ($field in @("ocp", "adjamp", "sets")) {
        $prev = $null
        foreach ($r in $g) {
            $v = [int]$r.$field
            if ($null -ne $prev -and $v -lt $prev) {
                $monoFail++
                if ($monoSamples.Count -lt 8) { $monoSamples += "$field dropped $prev->$v at load=$($r.load) grp=$k" }
            }
            $prev = $v
        }
    }
}

Write-Output "Total simulations parsed : $n"
Write-Output "  NOT-PERMITTED rows     : $npRows  (term75 above ~70C ambient -- expected; sized cleanly elsewhere)"
Write-Output "  conduit >4in overflow  : $overflow  (load exceeds one 4in EMT run -- capability boundary, not a sizing bug)"
Write-Output ""
$invOrder = @("ocp_exact","ocp_ge_i125","adjamp_ge_ocp","adjamp_recompute","basedamp_ge_ocp_hot",
    "wire_sets_mismatch","wire_np_mismatch","single_run_not_CU","parallel_not_AL",
    "neutral_missing","neutral_present_unwanted","vd_volts_formula","vd_pct_formula",
    "vd_negative","unknown_conductor","NP_boundary_wrong")
$totalFail = 0
Write-Output "INVARIANT CHECKS:"
foreach ($inv in $invOrder) {
    $c = 0; if ($counts.ContainsKey($inv)) { $c = $counts[$inv] }
    $totalFail += $c
    $status = $(if ($c -eq 0) { "PASS" } else { "FAIL ($c)" })
    Write-Output ("  {0,-28} {1}" -f $inv, $status)
}
$mstat = $(if ($monoFail -eq 0) { "PASS" } else { "FAIL ($monoFail)" })
Write-Output ("  {0,-28} {1}" -f "monotonic_load(suiteA)", $mstat)
$totalFail += $monoFail
Write-Output ""
Write-Output "TOTAL INVARIANT VIOLATIONS: $totalFail"
if ($totalFail -gt 0) {
    Write-Output "`n--- sample violations ---"
    foreach ($inv in $invOrder) {
        if ($samples.ContainsKey($inv)) {
            foreach ($s in $samples[$inv]) {
                $msg = $s[0]; $r = $s[1]
                Write-Output "[$inv] $msg"
                Write-Output "     in: suite=$($r.suite) load=$($r.load) ph=$($r.phase) V=$($r.volts) L=$($r.length) neut=$($r.neutral) amb=$($r.ambient) term=$($r.term) nccc=$($r.nccc) cap=$($r.cap)"
                Write-Output "     out: sets=$($r.sets) ocp=$($r.ocp) base=$($r.basedamp) adj=$($r.adjamp) vdv=$($r.vdv) vdp=$($r.vdp) fill=$($r.fillpct) wire=$($r.wire)"
            }
        }
    }
    foreach ($s in $monoSamples) { Write-Output "[monotonic] $s" }
}
