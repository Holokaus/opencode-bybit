param([string]$OutputDir=".")
$ErrorActionPreference="Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

Write-Host "=== PHASE 23 - TRADE LIFECYCLE ANALYSIS ===" -ForegroundColor Cyan
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Load candles
$csv = Import-Csv (Join-Path $PSScriptRoot "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n = $csv.Count
$hi=[double[]]::new($n);$lo=[double[]]::new($n);$op=[double[]]::new($n);$cl=[double[]]::new($n)
$vo=[double[]]::new($n);$dt=New-Object 'string[]' $n
for ($i=0;$i-lt$n;$i++) {
    $hi[$i]=[double]$csv[$i].High;$lo[$i]=[double]$csv[$i].Low
    $op[$i]=[double]$csv[$i].Open;$cl[$i]=[double]$csv[$i].Close
    $vo[$i]=[double]$csv[$i].Volume;$dt[$i]=$csv[$i].Date
}
$feeRate=0.0005;$slippage=0.0002;$exitBar=5;$hedgeStart=100;$maxLife=20
Write-Host "Candles: $n"

$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $cl $hi $lo $vo $n
Write-Host "Signals: $($sig.Length)"

# ===== BUILD TRADES =====
Write-Host "Building trade list with lifecycle PnL..." -ForegroundColor Yellow
$tradeList = New-Object 'System.Collections.Generic.List[PSObject]'
$lcRows = New-Object 'System.Collections.Generic.List[string]'

# CSV header for lifecycle
$lcHeader = "TradeID,EntryTime"
for ($k=1;$k-le$maxLife;$k++) { $lcHeader += ",PnL_Bar$k" }
$lcRows.Add($lcHeader)

for ($si=$hedgeStart;$si-lt$sig.Length;$si++) {
    if (-not $sig[$si]) { continue }
    $ex=$si+$exitBar; if ($ex-ge$n) { continue }
    
    $ePrice=$cl[$si]
    $effEntry=$ePrice*(1+$slippage)*(1+$feeRate)
    
    # Compute PnL at bars 1..maxLife
    $pnlParts = New-Object 'System.Collections.Generic.List[string]'
    for ($k=1;$k-le$maxLife;$k++) {
        $bk = $si+$k
        if ($bk -ge $n) { $pnlParts.Add(""); continue }
        $bkPrice = $cl[$bk]
        $effExit = $bkPrice*(1-$slippage)*(1-$feeRate)
        $p = ($effExit-$effEntry)/$effEntry*100
        $pnlParts.Add("$([Math]::Round($p,4))")
    }
    $pnlStr = $pnlParts -join ","
    
    # Actual exit PnL (bar 5)
    $xPrice=$cl[$ex]
    $effExit=$xPrice*(1-$slippage)*(1-$feeRate)
    $netPnL=($effExit-$effEntry)/$effEntry*100
    
    $tid = $tradeList.Count + 1
    $tradeList.Add([PSCustomObject]@{
        ID=$tid; EntryIdx=$si; ExitIdx=$ex; NetPnL=[Math]::Round($netPnL,4)
        EntryPrice=[Math]::Round($ePrice,4); ExitPrice=[Math]::Round($xPrice,4); Direction="LONG"
        EntryTime=$dt[$si]
    })
    
    $lcRows.Add("$tid,$($dt[$si]),$pnlStr")
}
$tradesArr = $tradeList.ToArray()
Write-Host "Trades: $($tradesArr.Count)"

# Export Phase 23.1
$lcRows -join "`r`n" | Out-File (Join-Path $OutputDir "trade_lifecycle.csv") -Encoding utf8
Write-Host "Phase 23.1: trade_lifecycle.csv written ($($tradesArr.Count) trades)"

# Pre-compute PnL arrays for quick access: lifecyclePNL[tradeIndex][bar-1] = PnL
Write-Host "Pre-computing PnL arrays..." -ForegroundColor Yellow
$lifePNL = @()  # array of arrays: [tradeIdx][bar-1]
$tradeEntryIdx = @()
foreach ($t in $tradesArr) {
    $si = $t.EntryIdx
    $ePrice=$cl[$si]
    $effEntry=$ePrice*(1+$slippage)*(1+$feeRate)
    $arr = @()
    for ($k=1;$k-le$maxLife;$k++) {
        $bk=$si+$k
        if ($bk-ge$n) { $arr += $null; continue }
        $effExit=$cl[$bk]*(1-$slippage)*(1-$feeRate)
        $arr += ($effExit-$effEntry)/$effEntry*100
    }
    $lifePNL += ,$arr
    $tradeEntryIdx += $si
}
Write-Host "PnL arrays computed: $($lifePNL.Length)"

# ===== PHASE 23.2: EDGE EVOLUTION =====
Write-Host "`n=== PHASE 23.2: EDGE EVOLUTION ===" -ForegroundColor Yellow
$hpResults = New-Object 'System.Collections.Generic.List[PSObject]'
for ($h=1;$h-le$maxLife;$h++) {
    $hpPNL = @()
    foreach ($arr in $lifePNL) {
        $v = $arr[$h-1]
        if ($v -ne $null) { $hpPNL += $v }
    }
    $c = $hpPNL.Count
    $wins = @($hpPNL | Where-Object { $_ -gt 0 })
    $losses = @($hpPNL | Where-Object { $_ -le 0 })
    $nw = $wins.Count; $nl = $losses.Count
    $wr = if ($c -gt 0) { $nw/$c*100 } else { 0 }
    $avgWin = if ($nw -gt 0) { ($wins | Measure-Object -Average).Average } else { 0 }
    $avgLoss = if ($nl -gt 0) { ($losses | Measure-Object -Average).Average } else { 0 }
    $pf = if ([Math]::Abs($avgLoss) -gt 0) { ($nw*$avgWin)/($nl*[Math]::Abs($avgLoss)) } else { 0 }
    $expectancy = ($wr/100*$avgWin + (1-$wr/100)*$avgLoss)
    $avgRet = if ($c -gt 0) { ($hpPNL | Measure-Object -Average).Average } else { 0 }
    # Compound return
    $compound = 1.0
    foreach ($p in $hpPNL) { $compound *= (1 + $p/100) }
    $compoundRet = ($compound-1)*100
    # Max drawdown (using additive equity)
    $eq = 0.0; $peak = 0.0; $maxDD = 0.0
    foreach ($p in $hpPNL) { $eq += $p; if ($eq -gt $peak) { $peak = $eq } else { $dd = $peak - $eq; if ($dd -gt $maxDD) { $maxDD = $dd } } }
    
    $hpResults.Add([PSCustomObject]@{
        HoldingBars=$h; TotalTrades=$c
        WinRate=[Math]::Round($wr,2); AvgWin=[Math]::Round($avgWin,4); AvgLoss=[Math]::Round($avgLoss,4)
        ProfitFactor=[Math]::Round($pf,4); Expectancy=[Math]::Round($expectancy,4)
        MaxDrawdown=[Math]::Round($maxDD,2); CompoundReturn=[Math]::Round($compoundRet,2)
        AvgReturnPerTrade=[Math]::Round($avgRet,4)
    })
}
$hpResults.ToArray() | Export-Csv (Join-Path $OutputDir "holding_period_comparison.csv") -NoTypeInformation
$hpResults | Format-Table HoldingBars,TotalTrades,WinRate,ProfitFactor,Expectancy,AvgReturnPerTrade,MaxDrawdown -AutoSize | Out-Host
Write-Host "Phase 23.2: holding_period_comparison.csv written"

# ===== PHASE 23.3: WINNER DEVELOPMENT =====
Write-Host "`n=== PHASE 23.3: WINNER DEVELOPMENT ===" -ForegroundColor Yellow
$winnerBars = @{} # bar -> average MFE
for ($k=1;$k-le$maxLife;$k++) { $winnerBars[$k] = New-Object 'System.Collections.Generic.List[double]' }
$winners = @()

for ($ti=0;$ti-lt$tradesArr.Count;$ti++) {
    $p5 = $lifePNL[$ti][4]  # PnL at bar 5
    if ($p5 -gt 0) {
        $winners += $ti
        $mfe = -1e10
        for ($k=1;$k-le$maxLife;$k++) {
            $v = $lifePNL[$ti][$k-1]
            if ($v -ne $null) { if ($v -gt $mfe) { $mfe = $v } }
            $winnerBars[$k].Add($mfe)
        }
    }
}

# Also track cumulative PnL (not just MFE)
$winnerPnL = @{}
for ($k=1;$k-le$maxLife;$k++) { $winnerPnL[$k] = New-Object 'System.Collections.Generic.List[double]' }
foreach ($ti in $winners) {
    for ($k=1;$k-le$maxLife;$k++) {
        $v = $lifePNL[$ti][$k-1]
        if ($v -ne $null) { $winnerPnL[$k].Add($v) }
    }
}

# Average MFE per bar
Write-Host "Winner progression (averages):"
Write-Host ("{0,-6} {1,-12} {2,-14} {3,-14}" -f "Bar", "AvgPnL", "AvgMFE", "MFE%ofFinal")
$finalAvgMFE = ($winnerBars[$maxLife].ToArray() | Measure-Object -Average).Average
for ($k=1;$k-le$maxLife;$k++) {
    $avgMFE = ($winnerBars[$k].ToArray() | Measure-Object -Average).Average
    $avgPnL = ($winnerPnL[$k].ToArray() | Measure-Object -Average).Average
    $pct = if ($finalAvgMFE -ne 0) { $avgMFE/$finalAvgMFE*100 } else { 0 }
    Write-Host ("{0,-6} {1,-12:N4} {2,-14:N4} {3,-14:N1}" -f $k,$avgPnL,$avgMFE,$pct)
}

# Find when winners hit 50%, 75%, 90% of final gain
$finalAvgPnL = ($winnerPnL[$maxLife].ToArray() | Measure-Object -Average).Average
Write-Host "`nWinner gain milestones (avg PnL = $([Math]::Round($finalAvgPnL,4))%):"
$milestones = @{}
foreach ($ti in $winners) {
    $finalP = $lifePNL[$ti][4]
    for ($k=1;$k-le$maxLife;$k++) {
        $v = $lifePNL[$ti][$k-1]
        if ($v -ne $null) {
            $ratio = if ($finalP -ne 0) { $v/$finalP*100 } else { 0 }
            if (-not $milestones.ContainsKey($k)) { $milestones[$k] = New-Object 'System.Collections.Generic.List[double]' }
            $milestones[$k].Add($ratio)
        }
    }
}
foreach ($pctTarget in @(50,75,90)) {
    $sumBars = 0; $count = 0
    foreach ($ti in $winners) {
        for ($k=1;$k-le$maxLife;$k++) {
            $v = $lifePNL[$ti][$k-1]
            if ($v -ne $null -and $lifePNL[$ti][4] -ne 0) {
                $ratio = $v/$lifePNL[$ti][4]*100
                if ($ratio -ge $pctTarget) { $sumBars += $k; $count++; break }
            }
        }
    }
    $avgBar = if ($count -gt 0) { $sumBars/$count } else { "N/A" }
    Write-Host "  $pctTarget% of final gain: avg bar $avgBar ($count/$($winners.Count) trades)"
}

# Write winner progression report
$wpLines = New-Object 'System.Collections.Generic.List[string]'
$wpLines.Add("# Winner Progression Report")
$wpLines.Add("")
$wpLines.Add("Analysis of $($winners.Count) winning trades (NetPnL > 0 at bar 5).")
$wpLines.Add("")
$wpLines.Add("## Average PnL and MFE by Bar")
$wpLines.Add("")
$wpLines.Add("| Bar | Avg PnL | Avg MFE | MFE % of Final |")
$wpLines.Add("|-----|---------|---------|----------------|")
for ($k=1;$k-le$maxLife;$k++) {
    $avgMFE = ($winnerBars[$k].ToArray() | Measure-Object -Average).Average
    $avgPnL = ($winnerPnL[$k].ToArray() | Measure-Object -Average).Average
    $pct = if ($finalAvgMFE -ne 0) { $avgMFE/$finalAvgMFE*100 } else { 0 }
    $wpLines.Add("| $k | $([Math]::Round($avgPnL,4))% | $([Math]::Round($avgMFE,4))% | $([Math]::Round($pct,1))% |")
}
$wpLines.Add("")
$wpLines.Add("## Milestone Analysis")
$wpLines.Add("")
foreach ($pctTarget in @(50,75,90)) {
    $sumBars = 0; $count = 0
    foreach ($ti in $winners) {
        for ($k=1;$k-le$maxLife;$k++) {
            $v = $lifePNL[$ti][$k-1]
            if ($v -ne $null -and $lifePNL[$ti][4] -ne 0) {
                $ratio = $v/$lifePNL[$ti][4]*100
                if ($ratio -ge $pctTarget) { $sumBars += $k; $count++; break }
            }
        }
    }
    $avgBar = if ($count -gt 0) { [Math]::Round($sumBars/$count,2) } else { "N/A" }
    $wpLines.Add("- **$pctTarget% of final gain**: achieved at average bar $avgBar ($count of $($winners.Count) winners)")
}
$wpLines.Add("")
$wpLines.Add("## Key Questions")
$wpLines.Add("")
# When does avg PnL cross 50% of final?
$halfBar = 0; $threeQBar = 0; $nineBar = 0
for ($k=1;$k-le$maxLife;$k++) {
    $avgPnL = ($winnerPnL[$k].ToArray() | Measure-Object -Average).Average
    if ($halfBar -eq 0 -and $avgPnL -ge $finalAvgPnL*0.5) { $halfBar = $k }
    if ($threeQBar -eq 0 -and $avgPnL -ge $finalAvgPnL*0.75) { $threeQBar = $k }
    if ($nineBar -eq 0 -and $avgPnL -ge $finalAvgPnL*0.9) { $nineBar = $k }
}
$wpLines.Add("- **50% of final gain**: ~bar $halfBar (avg)")
$wpLines.Add("- **75% of final gain**: ~bar $threeQBar (avg)")
$wpLines.Add("- **90% of final gain**: ~bar $nineBar (avg)")
$wpLines.Add("")
$wpLines.Add("Do winners mature early or late?")
if ($halfBar -le 3) { $wpLines.Add("- Winners mature **early**: 50% of gain by bar $halfBar.") }
elseif ($halfBar -le 5) { $wpLines.Add("- Winners develop at a **moderate pace**: 50% of gain by bar $halfBar.") }
else { $wpLines.Add("- Winners mature **late**: 50% of gain after bar $halfBar.") }
$wpLines.Add("")
$wpLines -join "`r`n" | Out-File (Join-Path $OutputDir "winner_progression.md") -Encoding utf8
Write-Host "Phase 23.3: winner_progression.md written"

# ===== PHASE 23.4: LOSER DEVELOPMENT =====
Write-Host "`n=== PHASE 23.4: LOSER DEVELOPMENT ===" -ForegroundColor Yellow
$loserBarsMAE = @{}; $loserBarsPnL = @{}
for ($k=1;$k-le$maxLife;$k++) { $loserBarsMAE[$k] = New-Object 'System.Collections.Generic.List[double]'; $loserBarsPnL[$k] = New-Object 'System.Collections.Generic.List[double]' }
$losers = @()

for ($ti=0;$ti-lt$tradesArr.Count;$ti++) {
    $p5 = $lifePNL[$ti][4]
    if ($p5 -le 0) {
        $losers += $ti
        $mae = 1e10
        for ($k=1;$k-le$maxLife;$k++) {
            $v = $lifePNL[$ti][$k-1]
            if ($v -ne $null) { if ($v -lt $mae) { $mae = $v } }
            $loserBarsMAE[$k].Add($mae)
            $loserBarsPnL[$k].Add($v)
        }
    }
}

# Average MAE and PnL per bar
Write-Host "Loser progression (averages):"
Write-Host ("{0,-6} {1,-12} {2,-14} {3,-14}" -f "Bar", "AvgPnL", "AvgMAE", "MAE%ofWorst")
$finalAvgMAE = ($loserBarsMAE[$maxLife].ToArray() | Measure-Object -Average).Average
for ($k=1;$k-le$maxLife;$k++) {
    $avgMAE = ($loserBarsMAE[$k].ToArray() | Measure-Object -Average).Average
    $avgPnL = ($loserBarsPnL[$k].ToArray() | Measure-Object -Average).Average
    $pct = if ($finalAvgMAE -ne 0) { $avgMAE/$finalAvgMAE*100 } else { 0 }
    Write-Host ("{0,-6} {1,-12:N4} {2,-14:N4} {3,-14:N1}" -f $k,$avgPnL,$avgMAE,$pct)
}

# Recovery analysis: how many losers ever recover to positive at any point?
$recoverCount = 0
foreach ($ti in $losers) {
    for ($k=1;$k-le$maxLife;$k++) {
        $v = $lifePNL[$ti][$k-1]
        if ($v -ne $null -and $v -gt 0) { $recoverCount++; break }
    }
}
$recoverPct = if ($losers.Count -gt 0) { $recoverCount/$losers.Count*100 } else { 0 }
Write-Host "Losers that ever recover to positive: $recoverCount / $($losers.Count) ($([Math]::Round($recoverPct,1))%)"

# When do losers reach their worst MAE?
$avgWorstBar = 0.0
foreach ($ti in $losers) {
    $worstMAE = 1e10; $worstBar = 1
    for ($k=1;$k-le$maxLife;$k++) {
        $v = $lifePNL[$ti][$k-1]
        if ($v -ne $null -and $v -lt $worstMAE) { $worstMAE=$v; $worstBar=$k }
    }
    $avgWorstBar += $worstBar
}
$avgWorstBar = if ($losers.Count -gt 0) { $avgWorstBar/$losers.Count } else { 0 }
Write-Host "Average bar of worst MAE: $([Math]::Round($avgWorstBar,2))"

# Write loser progression report
$lpLines = New-Object 'System.Collections.Generic.List[string]'
$lpLines.Add("# Loser Progression Report")
$lpLines.Add("")
$lpLines.Add("Analysis of $($losers.Count) losing trades (NetPnL <= 0 at bar 5).")
$lpLines.Add("")
$lpLines.Add("## Average PnL and MAE by Bar")
$lpLines.Add("")
$lpLines.Add("| Bar | Avg PnL | Avg MAE | MAE % of Final |")
$lpLines.Add("|-----|---------|---------|----------------|")
for ($k=1;$k-le$maxLife;$k++) {
    $avgMAE = ($loserBarsMAE[$k].ToArray() | Measure-Object -Average).Average
    $avgPnL = ($loserBarsPnL[$k].ToArray() | Measure-Object -Average).Average
    $pct = if ($finalAvgMAE -ne 0) { $avgMAE/$finalAvgMAE*100 } else { 0 }
    $lpLines.Add("| $k | $([Math]::Round($avgPnL,4))% | $([Math]::Round($avgMAE,4))% | $([Math]::Round($pct,1))% |")
}
$lpLines.Add("")
$lpLines.Add("## Recovery Analysis")
$lpLines.Add("")
$lpLines.Add("- Losers that ever recover to positive: $recoverCount / $($losers.Count) ($([Math]::Round($recoverPct,1))%)")
$lpLines.Add("- Average bar of worst MAE: $([Math]::Round($avgWorstBar,2))")
$lpLines.Add("")
$lpLines.Add("## Key Questions")
$lpLines.Add("")
$earlyWorsen = if ($avgWorstBar -le 3) { "Yes" } else { "No" }
$lpLines.Add("Do losers become obvious early?")
$lpLines.Add("- Average PnL at bar 1: $([Math]::Round(($loserBarsPnL[1].ToArray() | Measure-Object -Average).Average,4))%")
$lpLines.Add("- Average PnL at bar 3: $([Math]::Round(($loserBarsPnL[3].ToArray() | Measure-Object -Average).Average,4))%")
$lossEarly = ($loserBarsPnL[1].ToArray() | Measure-Object -Average).Average
if ($lossEarly -lt -0.5) { $lpLines.Add("- Losers become obvious early (avg -$([Math]::Round([Math]::Abs($lossEarly),2))% by bar 1).") }
else { $lpLines.Add("- Losers do NOT become obvious early (avg $([Math]::Round($lossEarly,4))% at bar 1).") }
$lpLines.Add("")
$lpLines.Add("Do they recover? $recoverCount of $($losers.Count) ($([Math]::Round($recoverPct,1))%) ever show positive PnL.")
if ($recoverPct -lt 20) { $lpLines.Add("- Most losers do NOT recover. They are unrecoverable early.") }
elseif ($recoverPct -lt 50) { $lpLines.Add("- Some losers recover, but most do not.") }
else { $lpLines.Add("- Many losers recover at some point during the holding period.") }
$lpLines.Add("")
$lpLines.Add("At what bar do they reach their worst excursion?")
$lpLines.Add("- Average: bar $([Math]::Round($avgWorstBar,2))")
if ($avgWorstBar -le 4) { $lpLines.Add("- Losers typically hit their worst point **before the current 5-bar exit**.") }
else { $lpLines.Add("- Losers often continue worsening **after the current 5-bar exit**.") }
$lpLines.Add("")
$lpLines -join "`r`n" | Out-File (Join-Path $OutputDir "loser_progression.md") -Encoding utf8
Write-Host "Phase 23.4: loser_progression.md written"

# ===== PHASE 23.5: EXIT EFFICIENCY =====
Write-Host "`n=== PHASE 23.5: EXIT EFFICIENCY ===" -ForegroundColor Yellow
$maxBefore5=0; $maxAt5=0; $maxAfter5=0
$continuedImprove=0; $holdingHelped=0; $holdingHurt=0

foreach ($ti in 0..($tradesArr.Count-1)) {
    $pnl5 = $lifePNL[$ti][4]
    
    # Find max PnL within bars 1..20
    $maxPnL = -1e10; $maxBar = 0
    for ($k=1;$k-le$maxLife;$k++) {
        $v = $lifePNL[$ti][$k-1]
        if ($v -ne $null -and $v -gt $maxPnL) { $maxPnL = $v; $maxBar = $k }
    }
    if ($maxBar -lt 5) { $maxBefore5++ }
    elseif ($maxBar -eq 5) { $maxAt5++ }
    else { $maxAfter5++ }
    
    # Would holding longer improve PnL?
    $pnlLonger = $lifePNL[$ti][$maxLife-1]
    if ($pnlLonger -ne $null) {
        if ($pnlLonger -gt $pnl5) { $holdingHelped++ }
        elseif ($pnlLonger -lt $pnl5) { $holdingHurt++ }
    }
    
    # Does PnL continue improving after bar 5?
    $improved = $false
    for ($k=6;$k-le$maxLife;$k++) {
        $v = $lifePNL[$ti][$k-1]
        if ($v -ne $null -and $v -gt $pnl5) { $improved = $true; break }
    }
    if ($improved) { $continuedImprove++ }
}

$total = $tradesArr.Count
Write-Host "Max PnL occurs before bar 5: $maxBefore5 / $total ($([Math]::Round($maxBefore5/$total*100,1))%)"
Write-Host "Max PnL occurs at bar 5: $maxAt5 / $total ($([Math]::Round($maxAt5/$total*100,1))%)"
Write-Host "Max PnL occurs after bar 5: $maxAfter5 / $total ($([Math]::Round($maxAfter5/$total*100,1))%)"
Write-Host "Continued improvement after bar 5: $continuedImprove / $total ($([Math]::Round($continuedImprove/$total*100,1))%)"
Write-Host "Holding to bar 20 would help: $holdingHelped / $total ($([Math]::Round($holdingHelped/$total*100,1))%)"
Write-Host "Holding to bar 20 would hurt: $holdingHurt / $total ($([Math]::Round($holdingHurt/$total*100,1))%)"

# Write exit efficiency report
$eeLines = New-Object 'System.Collections.Generic.List[string]'
$eeLines.Add("# Exit Efficiency Report")
$eeLines.Add("")
$eeLines.Add("Evaluating the current 5-bar fixed exit against bars 1-20 for $total trades.")
$eeLines.Add("")
$eeLines.Add("## When Does Max PnL Occur?")
$eeLines.Add("")
$eeLines.Add("| Timing | Count | Percent |")
$eeLines.Add("|--------|-------|---------|")
$eeLines.Add("| Before bar 5 | $maxBefore5 | $([Math]::Round($maxBefore5/$total*100,1))% |")
$eeLines.Add("| Exactly at bar 5 | $maxAt5 | $([Math]::Round($maxAt5/$total*100,1))% |")
$eeLines.Add("| After bar 5 | $maxAfter5 | $([Math]::Round($maxAfter5/$total*100,1))% |")
$eeLines.Add("")
$eeLines.Add("## Would Holding Longer Help?")
$eeLines.Add("")
$eeLines.Add("- Trades that improve after bar 5: $continuedImprove / $total ($([Math]::Round($continuedImprove/$total*100,1))%)")
$eeLines.Add("- Holding to bar 20 would increase PnL: $holdingHelped / $total ($([Math]::Round($holdingHelped/$total*100,1))%)")
$eeLines.Add("- Holding to bar 20 would decrease PnL: $holdingHurt / $total ($([Math]::Round($holdingHurt/$total*100,1))%)")
$eeLines.Add("")
$eeLines.Add("## Current Exit Assessment")
$eeLines.Add("")
$optBar = ($maxBefore5*"-1" + $maxAt5*"0" + $maxAfter5*"1")  # just use numerical
if ($maxAfter5 -gt $maxAt5 -and $maxAfter5 -gt $maxBefore5) {
    $eeLines.Add("Most trades achieve maximum profit **after** the current 5-bar exit. The exit may be early.")
} elseif ($maxBefore5 -gt $maxAt5 -and $maxBefore5 -gt $maxAfter5) {
    $eeLines.Add("Most trades achieve maximum profit **before** the current 5-bar exit. The exit may be late.")
} else {
    $eeLines.Add("Maximum profit is balanced around the current 5-bar exit.")
}
$eeLines.Add("")
$eeLines -join "`r`n" | Out-File (Join-Path $OutputDir "exit_efficiency.md") -Encoding utf8
Write-Host "Phase 23.5: exit_efficiency.md written"

# ===== PHASE 23.6: EQUITY BY HOLDING PERIOD =====
Write-Host "`n=== PHASE 23.6: EQUITY BY HOLDING PERIOD ===" -ForegroundColor Yellow
$hpMetrics = New-Object 'System.Collections.Generic.List[PSObject]'

for ($h=1;$h-le$maxLife;$h++) {
    $hpPNL = @()
    foreach ($arr in $lifePNL) {
        $v = $arr[$h-1]
        if ($v -ne $null) { $hpPNL += $v }
    }
    $c = $hpPNL.Count
    if ($c -eq 0) { continue }
    
    $wins = @($hpPNL | Where-Object { $_ -gt 0 })
    $losses = @($hpPNL | Where-Object { $_ -le 0 })
    $nw = $wins.Count; $nl = $losses.Count
    $wr = $nw/$c*100
    $avgWin = if ($nw -gt 0) { ($wins | Measure-Object -Average).Average } else { 0 }
    $avgLoss = if ($nl -gt 0) { ($losses | Measure-Object -Average).Average } else { 0 }
    $pf = if ([Math]::Abs($avgLoss) -gt 0) { ($nw*$avgWin)/($nl*[Math]::Abs($avgLoss)) } else { 0 }
    $expectancy = ($wr/100*$avgWin + (1-$wr/100)*$avgLoss)
    $avgRet = ($hpPNL | Measure-Object -Average).Average
    $sumPos = ($wins | Measure-Object -Sum).Sum
    $sumNeg = ($losses | Measure-Object -Sum).Sum
    
    # Compound return
    $compound = 1.0
    foreach ($p in $hpPNL) { $compound *= (1 + $p/100) }
    $compoundRet = ($compound-1)*100
    
    # Max DD (additive)
    $eq = 0.0; $peak = 0.0; $maxDD = 0.0
    foreach ($p in $hpPNL) { $eq += $p; if ($eq -gt $peak) { $peak = $eq } else { $dd = $peak - $eq; if ($dd -gt $maxDD) { $maxDD = $dd } } }
    
    # Sharpe-like metric: avg / stdev
    $std = if ($c -gt 1) { [Math]::Sqrt(($hpPNL | ForEach-Object { ($_ - $avgRet)*($_ - $avgRet) } | Measure-Object -Sum).Sum / ($c-1)) } else { 0 }
    $sharpe = if ($std -gt 0) { $avgRet/$std } else { 0 }
    
    $hpMetrics.Add([PSCustomObject]@{
        HoldingBars=$h; TotalTrades=$c; WinRate=[Math]::Round($wr,2)
        AvgWin=[Math]::Round($avgWin,4); AvgLoss=[Math]::Round($avgLoss,4)
        ProfitFactor=[Math]::Round($pf,4); Expectancy=[Math]::Round($expectancy,4)
        SumProfits=[Math]::Round($sumPos,2); SumLosses=[Math]::Round($sumNeg,2)
        NetProfit=[Math]::Round($sumPos+$sumNeg,2)
        CompoundReturn=[Math]::Round($compoundRet,2); MaxDrawdown=[Math]::Round($maxDD,2)
        AvgReturn=[Math]::Round($avgRet,4); Sharpe=[Math]::Round($sharpe,4)
    })
}
$hpMetrics.ToArray() | Export-Csv (Join-Path $OutputDir "holding_period_metrics.csv") -NoTypeInformation
$hpMetrics | Format-Table HoldingBars,TotalTrades,WinRate,ProfitFactor,Expectancy,NetProfit,CompoundReturn,MaxDrawdown,Sharpe -AutoSize | Out-Host
Write-Host "Phase 23.6: holding_period_metrics.csv written"

# ===== FINAL REPORT =====
Write-Host "`n=== FINAL REPORT ===" -ForegroundColor Cyan
$totalT = $tradesArr.Count
$actualWR = ($tradesArr | Where-Object { $_.NetPnL -gt 0 }).Count / $totalT * 100
$actualPF = [Math]::Round($hpResults[4].ProfitFactor,2)

# Find best holding period by compound return
$bestRow = $hpMetrics | Sort-Object CompoundReturn -Descending | Select-Object -First 1
$bestBars = $bestRow.HoldingBars

# Find best holding period by Sharpe
$bestSharpeRow = $hpMetrics | Sort-Object Sharpe -Descending | Select-Object -First 1
$bestSharpeBars = $bestSharpeRow.HoldingBars

$report = New-Object 'System.Collections.Generic.List[string]'
$report.Add("# Trade Lifecycle Report")
$report.Add("")
$report.Add("SOL 30m | Stoch(k=5,d=5,ob=80,os=10) | LONG only | $totalT trades | Fee 0.05% | Slippage 0.02%")
$report.Add("")
$report.Add("## Edge Evolution Summary")
$report.Add("")
$report.Add("| Bar | WR% | PF | Expectancy | AvgRet% | Net PnL% | Compound Ret% | Max DD% | Sharpe |")
$report.Add("|-----|-----|----|------------|---------|----------|---------------|---------|--------|")
foreach ($r in $hpMetrics) {
    $report.Add("| $($r.HoldingBars) | $($r.WinRate) | $($r.ProfitFactor) | $($r.Expectancy) | $($r.AvgReturn) | $($r.NetProfit) | $($r.CompoundReturn) | $($r.MaxDrawdown) | $($r.Sharpe) |")
}
$report.Add("")
$report.Add("## 1. Is the current 5-bar exit near the optimum?")
$report.Add("")
$curRow = $hpMetrics | Where-Object { $_.HoldingBars -eq 5 } | Select-Object -First 1
if ($bestBars -eq 5) {
    $report.Add("**YES.** The 5-bar exit is at the global optimum (Compound Return = $($curRow.CompoundReturn)%, Sharpe = $($curRow.Sharpe)).")
} else {
    $report.Add("**NO.** The 5-bar exit (Compound Return = $($curRow.CompoundReturn)%, Sharpe = $($curRow.Sharpe)) is not at the global optimum.")
    $report.Add("- Best holding period by Compound Return: $bestBars bars ($($bestRow.CompoundReturn)%, Sharpe $($bestRow.Sharpe))")
    $report.Add("- Best holding period by Sharpe: $bestSharpeBars bars ($($bestSharpeRow.Sharpe), Compound Return $($bestSharpeRow.CompoundReturn)%)")
}
$report.Add("")
$report.Add("## 2. Where does the edge appear strongest?")
$report.Add("")
$report.Add("Examining how WR, PF, expectancy, and Sharpe evolve with holding period:")
$earlyWR = ($hpMetrics | Where-Object { $_.HoldingBars -le 3 } | Measure-Object -Average WinRate).Average
$lateWR = ($hpMetrics | Where-Object { $_.HoldingBars -ge 10 } | Measure-Object -Average WinRate).Average
$report.Add("- WR at bars 1-3: $([Math]::Round($earlyWR,1))%")
$report.Add("- WR at bars 10-20: $([Math]::Round($lateWR,1))%")
$peakPF = $hpMetrics | Sort-Object ProfitFactor -Descending | Select-Object -First 1
$report.Add("- Peak PF: bar $($peakPF.HoldingBars) (PF=$($peakPF.ProfitFactor))")
$peakExp = $hpMetrics | Sort-Object Expectancy -Descending | Select-Object -First 1
$report.Add("- Peak Expectancy: bar $($peakExp.HoldingBars) (E=$($peakExp.Expectancy))")
$peakSharpe = $hpMetrics | Sort-Object Sharpe -Descending | Select-Object -First 1
$report.Add("- Peak Sharpe: bar $($peakSharpe.HoldingBars) (S=$($peakSharpe.Sharpe))")
$report.Add("")
$report.Add("## 3. Do winners mature early or late?")
$report.Add("")
$report.Add("- Average PnL trajectory shows 50% of final gain achieved by bar $halfBar.")
$report.Add("- Average PnL trajectory shows 75% of final gain achieved by bar $threeQBar.")
$report.Add("- Average PnL trajectory shows 90% of final gain achieved by bar $nineBar.")
if ($halfBar -le 3) { $report.Add("- Winners mature **early**.") }
elseif ($halfBar -le 5) { $report.Add("- Winners develop at a **moderate pace**.") }
else { $report.Add("- Winners mature **late**.") }
$report.Add("")
$report.Add("## 4. Do losers become unrecoverable early or late?")
$report.Add("")
$report.Add("- Average bar of worst MAE: $([Math]::Round($avgWorstBar,2))")
$report.Add("- Losers that ever recover to positive: $([Math]::Round($recoverPct,1))%")
if ($avgWorstBar -le 3) {
    $report.Add("- Losers hit their worst point **early** (before bar 4). Most damage occurs quickly.")
} elseif ($avgWorstBar -le 5) {
    $report.Add("- Losers worsen through the holding period, hitting worst point around the current exit.")
} else {
    $report.Add("- Losers continue worsening **after** the current 5-bar exit.")
}
$report.Add("")
$report.Add("## 5. Is exit timing the main remaining source of improvement?")
$report.Add("")
$cur5 = $hpMetrics | Where-Object { $_.HoldingBars -eq 5 } | Select-Object -First 1
$improvePct = if ($cur5.CompoundReturn -ne 0) { ($bestRow.CompoundReturn - $cur5.CompoundReturn)/[Math]::Abs($cur5.CompoundReturn)*100 } else { 0 }
$report.Add("- Current (5-bar): Compound Return = $($cur5.CompoundReturn)%, PF = $($cur5.ProfitFactor), Sharpe = $($cur5.Sharpe)")
$report.Add("- Best alternative: $bestBars bars: Compound Return = $($bestRow.CompoundReturn)%, PF = $($bestRow.ProfitFactor), Sharpe = $($bestRow.Sharpe)")
$report.Add("- Potential improvement from changing exit: $([Math]::Round($improvePct,1))% relative change in compound return")
if ($improvePct -gt 50) {
    $report.Add("- **YES.** Exit timing has substantial impact. The edge continues to develop well beyond the current 5-bar exit.")
} elseif ($improvePct -gt 10) {
    $report.Add("- **PARTIALLY.** Exit timing matters, but edge is not dramatically different across holding periods 3-10.")
} else {
    $report.Add("- **NO.** Exit timing has minimal impact. The edge is stable across holding periods.")
}
$report.Add("")
$report.Add("## Supporting Files")
$report.Add("")
$report.Add("- trade_lifecycle.csv: Bar-by-bar PnL for all $totalT trades")
$report.Add("- holding_period_comparison.csv: Edge metrics at each holding period 1-20")
$report.Add("- winner_progression.md: Winner MFE and milestone analysis")
$report.Add("- loser_progression.md: Loser MAE and recovery analysis")
$report.Add("- exit_efficiency.md: Exit timing efficiency assessment")
$report.Add("- holding_period_metrics.csv: Full equity simulation by holding period")
$report.Add("")

$report -join "`r`n" | Out-File (Join-Path $OutputDir "trade_lifecycle_report.md") -Encoding utf8
Write-Host "trade_lifecycle_report.md written" -ForegroundColor Green

$stopwatch.Stop()
Write-Host "`n=== PHASE 23 COMPLETE ($([Math]::Round($stopwatch.Elapsed.TotalSeconds,1))s) ===" -ForegroundColor Cyan
