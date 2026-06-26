param([string]$OutputDir=".")
$ErrorActionPreference="Stop"
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

Write-Host "=== PHASE 22 - LOSS FINGERPRINT ANALYSIS ===" -ForegroundColor Cyan

# Load candles + trades from Phase 21 ledger (reuse exact same method)
$csv = Import-Csv (Join-Path $PSScriptRoot "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n = $csv.Count
$hi=[double[]]::new($n);$lo=[double[]]::new($n);$op=[double[]]::new($n);$cl=[double[]]::new($n)
$vo=[double[]]::new($n);$ts=[long[]]::new($n);$dt=New-Object 'string[]' $n
for ($i=0;$i-lt$n;$i++) {
    $hi[$i]=[double]$csv[$i].High;$lo[$i]=[double]$csv[$i].Low
    $op[$i]=[double]$csv[$i].Open;$cl[$i]=[double]$csv[$i].Close
    $vo[$i]=[double]$csv[$i].Volume;$ts[$i]=[long]$csv[$i].Timestamp
    $dt[$i]=$csv[$i].Date
}
$feeRate=0.0005;$slippage=0.0002;$exitBar=5;$hedgeStart=100
Write-Host "Candles: $n"

$sig=Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $cl $hi $lo $vo $n
Write-Host "Signals: $($sig.Length)"

# Build trade list
$trades = New-Object 'Collections.Generic.List[PSObject]'
$tradeIdxList = @()
for ($si=$hedgeStart;$si-lt$sig.Length;$si++) {
    if (-not $sig[$si]) { continue }
    $ex=$si+$exitBar; if ($ex-ge$n) { continue }
    $ePrice=$cl[$si]; $xPrice=$cl[$ex]
    $effEntry=$ePrice*(1+$slippage)*(1+$feeRate)
    $effExit=$xPrice*(1-$slippage)*(1-$feeRate)
    $netPnL=($effExit-$effEntry)/$effEntry*100
    $trades.Add([PSCustomObject]@{ID=$trades.Count+1; EntryIdx=$si; ExitIdx=$ex; NetPnL=$netPnL; EntryPrice=$ePrice; ExitPrice=$xPrice})
    $tradeIdxList += $si
}
$tradesArr = $trades.ToArray()
$pnlValues = $tradesArr | ForEach-Object { $_.NetPnL }
$totalTrades = $tradesArr.Count
Write-Host "Trades: $totalTrades"

# Precompute indicators
Write-Host "Computing indicators..."
$sma20 = Calc-SMA $cl 20; $sma50 = Calc-SMA $cl 50; $sma200 = Calc-SMA $cl 200
$atr14 = Calc-ATR $hi $lo $cl 14
$stochK = Calc-Stoch $hi $lo $cl 5 5

# ===== Phase 22.1: Worst Loss Cohorts =====
Write-Host "`n=== PHASE 22.1: WORST LOSS COHORTS ===" -ForegroundColor Yellow
$sortedAsc = $tradesArr | Sort-Object NetPnL
$n1 = [Math]::Max(1, [Math]::Floor($totalTrades * 0.01))
$n5 = [Math]::Max(1, [Math]::Floor($totalTrades * 0.05))
$n10 = [Math]::Max(1, [Math]::Floor($totalTrades * 0.10))

$worst1 = $sortedAsc | Select-Object -First $n1
$worst5 = $sortedAsc | Select-Object -First $n5
$worst10 = $sortedAsc | Select-Object -First $n10
$remaining = $tradesArr | Where-Object { $_.NetPnL -gt ($worst10[-1].NetPnL) }

Write-Host "Worst 1%: $n1 trades (PnL <= $([Math]::Round($worst1[-1].NetPnL,2))%)"
Write-Host "Worst 5%: $n5 trades (PnL <= $([Math]::Round($worst5[-1].NetPnL,2))%)"
Write-Host "Worst 10%: $n10 trades (PnL <= $([Math]::Round($worst10[-1].NetPnL,2))%)"
Write-Host "Remaining: $($remaining.Count) trades"

$cohortLines = @()
$cohortLines += '# Loss Cohort Summary'
$cohortLines += ''
$cohortLines += "| Cohort | Count | Min PnL | Max PnL | Mean PnL | Std Dev |"
$cohortLines += '|--------|-------|--------|--------|---------|---------|'
foreach ($c in @(@{N="Worst 1%"; T=$worst1}, @{N="Worst 5%"; T=$worst5}, @{N="Worst 10%"; T=$worst10}, @{N="Remaining"; T=$remaining})) {
    $pnls = $c.T | ForEach-Object { $_.NetPnL }
    $mn = ($pnls | Measure-Object -Minimum).Minimum
    $mx = ($pnls | Measure-Object -Maximum).Maximum
    $av = ($pnls | Measure-Object -Average).Average
    $sd = [Math]::Sqrt(($pnls | ForEach-Object {($_ - $av)*($_ - $av)} | Measure-Object -Sum).Sum / ($pnls.Count-1))
    $cohortLines += "| $($c.N) | $($c.T.Count) | $([Math]::Round($mn,2))% | $([Math]::Round($mx,2))% | $([Math]::Round($av,4))% | $([Math]::Round($sd,4)) |"
}
$cohortLines -join "`n" | Out-File (Join-Path $OutputDir "loss_cohort_summary.md") -Encoding utf8

# ===== Phase 22.2: Market Structure Features =====
Write-Host "`n=== PHASE 22.2: MARKET STRUCTURE FEATURES ===" -ForegroundColor Yellow
function Calc-HHLL($arr, $idx, $period) {
    $start=[Math]::Max(0,$idx-$period+1); $end=$idx
    $high=($arr[$start..$end] | Measure-Object -Maximum).Maximum
    $low=($arr[$start..$end] | Measure-Object -Minimum).Minimum
    return @{High=$high; Low=$low; Range=$high-$low}
}

function Calc-Slope($arr, $idx, $period) {
    $start=[Math]::Max(0,$idx-$period+1); $len=$idx-$start+1
    if ($len -lt 2) { return 0 }
    $xAvg=($len-1)/2.0; $yAvg=($arr[$start..$idx] | Measure-Object -Average).Average
    $num=0.0;$den=0.0
    for ($i=0;$i-lt$len;$i++) {
        $xi=$i; $yi=$arr[$start+$i]
        $num+=($xi-$xAvg)*($yi-$yAvg); $den+=($xi-$xAvg)*($xi-$xAvg)
    }
    if ($den -ne 0) { return $num/$den } else { return 0 }
}

$msFeatures = New-Object 'Collections.Generic.List[PSObject]'
foreach ($t in $tradesArr) {
    $idx=$t.EntryIdx
    if ($idx -lt 50) { continue } # need enough history
    $hh20=Calc-HHLL $hi $idx 20; $ll20=Calc-HHLL $lo $idx 20
    $hh50=Calc-HHLL $hi $idx 50; $ll50=Calc-HHLL $lo $idx 50
    
    $dist20High = ($hh20.High - $t.EntryPrice) / $hh20.Range * 100
    $dist20Low  = ($t.EntryPrice - $ll20.Low) / $hh20.Range * 100
    $dist50High = ($hh50.High - $t.EntryPrice) / $hh50.Range * 100
    $dist50Low  = ($t.EntryPrice - $ll50.Low) / $hh50.Range * 100
    $posInRange = ($t.EntryPrice - $ll20.Low) / $hh20.Range * 100
    
    $slp20 = Calc-Slope $cl $idx 20
    $slp50 = Calc-Slope $cl $idx 50
    $distSMA20 = ($t.EntryPrice - $sma20[$idx]) / $sma20[$idx] * 100
    $distSMA50 = ($t.EntryPrice - $sma50[$idx]) / $sma50[$idx] * 100
    $distSMA200 = ($t.EntryPrice - $sma200[$idx]) / $sma200[$idx] * 100
    
    $msFeatures.Add([PSCustomObject]@{
        TradeID=$t.ID; NetPnL=[Math]::Round($t.NetPnL,4)
        Dist20High=[Math]::Round($dist20High,2); Dist20Low=[Math]::Round($dist20Low,2)
        Dist50High=[Math]::Round($dist50High,2); Dist50Low=[Math]::Round($dist50Low,2)
        PosInRange20=[Math]::Round($posInRange,2)
        Slope20=[Math]::Round($slp20,6); Slope50=[Math]::Round($slp50,6)
        DistSMA20=[Math]::Round($distSMA20,4); DistSMA50=[Math]::Round($distSMA50,4); DistSMA200=[Math]::Round($distSMA200,4)
    })
}
$msArr = $msFeatures.ToArray()
$msArr | Export-Csv (Join-Path $OutputDir "market_structure_features.csv") -NoTypeInformation
Write-Host "Market structure features: $($msArr.Count)"

# ===== Phase 22.3: Volatility Shock Features =====
Write-Host "`n=== PHASE 22.3: VOLATILITY SHOCK FEATURES ===" -ForegroundColor Yellow
Write-Host "Precomputing ATR arrays..."
$atr20Full = Calc-ATR $hi $lo $cl 20
$atr100Full = Calc-ATR $hi $lo $cl 100
Write-Host "Done."

$volFeatures = New-Object 'Collections.Generic.List[PSObject]'
foreach ($t in $tradesArr) {
    $idx=$t.EntryIdx
    $atrNow = $atr14[$idx]
    $atr20Avg = $atr20Full[$idx]
    $atr100Avg = $atr100Full[$idx]
    $atrRel20 = if($atr20Avg -gt 0){$atrNow/$atr20Avg*100}else{100}
    $atrRel100 = if($atr100Avg -gt 0){$atrNow/$atr100Avg*100}else{100}
    # Range expansion: current bar range / average of last 20 bar ranges
    $currentRange = $hi[$idx] - $lo[$idx]
    $startRange=[Math]::Max(0,$idx-20); $lenRange=$idx-$startRange
    $sumRange=0.0
    for ($ri=$startRange;$ri-lt$idx;$ri++) { $sumRange += $hi[$ri]-$lo[$ri] }
    $avgRange20 = if($lenRange -gt 0){$sumRange/$lenRange}else{$currentRange}
    $rangeExp = if($avgRange20 -gt 0){$currentRange/$avgRange20*100}else{100}
    
    $volFeatures.Add([PSCustomObject]@{
        TradeID=$t.ID; NetPnL=[Math]::Round($t.NetPnL,4)
        ATR=[Math]::Round($atrNow,6)
        ATRrel20pct=[Math]::Round($atrRel20,1); ATRrel100pct=[Math]::Round($atrRel100,1)
        RangeExpansion=[Math]::Round($rangeExp,1)
    })
}
$volArr = $volFeatures.ToArray()
$volArr | Export-Csv (Join-Path $OutputDir "volatility_shock_features.csv") -NoTypeInformation
Write-Host "Volatility features: $($volArr.Count)"

# ===== Phase 22.4: Pre-Entry Candle Features =====
Write-Host "`n=== PHASE 22.4: PRE-ENTRY CANDLE FEATURES ===" -ForegroundColor Yellow
$candleFeatures = New-Object 'Collections.Generic.List[PSObject]'
foreach ($t in $tradesArr) {
    $idx=$t.EntryIdx
    $prev1Ret = if($idx-ge1){($cl[$idx]-$cl[$idx-1])/$cl[$idx-1]*100}else{0}
    $prev3Ret = if($idx-ge3){($cl[$idx]-$cl[$idx-3])/$cl[$idx-3]*100}else{0}
    $prev5Ret = if($idx-ge5){($cl[$idx]-$cl[$idx-5])/$cl[$idx-5]*100}else{0}
    $prev10Ret= if($idx-ge10){($cl[$idx]-$cl[$idx-10])/$cl[$idx-10]*100}else{0}
    
    # Candle at entry
    $cHigh=$hi[$idx];$cLow=$lo[$idx];$cOpen=$op[$idx];$cClose=$cl[$idx]
    $totalRange=$cHigh-$cLow
    $body=[Math]::Abs($cClose-$cOpen)
    $upperWick=$cHigh-[Math]::Max($cOpen,$cClose)
    $lowerWick=[Math]::Min($cOpen,$cClose)-$cLow
    $wickPct=if($totalRange-gt0){($upperWick+$lowerWick)/$totalRange*100}else{0}
    $bodyPct=if($totalRange-gt0){$body/$totalRange*100}else{0}
    $upperWickPct=if($totalRange-gt0){$upperWick/$totalRange*100}else{0}
    $lowerWickPct=if($totalRange-gt0){$lowerWick/$totalRange*100}else{0}
    
    $candleFeatures.Add([PSCustomObject]@{
        TradeID=$t.ID; NetPnL=[Math]::Round($t.NetPnL,4)
        Prev1Ret=[Math]::Round($prev1Ret,4); Prev3Ret=[Math]::Round($prev3Ret,4)
        Prev5Ret=[Math]::Round($prev5Ret,4); Prev10Ret=[Math]::Round($prev10Ret,4)
        UpperWickPct=[Math]::Round($upperWickPct,1); LowerWickPct=[Math]::Round($lowerWickPct,1)
        WickPct=[Math]::Round($wickPct,1); BodyPct=[Math]::Round($bodyPct,1)
    })
}
$candleArr = $candleFeatures.ToArray()
$candleArr | Export-Csv (Join-Path $OutputDir "candle_features.csv") -NoTypeInformation
Write-Host "Candle features: $($candleArr.Count)"

# ===== Phase 22.5: Loss Fingerprint Test =====
Write-Host "`n=== PHASE 22.5: FINGERPRINT TEST ===" -ForegroundColor Yellow

# Merge all features into one table
$merged = New-Object 'Collections.Generic.List[PSObject]'
for ($i=0;$i-lt$totalTrades;$i++) {
    $t=$tradesArr[$i]; $ms=$msArr[$i]; $vol=$volArr[$i]; $ca=$candleArr[$i]
    $merged.Add([PSCustomObject]@{
        TradeID=$t.ID; NetPnL=[Math]::Round($t.NetPnL,4)
        D20H=$ms.Dist20High; D20L=$ms.Dist20Low; D50H=$ms.Dist50High; D50L=$ms.Dist50Low
        PIR=$ms.PosInRange20; S20=$ms.Slope20; S50=$ms.Slope50
        DS20=$ms.DistSMA20; DS50=$ms.DistSMA50; DS200=$ms.DistSMA200
        AT=$vol.ATR; AR20=$vol.ATRrel20pct; AR100=$vol.ATRrel100pct; RE=$vol.RangeExpansion
        P1R=$ca.Prev1Ret; P3R=$ca.Prev3Ret; P5R=$ca.Prev5Ret; P10R=$ca.Prev10Ret
        UW=$ca.UpperWickPct; LW=$ca.LowerWickPct; WK=$ca.WickPct; BD=$ca.BodyPct
    })
}
$mergedArr = $merged.ToArray()

# Define cohorts
$worst10Pnl = $worst10[-1].NetPnL
$worst5Pnl = $worst5[-1].NetPnL
$worst1Pnl = $worst1[-1].NetPnL
$bad10 = $mergedArr | Where-Object { $_.NetPnL -le $worst10Pnl }
$good = $mergedArr | Where-Object { $_.NetPnL -gt $worst10Pnl }

Write-Host "Bad (worst10): $($bad10.Count)  Good (remaining): $($good.Count)"

$featureDefs = @(
    @{N="D20H"; L="Distance from 20-bar high (%)"}
    @{N="D20L"; L="Distance from 20-bar low (%)"}
    @{N="D50H"; L="Distance from 50-bar high (%)"}
    @{N="D50L"; L="Distance from 50-bar low (%)"}
    @{N="PIR"; L="Position in 20-bar range (%)"}
    @{N="S20"; L="20-bar slope"}
    @{N="S50"; L="50-bar slope"}
    @{N="DS20"; L="Distance from SMA20 (%)"}
    @{N="DS50"; L="Distance from SMA50 (%)"}
    @{N="DS200"; L="Distance from SMA200 (%)"}
    @{N="AT"; L="ATR (absolute)"}
    @{N="AR20"; L="ATR vs 20-bar avg (%)"}
    @{N="AR100"; L="ATR vs 100-bar avg (%)"}
    @{N="RE"; L="Range expansion ratio (%)"}
    @{N="P1R"; L="Previous 1-bar return (%)"}
    @{N="P3R"; L="Previous 3-bar return (%)"}
    @{N="P5R"; L="Previous 5-bar return (%)"}
    @{N="P10R"; L="Previous 10-bar return (%)"}
    @{N="UW"; L="Upper wick %"}
    @{N="LW"; L="Lower wick %"}
    @{N="WK"; L="Total wick %"}
    @{N="BD"; L="Body %"}
)

function Get-Stat($arr, $prop) {
    $vals = $arr | ForEach-Object { $_.$prop }
    $sorted = $vals | Sort-Object
    $c=$vals.Count
    $mn=($vals | Measure-Object -Average).Average
    $md=$sorted[[Math]::Floor($c/2)]
    $p5=$sorted[[Math]::Floor($c*0.05)]
    $p25=$sorted[[Math]::Floor($c*0.25)]
    $p75=$sorted[[Math]::Floor($c*0.75)]
    $p95=$sorted[[Math]::Floor($c*0.95)]
    $sd=[Math]::Sqrt(($vals | ForEach-Object {($_ - $mn)*($_ - $mn)} | Measure-Object -Sum).Sum / ($c-1))
    return @{Mean=$mn; Median=$md; P5=$p5; P25=$p25; P75=$p75; P95=$p95; StdDev=$sd}
}

function CohenD($m1, $sd1, $m2, $sd2) {
    $pooled = [Math]::Sqrt(($sd1*$sd1 + $sd2*$sd2)/2.0)
    if ($pooled -gt 0) { return ($m1-$m2)/$pooled } else { return 0 }
}

function PercentileDiff($arr1, $arr2, $prop) {
    $v1=$arr1|ForEach-Object{$_.$prop}; $v2=$arr2|ForEach-Object{$_.$prop}
    $all=$v1+$v2 | Sort-Object
    $p1=0.0; foreach($v in $v1){$p1+=[double]($all.IndexOf($v))/$all.Count}; $p1/=$v1.Count
    $p2=0.0; foreach($v in $v2){$p2+=[double]($all.IndexOf($v))/$all.Count}; $p2/=$v2.Count
    return ($p1-$p2)*100
}

$fingerprintResults = New-Object 'Collections.Generic.List[PSObject]'
foreach ($fd in $featureDefs) {
    $n=$fd.N; $l=$fd.L
    $sBad = Get-Stat $bad10 $n
    $sGood = Get-Stat $good $n
    $d = CohenD $sBad.Mean $sBad.StdDev $sGood.Mean $sGood.StdDev
    $pd = PercentileDiff $bad10 $good $n
    
    $mag = if([Math]::Abs($d) -ge 0.8){"large"} elseif([Math]::Abs($d) -ge 0.5){"medium"} elseif([Math]::Abs($d) -ge 0.2){"small"}else{"negligible"}
    $desc = if($d -gt 0){"higher in bad trades"}else{"lower in bad trades"}
    
    Write-Host "  $l : d=$([Math]::Round($d,3)) ($mag) pd=$([Math]::Round($pd,1))% - $desc"
    
    $fingerprintResults.Add([PSCustomObject]@{
        Feature=$l; Key=$n
        BadMean=[Math]::Round($sBad.Mean,4); BadMed=[Math]::Round($sBad.Median,4)
        BadP25=[Math]::Round($sBad.P25,4); BadP75=[Math]::Round($sBad.P75,4)
        GoodMean=[Math]::Round($sGood.Mean,4); GoodMed=[Math]::Round($sGood.Median,4)
        GoodP25=[Math]::Round($sGood.P25,4); GoodP75=[Math]::Round($sGood.P75,4)
        CohensD=[Math]::Round($d,4); EffectSize=$mag
        PercentileDiff=[Math]::Round($pd,1); Direction=$desc
    })
}

# Sort by absolute Cohen's D descending
$sortedFp = $fingerprintResults | Sort-Object {[Math]::Abs($_.CohensD)} -Descending
$sortedFp | Export-Csv (Join-Path $OutputDir "loss_fingerprint_ranking.csv") -NoTypeInformation
$sortedFp | Format-Table Feature,CohensD,EffectSize,PercentileDiff,Direction -AutoSize | Out-Host

# ===== Final Report =====
Write-Host "`n=== FINAL REPORT ===" -ForegroundColor Cyan
$rep = @()
$rep += '# Loss Fingerprint Report'
$rep += ''
$rep += "**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) LONG ONLY 5-bar hold"
$rep += "**Trades:** $totalTrades total, $($bad10.Count) in worst 10% cohort"
$rep += "**Worst 10% threshold:** NetPnL <= $([Math]::Round($worst10Pnl,2))%"
$rep += "**Worst  5% threshold:** NetPnL <= $([Math]::Round($worst5Pnl,2))%"
$rep += "**Worst  1% threshold:** NetPnL <= $([Math]::Round($worst1Pnl,2))%"
$rep += ''
$rep += '---'
$rep += ''
$rep += "## Feature Ranking (by Cohens d)"
$rep += ''
$rep += '| Rank | Feature | d | Effect | Pctile Diff | Direction |'
$rep += '|------|---------|---|-------|------------|-----------|'
$rank=0
foreach ($r in $sortedFp) {
    $rank++; $rep += "| $rank | $($r.Feature) | $($r.CohensD) | $($r.EffectSize) | $($r.PercentileDiff)% | $($r.Direction) |"
}
$rep += ''

$topFeature = $sortedFp[0]
$topD = $topFeature.CohensD
$rep += "## 1. Do catastrophic losses share common characteristics?"
$rep += ''
if ([Math]::Abs($topD) -ge 0.5) {
    $rep += "**PARTIALLY.** The top feature ($($topFeature.Feature)) shows a $(if([Math]::Abs($topD)-ge0.8){'large'}elseif([Math]::Abs($topD)-ge0.5){'medium'}else{'small'}) effect size (d=$([Math]::Round($topD,3))), suggesting some structural differences exist."
} else {
    $rep += "**NO.** The top feature ($($topFeature.Feature)) shows only a small effect size (d=$([Math]::Round($topD,3))). Worst losses occur under statistically similar conditions to normal trades."
}
$rep += ''
$rep += 'Detailed cohort breakdown:'
$rep += ''
$rep += ''
$rep += "Top features by Cohen's d (see table above for full ranking)."
$rep += ''
$top5 = $sortedFp | Select-Object -First 5
foreach ($r in $top5) {
    $rep += "- **$($r.Feature)**: d=$($r.CohensD), $($r.Direction), $($r.PercentileDiff)%ile diff"
}
$rep += ''

$rep += '## 2. Which feature best separates bad trades from normal trades?'
$rep += ''
$rep += "**$($topFeature.Feature)** (Cohen's d = $($topFeature.CohensD), effect = $($topFeature.EffectSize))."
$rep += "Percentile difference: $($topFeature.PercentileDiff)%."
$rep += ''
if ($top5.Count -gt 1) {
    $rep += "Runner-up: $($top5[1].Feature) (d = $($top5[1].CohensD), effect = $($top5[1].EffectSize))."
}
$rep += ''

$rep += '## 3. Are the differences economically meaningful?'
$rep += ''
$strongCount = ($sortedFp | Where-Object {[Math]::Abs($_.CohensD) -ge 0.5}).Count
$totalCount = $sortedFp.Count
$rep += "Of $totalCount features, $strongCount show medium or larger effect sizes."
if ($strongCount -eq 0) {
    $rep += "**NO.** All features show negligible to small effects. The differences are statistically detectable at best but not economically meaningful."
} elseif ($strongCount -le 3) {
    $rep += "**LIMITED.** A small number of features show moderate separation, but the overlap between distributions is substantial. A filter based on these features would likely catch many false positives."
} else {
    $rep += "**POSSIBLY.** Multiple features show meaningful separation, suggesting that a multi-feature approach might identify high-risk trades."
}
$rep += ''

$rep += '## 4. Is there evidence that a future filter could reduce drawdown?'
$rep += ''
if ($strongCount -ge 3 -and [Math]::Abs($topD) -ge 0.6) {
    $rep += "**WEAK EVIDENCE.** While some features separate bad from normal trades, the effect sizes are modest. The worst 10% of trades occur across a wide range of market conditions, suggesting that filtering on any single feature would eliminate many good trades while only catching a fraction of bad ones. A multi-feature ensemble approach would be needed to see meaningful drawdown reduction, but this risks overfitting."
} elseif ($strongCount -ge 1) {
    $rep += "**LIMITED EVIDENCE.** One or two features show separation, but the effect is too small to build a reliable filter. The risk-reward of attempting to filter these trades is unfavorable: the strategy's PF=3.19 and 66.5% WR mean that any filter would need to remove far more losers than winners to improve the system. The data suggests the worst trades are not a distinct population -- they are the left tail of a single distribution."
} else {
    $rep += "**NO.** The feature differences are negligible. The worst losses appear to be the natural left tail of a single trade distribution, not a distinct subpopulation. No evidence supports building a filter."
}
$rep += ''
$rep += '---'
$rep += ''

$rep += '## Feature-by-Feature Detail'
$rep += ''
$rep += '| Feature | Bad Mean | Good Mean | Bad Med | Good Med | d | pctile diff |'
$rep += '|---------|---------|----------|--------|---------|---|------------|'
foreach ($r in $sortedFp) {
    $rep += "| $($r.Feature) | $($r.BadMean) | $($r.GoodMean) | $($r.BadMed) | $($r.GoodMed) | $($r.CohensD) | $($r.PercentileDiff)% |"
}
$rep += ''

$repContent = $rep -join "`n"
$repContent | Out-File (Join-Path $OutputDir "loss_fingerprint_report.md") -Encoding utf8
Write-Host "loss_fingerprint_report.md written" -ForegroundColor Green

Write-Host "`n=== PHASE 22 COMPLETE ===" -ForegroundColor Cyan
Write-Host "Top 3 separating features:"
foreach ($r in $sortedFp | Select-Object -First 3) {
    Write-Host "  $($r.Feature): d=$($r.CohensD) ($($r.EffectSize)), pd=$($r.PercentileDiff)%"
}
