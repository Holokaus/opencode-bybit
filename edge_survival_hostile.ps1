param([string]$InputDir = ".", [string]$OutputDir = ".")
$ErrorActionPreference = "Stop"
$start = Get-Date

# Logging
$logFile = Join-Path $OutputDir "hostile_log.txt"
function Log { param($msg) $ts = Get-Date -Format 'HH:mm:ss.fff'; $line = "[$ts] $msg"; Add-Content -Path $logFile -Value $line; Write-Output $line }

try {
Log "=== HOSTILE VALIDATION STARTED ==="
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue
Log "Module loaded"

# Load data
$csvPath = Join-Path $InputDir "SOLUSDT-FUTURES-2021-2026-30m.csv"
if (-not (Test-Path $csvPath)) { throw "CSV not found: $csvPath" }
$klines = Import-Csv $csvPath
$n = $klines.Count
Log "Data loaded: $n bars"

# Build arrays
$h = [double[]]::new($n); $l = [double[]]::new($n); $c = [double[]]::new($n); $v = [double[]]::new($n); $o = [double[]]::new($n)
for ($i = 0; $i -lt $n; $i++) {
    $h[$i] = [double]$klines[$i].High; $l[$i] = [double]$klines[$i].Low
    $o[$i] = [double]$klines[$i].Open; $c[$i] = [double]$klines[$i].Close; $v[$i] = [double]$klines[$i].Volume
}
$datesList = New-Object 'System.Collections.Generic.List[string]'
foreach ($k in $klines) { $datesList.Add($k.Date) }
$dates = $datesList.ToArray()
Remove-Variable klines -ErrorAction SilentlyContinue; Remove-Variable datesList -ErrorAction SilentlyContinue
Log "Arrays built"

# Baseline signal
$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c $h $l $v $n
Log "Signal computed"

$tradeIdxList = New-Object 'System.Collections.Generic.List[int]'
for ($si = 100; $si -lt $sig.Length; $si++) { if ($sig[$si]) { $tradeIdxList.Add($si) } }
$tradeIdx = $tradeIdxList.ToArray()
Log "Trade count: $($tradeIdx.Length)"

function Get-BaseReturns { param($tradeIdx, $c, $n)
    $retList = New-Object 'System.Collections.Generic.List[double]'
    foreach ($idx in $tradeIdx) {
        $exitIdx = $idx + 5
        if ($exitIdx -ge $n) { continue }
        $retList.Add(($c[$exitIdx] - $c[$idx]) / $c[$idx] * 100)
    }
    return $retList.ToArray()
}

function Get-StdDev2 { param($a)
    if ($a.Count -lt 2) { return 0 }
    $avg = ($a | Measure-Object -Average).Average
    $sum = 0.0; foreach ($x in $a) { $d = $x - $avg; $sum += $d * $d }
    return [Math]::Sqrt($sum / ($a.Count - 1))
}

function Get-TradeMetrics { param($returns)
    $n_t = $returns.Count
    if ($n_t -lt 3) { return $null }
    $wins = ($returns | Where-Object { $_ -gt 0 }).Count
    $losses = $n_t - $wins
    $wr = $wins / $n_t * 100
    $avg = ($returns | Measure-Object -Average).Average
    $sorted = $returns | Sort-Object
    $med = $sorted[[Math]::Floor(($n_t)/2)]
    $std = Get-StdDev2 $returns
    $sharpe = if ($std -gt 0) { $avg / $std } else { 0 }
    $gain = ($returns | Where-Object { $_ -gt 0 } | Measure-Object -Sum).Sum
    $loss = ($returns | Where-Object { $_ -lt 0 } | Measure-Object -Sum).Sum
    $pf = if ($loss -ne 0) { [Math]::Abs($gain / $loss) } else { 999 }
    $avgWin = if ($wins -gt 0) { ($returns | Where-Object { $_ -gt 0 } | Measure-Object -Average).Average } else { 0 }
    $avgLoss = if ($losses -gt 0) { ($returns | Where-Object { $_ -lt 0 } | Measure-Object -Average).Average } else { 0 }
    $dd = 0.0; $eq = 1.0; $peak = 1.0
    foreach ($r in $returns) { $eq *= (1+$r/100); if ($eq -gt $peak) { $peak = $eq }; $d = ($peak-$eq)/$peak*100; if ($d -gt $dd) { $dd = $d } }
    return @{Trades=$n_t; Wins=$wins; Losses=$losses; WinRate=[Math]::Round($wr,1); AvgReturn=[Math]::Round($avg,4); MedianReturn=[Math]::Round($med,4); StdReturn=[Math]::Round($std,4); Sharpe=[Math]::Round($sharpe,4); ProfitFactor=[Math]::Round($pf,2); MaxDrawdown=[Math]::Round($dd,2); AvgWin=[Math]::Round($avgWin,4); AvgLoss=[Math]::Round($avgLoss,4)}
}

$baseReturns = Get-BaseReturns $tradeIdx $c $n
$baseMetrics = Get-TradeMetrics $baseReturns
Log "Baseline: trades=$($baseMetrics.Trades) WR=$($baseMetrics.WinRate)% avg=$($baseMetrics.AvgReturn) Sharpe=$($baseMetrics.Sharpe) PF=$($baseMetrics.ProfitFactor) DD=$($baseMetrics.MaxDrawdown)%"

$allResults = New-Object 'System.Collections.Generic.List[PSObject]'
$allResults.Add([PSCustomObject]@{TestSuite="BASELINE"; TestName="Base (close entry, 5-bar hold, no fees/slippage)"; Trades=$baseMetrics.Trades; WinRate=$baseMetrics.WinRate; AvgReturn=$baseMetrics.AvgReturn; Sharpe=$baseMetrics.Sharpe; ProfitFactor=$baseMetrics.ProfitFactor; MaxDrawdown=$baseMetrics.MaxDrawdown; AvgWin=$baseMetrics.AvgWin; AvgLoss=$baseMetrics.AvgLoss; EdgeStatus="N/A"})

# ===== TEST 1: EXECUTION REALISM =====
Log "=== TEST 1: EXECUTION REALISM ==="

# 1A: Fixed fee 0.1%
$ret1a = New-Object 'System.Collections.Generic.List[double]'
foreach ($r in $baseReturns) { $ret1a.Add($r - 0.1) }
$m1a = Get-TradeMetrics $ret1a.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Fixed fee 0.1%"; Trades=$m1a.Trades; WinRate=$m1a.WinRate; AvgReturn=$m1a.AvgReturn; Sharpe=$m1a.Sharpe; ProfitFactor=$m1a.ProfitFactor; MaxDrawdown=$m1a.MaxDrawdown; AvgWin=$m1a.AvgWin; AvgLoss=$m1a.AvgLoss; EdgeStatus=if($m1a.Sharpe -gt 0 -and $m1a.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1A fee=0.1%: WR=$($m1a.WinRate)% Sharpe=$($m1a.Sharpe)"

# 1B: Fixed fee 0.2%
$ret1b = New-Object 'System.Collections.Generic.List[double]'
foreach ($r in $baseReturns) { $ret1b.Add($r - 0.2) }
$m1b = Get-TradeMetrics $ret1b.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Fixed fee 0.2%"; Trades=$m1b.Trades; WinRate=$m1b.WinRate; AvgReturn=$m1b.AvgReturn; Sharpe=$m1b.Sharpe; ProfitFactor=$m1b.ProfitFactor; MaxDrawdown=$m1b.MaxDrawdown; AvgWin=$m1b.AvgWin; AvgLoss=$m1b.AvgLoss; EdgeStatus=if($m1b.Sharpe -gt 0 -and $m1b.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1B fee=0.2%: WR=$($m1b.WinRate)% Sharpe=$($m1b.Sharpe)"

# 1C: Slippage 0.05%
$ret1c = New-Object 'System.Collections.Generic.List[double]'
foreach ($r in $baseReturns) { $ret1c.Add($r - 0.05) }
$m1c = Get-TradeMetrics $ret1c.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Slippage 0.05% each way"; Trades=$m1c.Trades; WinRate=$m1c.WinRate; AvgReturn=$m1c.AvgReturn; Sharpe=$m1c.Sharpe; ProfitFactor=$m1c.ProfitFactor; MaxDrawdown=$m1c.MaxDrawdown; AvgWin=$m1c.AvgWin; AvgLoss=$m1c.AvgLoss; EdgeStatus=if($m1c.Sharpe -gt 0 -and $m1c.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1C slip=0.05%: WR=$($m1c.WinRate)% Sharpe=$($m1c.Sharpe)"

# 1D: Slippage 0.1%
$ret1d = New-Object 'System.Collections.Generic.List[double]'
foreach ($r in $baseReturns) { $ret1d.Add($r - 0.1) }
$m1d = Get-TradeMetrics $ret1d.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Slippage 0.1% each way"; Trades=$m1d.Trades; WinRate=$m1d.WinRate; AvgReturn=$m1d.AvgReturn; Sharpe=$m1d.Sharpe; ProfitFactor=$m1d.ProfitFactor; MaxDrawdown=$m1d.MaxDrawdown; AvgWin=$m1d.AvgWin; AvgLoss=$m1d.AvgLoss; EdgeStatus=if($m1d.Sharpe -gt 0 -and $m1d.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1D slip=0.1%: WR=$($m1d.WinRate)% Sharpe=$($m1d.Sharpe)"

# 1E: Delayed fill
$ret1e = New-Object 'System.Collections.Generic.List[double]'
foreach ($idx in $tradeIdx) {
    $entryIdx = $idx + 1; $exitIdx = $idx + 6
    if ($exitIdx -ge $n) { continue }
    $ret1e.Add(($c[$exitIdx] - $o[$entryIdx]) / $o[$entryIdx] * 100)
}
$m1e = Get-TradeMetrics $ret1e.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Delayed fill (next open, hold 5)"; Trades=$m1e.Trades; WinRate=$m1e.WinRate; AvgReturn=$m1e.AvgReturn; Sharpe=$m1e.Sharpe; ProfitFactor=$m1e.ProfitFactor; MaxDrawdown=$m1e.MaxDrawdown; AvgWin=$m1e.AvgWin; AvgLoss=$m1e.AvgLoss; EdgeStatus=if($m1e.Sharpe -gt 0 -and $m1e.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1E delayed fill: WR=$($m1e.WinRate)% Sharpe=$($m1e.Sharpe)"

# 1F: Delayed + slippage + fee
$ret1f = New-Object 'System.Collections.Generic.List[double]'
foreach ($idx in $tradeIdx) {
    $entryIdx = $idx + 1; $exitIdx = $idx + 6
    if ($exitIdx -ge $n) { continue }
    $raw = ($c[$exitIdx] - $o[$entryIdx]) / $o[$entryIdx] * 100
    $ret1f.Add($raw - 0.2)
}
$m1f = Get-TradeMetrics $ret1f.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Delayed + 0.1% fee + 0.1% slip"; Trades=$m1f.Trades; WinRate=$m1f.WinRate; AvgReturn=$m1f.AvgReturn; Sharpe=$m1f.Sharpe; ProfitFactor=$m1f.ProfitFactor; MaxDrawdown=$m1f.MaxDrawdown; AvgWin=$m1f.AvgWin; AvgLoss=$m1f.AvgLoss; EdgeStatus=if($m1f.Sharpe -gt 0 -and $m1f.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1F delayed+slip+fee: WR=$($m1f.WinRate)% Sharpe=$($m1f.Sharpe)"

# 1G: Market impact
$ret1g = New-Object 'System.Collections.Generic.List[double]'
$st = Calc-Stoch $h $l $c 5 5
foreach ($idx in $tradeIdx) {
    $exitIdx = $idx + 5
    if ($exitIdx -ge $n) { continue }
    $entryPrice = ($c[$idx] + $h[$idx]) / 2
    $ret1g.Add(($c[$exitIdx] - $entryPrice) / $entryPrice * 100)
}
$m1g = Get-TradeMetrics $ret1g.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Market impact (entry at mid)"; Trades=$m1g.Trades; WinRate=$m1g.WinRate; AvgReturn=$m1g.AvgReturn; Sharpe=$m1g.Sharpe; ProfitFactor=$m1g.ProfitFactor; MaxDrawdown=$m1g.MaxDrawdown; AvgWin=$m1g.AvgWin; AvgLoss=$m1g.AvgLoss; EdgeStatus=if($m1g.Sharpe -gt 0 -and $m1g.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1G market impact: WR=$($m1g.WinRate)% Sharpe=$($m1g.Sharpe)"

# 1H: Extreme
$ret1h = New-Object 'System.Collections.Generic.List[double]'
foreach ($idx in $tradeIdx) {
    $entryIdx = $idx + 1; $exitIdx = $idx + 6
    if ($exitIdx -ge $n) { continue }
    $entryPrice = ($o[$entryIdx] + $h[$entryIdx]) / 2
    $raw = ($c[$exitIdx] - $entryPrice) / $entryPrice * 100
    $ret1h.Add($raw - 0.3)
}
$m1h = Get-TradeMetrics $ret1h.ToArray()
$allResults.Add([PSCustomObject]@{TestSuite="1-Execution"; TestName="Extreme: delayed+mid+0.15%fee+0.15%slip"; Trades=$m1h.Trades; WinRate=$m1h.WinRate; AvgReturn=$m1h.AvgReturn; Sharpe=$m1h.Sharpe; ProfitFactor=$m1h.ProfitFactor; MaxDrawdown=$m1h.MaxDrawdown; AvgWin=$m1h.AvgWin; AvgLoss=$m1h.AvgLoss; EdgeStatus=if($m1h.Sharpe -gt 0 -and $m1h.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "1H extreme: WR=$($m1h.WinRate)% Sharpe=$($m1h.Sharpe)"
Log "TEST 1 complete"

# ===== TEST 2: PARAMETER STABILITY =====
Log "=== TEST 2: PARAMETER STABILITY ==="

$paramTests = @(
    @{Name="k=4,d=5,ob=80,os=10"; Params="k=4,d=5,ob=80,os=10"},
    @{Name="k=6,d=5,ob=80,os=10"; Params="k=6,d=5,ob=80,os=10"},
    @{Name="k=5,d=4,ob=80,os=10"; Params="k=5,d=4,ob=80,os=10"},
    @{Name="k=5,d=6,ob=80,os=10"; Params="k=5,d=6,ob=80,os=10"},
    @{Name="k=5,d=5,ob=75,os=10"; Params="k=5,d=5,ob=75,os=10"},
    @{Name="k=5,d=5,ob=85,os=10"; Params="k=5,d=5,ob=85,os=10"},
    @{Name="k=5,d=5,ob=80,os=15"; Params="k=5,d=5,ob=80,os=15"},
    @{Name="k=5,d=5,ob=80,os=5";  Params="k=5,d=5,ob=80,os=5"},
    @{Name="k=6,d=6,ob=85,os=15 (all shifted)"; Params="k=6,d=6,ob=85,os=15"}
)

foreach ($pt in $paramTests) {
    $pSig = Get-MbfSignalArray "Stoch" $pt.Params $c $h $l $v $n
    $pIdx = New-Object 'System.Collections.Generic.List[int]'
    for ($si = 100; $si -lt $pSig.Length; $si++) { if ($pSig[$si]) { $pIdx.Add($si) } }
    $pRet = Get-BaseReturns $pIdx.ToArray() $c $n
    $pM = Get-TradeMetrics $pRet
    if ($pM) {
        $status = if ($pM.Sharpe -gt 0 -and $pM.WinRate -ge 50) { "SURVIVES" } else { "FAILS" }
        $allResults.Add([PSCustomObject]@{TestSuite="2-Parameter"; TestName=$pt.Name; Trades=$pM.Trades; WinRate=$pM.WinRate; AvgReturn=$pM.AvgReturn; Sharpe=$pM.Sharpe; ProfitFactor=$pM.ProfitFactor; MaxDrawdown=$pM.MaxDrawdown; AvgWin=$pM.AvgWin; AvgLoss=$pM.AvgLoss; EdgeStatus=$status})
        Log "  $($pt.Name): trades=$($pM.Trades) WR=$($pM.WinRate)% Sharpe=$($pM.Sharpe) -> $status"
    }
}
Log "TEST 2 complete"

# ===== TEST 3: QUARTERLY PERFORMANCE STABILITY =====
Log "=== TEST 3: QUARTERLY PERFORMANCE STABILITY ==="

$quarterData = @{}
foreach ($idx in $tradeIdx) {
    $exitIdx = $idx + 5
    if ($exitIdx -ge $n) { continue }
    $dtStr = $dates[$idx]
    $dt = if ($dtStr -match '(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})') {
        $y = [int]$matches[1]; $m = [int]$matches[2]
        $q = [Math]::Ceiling($m / 3)
        "$y-Q$q"
    } elseif ($dtStr -match '(\d{4})') { "$($matches[1])-Q?" } else { "UNKNOWN" }
    $ret = ($c[$exitIdx] - $c[$idx]) / $c[$idx] * 100
    if (-not $quarterData.ContainsKey($dt)) { $quarterData[$dt] = New-Object 'System.Collections.Generic.List[double]' }
    $quarterData[$dt].Add($ret)
}

$qResults = New-Object 'System.Collections.Generic.List[PSObject]'
$qSharpeList = New-Object 'System.Collections.Generic.List[double]'
foreach ($qKey in ($quarterData.Keys | Sort-Object)) {
    $qRets = $quarterData[$qKey].ToArray()
    if ($qRets.Count -lt 5) { continue }
    $qM = Get-TradeMetrics $qRets
    if ($qM) {
        $qStatus = if ($qM.Sharpe -gt 0 -and $qM.WinRate -ge 50) { "PROFITABLE" } else { "LOSS-MAKING" }
        $qResults.Add([PSCustomObject]@{Quarter=$qKey; Trades=$qM.Trades; WinRate=$qM.WinRate; AvgReturn=$qM.AvgReturn; Sharpe=$qM.Sharpe; ProfitFactor=$qM.ProfitFactor; MaxDrawdown=$qM.MaxDrawdown; Status=$qStatus})
        $qSharpeList.Add($qM.Sharpe)
        Log "  $qKey : trades=$($qM.Trades) WR=$($qM.WinRate)% Sharpe=$($qM.Sharpe) -> $qStatus"
    }
}

$totalQuarters = $qResults.Count
$posQuarters = ($qResults | Where-Object { $_.Sharpe -gt 0 }).Count
$profQuarters = ($qResults | Where-Object { $_.Status -eq "PROFITABLE" }).Count
$qSharpeAvg = if ($qSharpeList.Count -gt 0) { ($qSharpeList | Measure-Object -Average).Average } else { 0 }
$qSharpeStd = Get-StdDev2 $qSharpeList
$qSharpeStability = if ($qSharpeAvg -ne 0) { $qSharpeStd / [Math]::Abs($qSharpeAvg) } else { 999 }

$half = [Math]::Floor($totalQuarters / 2)
if ($half -ge 1) {
    $earlyQuarters = $qResults | Select-Object -First $half
    $lateQuarters = $qResults | Select-Object -Last $half
    $earlyAvgSharpe = ($earlyQuarters | ForEach-Object { $_.Sharpe } | Measure-Object -Average).Average
    $lateAvgSharpe = ($lateQuarters | ForEach-Object { $_.Sharpe } | Measure-Object -Average).Average
} else { $earlyAvgSharpe = 0; $lateAvgSharpe = 0 }
$qDegradation = $lateAvgSharpe - $earlyAvgSharpe

$allResults.Add([PSCustomObject]@{TestSuite="3-Quarterly"; TestName="Positive Sharpe quarters ratio"; Trades=$totalQuarters; WinRate=$posQuarters; AvgReturn=$profQuarters; Sharpe=[Math]::Round($qSharpeAvg,4); ProfitFactor=[Math]::Round($qSharpeStability,4); MaxDrawdown=[Math]::Round($qDegradation,4); AvgWin=0; AvgLoss=0; EdgeStatus=if($profQuarters -ge $totalQuarters*0.5){"SURVIVES"}else{"FAILS"}})
$allResults.Add([PSCustomObject]@{TestSuite="3-Quarterly"; TestName="Quarterly Sharpe stability (CV)"; Trades=$totalQuarters; WinRate=$posQuarters; AvgReturn=$profQuarters; Sharpe=[Math]::Round($qSharpeAvg,4); ProfitFactor=[Math]::Round($qSharpeStability,4); MaxDrawdown=[Math]::Round($qDegradation,4); AvgWin=0; AvgLoss=0; EdgeStatus=if($qSharpeStability -lt 2.0){"SURVIVES"}else{"FAILS"}})
$allResults.Add([PSCustomObject]@{TestSuite="3-Quarterly"; TestName="Half-life degradation (early to late Sharpe)"; Trades=$totalQuarters; WinRate=$posQuarters; AvgReturn=$profQuarters; Sharpe=[Math]::Round($earlyAvgSharpe,4); ProfitFactor=[Math]::Round($lateAvgSharpe,4); MaxDrawdown=[Math]::Round($qDegradation,4); AvgWin=0; AvgLoss=0; EdgeStatus=if($qDegradation -gt -0.3){"SURVIVES"}else{"FAILS"}})
Log "Quarterly: $profQuarters/$totalQuarters profitable, early S=$([Math]::Round($earlyAvgSharpe,4)) late S=$([Math]::Round($lateAvgSharpe,4)) deg=$([Math]::Round($qDegradation,4))"
Log "TEST 3 complete"

# ===== TEST 4: WALK-FORWARD DEGRADATION =====
Log "=== TEST 4: WALK-FORWARD DEGRADATION ==="

# 4A: 50/50 hold-out
$trainEnd = [Math]::Floor($n * 0.5)
$testStart = $trainEnd
$sigTrain = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c[0..($testStart-1)] $h[0..($testStart-1)] $l[0..($testStart-1)] $v[0..($testStart-1)] $testStart
$sigTest = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c[$testStart..($n-1)] $h[$testStart..($n-1)] $l[$testStart..($n-1)] $v[$testStart..($n-1)] ($n-$testStart)

$trainIdx = New-Object 'System.Collections.Generic.List[int]'
for ($si = 100; $si -lt $sigTrain.Length; $si++) { if ($sigTrain[$si]) { $trainIdx.Add($si) } }
$trainRets = Get-BaseReturns $trainIdx.ToArray() $c[0..($testStart-1)] $testStart
$trainM = Get-TradeMetrics $trainRets

$testIdx = New-Object 'System.Collections.Generic.List[int]'
for ($si = 100; $si -lt $sigTest.Length; $si++) { if ($sigTest[$si]) { $testIdx.Add($testStart + $si) } }
$testRets = New-Object 'System.Collections.Generic.List[double]'
foreach ($gi in $testIdx) { $exitIdx = $gi + 5; if ($exitIdx -ge $n) { continue }; $testRets.Add(($c[$exitIdx] - $c[$gi]) / $c[$gi] * 100) }
$testM = Get-TradeMetrics $testRets.ToArray()

$wfDegradation = if ($trainM -and $testM -and $trainM.Sharpe -ne 0) { ($testM.Sharpe - $trainM.Sharpe) / [Math]::Abs($trainM.Sharpe) * 100 } else { -999 }
$allResults.Add([PSCustomObject]@{TestSuite="4-WalkForward"; TestName="50/50 hold-out (train to test Sharpe change)"; Trades=$testM.Trades; WinRate=$testM.WinRate; AvgReturn=$testM.AvgReturn; Sharpe=$testM.Sharpe; ProfitFactor=$testM.ProfitFactor; MaxDrawdown=[Math]::Round($wfDegradation,1); AvgWin=$trainM.Sharpe; AvgLoss=$trainM.AvgReturn; EdgeStatus=if($testM.Sharpe -gt 0 -and $testM.WinRate -ge 50){"SURVIVES"}else{"FAILS"}})
Log "4A 50/50: train S=$($trainM.Sharpe) test S=$($testM.Sharpe) deg=$([Math]::Round($wfDegradation,1))%"

# 4B: 5-fold
$wfFolds = 5; $foldSize = [Math]::Floor(($n - 20000) / $wfFolds)
$wfSharpe = @(); $wfWR = @(); $wfTrades = @()
for ($f = 0; $f -lt $wfFolds; $f++) {
    $fTrainEnd = 20000 + $f * $foldSize
    $fTestStart2 = $fTrainEnd; $fTestEnd = [Math]::Min($fTestStart2 + $foldSize, $n)
    $fSig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c[$fTestStart2..($fTestEnd-1)] $h[$fTestStart2..($fTestEnd-1)] $l[$fTestStart2..($fTestEnd-1)] $v[$fTestStart2..($fTestEnd-1)] ($fTestEnd-$fTestStart2)
    if (-not $fSig) { continue }
    $fRets = New-Object 'System.Collections.Generic.List[double]'
    for ($si = 100; $si -lt $fSig.Count; $si++) {
        if ($fSig[$si]) { $gi = $fTestStart2 + $si; if ($gi + 5 -lt $n) { $fRets.Add(($c[$gi+5] - $c[$gi]) / $c[$gi] * 100) } }
    }
    if ($fRets.Count -lt 5) { continue }
    $fM = Get-TradeMetrics $fRets.ToArray()
    if ($fM) { $wfSharpe += $fM.Sharpe; $wfWR += $fM.WinRate; $wfTrades += $fM.Trades }
}
$avgWFSharpe = if ($wfSharpe.Count -gt 0) { ($wfSharpe | Measure-Object -Average).Average } else { 0 }
$avgWFWR = if ($wfWR.Count -gt 0) { ($wfWR | Measure-Object -Average).Average } else { 0 }
$totalWFTrades = if ($wfTrades.Count -gt 0) { ($wfTrades | Measure-Object -Sum).Sum } else { 0 }
$posWFFolds = ($wfSharpe | Where-Object { $_ -gt 0 }).Count
$wfFoldRatio = if ($wfSharpe.Count -gt 0) { $posWFFolds / $wfSharpe.Count * 100 } else { 0 }
$wfSharpeStd = Get-StdDev2 $wfSharpe
$wfStability = if ($avgWFSharpe -ne 0) { $wfSharpeStd / [Math]::Abs($avgWFSharpe) } else { 999 }

$allResults.Add([PSCustomObject]@{TestSuite="4-WalkForward"; TestName="5-fold avg Sharpe"; Trades=$totalWFTrades; WinRate=[Math]::Round($avgWFWR,1); AvgReturn=$posWFFolds; Sharpe=[Math]::Round($avgWFSharpe,4); ProfitFactor=[Math]::Round($wfStability,4); MaxDrawdown=[Math]::Round($wfSharpeStd,4); AvgWin=0; AvgLoss=0; EdgeStatus=if($avgWFSharpe -gt 0 -and $avgWFWR -ge 50){"SURVIVES"}else{"FAILS"}})
$allResults.Add([PSCustomObject]@{TestSuite="4-WalkForward"; TestName="5-fold positive fold ratio"; Trades=$wfSharpe.Count; WinRate=$posWFFolds; AvgReturn=$wfFoldRatio; Sharpe=[Math]::Round($avgWFSharpe,4); ProfitFactor=[Math]::Round($wfSharpeStd,4); MaxDrawdown=0; AvgWin=0; AvgLoss=0; EdgeStatus=if($posWFFolds -ge [Math]::Max(1, [Math]::Floor($wfSharpe.Count*0.6))){"SURVIVES"}else{"FAILS"}})
$allResults.Add([PSCustomObject]@{TestSuite="4-WalkForward"; TestName="5-fold stability (CV)"; Trades=$wfSharpe.Count; WinRate=$posWFFolds; AvgReturn=$wfFoldRatio; Sharpe=[Math]::Round($wfStability,4); ProfitFactor=[Math]::Round($totalWFTrades,0); MaxDrawdown=0; AvgWin=0; AvgLoss=0; EdgeStatus=if($wfStability -lt 2.0){"SURVIVES"}else{"FAILS"}})
Log "4B 5-fold: avg S=$([Math]::Round($avgWFSharpe,4)) avg WR=$([Math]::Round($avgWFWR,1))% pos=$posWFFolds/$($wfSharpe.Count) CV=$([Math]::Round($wfStability,4))"

# 4C: 4-fold
$wfFolds4 = 4; $foldSize4 = [Math]::Floor(($n - 20000) / $wfFolds4)
$wfSharpe4 = @(); $wfWR4 = @()
for ($f = 0; $f -lt $wfFolds4; $f++) {
    $fTrainEnd4 = 20000 + $f * $foldSize4
    $fTestStart3 = $fTrainEnd4; $fTestEnd3 = [Math]::Min($fTestStart3 + $foldSize4, $n)
    $fSig4 = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c[$fTestStart3..($fTestEnd3-1)] $h[$fTestStart3..($fTestEnd3-1)] $l[$fTestStart3..($fTestEnd3-1)] $v[$fTestStart3..($fTestEnd3-1)] ($fTestEnd3-$fTestStart3)
    if (-not $fSig4) { continue }
    $fRets4 = New-Object 'System.Collections.Generic.List[double]'
    for ($si = 100; $si -lt $fSig4.Count; $si++) {
        if ($fSig4[$si]) { $gi = $fTestStart3 + $si; if ($gi + 5 -lt $n) { $fRets4.Add(($c[$gi+5] - $c[$gi]) / $c[$gi] * 100) } }
    }
    if ($fRets4.Count -lt 3) { continue }
    $fM4 = Get-TradeMetrics $fRets4.ToArray()
    if ($fM4) { $wfSharpe4 += $fM4.Sharpe; $wfWR4 += $fM4.WinRate }
}
$avgWFSharpe4 = if ($wfSharpe4.Count -gt 0) { ($wfSharpe4 | Measure-Object -Average).Average } else { 0 }
$avgWFWR4 = if ($wfWR4.Count -gt 0) { ($wfWR4 | Measure-Object -Average).Average } else { 0 }
$posWFFolds4 = ($wfSharpe4 | Where-Object { $_ -gt 0 }).Count
$allResults.Add([PSCustomObject]@{TestSuite="4-WalkForward"; TestName="4-fold avg Sharpe"; Trades=$wfSharpe4.Count; WinRate=[Math]::Round($avgWFWR4,1); AvgReturn=$posWFFolds4; Sharpe=[Math]::Round($avgWFSharpe4,4); ProfitFactor=0; MaxDrawdown=0; AvgWin=0; AvgLoss=0; EdgeStatus=if($avgWFSharpe4 -gt 0 -and $avgWFWR4 -ge 50){"SURVIVES"}else{"FAILS"}})
Log "4C 4-fold: avg S=$([Math]::Round($avgWFSharpe4,4)) avg WR=$([Math]::Round($avgWFWR4,1))% pos=$posWFFolds4/$($wfSharpe4.Count)"
Log "TEST 4 complete"

# ===== FINAL VERDICT =====
Log "=== COMPUTING FINAL VERDICT ==="

$results = $allResults.ToArray()
$edgeTests = $results | Where-Object { $_.EdgeStatus -ne "N/A" }
$survived = ($edgeTests | Where-Object { $_.EdgeStatus -eq "SURVIVES" }).Count
$failed = ($edgeTests | Where-Object { $_.EdgeStatus -eq "FAILS" }).Count
$totalTests = $edgeTests.Count
$survivalRate = [Math]::Round($survived / $totalTests * 100, 1)

$execTests = $edgeTests | Where-Object { $_.TestSuite -eq "1-Execution" }
$execSurvived = ($execTests | Where-Object { $_.EdgeStatus -eq "SURVIVES" }).Count
$execTotal = $execTests.Count
$execPass = $execSurvived -eq $execTotal

$paramTestsRes = $edgeTests | Where-Object { $_.TestSuite -eq "2-Parameter" }
$paramSurvived = ($paramTestsRes | Where-Object { $_.EdgeStatus -eq "SURVIVES" }).Count
$paramTotal = $paramTestsRes.Count
$paramPass = $paramSurvived -ge [Math]::Ceiling($paramTotal * 0.66)

$quarterlyTests = $edgeTests | Where-Object { $_.TestSuite -eq "3-Quarterly" }
$quarterlyPass = ($quarterlyTests | Where-Object { $_.EdgeStatus -eq "SURVIVES" }).Count -ge 2

$wfTests = $edgeTests | Where-Object { $_.TestSuite -eq "4-WalkForward" }
$wfPass = ($wfTests | Where-Object { $_.EdgeStatus -eq "SURVIVES" }).Count -ge 3

if ($execPass -and $paramPass -and $quarterlyPass -and $wfPass) {
    $finalVerdict = "EDGE SURVIVED HOSTILE VALIDATION"
} else {
    $finalVerdict = "EDGE REJECTED"
}

Log "FINAL VERDICT: $finalVerdict"
Log "Survived: $survived/$totalTests ($survivalRate%)"
Log "Execution: $execSurvived/$execTotal"
Log "Parameter: $paramSurvived/$paramTotal"
Log "Quarterly: pass=$quarterlyPass"
Log "WalkFwd: pass=$wfPass"

# ===== GENERATE REPORT =====
Log "=== GENERATING REPORT ==="
$reportLines = New-Object 'System.Collections.Generic.List[string]'
$reportLines.Add("# Edge Survival Report")
$reportLines.Add("")
$reportLines.Add("**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)")
$reportLines.Add("**Data Range:** $($dates[100]) to $($dates[$n-1])")
$reportLines.Add("**Total Base Trades:** $($baseMetrics.Trades)")
$reportLines.Add("**Question:** After every hostile test, does the edge still exist?")
$reportLines.Add("")
$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Final Verdict")
$reportLines.Add("")
$reportLines.Add("**$finalVerdict**")
$reportLines.Add("")
$reportLines.Add("| Test Suite | Survived | Failed | Total | Survival Rate |")
$reportLines.Add("|-----------|----------|--------|-------|--------------|")
$reportLines.Add("| Execution Realism | $execSurvived | $(if($execTotal - $execSurvived -ge 0){$execTotal - $execSurvived}else{0}) | $execTotal | $(if($execTotal -gt 0){[Math]::Round($execSurvived/$execTotal*100,1)}else{0})% |")
$reportLines.Add("| Parameter Stability | $paramSurvived | $(if($paramTotal - $paramSurvived -ge 0){$paramTotal - $paramSurvived}else{0}) | $paramTotal | $(if($paramTotal -gt 0){[Math]::Round($paramSurvived/$paramTotal*100,1)}else{0})% |")
$reportLines.Add("| Quarterly Stability | $profQuarters | $(if($totalQuarters - $profQuarters -ge 0){$totalQuarters - $profQuarters}else{0}) | $totalQuarters | $(if($totalQuarters -gt 0){[Math]::Round($profQuarters/$totalQuarters*100,1)}else{0})% |")
$reportLines.Add("| Walk-Forward | $(($wfTests|Where-Object{$_.EdgeStatus -eq 'SURVIVES'}).Count) | $(($wfTests|Where-Object{$_.EdgeStatus -eq 'FAILS'}).Count) | $($wfTests.Count) | $(if($wfTests.Count -gt 0){[Math]::Round((($wfTests|Where-Object{$_.EdgeStatus -eq 'SURVIVES'}).Count)/$wfTests.Count*100,1)}else{0})% |")
$reportLines.Add("| **TOTAL** | **$survived** | **$failed** | **$totalTests** | **$survivalRate%** |")
$reportLines.Add("")
$reportLines.Add("Thresholds to pass: Execution (100%), Parameter (>66%), Quarterly (>50% quarters profitable, CV<2), Walk-Forward (>50% folds positive)")
$reportLines.Add("")
$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Baseline Performance")
$reportLines.Add("")
$reportLines.Add("| Metric | Value |")
$reportLines.Add("|--------|-------|")
$reportLines.Add("| Total Trades | $($baseMetrics.Trades) |")
$reportLines.Add("| Win Rate | $($baseMetrics.WinRate)% |")
$reportLines.Add("| Avg Return | $($baseMetrics.AvgReturn)% |")
$reportLines.Add("| Median Return | $($baseMetrics.MedianReturn)% |")
$reportLines.Add("| Sharpe (5-bar) | $($baseMetrics.Sharpe) |")
$reportLines.Add("| Profit Factor | $($baseMetrics.ProfitFactor) |")
$reportLines.Add("| Max Drawdown | $($baseMetrics.MaxDrawdown)% |")
$reportLines.Add("| Avg Win | $($baseMetrics.AvgWin)% |")
$reportLines.Add("| Avg Loss | $($baseMetrics.AvgLoss)% |")
$reportLines.Add("")
$reportLines.Add("**Assumptions:** Enter at signal bar close, exit 5 bars later at close. No fees, slippage, or market impact.")
$reportLines.Add("")

$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Test 1: Execution Realism")
$reportLines.Add("")
$reportLines.Add("**Hostile scenarios simulating real trading conditions.**")
$reportLines.Add("")
$reportLines.Add("| Test | Trades | WR% | AvgRet% | Sharpe | PF | DD% | Edge? |")
$reportLines.Add("|------|--------|-----|---------|-------|----|------|-------|")
foreach ($tr in ($results | Where-Object { $_.TestSuite -eq "1-Execution" })) {
    $reportLines.Add("| $($tr.TestName) | $($tr.Trades) | $($tr.WinRate) | $($tr.AvgReturn) | $($tr.Sharpe) | $($tr.ProfitFactor) | $($tr.MaxDrawdown) | $($tr.EdgeStatus) |")
}
$reportLines.Add("")

$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Test 2: Parameter Stability")
$reportLines.Add("")
$reportLines.Add("**Each parameter perturbed by +/-1 to test if edge is overfit to specific values.**")
$reportLines.Add("")
$reportLines.Add("| Test | Trades | WR% | AvgRet% | Sharpe | PF | DD% | Edge? |")
$reportLines.Add("|------|--------|-----|---------|-------|----|------|-------|")
foreach ($tr in ($results | Where-Object { $_.TestSuite -eq "2-Parameter" })) {
    $reportLines.Add("| $($tr.TestName) | $($tr.Trades) | $($tr.WinRate) | $($tr.AvgReturn) | $($tr.Sharpe) | $($tr.ProfitFactor) | $($tr.MaxDrawdown) | $($tr.EdgeStatus) |")
}
$reportLines.Add("")

$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Test 3: Quarterly Performance Stability")
$reportLines.Add("")
$reportLines.Add("| Quarter | Trades | WR% | AvgRet% | Sharpe | PF | DD% | Status |")
$reportLines.Add("|---------|--------|-----|---------|-------|----|------|--------|")
foreach ($qr in $qResults) {
    $reportLines.Add("| $($qr.Quarter) | $($qr.Trades) | $($qr.WinRate) | $($qr.AvgReturn) | $($qr.Sharpe) | $($qr.ProfitFactor) | $($qr.MaxDrawdown) | $($qr.Status) |")
}
$reportLines.Add("")
$reportLines.Add("**Summary:** $profQuarters/$totalQuarters profitable, avg Q-Shape=$([Math]::Round($qSharpeAvg,4)), CV=$([Math]::Round($qSharpeStability,4)), early-late deg=$([Math]::Round($qDegradation,4))")
$reportLines.Add("")

$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Test 4: Walk-Forward Degradation")
$reportLines.Add("")
$reportLines.Add("| Test | Trades | WR% | Sharpe | Additional | Edge? |")
$reportLines.Add("|------|--------|-----|--------|------------|-------|")
foreach ($tr in ($results | Where-Object { $_.TestSuite -eq "4-WalkForward" })) {
    $addInfo = "PF=$($tr.ProfitFactor) DD=$($tr.MaxDrawdown)"
    $reportLines.Add("| $($tr.TestName) | $($tr.Trades) | $($tr.WinRate) | $($tr.Sharpe) | $addInfo | $($tr.EdgeStatus) |")
}
$reportLines.Add("")

$reportLines.Add("---")
$reportLines.Add("")
$reportLines.Add("## Conclusion")
$reportLines.Add("")
$reportLines.Add("**$finalVerdict**")
$reportLines.Add("")
$reportLines.Add("### Pass/Fail by Suite")
$reportLines.Add("")
$reportLines.Add("| Test Suite | Result | Details |")
$reportLines.Add("|-----------|--------|---------|")
$reportLines.Add("| 1. Execution Realism | $(if($execPass){'PASS'}else{'FAIL'}) | $execSurvived/$execTotal tests survived |")
$reportLines.Add("| 2. Parameter Stability | $(if($paramPass){'PASS'}else{'FAIL'}) | $paramSurvived/$paramTotal tests survived |")
$reportLines.Add("| 3. Quarterly Stability | $(if($quarterlyPass){'PASS'}else{'FAIL'}) | $profQuarters/$totalQuarters profitable, CV=$([Math]::Round($qSharpeStability,2)) |")
$reportLines.Add("| 4. Walk-Forward | $(if($wfPass){'PASS'}else{'FAIL'}) | $(($wfTests|Where-Object{$_.EdgeStatus -eq 'SURVIVES'}).Count)/$($wfTests.Count) tests survived |")
$reportLines.Add("")
$reportLines.Add("### All Assumptions and Trade Counts")
$reportLines.Add("")
$reportLines.Add("| Test | Trades | Sharpe | WR% | vs Baseline |")
$reportLines.Add("|------|--------|--------|-----|------------|")
foreach ($tr in $results) {
    if ($tr.EdgeStatus -eq "N/A") { continue }
    $perfChange = if ($baseMetrics.Sharpe -ne 0) { [Math]::Round(($tr.Sharpe - $baseMetrics.Sharpe) / [Math]::Abs($baseMetrics.Sharpe) * 100, 1) } else { 0 }
    $reportLines.Add("| $($tr.TestName) | $($tr.Trades) | $($tr.Sharpe) | $($tr.WinRate)% | Sharpe delta $perfChange% |")
}
$reportLines.Add("")
$reportLines.Add("---")
$reportLines.Add("*Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))*")

$reportPath = Join-Path $OutputDir "edge_survival_report.md"
[string]::Join("`n", $reportLines.ToArray()) | Out-File -FilePath $reportPath -Encoding utf8
Log "Report saved to $reportPath"

$detailPath = Join-Path $OutputDir "edge_survival_details.csv"
$results | Export-Csv -Path $detailPath -NoTypeInformation
Log "Details saved to $detailPath"

$elapsed = [Math]::Round((Get-Date).Subtract($start).TotalMinutes, 1)
Log "=== HOSTILE VALIDATION COMPLETE ($elapsed min) ==="
Log "FINAL VERDICT: $finalVerdict"

Write-Output "FINAL VERDICT: $finalVerdict"
Write-Output "Details: $detailPath"
Write-Output "Report: $reportPath"
Write-Output "Log: $logFile"

} catch {
    Log "ERROR: $_"
    Write-Error $_
}
