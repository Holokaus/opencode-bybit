param([string]$OutputDir=".")
$ErrorActionPreference="Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

Write-Host "=== PHASE 17 FORWARD TEST ===" -ForegroundColor Cyan

$k=Import-Csv (Join-Path $PSScriptRoot "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n=$k.Count
Write-Host ("Total bars: " + $n)

$hi=[double[]]::new($n);$lo=[double[]]::new($n);$cl=[double[]]::new($n);$vo=[double[]]::new($n);$op=[double[]]::new($n);$ts=[long[]]::new($n);$dt=New-Object 'string[]' $n
for($i=0;$i-lt$n;$i++){$hi[$i]=[double]$k[$i].High;$lo[$i]=[double]$k[$i].Low;$op[$i]=[double]$k[$i].Open;$cl[$i]=[double]$k[$i].Close;$vo[$i]=[double]$k[$i].Volume;$ts[$i]=[long]$k[$i].Timestamp;$dt[$i]=$k[$i].Date}
Remove-Variable k -ErrorAction SilentlyContinue

$split = $n - 10000
Write-Host ("Split: bars 0..$split historical, bars $($split+1)..$($n-1) forward")
$histEnd = $split - 1
$fwdStart = $split

Write-Host "`nGenerating signals..."
$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $cl $hi $lo $vo $n
Write-Host ("Signal array length: " + $sig.Length)

function Get-TradeResults($sig, $cl, $dates, $n, $startIdx, $endIdx, $label) {
    $trades = New-Object 'Collections.Generic.List[PSObject]'
    for ($si = $startIdx; $si -le $endIdx -and $si -lt $sig.Length; $si++) {
        if (-not $sig[$si]) { continue }
        $ex = $si + 5
        if ($ex -ge $n) { continue }
        
        $entryPrice = $cl[$si]; $exitPrice = $cl[$ex]
        $ret = ($exitPrice - $entryPrice) / $entryPrice * 100
        
        $feeRate = 0.0005; $slippage = 0.0002
        $effEntry = $entryPrice * (1 + $slippage) * (1 + $feeRate)
        $effExit = $exitPrice * (1 - $slippage) * (1 - $feeRate)
        $pnl = ($effExit - $effEntry) / $effEntry * 100
        
        $trade = [PSCustomObject]@{
            EntryIdx=$si; ExitIdx=$ex
            EntryDate=$dates[$si]; ExitDate=$dates[$ex]
            EntryPrice=[Math]::Round($entryPrice,4); ExitPrice=[Math]::Round($exitPrice,4)
            ReturnPct=[Math]::Round($ret,4); PnL=[Math]::Round($pnl,4)
        }
        $trades.Add($trade)
    }
    $tradesArr = $trades.ToArray()
    
    if ($tradesArr.Count -eq 0) {
        Write-Host ("$label : 0 trades") -ForegroundColor Yellow
        return @{Trades=@(); Count=0; WR=0; PF=0; AvgRet=0; Expectancy=0; MaxDD=0; Sharpe=0}
    }
    
    $win = ($tradesArr | Where-Object { $_.PnL -gt 0 }).Count
    $loss = $tradesArr.Count - $win
    $wr = [Math]::Round($win / $tradesArr.Count * 100, 2)
    
    $avgWin = if($win -gt 0) { ($tradesArr | Where-Object { $_.PnL -gt 0 } | Measure-Object -Average PnL).Average } else { 0 }
    $avgLoss = if($loss -gt 0) { ($tradesArr | Where-Object { $_.PnL -le 0 } | Measure-Object -Average PnL).Average } else { 0 }
    $pf = if($avgLoss -ne 0 -and $loss -gt 0) { [Math]::Round(($win * $avgWin) / (-$loss * $avgLoss), 4) } elseif($loss -eq 0) { 999.99 } else { 0 }
    $expectancy = [Math]::Round(($wr/100*$avgWin) - ((100-$wr)/100)*$avgLoss, 4)
    $avgRet = [Math]::Round(($tradesArr | Measure-Object -Average PnL).Average, 4)
    
    $cum = 0.0; $peak = 0.0; $maxDd = 0.0
    foreach ($t in $tradesArr) { $cum += $t.PnL; if ($cum -gt $peak) { $peak = $cum }; $dd = if ($peak -gt 0) { ($peak - $cum) / $peak * 100 } else { 0 }; if ($dd -gt $maxDd) { $maxDd = $dd } }
    
    if ($tradesArr.Count -gt 1) {
        $pnls = $tradesArr | ForEach-Object { $_.PnL }
        $avgP = ($pnls | Measure-Object -Average).Average
        $sumSq = 0.0; foreach ($p in $pnls) { $sumSq += ($p - $avgP) * ($p - $avgP) }
        $stdP = [Math]::Sqrt($sumSq / ($pnls.Count - 1))
        $sharpe = if ($stdP -gt 0) { [Math]::Round($avgP / $stdP * [Math]::Sqrt(252*48), 4) } else { 0 }
    } else { $sharpe = 0 }
    
    Write-Host ("$label : " + $tradesArr.Count + " trades, WR=" + $wr + "%, PF=" + $pf + ", Expectancy=" + $expectancy + ", AvgRet=" + $avgRet + "%, DD=" + [Math]::Round($maxDd,2) + "%, Sharpe=" + $sharpe)
    
    return @{Trades=$tradesArr; Count=$tradesArr.Count; WR=$wr; PF=$pf; AvgRet=$avgRet; Expectancy=$expectancy; MaxDD=$maxDd; Sharpe=$sharpe}
}

Write-Host "`n=== HISTORICAL PERIOD ==="
$histResult = Get-TradeResults $sig $cl $dt $n 100 $histEnd "Historical"

Write-Host "`n=== FORWARD PERIOD ==="
$fwdResult = Get-TradeResults $sig $cl $dt $n $fwdStart ($n-1) "Forward"

# Precompute stoch once
$stochVals = Calc-Stoch $hi $lo $cl 5 5

# Phase 17.1 - Signal Engine
Write-Host "`n=== PHASE 17.1: SIGNAL ENGINE ==="
$fwdSigsList = New-Object 'Collections.Generic.List[PSObject]'
for ($si = $fwdStart; $si -lt $sig.Length; $si++) {
    if (-not $sig[$si]) { continue }
    $fwdSigsList.Add([PSCustomObject]@{
        Timestamp = $ts[$si]
        Date = $dt[$si]
        Signal = if ($stochVals[$si+10] -gt 80) { "OVERBOUGHT" } elseif ($stochVals[$si+10] -lt 10) { "OVERSOLD" } else { "UNKNOWN" }
        EntryPrice = [Math]::Round($cl[$si],4)
        StochK = [Math]::Round($stochVals[$si+10],2)
    })
}
$fwdSigsArr = $fwdSigsList.ToArray()
$fwdSigsArr | Export-Csv (Join-Path $OutputDir "forward_signals.csv") -NoTypeInformation
Write-Host ("Forward signals: " + $fwdSigsArr.Count)
if ($fwdSigsArr.Count -gt 0) {
    Write-Host ("  Range: " + $fwdSigsArr[0].Date + " to " + $fwdSigsArr[-1].Date)
    $ob = ($fwdSigsArr | Where-Object { $_.Signal -eq "OVERBOUGHT" }).Count
    $os = ($fwdSigsArr | Where-Object { $_.Signal -eq "OVERSOLD" }).Count
    Write-Host ("  OVERBOUGHT=$ob OVERSOLD=$os")
}

# Phase 17.3 - Daily Logging
Write-Host "`n=== PHASE 17.3: TRADE LOG ==="
$tradeLog = New-Object 'Collections.Generic.List[PSObject]'
foreach ($t in $fwdResult.Trades) {
    $tradeLog.Add([PSCustomObject]@{
        SignalTime=$t.EntryDate
        EntryPrice=$t.EntryPrice
        ExitPrice=$t.ExitPrice
        PnL=$t.PnL
        HoldingTime=150
        ReturnPct=$t.ReturnPct
    })
}
$tradeLogArr = $tradeLog.ToArray()
$tradeLogArr | Export-Csv (Join-Path $OutputDir "forward_trade_log.csv") -NoTypeInformation

# Phase 17.4 - Performance Tracking
Write-Host "=== PHASE 17.4: METRICS ==="
$metricsList = New-Object 'Collections.Generic.List[PSObject]'
$cumPnl = 0.0; $wins=0; $losses=0; $peak=0.0; $maxDd=0.0
foreach ($t in $fwdResult.Trades) {
    $cumPnl += $t.PnL
    if ($t.PnL -gt 0) { $wins++ } else { $losses++ }
    if ($cumPnl -gt $peak) { $peak = $cumPnl }
    $dd = if ($peak -gt 0) { ($peak - $cumPnl) / $peak * 100 } else { 0 }
    if ($dd -gt $maxDd) { $maxDd = $dd }
    
    $tot = $wins + $losses
    $wr = if ($tot -gt 0) { [Math]::Round($wins/$tot*100,2) } else { 0 }
    $metricsList.Add([PSCustomObject]@{
        Trade=$tot; Date=$t.EntryDate
        CumulativePnL=[Math]::Round($cumPnl,4); WinRate=$wr
        Drawdown=[Math]::Round($dd,4)
    })
}
$metricsList.ToArray() | Export-Csv (Join-Path $OutputDir "forward_metrics.csv") -NoTypeInformation
Write-Host ("Metrics: " + $metricsList.Count + " rows")

# Phase 17.5 - Historical Comparison
Write-Host "=== PHASE 17.5: COMPARISON ==="
$compList = New-Object 'Collections.Generic.List[PSObject]'
$compList.Add([PSCustomObject]@{Metric="WinRate"; Expected=$histResult.WR; Observed=$fwdResult.WR; Status=if([Math]::Abs($fwdResult.WR-$histResult.WR)-le10){"WITHIN_RANGE"}else{"DIVERGED"}})
$compList.Add([PSCustomObject]@{Metric="ProfitFactor"; Expected=$histResult.PF; Observed=$fwdResult.PF; Status=if($fwdResult.PF-ge($histResult.PF*0.5)){"WITHIN_RANGE"}else{"DIVERGED"}})
$compList.Add([PSCustomObject]@{Metric="Expectancy"; Expected=$histResult.Expectancy; Observed=$fwdResult.Expectancy; Status=if($fwdResult.Expectancy-gt0){"WITHIN_RANGE"}else{"DIVERGED"}})
$compList.Add([PSCustomObject]@{Metric="AvgReturnPerTrade"; Expected=$histResult.AvgRet; Observed=$fwdResult.AvgRet; Status=if($fwdResult.AvgRet-gt0){"WITHIN_RANGE"}else{"DIVERGED"}})
$compList.Add([PSCustomObject]@{Metric="SharpeAnnualized"; Expected=$histResult.Sharpe; Observed=$fwdResult.Sharpe; Status=if($fwdResult.Sharpe-gt0){"WITHIN_RANGE"}else{"DIVERGED"}})
$compList.Add([PSCustomObject]@{Metric="MaxDrawdown"; Expected=[Math]::Round($histResult.MaxDD,2); Observed=[Math]::Round($fwdResult.MaxDD,2); Status="INFO"})
$compList.Add([PSCustomObject]@{Metric="TotalTrades"; Expected=$histResult.Count; Observed=$fwdResult.Count; Status="FORWARD_PERIOD"})
$compList.ToArray() | Export-Csv (Join-Path $OutputDir "forward_vs_historical.csv") -NoTypeInformation
$compList.ToArray() | Format-Table -AutoSize

# Phase 17.6 - Degradation Detection
Write-Host "`n=== PHASE 17.6: DEGRADATION ==="
$degList = New-Object 'Collections.Generic.List[PSObject]'
$degFlag = $false; $degReasons = @()

if ($fwdResult.Count -ge 10) {
    $mid = [Math]::Floor($fwdResult.Count / 2)
    $earlyTrades = $fwdResult.Trades[0..($mid-1)]
    $lateTrades = $fwdResult.Trades[$mid..($fwdResult.Count-1)]
    
    function Get-BlockMetrics($tArr, $label) {
        $w = ($tArr | Where-Object { $_.PnL -gt 0 }).Count
        $c = $tArr.Count
        $wr = if($c -gt 0) { [Math]::Round($w/$c*100,2) } else { 0 }
        $avg = if($c -gt 0) { [Math]::Round(($tArr | Measure-Object -Average PnL).Average, 4) } else { 0 }
        return @{WR=$wr; AvgRet=$avg; Count=$c}
    }
    
    $early = Get-BlockMetrics $earlyTrades "Early"
    $late = Get-BlockMetrics $lateTrades "Late"
    $degList.Add([PSCustomObject]@{Period="EarlyHalf"; Trades=$early.Count; WinRate=$early.WR; AvgReturn=$early.AvgRet})
    $degList.Add([PSCustomObject]@{Period="LateHalf"; Trades=$late.Count; WinRate=$late.WR; AvgReturn=$late.AvgRet})
    $degList.Add([PSCustomObject]@{Period="WR_Change"; Trades=""; WinRate=[Math]::Round($late.WR-$early.WR,2); AvgReturn=""})
    $degList.Add([PSCustomObject]@{Period="AvgRet_Change"; Trades=""; WinRate=""; AvgReturn=[Math]::Round($late.AvgRet-$early.AvgRet,4)})
    
    if ($early.WR - $late.WR -gt 15) { $degFlag = $true; $degReasons += "WR dropped $($early.WR - $late.WR) pp from early to late half" }
    if ($early.AvgRet - $late.AvgRet -gt 0.5) { $degFlag = $true; $degReasons += "Avg return dropped $([Math]::Round($early.AvgRet-$late.AvgRet,4)) pp" }
    
    $windowSize = [Math]::Max(20, [Math]::Floor($fwdResult.Count / 10))
    $prevWr = $null
    for ($i = 0; $i -le $fwdResult.Count - $windowSize; $i += [Math]::Max(1, [Math]::Floor($windowSize/2))) {
        $win = $fwdResult.Trades[$i..($i+$windowSize-1)]
        $w = ($win | Where-Object { $_.PnL -gt 0 }).Count
        $wwr = [Math]::Round($w/$windowSize*100,2)
        if ($prevWr -ne $null -and ($prevWr - $wwr) -gt 25) {
            $degFlag = $true
            $degReasons += "WR dropped $($prevWr - $wwr) pp at trade $($i+$windowSize)"
        }
        $prevWr = $wwr
    }
    
    $consec = 0
    for ($i = $fwdResult.Count - 1; $i -ge 0; $i--) {
        if ($fwdResult.Trades[$i].PnL -le 0) { $consec++ } else { break }
    }
    if ($consec -ge 5) { $degFlag = $true; $degReasons += "$consec consecutive losses at end of forward period" }
    
    $degList.Add([PSCustomObject]@{Period="ConsecutiveLosses"; Trades=$consec; WinRate=""; AvgReturn=""})
} else {
    $degList.Add([PSCustomObject]@{Period="Analysis"; Trades=""; WinRate="Insufficient forward trades (need >=10)"; AvgReturn=""})
}

$degList.Add([PSCustomObject]@{Period="DegradationDetected"; Trades=if($degFlag){"YES"}else{"NO"}; WinRate=$degReasons -join '; '; AvgReturn=""})
$degList.ToArray() | Export-Csv (Join-Path $OutputDir "degradation_report.csv") -NoTypeInformation
$degList.ToArray() | Format-Table -AutoSize

# Final Dashboard
Write-Host "`n=== GENERATING DASHBOARD ==="
$md = @()
$md += "# Forward Test Dashboard"
$md += ""
$md += "**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) - LONG ONLY - 5-bar hold"
$md += "**Historical period:** bars 0..$histEnd ($($histResult.Count) trades)"
$md += "**Forward period:** bars $fwdStart..$($n-1) ($($fwdResult.Count) trades)"
$md += ""
$md += "## 1. How many signals were generated?"
$md += ("- **Forward signals:** " + $fwdSigsArr.Count)
$md += ("- **Forward trades (after 5-bar exit):** " + $fwdResult.Count)
$sigRate = if($fwdSigsArr.Count -gt 0) { [Math]::Round($fwdSigsArr.Count/10000*100,2) } else { 0 }
$md += ("- **Signal rate:** " + $sigRate + "% of forward bars")
$md += ""
$md += "## 2. How many trades were executed?"
$md += ("- **Forward trades:** " + $fwdResult.Count)
$md += ("- **Historical trades:** " + $histResult.Count)
$md += ""
$md += "## 3. How does forward performance compare to historical?"
$md += ""
$md += "| Metric | Historical | Forward | Status |"
$md += "|--------|-----------|---------|--------|"
foreach ($c in $compList) {
    $md += ("| " + $c.Metric + " | " + $c.Expected + " | " + $c.Observed + " | " + $c.Status + " |")
}
$md += ""
$md += "| Fees+slippage | 0.14% round-trip | 0.14% round-trip | same |"
$md += ""
$md += "## 4. Is the edge behaving as expected?"
$edgeOk = if ($fwdResult.Expectancy -le 0) { "NO" } else { "YES" }
$md += ("- **Edge status:** " + $edgeOk)
$md += ("- **Forward expectancy:** " + $fwdResult.Expectancy)
$md += ("- **Historical expectancy:** " + $histResult.Expectancy)
if ($fwdResult.Count -gt 0) {
    $fwdOb = 0
    foreach ($t in $fwdResult.Trades) {
        $si = $t.EntryIdx
        if ($si + 10 -lt $stochVals.Length -and $stochVals[$si+10] -gt 80) { $fwdOb++ }
    }
    $fwdOs = $fwdResult.Count - $fwdOb
    $md += ("- **Forward signal composition:** " + $fwdOb + " overbought, " + $fwdOs + " oversold")
}
$md += ("- **Forward Sharpe (annualized):** " + $fwdResult.Sharpe)
$md += ("- **Historical Sharpe (annualized):** " + $histResult.Sharpe)
$md += ""
$md += "## 5. Has degradation been detected?"
$flagDegraded = if ($degFlag) { "YES" } else { "NO" }
$md += ("- **Degradation:** " + $flagDegraded)
if ($degReasons.Count -gt 0) {
    foreach ($r in $degReasons) { $md += ("  - " + $r) }
} else {
    $md += "  - No degradation detected"
}
$md += ""

$earlyRow = $degList | Where-Object { $_.Period -eq "EarlyHalf" }
$lateRow = $degList | Where-Object { $_.Period -eq "LateHalf" }
if ($earlyRow -and $lateRow) {
    $md += "| Period | Trades | WinRate | AvgReturn |"
    $md += "|--------|--------|---------|-----------|"
    $md += ("| Early half | " + $earlyRow.Trades + " | " + $earlyRow.WinRate + "% | " + $earlyRow.AvgReturn + " |")
    $md += ("| Late half | " + $lateRow.Trades + " | " + $lateRow.WinRate + "% | " + $lateRow.AvgReturn + " |")
    $md += ""
}

$md += "## Execution Assumptions"
$md += "- Fee: 0.05% per side (0.10% round trip)"
$md += "- Slippage: 0.02% per side (0.04% round trip)"
$md += "- Total friction: 0.14% round trip"
$md += "- Entry: close of signal bar + slippage + fee"
$md += "- Exit: close of bar+5 - slippage - fee"
$md += "- Holding period: 5 bars (150 minutes)"
$md += "- Direction: Long only"
$md += ""
$md += "## Output Files"
$md += "- forward_signals.csv : All forward period signals"
$md += "- forward_trade_log.csv : Every forward trade with PnL"
$md += "- forward_metrics.csv : Cumulative performance tracking"
$md += "- forward_vs_historical.csv : Historical vs forward comparison"
$md += "- degradation_report.csv : Degradation analysis"
$md += "- execution_assumptions.md : Full assumption documentation"
$md += "- forward_test_dashboard.md : This file"

$mdContent = $md -join "`n"
$mdContent | Out-File (Join-Path $OutputDir "forward_test_dashboard.md") -Encoding utf8
Write-Host "Dashboard written" -ForegroundColor Green

Write-Host "`n=== PHASE 17 COMPLETE ===" -ForegroundColor Cyan
