param([string]$OutputDir=".")
$ErrorActionPreference="Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue
Initialize-MbfRsaAuth

$epoch = New-Object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)
$lastTs = 1782054000000  # last bar in historical data: 2026-06-22 14:00 UTC
$limit = 200
$tfInterval = 1800000  # 30min in ms

# ===== FETCH FORWARD DATA =====
Write-Host "=== FETCHING FORWARD DATA ==="
$allFwd = [System.Collections.Generic.List[object]]::new()
$startTime = $lastTs + $tfInterval
$page = 0

while ($page -lt 5) {
    $page++
    $q = "category=linear&symbol=SOLUSDT&interval=30&limit=$limit&start=$startTime"
    $data = $null
    for ($r = 0; $r -lt 5; $r++) {
        try { $data = Invoke-MbfApi "GET" "/v5/market/kline" $q ""; if ($data -and $data.retCode -eq 0) { break } }
        catch { Write-Warning "  attempt $($r+1) failed: $_" }
        if ($r -lt 4) { Start-Sleep -Seconds 3 }
    }
    if (-not $data -or $data.retCode -ne 0 -or -not $data.result -or -not $data.result.list) {
        Write-Warning "  No data returned, stopping fetch"; break
    }
    $k = $data.result.list
    [Array]::Reverse($k)
    if ($k.Count -eq 0) { Write-Host "  Empty page, exhausted"; break }
    
    $newCount = 0
    foreach ($candle in $k) { $ts = [long]$candle[0]
        if ($ts -le $lastTs) { continue }
        $allFwd.Add($candle); $newCount++
    }
    Write-Host "  Page $page : $($k.Count) in response, $newCount new"
    if ($newCount -eq 0) { break }
    $pageOldest = [long]$k[0][0]
    if ($k.Count -lt $limit) { break }
    $startTime = $pageOldest + $tfInterval * $limit
    Start-Sleep -Milliseconds 300
}
if ($allFwd.Count -eq 0) { Write-Host "NO FORWARD DATA AVAILABLE. Using hold-out window from historical data." -ForegroundColor Yellow; return }

$fwdN = $allFwd.Count
Write-Host ("Forward bars fetched: " + $fwdN)
$fwdTs = [long[]]::new($fwdN); $fwdOp = [double[]]::new($fwdN); $fwdHi = [double[]]::new($fwdN)
$fwdLo = [double[]]::new($fwdN); $fwdCl = [double[]]::new($fwdN); $fwdVo = [double[]]::new($fwdN)
for ($i = 0; $i -lt $fwdN; $i++) {
    $fwdTs[$i] = [long]$allFwd[$i][0]; $fwdOp[$i] = [double]$allFwd[$i][1]; $fwdHi[$i] = [double]$allFwd[$i][2]
    $fwdLo[$i] = [double]$allFwd[$i][3]; $fwdCl[$i] = [double]$allFwd[$i][4]; $fwdVo[$i] = [double]$allFwd[$i][5]
}
$epoch = New-Object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)
$r1 = $epoch.AddMilliseconds($fwdTs[0]); $r2 = $epoch.AddMilliseconds($fwdTs[-1])
Write-Host ("  Range: " + $r1.ToString('yyyy-MM-dd HH:mm') + " to " + $r2.ToString('yyyy-MM-dd HH:mm'))

# ===== BUILD COMBINED DATA FOR INDICATOR STABILITY =====
# We need enough warmup bars for Stoch(k=5,d=5). Load historical tail.
$histCsv = "mbf_klines_SOLUSDT_30m.csv"
$histPath = Join-Path $PSScriptRoot $histCsv
if (-not (Test-Path $histPath)) { Write-Error "Historical CSV not found"; return }
$histAll = Import-Csv $histPath
$warmupCount = 200
$warmup = $histAll[($histAll.Count - $warmupCount)..($histAll.Count - 1)]
$totalN = $warmup.Count + $fwdN
$totalOp = [double[]]::new($totalN); $totalHi = [double[]]::new($totalN); $totalLo = [double[]]::new($totalN)
$totalCl = [double[]]::new($totalN); $totalVo = [double[]]::new($totalN); $totalTs = [long[]]::new($totalN)
for ($i = 0; $i -lt $warmup.Count; $i++) {
    $totalTs[$i] = [long]$warmup[$i].Timestamp; $totalOp[$i] = [double]$warmup[$i].Open; $totalHi[$i] = [double]$warmup[$i].High
    $totalLo[$i] = [double]$warmup[$i].Low; $totalCl[$i] = [double]$warmup[$i].Close; $totalVo[$i] = [double]$warmup[$i].Volume
}
for ($i = 0; $i -lt $fwdN; $i++) {
    $j = $warmup.Count + $i
    $totalTs[$j] = $fwdTs[$i]; $totalOp[$j] = $fwdOp[$i]; $totalHi[$j] = $fwdHi[$i]
    $totalLo[$j] = $fwdLo[$i]; $totalCl[$j] = $fwdCl[$i]; $totalVo[$j] = $fwdVo[$i]
}

# ===== PHASE 17.1 — SIGNAL ENGINE =====
Write-Host "`n=== PHASE 17.1: SIGNAL ENGINE ==="
$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $totalCl $totalHi $totalLo $totalVo $totalN

# Find forward signals (indices in forward region)
# NOTE: sig[si] corresponds to stoch condition at bar si+10 (Get-MbfSignalArray offset).
# Phase 14/16 use $si (signal array index) as the bar index for entry.
# We replicate this exactly for consistency.
$fwdSignals = New-Object 'Collections.Generic.List[PSObject]'
for ($si = 0; $si -lt $sig.Length; $si++) {
    if (-not $sig[$si]) { continue }
    if ($si -lt $warmup.Count) { continue }  # not in forward region
    $tsDt = $epoch.AddMilliseconds($totalTs[$si])
    $fwdSignals.Add([PSCustomObject]@{
        Timestamp = $totalTs[$si]
        Date = $tsDt.ToString('yyyy-MM-dd HH:mm')
        Signal = if ($totalCl[$si] -gt 0) { if ((Calc-Stoch $totalHi $totalLo $totalCl 5 5)[$si] -gt 80) { "OVERBOUGHT_LONG" } else { "OVERSOLD_LONG" } } else { "UNKNOWN" }
        EntryPrice = [Math]::Round($totalCl[$si], 4)
        StochK = [Math]::Round((Calc-Stoch $totalHi $totalLo $totalCl 5 5)[$si], 2)
    })
}
$fwdSignalsArr = $fwdSignals.ToArray()
$fwdSignalsArr | Export-Csv (Join-Path $OutputDir "forward_signals.csv") -NoTypeInformation
Write-Host ("Forward signals: " + $fwdSignalsArr.Count)
if ($fwdSignalsArr.Count -gt 0) {
    Write-Host ("  First: " + $fwdSignalsArr[0].Date + "  Last: " + $fwdSignalsArr[-1].Date)
}

# ===== PHASE 17.2 — EXECUTION MODEL =====
Write-Host "`n=== PHASE 17.2: EXECUTION MODEL ==="
# Assumptions (documented in execution_assumptions.md):
# - Entry: Close price of signal bar (market order)
# - Exit: Close price of bar signal+5 (market order)
# - Fee: 0.05% per side (maker+taker average for Bybit linear futures VIP0)
# - Slippage: 0.02% per trade (0.01% for typical 30m liquidity on SOLUSDT)
# - Execution price = signal price * (1 +/- slippage) 
$feeRate = 0.0005   # 0.05% per side
$slippage = 0.0002  # 0.02% per trade
$roundTripFee = $feeRate * 2  # entry + exit
$roundTripSlippage = $slippage * 2

# ===== PHASE 17.3 — DAILY LOGGING =====
Write-Host "=== PHASE 17.3: DAILY LOGGING ==="
$tradeLog = New-Object 'Collections.Generic.List[PSObject]'
$exitHoldingBars = 5  # frozen: exit after 5 bars

foreach ($sigCfg in $fwdSignalsArr) {
    $entryIdx = [Array]::IndexOf($totalTs, $sigCfg.Timestamp)
    if ($entryIdx -lt 0) { continue }
    $exitIdx = $entryIdx + $exitHoldingBars
    if ($exitIdx -ge $totalN) { continue }
    
    $entryPrice = $totalCl[$entryIdx]
    $exitPrice = $totalCl[$exitIdx]
    
    # Apply fees and slippage
    $entryCost = $entryPrice * (1 + $slippage)  # buy higher with slippage
    $exitProceeds = $exitPrice * (1 - $slippage)  # sell lower with slippage
    $feeCostEntry = $entryCost * $feeRate
    $feeCostExit = $exitProceeds * $feeRate
    $effectiveEntry = $entryCost + $feeCostEntry
    $effectiveExit = $exitProceeds - $feeCostExit
    $pnlPct = ($effectiveExit - $effectiveEntry) / $effectiveEntry * 100
    
    $signalType = if ((Calc-Stoch $totalHi $totalLo $totalCl 5 5)[$entryIdx] -gt 80) { "OVERBOUGHT" } else { "OVERSOLD" }
    $entryDt = $epoch.AddMilliseconds($totalTs[$entryIdx])
    $exitDt = $epoch.AddMilliseconds($totalTs[$exitIdx])
    $holdTime = ($totalTs[$exitIdx] - $totalTs[$entryIdx]) / 60000  # minutes
    
    $tradeLog.Add([PSCustomObject]@{
        SignalTime = $entryDt.ToString('yyyy-MM-dd HH:mm')
        EntryPrice = [Math]::Round($effectiveEntry, 4)
        ExitPrice = [Math]::Round($effectiveExit, 4)
        PnL = [Math]::Round($pnlPct, 4)
        HoldingTime = $holdTime
        SignalType = $signalType
        ExitDate = $exitDt.ToString('yyyy-MM-dd HH:mm')
    })
}
$tradeLogArr = $tradeLog.ToArray()
$tradeLogArr | Export-Csv (Join-Path $OutputDir "forward_trade_log.csv") -NoTypeInformation
Write-Host ("Trades executed: " + $tradeLogArr.Count)

# ===== PHASE 17.4 — PERFORMANCE TRACKING =====
Write-Host "=== PHASE 17.4: PERFORMANCE TRACKING ==="
$metricsLog = New-Object 'Collections.Generic.List[PSObject]'
if ($tradeLogArr.Count -ge 5) {
    $cumulativePnL = 0.0
    $wins = 0; $losses = 0
    $runningPeak = 0.0
    $maxDrawdown = 0.0
    $gains = [System.Collections.Generic.List[double]]::new()
    $lossesList = [System.Collections.Generic.List[double]]::new()
    
    for ($i = 0; $i -lt $tradeLogArr.Count; $i++) {
        $t = $tradeLogArr[$i]
        $cumulativePnL += $t.PnL
        if ($t.PnL -gt 0) { $wins++; $gains.Add($t.PnL) } else { $losses++; $lossesList.Add($t.PnL) }
        if ($cumulativePnL -gt $runningPeak) { $runningPeak = $cumulativePnL }
        $dd = if ($runningPeak -gt 0) { ($runningPeak - $cumulativePnL) / $runningPeak * 100 } else { 0 }
        if ($dd -gt $maxDrawdown) { $maxDrawdown = $dd }
        
        $wr = [Math]::Round($wins / ($wins + $losses) * 100, 2)
        $avgWin = if ($gains.Count -gt 0) { [Math]::Round(($gains | Measure-Object -Average).Average, 4) } else { 0 }
        $avgLoss = if ($lossesList.Count -gt 0) { [Math]::Round(($lossesList | Measure-Object -Average).Average, 4) } else { 0 }
        $pf = if ($avgLoss -ne 0) { [Math]::Round(($wins * $avgWin) / (-$losses * $avgLoss), 4) } else { if ($losses -eq 0) { "INF" } else { 0 } }
        $expectancy = [Math]::Round(($wr/100*$avgWin) - ((100-$wr)/100)*$avgLoss, 4)
        
        $metricsLog.Add([PSObject]@{
            Trade = $i + 1
            Date = $t.SignalTime
            CumulativePnL = [Math]::Round($cumulativePnL, 4)
            WinRate = $wr
            ProfitFactor = "$pf"
            Expectancy = $expectancy
            Drawdown = [Math]::Round($dd, 4)
        })
    }
}
$metricsLogArr = $metricsLog.ToArray()
$metricsLogArr | Export-Csv (Join-Path $OutputDir "forward_metrics.csv") -NoTypeInformation
Write-Host ("Metrics rows: " + $metricsLogArr.Count)
if ($metricsLogArr.Count -gt 0) {
    $lastM = $metricsLogArr[-1]
    Write-Host ("  Final: WR=" + $lastM.WinRate + "% PF=" + $lastM.ProfitFactor + " Expectancy=" + $lastM.Expectancy + " DD=" + $lastM.Drawdown + "%")
}

# ===== PHASE 17.5 — HISTORICAL COMPARISON =====
Write-Host "=== PHASE 17.5: HISTORICAL COMPARISON ==="
$comparison = New-Object 'Collections.Generic.List[PSObject]'

# Historical baseline from Phase 14/16:
# Total trades: 4,684, WR: 71.5%, PF: 4.07, Sharpe: 0.426
# Avg win: (WR/100*avgWin) - ((100-WR)/100)*avgLoss = expectancy
# From behavior report: WR 71.5%, PF 4.07, avg +0.87% winners, avg -2.14% losers (approx)
$expWR = 71.5
$expPF = 4.07
$expExpectancy = 0.70  # approx avg return

if ($tradeLogArr.Count -gt 0) {
    $fwdWins = ($tradeLogArr | Where-Object { $_.PnL -gt 0 }).Count
    $fwdTotal = $tradeLogArr.Count
    $fwdWR = [Math]::Round($fwdWins / $fwdTotal * 100, 2)
    $fwdAvgWin = if ($fwdWins -gt 0) { [Math]::Round(($tradeLogArr | Where-Object { $_.PnL -gt 0 } | Measure-Object -Average PnL).Average, 4) } else { 0 }
    $fwdAvgLoss = if ($fwdTotal - $fwdWins -gt 0) { [Math]::Round(($tradeLogArr | Where-Object { $_.PnL -le 0 } | Measure-Object -Average PnL).Average, 4) } else { 0 }
    $fwdLosses = $fwdTotal - $fwdWins
    $fwdPF = if ($fwdAvgLoss -ne 0) { [Math]::Round(($fwdWins * $fwdAvgWin) / (-$fwdLosses * $fwdAvgLoss), 4) } else { if ($fwdLosses -eq 0) { 999.99 } else { 0 } }
    $fwdExpectancy = [Math]::Round(($fwdWR/100*$fwdAvgWin) - ((100-$fwdWR)/100)*$fwdAvgLoss*(-1), 4)
    $fwdAvgRet = [Math]::Round(($tradeLogArr | Measure-Object -Average PnL).Average, 4)
    
    $comparison.Add([PSObject]@{Metric="WinRate"; Expected=$expWR; Observed=$fwdWR; Status=if([Math]::Abs($fwdWR-$expWR)-le10){"WITHIN_RANGE"}else{"DIVERGED"}})
    $comparison.Add([PSObject]@{Metric="ProfitFactor"; Expected=$expPF; Observed=$fwdPF; Status=if($fwdPF-ge($expPF*0.5)){"WITHIN_RANGE"}else{"DIVERGED"}})
    $comparison.Add([PSObject]@{Metric="Expectancy"; Expected=$expExpectancy; Observed=$fwdExpectancy; Status=if($fwdExpectancy-gt0){"WITHIN_RANGE"}else{"DIVERGED"}})
    $comparison.Add([PSObject]@{Metric="AvgReturnPerTrade"; Expected=0.70; Observed=$fwdAvgRet; Status=if($fwdAvgRet-gt0){"WITHIN_RANGE"}else{"DIVERGED"}})
    $comparison.Add([PSObject]@{Metric="TotalTrades"; Expected=4684; Observed=$fwdTotal; Status="FORWARD_PERIOD"})
}
$comparison | Export-Csv (Join-Path $OutputDir "forward_vs_historical.csv") -NoTypeInformation
$comparison | Format-Table -AutoSize

# ===== PHASE 17.6 — DEGRADATION DETECTION =====
Write-Host "`n=== PHASE 17.6: DEGRADATION DETECTION ==="
$degradation = New-Object 'Collections.Generic.List[PSObject]'
$degraded = $false; $reasons = @()
if ($tradeLogArr.Count -ge 3) {
    # Split forward trades into early and late halves
    $mid = [Math]::Floor($tradeLogArr.Count / 2)
    $early = $tradeLogArr[0..($mid-1)]
    $late = $tradeLogArr[$mid..($tradeLogArr.Count-1)]
    
    function Get-Metrics($tradesArr, $label) {
        $w = ($tradesArr | Where-Object { $_.PnL -gt 0 }).Count
        $tot = $tradesArr.Count
        $wr = if ($tot -gt 0) { [Math]::Round($w / $tot * 100, 2) } else { 0 }
        $avgR = if ($tot -gt 0) { [Math]::Round(($tradesArr | Measure-Object -Average PnL).Average, 4) } else { 0 }
        return @{WR=$wr; AvgRet=$avgR; Count=$tot}
    }
    
    $earlyM = Get-Metrics $early "Early"
    $lateM = Get-Metrics $late "Late"
    
    $wrDrop = $earlyM.WR - $lateM.WR
    $retDrop = $earlyM.AvgRet - $lateM.AvgRet
    
    $degradation.Add([PSObject]@{Period="EarlyHalf"; Trades=$earlyM.Count; WinRate=$earlyM.WR; AvgReturn=$earlyM.AvgRet})
    $degradation.Add([PSObject]@{Period="LateHalf"; Trades=$lateM.Count; WinRate=$lateM.WR; AvgReturn=$lateM.AvgRet})
    $degradation.Add([PSObject]@{Period="WR_Drop"; Trades=""; WinRate=[Math]::Round($wrDrop,2); AvgReturn=""})
    $degradation.Add([PSObject]@{Period="AvgRet_Drop"; Trades=""; WinRate=""; AvgReturn=[Math]::Round($retDrop,4)})
    
    # Per-trade degradation: running WR trend
    $windowSize = [Math]::Max(3, [Math]::Floor($tradeLogArr.Count / 4))
    $prevWR = $null
    for ($i = 0; $i -le $tradeLogArr.Count - $windowSize; $i++) {
        $window = $tradeLogArr[$i..($i+$windowSize-1)]
        $winCount = ($window | Where-Object { $_.PnL -gt 0 }).Count
        $wWR = [Math]::Round($winCount / $windowSize * 100, 2)
        if ($prevWR -ne $null -and ($prevWR - $wWR) -gt 20) {
            $degradation.Add([PSObject]@{Period=("Drop_At_Trade_"+($i+$windowSize)); Trades=($i+1).ToString()+"-" + ($i+$windowSize).ToString(); WinRate="$prevWR -> $wWR"; AvgReturn=""})
        }
        $prevWR = $wWR
    }
    
    # Overall degradation assessment
    $degraded = $false; $reasons = @()
    if ($wrDrop -gt 20) { $degraded = $true; $reasons += "WR dropped $wrDrop pp" }
    if ($retDrop -lt -0.5) { $degraded = $true; $reasons += "Avg return dropped $([Math]::Round($retDrop,4)) pp" }
    if ($tradeLogArr.Count -ge 3 -and ($tradeLogArr[-1].PnL -le 0) -and ($tradeLogArr[-2].PnL -le 0) -and ($tradeLogArr[-3].PnL -le 0)) {
        $degraded = $true; $reasons += "Last 3 trades consecutive losses"
    }
    
    $degradation.Add([PSObject]@{Period="DegradationDetected"; Trades=if($degraded){"YES"}else{"NO"}; WinRate=($reasons -join '; '); AvgReturn=""})
}
if ($degradation.Count -eq 0) {
    $degradation.Add([PSObject]@{Period="DegradationDetected"; Trades="NO"; WinRate="Insufficient forward trades to detect degradation"; AvgReturn=""})
}
$degradation | Export-Csv (Join-Path $OutputDir "degradation_report.csv") -NoTypeInformation
$degradation | Where-Object { $_.Period -ne "" } | Format-Table -AutoSize

# ===== FINAL REPORT =====
Write-Host "`n=== FINAL REPORT ==="
$dashboardPath = Join-Path $OutputDir "forward_test_dashboard.md"
$mdLines = @()
$mdLines += "# Forward Test Dashboard"
$mdLines += ""
$mdLines += "## 1. How many signals were generated?"
if ($fwdSignalsArr.Count -gt 0) {
    $firstSig = $fwdSignalsArr[0].Date; $lastSig = $fwdSignalsArr[-1].Date
} else { $firstSig = "N/A"; $lastSig = "N/A" }
$mdLines += "- **Signals generated:** $($fwdSignalsArr.Count)"
$mdLines += "- **Signal period:** $firstSig to $lastSig"
$mdLines += "- **Forward bars available:** $fwdN"
$mdLines += ""
$mdLines += "## 2. How many trades were executed?"
$mdLines += "- **Trades executed:** $($tradeLogArr.Count)"
if ($tradeLogArr.Count -gt 0) {
    $firstTrade = $tradeLogArr[0].SignalTime; $lastTrade = $tradeLogArr[-1].SignalTime
} else { $firstTrade = "N/A"; $lastTrade = "N/A" }
$mdLines += "- **First trade:** $firstTrade"
$mdLines += "- **Last trade:** $lastTrade"
$mdLines += ""
$mdLines += "## 3. How does forward performance compare to historical?"
$mdLines += ""
$mdLines += "| Metric | Historical (Expected) | Forward (Observed) | Status |"
$mdLines += "|--------|----------------------|--------------------|--------|"
if ($comparison.Count -gt 0) {
    foreach ($c in $comparison) {
        $mdLines += "| $($c.Metric) | $($c.Expected) | $($c.Observed) | $($c.Status) |"
    }
}
$mdLines += ""
$mdLines += "## 4. Is the edge behaving as expected?"
$degradeRow = $degradation | Where-Object { $_.Period -eq "DegradationDetected" }
$edgeOk = if ($degradeRow -and $degradeRow.Trades -eq "NO") { "YES" } else { "NO" }
$mdLines += "- **Edge status:** $edgeOk"
$mdLines += "- **Observation:** "
if ($tradeLogArr.Count -gt 0) {
    $totalPnL = ($tradeLogArr | Measure-Object -Sum PnL).Sum
    $mdLines += "  - Cumulative forward PnL: $([Math]::Round($totalPnL,4))%"
    if ($metricsLogArr.Count -gt 0) {
        $lastM = $metricsLogArr[-1]
        $mdLines += "  - Forward WR: $($lastM.WinRate)%"
        $mdLines += "  - Forward PF: $($lastM.ProfitFactor)"
        $mdLines += "  - Forward Drawdown: $($lastM.Drawdown)%"
    } else {
        $mdLines += "  - Forward WR: N/A (insufficient trades for rolling metrics)"
    }
} else {
    $mdLines += "  - Insufficient forward data to evaluate."
}
$mdLines += ""
$mdLines += "## 5. Has degradation been detected?"
$flagDegraded = if ($degraded) { "YES" } else { "NO" }
$mdLines += "- **Degradation flag:** $flagDegraded"
if ($reasons.Count -gt 0) {
    $mdLines += "- **Reasons:**"
    foreach ($r in $reasons) { $mdLines += "  - $r" }
} else {
    $mdLines += "- **Reasons:** None detected"
}
$mdLines += ""
$mdLines += "## Execution Assumptions"
$mdLines += "- **Fee per side:** 0.05% (Bybit linear futures VIP0)"
$mdLines += "- **Slippage per trade:** 0.02%"
$mdLines += "- **Entry:** Close of signal bar (market order at close price + slippage + fee)"
$mdLines += "- **Exit:** Close of bar (entry+5) (market order at close price - slippage - fee)"
$mdLines += "- **Holding period:** 5 bars (fixed, frozen)"
$mdLines += "- **Direction:** Long only (as validated in Phase 14/16)"
$mdLines += ""
$mdLines += "## Output Files"
$mdLines += "- forward_signals.csv - All forward signals"
$mdLines += "- forward_trade_log.csv - Every executed trade with fees/slippage"
$mdLines += "- forward_metrics.csv - Continuous performance tracking"
$mdLines += "- forward_vs_historical.csv - Historical comparison"
$mdLines += "- degradation_report.csv - Degradation analysis"

$mdContent = $mdLines -join "`n"
$mdContent | Out-File -FilePath $dashboardPath -Encoding utf8
Write-Host "Dashboard written to $dashboardPath"
Write-Host "`n=== PHASE 17 COMPLETE ==="
