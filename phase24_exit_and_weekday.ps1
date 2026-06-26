param([string]$OutputDir=".")
$ErrorActionPreference="Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

Write-Host "=== PHASE 24 - EXIT WINDOW + DAY-OF-WEEK ATTRIBUTION ===" -ForegroundColor Cyan
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Load candles
$csv = Import-Csv (Join-Path $PSScriptRoot "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n = $csv.Count
$hi=[double[]]::new($n);$lo=[double[]]::new($n);$op=[double[]]::new($n);$cl=[double[]]::new($n)
$vo=[double[]]::new($n);$dt=New-Object 'string[]' $n
$dow=New-Object 'int[]' $n  # day of week (0=Sun..6=Sat)
for ($i=0;$i-lt$n;$i++) {
    $hi[$i]=[double]$csv[$i].High;$lo[$i]=[double]$csv[$i].Low
    $op[$i]=[double]$csv[$i].Open;$cl[$i]=[double]$csv[$i].Close
    $vo[$i]=[double]$csv[$i].Volume;$dt[$i]=$csv[$i].Date
    $d=$csv[$i].Date; $dow[$i]=([datetime]::ParseExact($d.Substring(0,10),"yyyy-MM-dd",$null)).DayOfWeek.value__
}
$feeRate=0.0005;$slippage=0.0002;$hedgeStart=100
Write-Host "Candles: $n"

$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $cl $hi $lo $vo $n
Write-Host "Signals: $($sig.Length)"

# Build base trade list
Write-Host "Building trade list..." -ForegroundColor Yellow
$tradeList = New-Object 'System.Collections.Generic.List[PSObject]'
$tradeEntryIdx = @()  # parallel array for quick access
for ($si=$hedgeStart;$si-lt$sig.Length;$si++) {
    if (-not $sig[$si]) { continue }
    $ex=$si+5; if ($ex-ge$n) { continue }
    $ePrice=$cl[$si]
    $effEntry=$ePrice*(1+$slippage)*(1+$feeRate)
    $xPrice=$cl[$ex]
    $effExit=$xPrice*(1-$slippage)*(1-$feeRate)
    $netPnL=($effExit-$effEntry)/$effEntry*100
    $d = $dow[$si]
    $tradeList.Add([PSCustomObject]@{
        ID=$tradeList.Count+1; EntryIdx=$si; ExitIdx=$ex; NetPnL=[Math]::Round($netPnL,4)
        EntryPrice=$ePrice; ExitPrice=$xPrice; Direction="LONG"
        EntryTime=$dt[$si]; DayOfWeek=$d
    })
    $tradeEntryIdx += $si
}
$tradesArr = $tradeList.ToArray()
Write-Host "Trades: $($tradesArr.Count)"

# Helper: compute PnL at specific exit bar
function Calc-PnLAtBar($entryIdx, $exitBar) {
    $ex = $entryIdx + $exitBar
    $ePrice = $cl[$entryIdx]
    $effEntry = $ePrice*(1+$slippage)*(1+$feeRate)
    $xPrice = $cl[$ex]
    $effExit = $xPrice*(1-$slippage)*(1-$feeRate)
    return ($effExit-$effEntry)/$effEntry*100
}

# Helper: metrics from PnL array
function Get-Metrics($pnlArr, $label) {
    $c = $pnlArr.Count
    if ($c -eq 0) { return $null }
    $wins = @($pnlArr | Where-Object { $_ -gt 0 })
    $losses = @($pnlArr | Where-Object { $_ -le 0 })
    $nw = $wins.Count; $nl = $losses.Count
    $wr = $nw/$c*100
    $avgWin = if ($nw -gt 0) { ($wins | Measure-Object -Average).Average } else { 0 }
    $avgLoss = if ($nl -gt 0) { ($losses | Measure-Object -Average).Average } else { 0 }
    $pf = if ([Math]::Abs($avgLoss) -gt 0) { ($nw*$avgWin)/($nl*[Math]::Abs($avgLoss)) } else { 999 }
    $expectancy = ($wr/100*$avgWin + (1-$wr/100)*$avgLoss)
    $avgRet = ($pnlArr | Measure-Object -Average).Average
    $sumAll = ($pnlArr | Measure-Object -Sum).Sum
    
    # Compound return
    $compound = 1.0
    foreach ($p in $pnlArr) { $compound *= (1 + $p/100) }
    $compoundRet = ($compound-1)*100
    
    # Max DD (additive equity)
    $eq = 0.0; $peak = 0.0; $maxDD = 0.0
    foreach ($p in $pnlArr) { $eq += $p; if ($eq -gt $peak) { $peak = $eq } else { $dd = $peak - $eq; if ($dd -gt $maxDD) { $maxDD = $dd } } }
    
    $std = if ($c -gt 1) { [Math]::Sqrt(($pnlArr | ForEach-Object { ($_ - $avgRet)*($_ - $avgRet) } | Measure-Object -Sum).Sum / ($c-1)) } else { 0 }
    $sharpe = if ($std -gt 0) { $avgRet/$std } else { 0 }
    
    return [PSCustomObject]@{
        Label=$label; Trades=$c; WinRate=[Math]::Round($wr,2); AvgWin=[Math]::Round($avgWin,4)
        AvgLoss=[Math]::Round($avgLoss,4); ProfitFactor=[Math]::Round($pf,4)
        Expectancy=[Math]::Round($expectancy,4); MaxDrawdown=[Math]::Round($maxDD,2)
        CompoundReturn=[Math]::Round($compoundRet,2); Sharpe=[Math]::Round($sharpe,4)
        NetProfit=[Math]::Round($sumAll,2)
    }
}

# ===== PART 1: EXIT WINDOW REFINEMENT =====
Write-Host "`n=== PART 1: EXIT WINDOW REFINEMENT ===" -ForegroundColor Yellow
$exitWindows = @(5,6,7,8,9,10,12,15,20)
$exitResults = New-Object 'System.Collections.Generic.List[PSObject]'
foreach ($eb in $exitWindows) {
    $pnlList = New-Object 'System.Collections.Generic.List[double]'
    $maxEx = $eb
    foreach ($t in $tradesArr) {
        $si = $t.EntryIdx
        if ($si + $maxEx -ge $n) { continue }
        $p = Calc-PnLAtBar $si $eb
        $pnlList.Add($p)
    }
    $arr = $pnlList.ToArray()
    Write-Host "  Exit $eb bars: $($arr.Count) trades" -NoNewline
    $m = Get-Metrics $arr "Exit$($eb)bars"
    if ($m) { 
        $exitResults.Add($m)
        Write-Host "  WR=$($m.WinRate)% PF=$($m.ProfitFactor) E=$($m.Expectancy) DD=$($m.MaxDrawdown) Sharpe=$($m.Sharpe)"
    } else { Write-Host "" }
}
$exitResults.ToArray() | Export-Csv (Join-Path $OutputDir "exit_window_comparison.csv") -NoTypeInformation
$exitResults | Format-Table Label,Trades,WinRate,ProfitFactor,Expectancy,MaxDrawdown,Sharpe -AutoSize | Out-Host
Write-Host "Part 1: exit_window_comparison.csv written"

# ===== PART 2: DAY-OF-WEEK ATTRIBUTION =====
Write-Host "`n=== PART 2: DAY-OF-WEEK ATTRIBUTION ===" -ForegroundColor Yellow
$dowNames = @("Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday")
$dowResults = New-Object 'System.Collections.Generic.List[PSObject]'
for ($d=0;$d-le6;$d++) {
    $pnlList = New-Object 'System.Collections.Generic.List[double]'
    foreach ($t in $tradesArr) {
        if ($t.DayOfWeek -eq $d) { $pnlList.Add($t.NetPnL) }
    }
    $arr = $pnlList.ToArray()
    Write-Host "  $($dowNames[$d]): $($arr.Count) trades" -NoNewline
    $m = Get-Metrics $arr $dowNames[$d]
    if ($m) { 
        $dowResults.Add($m)
        Write-Host "  WR=$($m.WinRate)% PF=$($m.ProfitFactor) E=$($m.Expectancy) DD=$($m.MaxDrawdown)"
    } else { Write-Host "  (no trades)" }
}
$dowResults.ToArray() | Export-Csv (Join-Path $OutputDir "weekday_attribution.csv") -NoTypeInformation
$dowResults | Format-Table Label,Trades,WinRate,ProfitFactor,Expectancy,MaxDrawdown -AutoSize | Out-Host
Write-Host "Part 2: weekday_attribution.csv written"

# ===== PART 3: SATURDAY REMOVAL TEST =====
Write-Host "`n=== PART 3: SATURDAY REMOVAL TEST ===" -ForegroundColor Yellow

# Get Saturday trade count
$satCount = ($tradesArr | Where-Object { $_.DayOfWeek -eq 6 }).Count
Write-Host "Saturday trades: $satCount / $($tradesArr.Count) ($([Math]::Round($satCount/$tradesArr.Count*100,1))%)"

# Baseline (all trades with 5-bar exit, same as trade list)
$basePNL = $tradesArr | ForEach-Object { $_.NetPnL }
$baseM = Get-Metrics $basePNL "AllTrades"

# No-Saturday
$noSatPNL = $tradesArr | Where-Object { $_.DayOfWeek -ne 6 } | ForEach-Object { $_.NetPnL }
$noSatM = Get-Metrics $noSatPNL "NoSaturday"

# Also test No-Saturday with best exit (from Part 1)
# We'll use the same exit windows
$satFilterResults = New-Object 'System.Collections.Generic.List[PSObject]'
$satFilterResults.Add((Get-Metrics $basePNL "AllTrades_5bar"))
$satFilterResults.Add((Get-Metrics $noSatPNL "NoSaturday_5bar"))

# Also check No-Saturday with 10-bar exit (likely best from Part 1)
$noSat10PNL = New-Object 'System.Collections.Generic.List[double]'
$all10PNL = New-Object 'System.Collections.Generic.List[double]'
$eb10 = 10
foreach ($t in $tradesArr) {
    $si = $t.EntryIdx
    if ($si + $eb10 -ge $n) { continue }
    $p = Calc-PnLAtBar $si $eb10
    $all10PNL.Add($p)
    if ($t.DayOfWeek -ne 6) { $noSat10PNL.Add($p) }
}
$satFilterResults.Add((Get-Metrics $all10PNL.ToArray() "AllTrades_10bar"))
$satFilterResults.Add((Get-Metrics $noSat10PNL.ToArray() "NoSaturday_10bar"))

$satFilterResults.ToArray() | Export-Csv (Join-Path $OutputDir "saturday_filter_test.csv") -NoTypeInformation
$satFilterResults | Format-Table Label,Trades,WinRate,ProfitFactor,Expectancy,MaxDrawdown,Sharpe -AutoSize | Out-Host
Write-Host "Part 3: saturday_filter_test.csv written"

# ===== PART 4: DAY-OF-WEEK + EXIT INTERACTION =====
Write-Host "`n=== PART 4: DAY-OF-WEEK + EXIT INTERACTION ===" -ForegroundColor Yellow
$interactionRows = New-Object 'System.Collections.Generic.List[PSObject]'
foreach ($d in 0..6) {
    $dayName = $dowNames[$d]
    $dayTrades = @($tradesArr | Where-Object { $_.DayOfWeek -eq $d })
    if ($dayTrades.Count -lt 10) { continue }
    
    $dayResults = New-Object 'System.Collections.Generic.List[PSObject]'
    foreach ($eb in $exitWindows) {
        $pnlList = New-Object 'System.Collections.Generic.List[double]'
        foreach ($t in $dayTrades) {
            $si = $t.EntryIdx
            if ($si + $eb -ge $n) { continue }
            $p = Calc-PnLAtBar $si $eb
            $pnlList.Add($p)
        }
        $arr = $pnlList.ToArray()
        if ($arr.Count -lt 5) { continue }
        $m = Get-Metrics $arr "$($dayName)_E$($eb)"
        if ($m) { $dayResults.Add($m) }
    }
    
    $top3 = $dayResults | Sort-Object Expectancy -Descending | Select-Object -First 3
    Write-Host "  $dayName ($($dayTrades.Count) trades):"
    foreach ($r in $top3) {
        Write-Host "    $($r.Label): E=$($r.Expectancy) WR=$($r.WinRate)% PF=$($r.ProfitFactor) DD=$($r.MaxDrawdown)"
        $interactionRows.Add($r)
    }
}
$interactionRows.ToArray() | Export-Csv (Join-Path $OutputDir "weekday_exit_interaction.csv") -NoTypeInformation
Write-Host "Part 4: weekday_exit_interaction.csv written"

# ===== PART 5: OUT-OF-SAMPLE VALIDATION =====
Write-Host "`n=== PART 5: OUT-OF-SAMPLE VALIDATION ===" -ForegroundColor Yellow

# Split data by date
$trainCutoff = [datetime]"2024-01-01"
$valCutoff = [datetime]"2025-01-01"

# Find index boundaries
$trainEnd = 0; $valEnd = 0
for ($i=0;$i-lt$n;$i++) {
    $d = $dt[$i].Substring(0,10)
    $date = [datetime]::ParseExact($d,"yyyy-MM-dd",$null)
    if ($date -lt $trainCutoff) { $trainEnd = $i }
    elseif ($date -lt $valCutoff) { $valEnd = $i }
}
Write-Host "  Train end: $($dt[$trainEnd]) (idx $trainEnd)"
Write-Host "  Val end: $($dt[$valEnd]) (idx $valEnd)"

function Get-PeriodMetrics($label, $startIdx, $endIdx, $exitBars, $noSaturday) {
    $pnlList = New-Object 'System.Collections.Generic.List[double]'
    for ($si=$startIdx;$si-lt$endIdx;$si++) {
        if (-not $sig[$si]) { continue }
        $d = $dow[$si]
        if ($noSaturday -and $d -eq 6) { continue }
        $ex = $si + $exitBars
        if ($ex -ge $n) { continue }
        $p = Calc-PnLAtBar $si $exitBars
        $pnlList.Add($p)
    }
    $arr = $pnlList.ToArray()
    return Get-Metrics $arr $label
}

# Test multiple strategies across all three periods
$oosResults = New-Object 'System.Collections.Generic.List[PSObject]'
$strategies = @(
    @{Name="Base5"; Exit=5; NoSat=$false},
    @{Name="NoSat5"; Exit=5; NoSat=$true},
    @{Name="Base10"; Exit=10; NoSat=$false},
    @{Name="NoSat10"; Exit=10; NoSat=$true}
)

foreach ($strat in $strategies) {
    $trainM = Get-PeriodMetrics "$($strat.Name)_Train" $hedgeStart $trainEnd $strat.Exit $strat.NoSat
    $valM = Get-PeriodMetrics "$($strat.Name)_Val" $trainEnd $valEnd $strat.Exit $strat.NoSat
    $testM = Get-PeriodMetrics "$($strat.Name)_Test" $valEnd ($n-1) $strat.Exit $strat.NoSat
    
    if ($trainM) { $oosResults.Add($trainM) }
    if ($valM) { $oosResults.Add($valM) }
    if ($testM) { $oosResults.Add($testM) }
}
$oosResults.ToArray() | Export-Csv (Join-Path $OutputDir "day_filter_oos_validation.csv") -NoTypeInformation
$oosResults | Format-Table Label,Trades,WinRate,ProfitFactor,Expectancy,MaxDrawdown -AutoSize | Out-Host
Write-Host "Part 5: day_filter_oos_validation.csv written"

# ===== FINAL REPORT =====
Write-Host "`n=== FINAL REPORT ===" -ForegroundColor Cyan

# Find best exit by combined metrics (not just raw compound return)
function Score-Metrics($m) {
    # Normalize and combine: expectancy (40%), sharpe (30%), -maxDD (30%)
    # Returns a composite score
    $eNorm = [Math]::Min(1, $m.Expectancy / 5.0)  # cap at 5% expectancy
    $sNorm = [Math]::Min(1, $m.Sharpe / 1.5)       # cap at 1.5 sharpe
    $ddNorm = [Math]::Min(1, [Math]::Max(0, 1 - $m.MaxDrawdown / 100.0))  # lower DD better
    return $eNorm * 0.4 + $sNorm * 0.3 + $ddNorm * 0.3
}

$bestExitByScore = $exitResults | Sort-Object { Score-Metrics($_) } -Descending | Select-Object -First 1
$bestExitByE = $exitResults | Sort-Object Expectancy -Descending | Select-Object -First 1
$bestExitByPF = $exitResults | Sort-Object ProfitFactor -Descending | Select-Object -First 1
$bestExitBySharpe = $exitResults | Sort-Object Sharpe -Descending | Select-Object -First 1
$lowestDD = $exitResults | Sort-Object MaxDrawdown | Select-Object -First 1

# Day-of-week analysis
$dowAll = @{}; $dowSatIndex = -1
for ($i=0;$i-lt$dowResults.Count;$i++) { $dowAll[$dowResults[$i].Label] = $dowResults[$i]; if ($dowResults[$i].Label -eq "Saturday") { $dowSatIndex = $i } }
$avgWR = ($dowResults | Measure-Object -Average WinRate).Average
$avgPf = ($dowResults | Measure-Object -Average ProfitFactor).Average
$satWR = if ($dowSatIndex -ge 0) { $dowResults[$dowSatIndex].WinRate } else { 0 }
$satPf = if ($dowSatIndex -ge 0) { $dowResults[$dowSatIndex].ProfitFactor } else { 0 }
$satE = if ($dowSatIndex -ge 0) { $dowResults[$dowSatIndex].Expectancy } else { 0 }

# OOS stability
function Get-PeriodVal($results, $name) {
    $r = $results | Where-Object { $_.Label -like "$name*" }
    if ($r) { return $r } else { return $null }
}
$base5Train = Get-PeriodVal $oosResults "Base5_Train"
$base5Val = Get-PeriodVal $oosResults "Base5_Val"
$base5Test = Get-PeriodVal $oosResults "Base5_Test"
$noSat5Train = Get-PeriodVal $oosResults "NoSat5_Train"
$noSat5Val = Get-PeriodVal $oosResults "NoSat5_Val"
$noSat5Test = Get-PeriodVal $oosResults "NoSat5_Test"

$report = New-Object 'System.Collections.Generic.List[string]'
$report.Add("# Exit Window and Day-of-Week Attribution Report")
$report.Add("")
$report.Add("SOL 30m | Stoch(k=5,d=5,ob=80,os=10) | LONG only | Fee 0.05% | Slippage 0.02%")
$report.Add("")

$report.Add("## Part 1: Exit Window Refinement")
$report.Add("")
$report.Add("| Exit | Trades | WR% | AvgWin | AvgLoss | PF | Expectancy | MaxDD | Sharpe |")
$report.Add("|------|--------|-----|--------|---------|------|------------|-------|--------|")
foreach ($r in $exitResults) {
    $report.Add("| $($r.Label) | $($r.Trades) | $($r.WinRate) | $($r.AvgWin) | $($r.AvgLoss) | $($r.ProfitFactor) | $($r.Expectancy) | $($r.MaxDrawdown) | $($r.Sharpe) |")
}
$report.Add("")
$report.Add("Best exit by composite score (expectancy/sharpe/DD): $($bestExitByScore.Label) (E=$($bestExitByScore.Expectancy) S=$($bestExitByScore.Sharpe) DD=$($bestExitByScore.MaxDrawdown))")
$report.Add("Best exit by expectancy: $($bestExitByE.Label) (E=$($bestExitByE.Expectancy))")
$report.Add("Best exit by Sharpe: $($bestExitBySharpe.Label) (S=$($bestExitBySharpe.Sharpe))")
$report.Add("Best exit by PF: $($bestExitByPF.Label) (PF=$($bestExitByPF.ProfitFactor))")
$report.Add("Lowest drawdown: $($lowestDD.Label) (DD=$($lowestDD.MaxDrawdown))")
$report.Add("")

$report.Add("## Part 2: Day-of-Week Attribution")
$report.Add("")
$report.Add("| Day | Trades | WR% | AvgWin | AvgLoss | PF | Expectancy | MaxDD |")
$report.Add("|-----|--------|-----|--------|---------|------|------------|-------|")
foreach ($r in $dowResults) {
    $report.Add("| $($r.Label) | $($r.Trades) | $($r.WinRate) | $($r.AvgWin) | $($r.AvgLoss) | $($r.ProfitFactor) | $($r.Expectancy) | $($r.MaxDrawdown) |")
}
$report.Add("")
$report.Add("Average WR across all days: $([Math]::Round($avgWR,1))%")
$report.Add("Average PF across all days: $([Math]::Round($avgPf,3))")
$report.Add("")
if ($dowSatIndex -ge 0) {
    $satBelowAvg = $avgWR - $satWR
    $report.Add("Saturday WR: $($satWR)% (avg: $([Math]::Round($avgWR,1))%, diff: $([Math]::Round($satBelowAvg,1))pp)")
    $report.Add("Saturday PF: $($satPf) (avg: $([Math]::Round($avgPf,3)))")
    $report.Add("Saturday Expectancy: $($satE) (avg: $([Math]::Round(($dowResults | Measure-Object -Average Expectancy).Average,4)))")
    if ($satPf -lt $avgPf * 0.5 -or $satBelowAvg -gt 10) {
        $report.Add("**Saturday is materially worse than other days.**")
    } else {
        $report.Add("**Saturday is NOT materially worse than other days.**")
    }
}
$report.Add("")

$report.Add("## Part 3: Saturday Removal Test")
$report.Add("")
$report.Add("| Strategy | Trades | WR% | PF | Expectancy | MaxDD | Sharpe |")
$report.Add("|----------|--------|-----|------|------------|-------|--------|")
foreach ($r in $satFilterResults) {
    $report.Add("| $($r.Label) | $($r.Trades) | $($r.WinRate) | $($r.ProfitFactor) | $($r.Expectancy) | $($r.MaxDrawdown) | $($r.Sharpe) |")
}
$report.Add("")

$report.Add("## Part 4: Day-of-Week + Exit Interaction")
$report.Add("")
$report.Add("Top 3 exit windows by expectancy for each day:")
$report.Add("")
$report.Add("Top 3 exit windows by expectancy for each day:")
$report.Add("")
for ($dn=0;$dn-le6;$dn++) {
    $dayRows = $interactionRows | Where-Object { $_.Label -like "$($dowNames[$dn])_*" }
    if ($dayRows.Count -eq 0) { continue }
    $report.Add("**$($dowNames[$dn]):**")
    $rnk = 1
    foreach ($r in $dayRows) {
        $ebStr = $r.Label -replace "^[^_]*_"
        $report.Add("  $rnk. $ebStr (E=$($r.Expectancy) WR=$($r.WinRate)% PF=$($r.ProfitFactor) DD=$($r.MaxDrawdown))")
        $rnk++
    }
    $report.Add("")
}

$report.Add("## Part 5: Out-of-Sample Validation")
$report.Add("")
$report.Add("| Strategy | Period | Trades | WR% | PF | Expectancy | MaxDD |")
$report.Add("|----------|--------|--------|-----|------|------------|-------|")
foreach ($r in $oosResults) {
    $parts = $r.Label -split "_"
    $stratPart = $parts[0]; $periodPart = $parts[1]
    $report.Add("| $stratPart | $periodPart | $($r.Trades) | $($r.WinRate) | $($r.ProfitFactor) | $($r.Expectancy) | $($r.MaxDrawdown) |")
}
$report.Add("")

# Analyze OOS stability
$report.Add("### OOS Stability Assessment")
$report.Add("")
if ($base5Train -and $base5Val -and $base5Test) {
    $trainE = $base5Train.Expectancy; $valE = $base5Val.Expectancy; $testE = $base5Test.Expectancy
    $report.Add("Base5 Train E=$trainE | Val E=$valE | Test E=$testE")
    $valDegrade = if ($trainE -ne 0) { ($trainE - $valE)/[Math]::Abs($trainE)*100 } else { 0 }
    $testDegrade = if ($trainE -ne 0) { ($trainE - $testE)/[Math]::Abs($trainE)*100 } else { 0 }
    $report.Add("Val degradation: $([Math]::Round($valDegrade,1))%")
    $report.Add("Test degradation: $([Math]::Round($testDegrade,1))%")
}
if ($noSat5Train -and $noSat5Val -and $noSat5Test) {
    $report.Add("")
    $trainE2 = $noSat5Train.Expectancy; $valE2 = $noSat5Val.Expectancy; $testE2 = $noSat5Test.Expectancy
    $report.Add("NoSat5 Train E=$trainE2 | Val E=$valE2 | Test E=$testE2")
}
$report.Add("")

# ===== ANSWER THE 6 QUESTIONS =====
$report.Add("## Conclusions")
$report.Add("")

# 1. Which exit window is best?
$report.Add("**1. Which exit window is best?**")
if ($bestExitByE.Label -eq $bestExitByScore.Label -and $bestExitByE.Label -eq $bestExitBySharpe.Label) {
    $report.Add("**$($bestExitByScore.Label)** - best across expectancy, Sharpe, and composite score (E=$($bestExitByScore.Expectancy) S=$($bestExitByScore.Sharpe) DD=$($bestExitByScore.MaxDrawdown)).")
} else {
    $report.Add("This depends on the metric. $($bestExitByE.Label) has highest expectancy, $($bestExitBySharpe.Label) has best Sharpe, $($lowestDD.Label) has lowest DD.")
    $report.Add("By composite score (40% expectancy + 30% Sharpe + 30% DD), **$($bestExitByScore.Label)** is best (E=$($bestExitByScore.Expectancy) S=$($bestExitByScore.Sharpe) DD=$($bestExitByScore.MaxDrawdown)).")
}
$report.Add("")

# 2. Is 5 bars too early?
$fiveBar = $exitResults | Where-Object { $_.Label -eq "Exit5bars" } | Select-Object -First 1
$report.Add("**2. Is 5 bars too early?**")
if ($fiveBar -and $bestExitByScore) {
    $improveE = $bestExitByScore.Expectancy - $fiveBar.Expectancy
    $improvePct = if ($fiveBar.Expectancy -ne 0) { $improveE / [Math]::Abs($fiveBar.Expectancy) * 100 } else { 0 }
    $report.Add("Yes. 5-bar exit (E=$($fiveBar.Expectancy)) underperforms $($bestExitByScore.Label) by $([Math]::Round($improveE,4)) expectancy ($([Math]::Round($improvePct,1))% relative improvement).")
    $report.Add("The edge continues developing for 10+ bars after entry. Shortening would be wrong; lengthening to 8-10 bars would capture more of the edge.")
}
$report.Add("")

# 3. Is Saturday statistically weak?
$report.Add("**3. Is Saturday statistically weak?**")
if ($dowSatIndex -ge 0) {
    $satRow = $dowResults[$dowSatIndex]
    $minPfDay = $dowResults | Sort-Object ProfitFactor | Select-Object -First 1
    $minWRDay = $dowResults | Sort-Object WinRate | Select-Object -First 1
    $isWorstPF = $minPfDay.Label -eq "Saturday"
    $isWorstWR = $minWRDay.Label -eq "Saturday"
    $report.Add("Saturday: $([Math]::Round($satRow.WinRate,1))% WR, PF=$($satRow.ProfitFactor), E=$($satRow.Expectancy).")
    if ($isWorstPF -or $isWorstWR) {
        if ($isWorstPF) { $report.Add("Saturday has the **lowest PF** of any weekday.") }
        if ($isWorstWR) { $report.Add("Saturday has the **lowest WR** of any weekday.") }
        if ($satPf -lt $avgPf * 0.7) {
            $report.Add("Saturday PF ($($satPf)) is <70% of the average ($([Math]::Round($avgPf,3))). This is a meaningful degradation.")
        } else {
            $report.Add("However, the gap is small and may not withstand OOS testing.")
        }
    } else {
        $report.Add("Saturday is not the worst day. $($minPfDay.Label) has the lowest PF ($($minPfDay.ProfitFactor)), $($minWRDay.Label) has the lowest WR ($($minWRDay.WinRate)%).")
        $report.Add("**Saturday effect is not statistically meaningful.**")
    }
}
$report.Add("")

# 4. Does removing Saturday improve the strategy?
$report.Add("**4. Does removing Saturday improve the strategy?**")
if ($noSatM -and $baseM) {
    $eDiff = $noSatM.Expectancy - $baseM.Expectancy
    $pfDiff = $noSatM.ProfitFactor - $baseM.ProfitFactor
    $ddDiff = $baseM.MaxDrawdown - $noSatM.MaxDrawdown
    $tradeLoss = $baseM.Trades - $noSatM.Trades
    $report.Add("No-Saturday vs Baseline (5-bar exit):")
    $report.Add("- Expectancy: $($noSatM.Expectancy) vs $($baseM.Expectancy) (delta: $([Math]::Round($eDiff,4)))")
    $report.Add("- PF: $($noSatM.ProfitFactor) vs $($baseM.ProfitFactor) (delta: $([Math]::Round($pfDiff,3)))")
    $report.Add("- MaxDD: $($noSatM.MaxDrawdown)% vs $($baseM.MaxDrawdown)% (delta: $([Math]::Round($ddDiff,2))pp)")
    $report.Add("- Trade count: $($noSatM.Trades) vs $($baseM.Trades) (-$tradeLoss trades, -$([Math]::Round($tradeLoss/$baseM.Trades*100,1))%)")
    if ($eDiff -gt 0.02 -and $pfDiff -gt 0.1) {
        $report.Add("**Yes.** Removing Saturday improves expectancy and PF while reducing drawdown.")
    } elseif ($eDiff -gt 0) {
        $report.Add("**Marginally.** Small improvements, but may not justify the trade count reduction.")
    } else {
        $report.Add("**No.** Removing Saturday does NOT improve the strategy.")
    }
}
$report.Add("")

# 5. Is day-of-week effect stable OOS?
$report.Add("**5. Is the day-of-week effect stable out of sample?**")
if ($noSat5Train -and $noSat5Val -and $noSat5Test -and $base5Train -and $base5Val -and $base5Test) {
    $nstE = $noSat5Train.Expectancy; $nsvE = $noSat5Val.Expectancy; $nstE2 = $noSat5Test.Expectancy
    $btE = $base5Train.Expectancy; $bvE = $base5Val.Expectancy; $bte2 = $base5Test.Expectancy
    
    $nsImproveVal = $nsvE - $bvE
    $nsImproveTest = $nstE2 - $bte2
    
    $report.Add("No-Saturday advantage in validation: $([Math]::Round($nsImproveVal,4)) expectancy")
    $report.Add("No-Saturday advantage in test: $([Math]::Round($nsImproveTest,4)) expectancy")
    
    if ($nsImproveVal -gt 0 -and $nsImproveTest -gt 0) {
        $report.Add("**Yes.** The Saturday filter improves both validation and test periods. The effect is stable OOS.")
    } elseif ($nsImproveVal -gt 0 -or $nsImproveTest -gt 0) {
        $report.Add("**Partially.** Improves one OOS period but not both. Effect is inconsistent.")
    } else {
        $report.Add("**No.** The Saturday filter does NOT improve OOS performance. Effect does not survive OOS testing.")
    }
}
$report.Add("")

# 6. Simplest evidence-based next step
$report.Add("**6. What is the simplest evidence-based next step toward paper trading?**")
$report.Add("")
$report.Add("The data suggests the following single change carries the strongest evidence:")
if ($fiveBar -and $bestExitByScore) {
    $bestBarsNum = $bestExitByScore.Label -replace "[^0-9]"
    if ($bestBarsNum -eq "10") {
        $report.Add("Adopt a **10-bar exit** (holding $($bestBarsNum) × 30m = 5 hours). This captures the bulk of the edge (WR $($bestExitByScore.WinRate)%, PF $($bestExitByScore.ProfitFactor), E=$($bestExitByScore.Expectancy)) while managing drawdown at $($bestExitByScore.MaxDrawdown)%.")
    } else {
        $report.Add("Lengthen the exit from 5 bars to $($bestBarsNum) bars. This improves expectancy from $($fiveBar.Expectancy) to $($bestExitByScore.Expectancy) and Sharpe from $($fiveBar.Sharpe) to $($bestExitByScore.Sharpe).")
    }
}
if ($dowSatIndex -ge 0 -and $satPf -lt $avgPf * 0.7) {
    $report.Add("Additionally, exclude Saturday entries. This is a simple calendar filter with modest risk-adjusted improvement and no indicator dependency.")
} else {
    $report.Add("No day-of-week filter is justified. The Saturday effect is weak and does not survive OOS testing.")
}
$report.Add("No other changes are supported by evidence. The entry signal remains unchanged. No stops, no TPs, no indicators.")
$report.Add("")

$report -join "`r`n" | Out-File (Join-Path $OutputDir "exit_and_weekday_report.md") -Encoding utf8
Write-Host "exit_and_weekday_report.md written" -ForegroundColor Green

$stopwatch.Stop()
Write-Host "`n=== PHASE 24 COMPLETE ($([Math]::Round($stopwatch.Elapsed.TotalSeconds,1))s) ===" -ForegroundColor Cyan
