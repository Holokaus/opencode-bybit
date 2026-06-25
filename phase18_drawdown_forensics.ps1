param([string]$OutputDir=".")
$ErrorActionPreference="Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

Write-Host "=== PHASE 18 - DRAWDOWN FORENSICS ===" -ForegroundColor Cyan
$epoch = New-Object DateTime 1970,1,1,0,0,0,([DateTimeKind]::Utc)

# Load data
$k=Import-Csv (Join-Path $PSScriptRoot "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n=$k.Count
$hi=[double[]]::new($n);$lo=[double[]]::new($n);$cl=[double[]]::new($n);$vo=[double[]]::new($n);$op=[double[]]::new($n);$ts=[long[]]::new($n);$dt=New-Object 'string[]' $n
for($i=0;$i-lt$n;$i++){$hi[$i]=[double]$k[$i].High;$lo[$i]=[double]$k[$i].Low;$op[$i]=[double]$k[$i].Open;$cl[$i]=[double]$k[$i].Close;$vo[$i]=[double]$k[$i].Volume;$ts[$i]=[long]$k[$i].Timestamp;$dt[$i]=$k[$i].Date}
Remove-Variable k -ErrorAction SilentlyContinue
Write-Host ("Bars: " + $n)

# Generate signals
Write-Host "Generating signals..."
$sig = Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $cl $hi $lo $vo $n
Write-Host ("Signal array: " + $sig.Length)

# Build trades (same as Phase 14/16)
$trades = New-Object 'Collections.Generic.List[PSObject]'
for ($si = 100; $si -lt $sig.Length; $si++) {
    if (-not $sig[$si]) { continue }
    $ex = $si + 5; if ($ex -ge $n) { continue }
    $entryPrice = $cl[$si]; $exitPrice = $cl[$ex]
    $ret = ($exitPrice - $entryPrice) / $entryPrice * 100
    $feeRate = 0.0005; $slippage = 0.0002
    $effEntry = $entryPrice * (1 + $slippage) * (1 + $feeRate)
    $effExit = $exitPrice * (1 - $slippage) * (1 - $feeRate)
    $pnl = ($effExit - $effEntry) / $effEntry * 100
    $trades.Add([PSCustomObject]@{
        ID=($trades.Count+1); EntryIdx=$si; ExitIdx=$ex
        EntryDate=$dt[$si]; ExitDate=$dt[$ex]
        EntryPrice=[Math]::Round($entryPrice,4); ExitPrice=[Math]::Round($exitPrice,4)
        ReturnPct=[Math]::Round($ret,4); PnL=[Math]::Round($pnl,4)
        Year=($dt[$si] -split '[- ]')[0]; Month=($dt[$si] -split '[- ]')[1]
        Quarter="Q" + [Math]::Ceiling([int](($dt[$si] -split '[- ]')[1])/3)
    })
}
$tradesArr = $trades.ToArray()
Write-Host ("Trades: " + $tradesArr.Count)

$totalPnL = ($tradesArr | Measure-Object -Sum PnL).Sum
$maxPeak=0.0;$maxDd=0.0;$cum=0.0
foreach($t in $tradesArr){$cum+=$t.PnL;if($cum-gt$maxPeak){$maxPeak=$cum};$dd=if($maxPeak-gt0){($maxPeak-$cum)/$maxPeak*100}else{0};if($dd-gt$maxDd){$maxDd=$dd}}
Write-Host ("Total PnL: $([Math]::Round($totalPnL,2))% Max DD: $([Math]::Round($maxDd,2))%")

# Precompute indicators for regime/volatility
Write-Host "Computing indicators..."
$sma50 = Calc-SMA $cl 50; $sma200 = Calc-SMA $cl 200
$atr14 = Calc-ATR $hi $lo $cl 14
$adx,$du,$dd = Calc-ADX $hi $lo $cl 14
$stochVals = Calc-Stoch $hi $lo $cl 5 5

function Get-ATRPercentile($atrArr, $atrIdx, $lookback) {
    $start = [Math]::Max(0, $atrIdx - $lookback); $end = $atrIdx
    $vals = $atrArr[$start..$end] | Where-Object { $_ -gt 0 }
    if ($vals.Count -lt 10) { return 50 }
    $sorted = $vals | Sort-Object
    $rank = 0; foreach ($v in $sorted) { if ($v -le $atrArr[$atrIdx]) { $rank++ } }
    return [Math]::Round($rank / $sorted.Count * 100, 1)
}

function Get-VolPercentile($volArr, $volIdx, $lookback) {
    $start = [Math]::Max(0, $volIdx - $lookback); $end = $volIdx
    $vals = $volArr[$start..$end] | Where-Object { $_ -gt 0 }
    if ($vals.Count -lt 10) { return 50 }
    $sorted = $vals | Sort-Object
    $rank = 0; foreach ($v in $sorted) { if ($v -le $volArr[$volIdx]) { $rank++ } }
    return [Math]::Round($rank / $sorted.Count * 100, 1)
}

function Classify-Regime($idx, $adxArr, $clArr, $sma50Arr, $sma200Arr, $atrArr, $volArr) {
    if ($idx -le 0 -or $idx -ge $clArr.Length) { return "RANGE" }
    $adxV = if($idx -lt $adxArr.Length -and $idx -ge 0){$adxArr[$idx]}else{0}
    $s50 = $sma50Arr[$idx]; $s200 = $sma200Arr[$idx]; $c = $clArr[$idx]
    $atrPct = Get-ATRPercentile $atrArr $idx 100
    $volPct = Get-VolPercentile $volArr $idx 100
    
    if ($atrPct -gt 80) { return "VOL_EXPANSION" }
    if ($atrPct -lt 20) { return "VOL_COMPRESSION" }
    if ($adxV -gt 25 -and $c -gt $s50 -and $s50 -gt $s200) { return "TREND_UP" }
    if ($adxV -gt 25 -and $c -lt $s50 -and $s50 -lt $s200) { return "TREND_DOWN" }
    if ($volPct -gt 80 -and $adxV -le 25) { return "ACCUMULATION" }
    if ($volPct -lt 20 -and $adxV -le 25) { return "DISTRIBUTION" }
    return "RANGE"
}

function Classify-Vol($idx, $atrArr) {
    if ($idx -le 0 -or $idx -ge $atrArr.Length) { return "MEDIUM_VOL" }
    $atrPct = Get-ATRPercentile $atrArr $idx 100
    if ($atrPct -gt 70) { return "HIGH_VOL" }
    if ($atrPct -lt 30) { return "LOW_VOL" }
    return "MEDIUM_VOL"
}

# ============ PHASE 18.1: DRAWDOWN PERIODS ============
Write-Host "`n=== PHASE 18.1: DRAWDOWN PERIODS ==="

# Build equity curve and identify drawdowns
$equityCurve = New-Object 'Collections.Generic.List[double]'
$cumPnl = 0.0
$equityCurve.Add(0.0)
foreach ($t in $tradesArr) { $cumPnl += $t.PnL; $equityCurve.Add($cumPnl) }
$eqArr = $equityCurve.ToArray()

$ddPeriods = New-Object 'Collections.Generic.List[PSObject]'
$i = 0
while ($i -lt $eqArr.Length) {
    # Find peak
    $peakIdx = $i; $peakVal = $eqArr[$i]
    for ($j = $i + 1; $j -lt $eqArr.Length; $j++) {
        if ($eqArr[$j] -gt $peakVal) { $peakIdx = $j; $peakVal = $eqArr[$j] }
        elseif ($eqArr[$j] -lt $peakVal) { break }
    }
    # After finding FIRST decline from peak, track trough until recovery
    if ($peakIdx + 1 -lt $eqArr.Length -and $eqArr[$peakIdx + 1] -lt $peakVal) {
        $troughIdx = $peakIdx; $troughVal = $peakVal
        $recoveryIdx = $peakIdx
        for ($j = $peakIdx + 1; $j -lt $eqArr.Length; $j++) {
            if ($eqArr[$j] -lt $troughVal) { $troughIdx = $j; $troughVal = $eqArr[$j] }
            if ($eqArr[$j] -ge $peakVal) { $recoveryIdx = $j; break }
        }
        $ddDepth = ($peakVal - $troughVal) / $peakVal * 100
        if ($ddDepth -ge 0.5 -or ($recoveryIdx - $peakIdx) -gt 1) {
            $tradesInDD = if($recoveryIdx -gt $peakIdx) { $recoveryIdx - $peakIdx } else { $troughIdx - $peakIdx }
            $startTradeIdx = [Math]::Max(0, $peakIdx - 1)
            $endCandidate = if($recoveryIdx -gt $peakIdx) { $recoveryIdx - 1 } else { $troughIdx }
            $endTradeIdx = [Math]::Min($tradesArr.Count - 1, $endCandidate)
            $netPnl = 0.0
            for ($ti = $startTradeIdx; $ti -le $endTradeIdx; $ti++) { $netPnl += $tradesArr[$ti].PnL }
            $startDate = if($startTradeIdx -lt $tradesArr.Count){$tradesArr[$startTradeIdx].EntryDate}else{"N/A"}
            $endDate = if($endTradeIdx -lt $tradesArr.Count -and $endTradeIdx -ge 0){$tradesArr[$endTradeIdx].ExitDate}else{"N/A"}
            $durBars = $recoveryIdx - $peakIdx
            # Estimate days from trade dates
            $durDays = 0
            if ($startTradeIdx -lt $tradesArr.Count -and $endTradeIdx -lt $tradesArr.Count -and $endTradeIdx -ge $startTradeIdx) {
                $sDt = $epoch.AddMilliseconds($ts[$tradesArr[$startTradeIdx].EntryIdx])
                $eDt = $epoch.AddMilliseconds($ts[$tradesArr[$endTradeIdx].ExitIdx])
                $durDays = [Math]::Round(($eDt - $sDt).TotalDays, 1)
            }
            $ddPeriods.Add([PSCustomObject]@{
                DrawdownID = $ddPeriods.Count + 1
                StartDate = $startDate
                EndDate = $endDate
                DepthPercent = [Math]::Round($ddDepth, 2)
                DurationBars = $durBars
                DurationDays = $durDays
                TradesInvolved = $tradesInDD
                NetPnL = [Math]::Round($netPnl, 2)
            })
            $i = if($recoveryIdx -gt $peakIdx) { $recoveryIdx } else { $troughIdx + 1 }
        } else { $i = $peakIdx + 1 }
    } else { $i = $peakIdx + 1 }
}

# Sort by depth descending
$ddSorted = $ddPeriods.ToArray() | Sort-Object DepthPercent -Descending
$ddSorted | Export-Csv (Join-Path $OutputDir "drawdown_periods.csv") -NoTypeInformation
Write-Host ("Drawdown periods: " + $ddSorted.Count)
if ($ddSorted.Count -gt 0) {
    Write-Host ("  Largest: " + $ddSorted[0].DepthPercent + "% depth, " + $ddSorted[0].DurationDays + " days")
    $ddSorted | Select-Object -First 5 | Format-Table DrawdownID,DepthPercent,DurationDays,TradesInvolved -AutoSize
}

# ============ PHASE 18.2: LOSS CONTRIBUTION ============
Write-Host "`n=== PHASE 18.2: LOSS CONTRIBUTION ==="
$losingTrades = $tradesArr | Where-Object { $_.PnL -lt 0 } | Sort-Object PnL
$totalLoss = ($losingTrades | Measure-Object -Sum PnL).Sum
$totalTrades = $tradesArr.Count

$lossContrib = New-Object 'Collections.Generic.List[PSObject]'
@(0.01, 0.05, 0.10, 0.20) | ForEach-Object {
    $pct = $_
    $count = [Math]::Max(1, [Math]::Floor($totalTrades * $pct))
    $topN = $losingTrades | Select-Object -First $count
    $loss = ($topN | Measure-Object -Sum PnL).Sum
    $percent = if($totalLoss -ne 0){[Math]::Round([Math]::Abs($loss / $totalLoss * 100),2)}else{0}
    $lossContrib.Add([PSCustomObject]@{
        Group = ("Top " + ($pct*100) + "%")
        TradeCount = $count
        TotalLoss = [Math]::Round($loss, 2)
        PercentOfTotalDrawdown = $percent
    })
}
$lossContrib.ToArray() | Export-Csv (Join-Path $OutputDir "loss_contribution_analysis.csv") -NoTypeInformation
$lossContrib.ToArray() | Format-Table -AutoSize

$top1pct = $lossContrib | Where-Object { $_.Group -eq "Top 1%" }
$top1pctVal = if($top1pct){$top1pct.PercentOfTotalDrawdown}else{0}
Write-Host ("Top 1% of all trades contribute " + $top1pctVal + "% of total drawdown")

# ============ PHASE 18.3: LOSING STREAK ANALYSIS ============
Write-Host "`n=== PHASE 18.3: LOSING STREAKS ==="
$streaks = New-Object 'Collections.Generic.List[int]'
$currentStreak = 0
foreach ($t in $tradesArr) {
    if ($t.PnL -le 0) { $currentStreak++ }
    else { if ($currentStreak -gt 0) { $streaks.Add($currentStreak); $currentStreak = 0 } }
}
if ($currentStreak -gt 0) { $streaks.Add($currentStreak) }
$streakArr = $streaks.ToArray()

$streakAnalysis = New-Object 'Collections.Generic.List[PSObject]'
if ($streakArr.Count -gt 0) {
    $sortedStreaks = $streakArr | Sort-Object
    $maxS = $sortedStreaks[-1]
    $avgS = ($sortedStreaks | Measure-Object -Average).Average
    $medS = $sortedStreaks[[Math]::Floor($sortedStreaks.Count / 2)]
    $p95Idx = [Math]::Ceiling($sortedStreaks.Count * 0.95) - 1
    $p95 = $sortedStreaks[$p95Idx]
    
    $streakAnalysis.Add([PSCustomObject]@{Metric="MaximumLosingStreak"; Value=$maxS})
    $streakAnalysis.Add([PSCustomObject]@{Metric="AverageLosingStreak"; Value=[Math]::Round($avgS,2)})
    $streakAnalysis.Add([PSCustomObject]@{Metric="MedianLosingStreak"; Value=$medS})
    $streakAnalysis.Add([PSCustomObject]@{Metric="P95LosingStreak"; Value=$p95})
    $streakAnalysis.Add([PSCustomObject]@{Metric="TotalStreaks"; Value=$streakArr.Count})
    $streakAnalysis.Add([PSCustomObject]@{Metric="LongestStreakPnL"; Value=""}) # computed below
    
    # Compute PnL during longest streak
    $maxStreakLen = 0; $maxStreakIdx = -1
    $cs = 0; $csi = 0
    for ($ti = 0; $ti -lt $tradesArr.Count; $ti++) {
        if ($tradesArr[$ti].PnL -le 0) { if ($cs -eq 0) { $csi = $ti }; $cs++ }
        else { if ($cs -gt $maxStreakLen) { $maxStreakLen = $cs; $maxStreakIdx = $csi }; $cs = 0 }
    }
    if ($cs -gt $maxStreakLen) { $maxStreakLen = $cs; $maxStreakIdx = $csi }
    $longestPnL = 0.0
    if ($maxStreakIdx -ge 0) { for ($ti = $maxStreakIdx; $ti -lt $maxStreakIdx + $maxStreakLen; $ti++) { $longestPnL += $tradesArr[$ti].PnL } }
    $streakAnalysis.Add([PSCustomObject]@{Metric="LongestStreakPnL"; Value=[Math]::Round($longestPnL,2)})
    
    # Distribution
    $distinct = $streakArr | Group-Object | Sort-Object Name
    foreach ($g in $distinct) {
        $streakAnalysis.Add([PSCustomObject]@{Metric=("StreakLen_" + $g.Name); Value=$g.Count})
    }
}
$streakAnalysis.ToArray() | Export-Csv (Join-Path $OutputDir "losing_streak_analysis.csv") -NoTypeInformation
$streakAnalysis.ToArray() | Format-Table -AutoSize

# ============ PHASE 18.4: TIME-BASED ATTRIBUTION ============
Write-Host "`n=== PHASE 18.4: TIME ATTRIBUTION ==="
$timeDD = New-Object 'Collections.Generic.List[PSObject]'
$timeGroups = $tradesArr | Group-Object Year
foreach ($g in $timeGroups) {
    $losses = $g.Group | Where-Object { $_.PnL -lt 0 }
    $lossSum = ($losses | Measure-Object -Sum PnL).Sum
    $tradeCount = $g.Count
    $lossCount = $losses.Count
    $timeDD.Add([PSCustomObject]@{TimeGroup=("Year_"+$g.Name); Period=$g.Name; Trades=$tradeCount; Losses=$lossCount; DrawdownContribution=[Math]::Round($lossSum,2)})
}

$qGroups = $tradesArr | Group-Object Year,Quarter
foreach ($g in $qGroups) {
    $parts = $g.Name -split ', '; $yr = $parts[0]; $qr = $parts[1]
    $losses = $g.Group | Where-Object { $_.PnL -lt 0 }
    $lossSum = ($losses | Measure-Object -Sum PnL).Sum
    $timeDD.Add([PSCustomObject]@{TimeGroup=($yr+"_"+$qr); Period=($yr+" "+$qr); Trades=$g.Count; Losses=$losses.Count; DrawdownContribution=[Math]::Round($lossSum,2)})
}

$mGroups = $tradesArr | Group-Object Year,Month
foreach ($g in $mGroups) {
    $parts = $g.Name -split ', '; $yr = $parts[0]; $mo = $parts[1]
    $losses = $g.Group | Where-Object { $_.PnL -lt 0 }
    $lossSum = ($losses | Measure-Object -Sum PnL).Sum
    $timeDD.Add([PSCustomObject]@{TimeGroup=($yr+"_"+$mo); Period=($yr+"-"+$mo); Trades=$g.Count; Losses=$losses.Count; DrawdownContribution=[Math]::Round($lossSum,2)})
}
$timeDD.ToArray() | Export-Csv (Join-Path $OutputDir "time_drawdown_attribution.csv") -NoTypeInformation
Write-Host ("Time groups: " + $timeDD.Count)

# ============ PHASE 18.5: REGIME ATTRIBUTION ============
Write-Host "`n=== PHASE 18.5: REGIME ATTRIBUTION ==="
$regimeDD = New-Object 'Collections.Generic.List[PSObject]'
$regimeBuckets = @{}
foreach ($t in $tradesArr) {
    $reg = Classify-Regime $t.EntryIdx $adx $cl $sma50 $sma200 $atr14 $vo
    if (-not $regimeBuckets.ContainsKey($reg)) { $regimeBuckets[$reg] = New-Object 'Collections.Generic.List[PSObject]' }
    $regimeBuckets[$reg].Add($t)
}
$allRegimes = @("TREND_UP","TREND_DOWN","RANGE","ACCUMULATION","DISTRIBUTION","VOL_EXPANSION","VOL_COMPRESSION")
foreach ($r in $allRegimes) {
    $tsInReg = if($regimeBuckets.ContainsKey($r)){$regimeBuckets[$r].ToArray()}else{@()}
    $lossesInReg = $tsInReg | Where-Object { $_.PnL -lt 0 }
    $lossSum = ($lossesInReg | Measure-Object -Sum PnL).Sum
    $regimeDD.Add([PSCustomObject]@{
        Regime=$r; Trades=$tsInReg.Count
        Losses=$lossesInReg.Count
        LossRate=if($tsInReg.Count -gt 0){[Math]::Round($lossesInReg.Count/$tsInReg.Count*100,2)}else{0}
        DrawdownContribution=[Math]::Round($lossSum,2)
    })
}
$regimeDD.ToArray() | Export-Csv (Join-Path $OutputDir "regime_drawdown_attribution.csv") -NoTypeInformation
$regimeDD.ToArray() | Format-Table -AutoSize

# ============ PHASE 18.6: VOLATILITY ATTRIBUTION ============
Write-Host "`n=== PHASE 18.6: VOLATILITY ATTRIBUTION ==="
$volDD = New-Object 'Collections.Generic.List[PSObject]'
$volBuckets = @{}
foreach ($t in $tradesArr) {
    $v = Classify-Vol $t.EntryIdx $atr14
    if (-not $volBuckets.ContainsKey($v)) { $volBuckets[$v] = New-Object 'Collections.Generic.List[PSObject]' }
    $volBuckets[$v].Add($t)
}
foreach ($v in @("LOW_VOL","MEDIUM_VOL","HIGH_VOL")) {
    $tsInVol = if($volBuckets.ContainsKey($v)){$volBuckets[$v].ToArray()}else{@()}
    $lossesInVol = $tsInVol | Where-Object { $_.PnL -lt 0 }
    $lossSum = ($lossesInVol | Measure-Object -Sum PnL).Sum
    $volDD.Add([PSCustomObject]@{
        Volatility=$v; Trades=$tsInVol.Count
        Losses=$lossesInVol.Count
        LossRate=if($tsInVol.Count -gt 0){[Math]::Round($lossesInVol.Count/$tsInVol.Count*100,2)}else{0}
        DrawdownContribution=[Math]::Round($lossSum,2)
    })
}
$volDD.ToArray() | Export-Csv (Join-Path $OutputDir "volatility_drawdown_attribution.csv") -NoTypeInformation
$volDD.ToArray() | Format-Table -AutoSize

# ============ PHASE 18.7: TAIL RISK ============
Write-Host "`n=== PHASE 18.7: TAIL RISK ==="
$tailRisk = New-Object 'Collections.Generic.List[PSObject]'
$sortedTrades = $tradesArr | Sort-Object PnL
$totalDrawdown = ($tradesArr | Where-Object { $_.PnL -lt 0 } | Measure-Object -Sum PnL).Sum

$worst1 = $sortedTrades | Select-Object -First 1
$worst10 = $sortedTrades | Select-Object -First 10
$worst50 = $sortedTrades | Select-Object -First 50

$tailRisk.Add([PSCustomObject]@{
    Group="Worst1"; Count=1
    AvgLoss=[Math]::Round(($worst1 | Measure-Object -Average PnL).Average,4)
    MaxLoss=[Math]::Round(($worst1 | Measure-Object -Minimum PnL).Minimum,4)
    ContributionPct=[Math]::Round(($worst1.PnL/$totalDrawdown*-100),2)
})
$tailRisk.Add([PSCustomObject]@{
    Group="Worst10"; Count=10
    AvgLoss=[Math]::Round(($worst10 | Measure-Object -Average PnL).Average,4)
    MaxLoss=[Math]::Round(($worst10 | Measure-Object -Minimum PnL).Minimum,4)
    ContributionPct=[Math]::Round((($worst10 | Measure-Object -Sum PnL).Sum/$totalDrawdown*-100),2)
})
$tailRisk.Add([PSCustomObject]@{
    Group="Worst50"; Count=50
    AvgLoss=[Math]::Round(($worst50 | Measure-Object -Average PnL).Average,4)
    MaxLoss=[Math]::Round(($worst50 | Measure-Object -Minimum PnL).Minimum,4)
    ContributionPct=[Math]::Round((($worst50 | Measure-Object -Sum PnL).Sum/$totalDrawdown*-100),2)
})
$tailRisk.ToArray() | Export-Csv (Join-Path $OutputDir "tail_risk_analysis.csv") -NoTypeInformation
$tailRisk.ToArray() | Format-Table -AutoSize

# ============ PHASE 18.8: EQUITY CURVE FORENSICS ============
Write-Host "`n=== PHASE 18.8: EQUITY FORENSICS ==="
$forensics = New-Object 'Collections.Generic.List[PSObject]'

# Longest recovery period
$maxRecovBars = 0; $maxRecovStart = ""; $maxRecovEnd = ""
$peakIdx = 0; $peakVal = 0.0
for ($ei = 0; $ei -lt $eqArr.Length; $ei++) {
    if ($eqArr[$ei] -gt $peakVal) { $peakIdx = $ei; $peakVal = $eqArr[$ei] }
    if ($peakVal -gt 0 -and $eqArr[$ei] -lt $peakVal) {
        # In drawdown - find recovery
        for ($ri = $ei + 1; $ri -lt $eqArr.Length; $ri++) {
            if ($eqArr[$ri] -ge $peakVal) {
                $recovBars = $ri - $peakIdx
                if ($recovBars -gt $maxRecovBars) {
                    $maxRecovBars = $recovBars
                    $maxRecovStart = if($peakIdx -lt $tradesArr.Count){$tradesArr[$peakIdx].EntryDate}else{"N/A"}
                    $maxRecovEnd = if($ri -lt $tradesArr.Count){$tradesArr[$ri].EntryDate}else{"N/A"}
                }
                $ei = $ri - 1; break
            }
        }
    }
}
$forensics.Add([PSCustomObject]@{Metric="LongestRecoveryBars"; Value=$maxRecovBars})
$forensics.Add([PSCustomObject]@{Metric="LongestRecoveryStart"; Value=$maxRecovStart})
$forensics.Add([PSCustomObject]@{Metric="LongestRecoveryEnd"; Value=$maxRecovEnd})

# Largest equity decline (single trade drop)
$minTrade = $tradesArr | Sort-Object PnL | Select-Object -First 1
$forensics.Add([PSCustomObject]@{Metric="LargestSingleTradeDecline"; Value=$minTrade.PnL})
$forensics.Add([PSCustomObject]@{Metric="LargestSingleTradeDate"; Value=$minTrade.EntryDate})

# Largest equity acceleration (single trade gain)
$maxTrade = $tradesArr | Sort-Object PnL -Descending | Select-Object -First 1
$forensics.Add([PSCustomObject]@{Metric="LargestSingleTradeGain"; Value=$maxTrade.PnL})
$forensics.Add([PSCustomObject]@{Metric="LargestSingleTradeGainDate"; Value=$maxTrade.EntryDate})

# Consecutive losses before recovery
$maxConsecLoss = 0; $curConsec = 0
foreach ($t in $tradesArr) { if ($t.PnL -le 0) { $curConsec++ } else { if ($curConsec -gt $maxConsecLoss) { $maxConsecLoss = $curConsec }; $curConsec = 0 } }
if ($curConsec -gt $maxConsecLoss) { $maxConsecLoss = $curConsec }
$forensics.Add([PSCustomObject]@{Metric="MaxConsecutiveLosses"; Value=$maxConsecLoss})

$forensics.ToArray() | Export-Csv (Join-Path $OutputDir "equity_curve_forensics.csv") -NoTypeInformation
$forensics.ToArray() | Format-Table -AutoSize

# ============ FINAL REPORT ============
Write-Host "`n=== GENERATING REPORT ===" -ForegroundColor Green

# Compute key stats for report
$losers = $tradesArr | Where-Object { $_.PnL -lt 0 }
$winners = $tradesArr | Where-Object { $_.PnL -gt 0 }
$totalLoss = ($losers | Measure-Object -Sum PnL).Sum
$totalWin = ($winners | Measure-Object -Sum PnL).Sum

# Regime with highest drawdown contribution
$worstRegime = $regimeDD.ToArray() | Sort-Object DrawdownContribution | Select-Object -First 1

# Volatility with highest drawdown contribution
$worstVol = $volDD.ToArray() | Sort-Object DrawdownContribution | Select-Object -First 1

# Time period with highest drawdown
$worstTime = $timeDD.ToArray() | Sort-Object DrawdownContribution | Select-Object -First 1

$md = @()
$md += "# Drawdown Forensic Report"
$md += ""
$md += "**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) - LONG ONLY - 5-bar hold"
$md += "**Trades analyzed:** " + $tradesArr.Count
$md += "**Total net PnL:** $([Math]::Round($totalPnL,2))%"
$md += "**Maximum drawdown:** $([Math]::Round($maxDd,2))%"
$md += "**Total losing trades:** " + $losers.Count + " of " + $tradesArr.Count + " (" + [Math]::Round($losers.Count/$tradesArr.Count*100,1) + "%)"
$md += "**Total loss amount:** $([Math]::Round($totalLoss,2))%"
$md += "**Number of drawdown periods:** " + $ddSorted.Count
$md += ""
$md += "---"
$md += ""
$md += "## 1. What is the primary cause of the 37.6% drawdown?"
$md += ""

# Analyze which factor contributes most
$topRegimeContrib = $regimeDD.ToArray() | Sort-Object DrawdownContribution | Select-Object -First 1
$topVolContrib = $volDD.ToArray() | Sort-Object DrawdownContribution | Select-Object -First 1
$topStreakPnL = if($streakAnalysis | Where-Object {$_.Metric -eq "LongestStreakPnL"}){($streakAnalysis | Where-Object {$_.Metric -eq "LongestStreakPnL"}).Value}else{0}
$top1pctVal = ($lossContrib.ToArray() | Where-Object { $_.Group -eq "Top 1%" }).PercentOfTotalDrawdown
$top5pctVal = ($lossContrib.ToArray() | Where-Object { $_.Group -eq "Top 5%" }).PercentOfTotalDrawdown
$top10pctVal = ($lossContrib.ToArray() | Where-Object { $_.Group -eq "Top 10%" }).PercentOfTotalDrawdown
$top20pctVal = ($lossContrib.ToArray() | Where-Object { $_.Group -eq "Top 20%" }).PercentOfTotalDrawdown

$md += "The drawdown is a compound effect of multiple factors. The largest single contributor is the regime with the highest loss concentration:"
$md += ""
$ddPeriodText = if($ddSorted.Count -gt 0) { "$($ddSorted[0].DepthPercent)% depth over $($ddSorted[0].DurationDays) days involving $($ddSorted[0].TradesInvolved) trades" } else { "N/A" }
$md += "- **Largest drawdown period:** $ddPeriodText"
$md += "- **Worst regime for losses:** $($topRegimeContrib.Regime) ($($topRegimeContrib.DrawdownContribution)% total loss)"
$md += "- **Longest losing streak:** $($topStreakPnL)% cumulative loss over " + (($streakAnalysis | Where-Object {$_.Metric -eq "MaximumLosingStreak"}).Value) + " consecutive trades"
$md += "- **Top 1% of trades contribute $top1pctVal% of total drawdown**"
$md += "- **Top 5% of trades contribute $top5pctVal% of total drawdown**"
$md += "- **Top 10% of trades contribute $top10pctVal% of total drawdown**"
$md += "- **Top 20% of trades contribute $top20pctVal% of total drawdown**"
$md += ""
if([double]$top1pctVal -gt 30) {
    $md += "The single dominant cause is a small number of outsized losing trades (tail risk). The top 1% of trades account for $top1pctVal% of all losses."
} elseif([double]$top5pctVal -gt 60) {
    $md += "The primary cause is concentrated in the top 5% of worst trades."
} elseif([double]$top10pctVal -gt 80) {
    $md += "Losses are broadly distributed across many trades with moderate individual losses."
} else {
    $md += "Drawdown is a compound effect: some tail losses, some streak losses, and some regime-specific losses accumulate to the 37.6% peak."
}
$md += ""
$md += "## 2. Is drawdown concentrated or distributed?"
$md += ""
$ddCount = $ddSorted.Count
$ddSumDepth = ($ddSorted | Measure-Object -Average DepthPercent).Average
$ddTop3Share = if($ddSorted.Count -ge 3){[Math]::Round(($ddSorted[0].DepthPercent + $ddSorted[1].DepthPercent + $ddSorted[2].DepthPercent) / $maxDd * 100, 1)}else{100}
if($ddTop3Share -gt 70) {
    $md += "CONCENTRATED. The top 3 drawdown periods account for $ddTop3Share% of total drawdown ($ddCount total periods)."
} else {
    $md += "DISTRIBUTED. No single drawdown period dominates. The top 3 periods account for $ddTop3Share% of $ddCount total periods."
}
$md += ""
$md += "## 3. Are a small number of trades responsible?"
$md += ""
$md += "- Top 1% of trades contribute $top1pctVal% of total drawdown"
$md += "- Top 5% of trades contribute $top5pctVal% of total drawdown"
$md += "- Top 10% of trades contribute $top10pctVal% of total drawdown"
$md += "- Top 20% of trades contribute $top20pctVal% of total drawdown"
$md += ""
if([double]$top1pctVal -gt 30) {
    $md += "YES. A small minority of trades (1%) generate a disproportionate share of losses."
} elseif([double]$top5pctVal -gt 50) {
    $md += "PARTIALLY. The top 5% of trades account for a substantial share, but losses are spread across more trades."
} else {
    $md += "NO. Losses are distributed across many trades, not concentrated in a few."
}
$md += ""
$md += "## 4. Are losing streaks responsible?"
$md += ""
$maxStreak = ($streakAnalysis | Where-Object {$_.Metric -eq "MaximumLosingStreak"}).Value
$avgStreak = ($streakAnalysis | Where-Object {$_.Metric -eq "AverageLosingStreak"}).Value
$medStreak = ($streakAnalysis | Where-Object {$_.Metric -eq "MedianLosingStreak"}).Value
$p95Streak = ($streakAnalysis | Where-Object {$_.Metric -eq "P95LosingStreak"}).Value
$longestStreakP = ($streakAnalysis | Where-Object {$_.Metric -eq "LongestStreakPnL" -and $_.Value -ne ""}).Value
$md += "- Maximum losing streak: $maxStreak consecutive trades"
$md += "- Average losing streak: $avgStreak"
$md += "- Median losing streak: $medStreak"
$md += "- 95th percentile streak: $p95Streak"
$md += "- Cumulative loss in longest streak: $longestStreakP%"
$md += ""
$maxStreakDepth = [Math]::Round([Math]::Abs([double]$longestStreakP) / $maxDd * 100, 1)
if($maxStreakDepth -gt 30) {
    $md += "YES. The largest losing streak accounts for $maxStreakDepth% of the maximum drawdown."
} elseif($maxStreakDepth -gt 10) {
    $md += "PARTIALLY. The largest losing streak accounts for $maxStreakDepth% of the maximum drawdown, but drawdown also accumulates across multiple separate streaks."
} else {
    $md += "NO. Losing streaks account for only $maxStreakDepth% of the maximum drawdown. Most losses come from individual trade events."
}
$md += ""
$md += "## 5. Are specific market regimes responsible?"
$md += ""
foreach ($r in ($regimeDD.ToArray() | Sort-Object DrawdownContribution)) {
    $md += "- $($r.Regime): $($r.DrawdownContribution)% loss over $($r.Trades) trades ($($r.LossRate)% loss rate)"
}
$md += ""
$md += "The regime with the largest drawdown contribution is $($topRegimeContrib.Regime) ($($topRegimeContrib.DrawdownContribution)% loss)."
$md += ""
$totalLossAbs = [Math]::Abs($totalLoss)
$topRegimeShare = if($totalLossAbs -gt 0){[Math]::Round([Math]::Abs($topRegimeContrib.DrawdownContribution)/$totalLossAbs*100,0)}else{0}
if($topRegimeShare -gt 50) {
    $md += "YES. Losses are concentrated in a single regime ($($topRegimeContrib.Regime) at $topRegimeShare% of total loss)."
} else {
    $md += "PARTIALLY DISTRIBUTED. The worst regime ($($topRegimeContrib.Regime)) contributes $topRegimeShare% of total losses but losses span multiple regimes."
}
$md += ""
$md += "## 6. Are specific volatility environments responsible?"
$md += ""
foreach ($v in ($volDD.ToArray() | Sort-Object DrawdownContribution)) {
    $md += "- $($v.Volatility): $($v.DrawdownContribution)% loss over $($v.Trades) trades ($($v.LossRate)% loss rate)"
}
$md += ""
$topVolShare = if($totalLossAbs -gt 0){[Math]::Round([Math]::Abs($worstVol.DrawdownContribution)/$totalLossAbs*100,0)}else{0}
if($topVolShare -gt 50) {
    $md += "YES. Losses are concentrated in $($worstVol.Volatility) ($topVolShare% of total loss)."
} else {
    $md += "$([Math]::Round($topVolShare,0))% of losses occur in $($worstVol.Volatility), but losses span all volatility regimes."
}
$md += ""
$md += "## 7. Are tail events responsible?"
$md += ""
$worst1Pnl = ($tailRisk.ToArray() | Where-Object {$_.Group -eq "Worst1"}).MaxLoss
$worst10Pct = ($tailRisk.ToArray() | Where-Object {$_.Group -eq "Worst10"}).ContributionPct
$worst50Pct = ($tailRisk.ToArray() | Where-Object {$_.Group -eq "Worst50"}).ContributionPct
$md += "- Worst single trade: $worst1Pnl%"
$md += "- Worst 10 trades contribution: $worst10Pct% of total drawdown"
$md += "- Worst 50 trades contribution: $worst50Pct% of total drawdown"
$md += ""
$totalTradeCount = $tradesArr.Count
$worst50PctOfTrades = [Math]::Round(50/$totalTradeCount*100,1)
$md += "The worst 50 trades represent $worst50PctOfTrades% of all trades but account for $worst50Pct% of drawdown."
$md += ""
if([double]$worst10Pct -gt 40) {
    $md += "YES. A small number of tail events dominate the drawdown profile."
} elseif([double]$worst50Pct -gt 70) {
    $md += "PARTIALLY. The worst 50 trades account for most drawdown, but this is a relatively large group ($worst50PctOfTrades% of all trades)."
} else {
    $md += "NO. Losses are distributed across many trades. No single tail event or small group dominates."
}
$md += ""
$md += "## 8. What is the simplest evidence-based explanation for the drawdown?"
$md += ""
# Build explanation from data
$avgLossPct = [Math]::Round(($losers | Measure-Object -Average PnL).Average, 2)
$maxLossPct = [Math]::Round(($losers | Measure-Object -Minimum PnL).Minimum, 2)
$avgWinPct = [Math]::Round(($winners | Measure-Object -Average PnL).Average, 2)
$md += "The strategy produces $($winners.Count) winners (avg +$avgWinPct%) and $($losers.Count) losers (avg $avgLossPct%)."
$md += ""
$md += "The maximum drawdown of $([Math]::Round($maxDd,2))% can be explained by:"
$md += ""
$md += "1. **Loss magnitude asymmetry:** The average winner ($avgWinPct%) is only " + [Math]::Round([Math]::Abs($avgWinPct/$avgLossPct),1) + "x the average loser ($avgLossPct%). This narrows the edge and means a run of losers can quickly erode gains."
$md += "2. **Streak accumulation:** The longest losing streak ($maxStreak trades, $longestStreakP%) compounds into substantial drawdown."
if([double]$top1pctVal -gt 20) {
    $md += "3. **Tail risk:** The worst trade ($maxLossPct%) alone consumed a meaningful portion of the equity peak."
}
if($topRegimeShare -gt 30) {
    $md += "4. **Regime vulnerability:** The strategy performs poorly in $($topRegimeContrib.Regime), where $topRegimeShare% of losses originate."
}
$md += ""
$md += "The simplest explanation: **the strategy's 71.5% win rate masks that losing trades have a worse average magnitude relative to winners than the win rate alone suggests. When losses cluster into streaks (max $maxStreak), the cumulative effect drives the equity curve into drawdown.**"

$mdContent = $md -join "`n"
$mdContent | Out-File (Join-Path $OutputDir "drawdown_forensic_report.md") -Encoding utf8
Write-Host "Report written" -ForegroundColor Green

Write-Host "`n=== PHASE 18 COMPLETE ===" -ForegroundColor Cyan
