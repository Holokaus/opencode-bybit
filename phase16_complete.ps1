param([string]$InputDir=".",[string]$OutputDir=".")
$ErrorActionPreference="Stop"
Write-Host "=== PHASE 16 STARTED ==="
Import-Module "$PSScriptRoot\Modules\MarketBehaviorFramework.psm1" -Force -WarningAction SilentlyContinue

$k=Import-Csv (Join-Path $InputDir "SOLUSDT-FUTURES-2021-2026-30m.csv")
$n=$k.Count
$hi=[double[]]::new($n);$lo=[double[]]::new($n);$cl=[double[]]::new($n);$vo=[double[]]::new($n);$op=[double[]]::new($n)
for($i=0;$i-lt$n;$i++){$hi[$i]=[double]$k[$i].High;$lo[$i]=[double]$k[$i].Low;$op[$i]=[double]$k[$i].Open;$cl[$i]=[double]$k[$i].Close;$vo[$i]=[double]$k[$i].Volume}
$dl=New-Object 'Collections.Generic.List[string]';foreach($r in $k){$dl.Add($r.Date)};$dates=$dl.ToArray()
Remove-Variable k,dl -ErrorAction SilentlyContinue

$sig=Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $cl $hi $lo $vo $n
$siList=New-Object 'Collections.Generic.List[int]'
for($si=100;$si-lt$sig.Length;$si++){if($sig[$si]){$siList.Add($si)}}
$tIdx=$siList.ToArray()
Write-Host ("Signals: " + $tIdx.Length)

# Build trade records
$trades=New-Object 'Collections.Generic.List[PSObject]'
foreach($ix in $tIdx){
    $ex=$ix+5;if($ex-ge$n){continue}
    $entryPrice=$cl[$ix];$exitPrice=$cl[$ex]
    $ret=($exitPrice-$entryPrice)/$entryPrice*100
    $dateEntry=$dates[$ix];$dateExit=$dates[$ex]
    
    # Determine if signal was oversold (long) or overbought (short)
    $stochVal=$null # We'll compute in a separate pass
    $signalType=""
    if($ix -ge 5){# rough check - we'll do proper stoch calc later
    }
    
    $trades.Add([PSCustomObject]@{
        EntryIdx=$ix;ExitIdx=$ex;EntryDate=$dateEntry;ExitDate=$dateExit
        EntryPrice=[Math]::Round($entryPrice,4);ExitPrice=[Math]::Round($exitPrice,4)
        ReturnPct=[Math]::Round($ret,4);HighBar=-1;LowBar=-1
    })
}
$tradeArr=$trades.ToArray()
Write-Host ("Trades: " + $tradeArr.Count)

# ===== PHASE 16.1 — YEAR-BY-YEAR =====
Write-Host "`n=== PHASE 16.1: YEARLY DECAY ==="
$yearBuckets=@{}
foreach($t in $tradeArr){
    $y=($t.EntryDate -split '[- ]')[0]
    if(-not$yearBuckets.ContainsKey($y)){$yearBuckets[$y]=New-Object 'Collections.Generic.List[double]'}
    $yearBuckets[$y].Add($t.ReturnPct)
}
$yearRows=New-Object 'Collections.Generic.List[PSObject]'
$yearMeans=@()
foreach($y in ($yearBuckets.Keys|Sort-Object)){
    $ra=$yearBuckets[$y].ToArray();$cnt=$ra.Count
    if($cnt-lt3){continue}
    $wins=($ra|?{$_-gt0}).Count;$losses=$cnt-$wins;$wr=$wins/$cnt*100
    $avg=($ra|Measure -Average).Average
    $g=($ra|?{$_-gt0}|Measure -Sum).Sum;$ls=($ra|?{$_-lt0}|Measure -Sum).Sum;$pf=if($ls-ne0){[Math]::Abs($g/$ls)}else{999}
    $sdSum=0.0;foreach($x in $ra){$d=$x-$avg;$sdSum+=$d*$d};$sd=[Math]::Sqrt($sdSum/($cnt-1));$sh=if($sd-gt0){$avg/$sd}else{0}
    $dd=0.0;$eq=1.0;$pk=1.0;foreach($x in $ra){$eq*=(1+$x/100);if($eq-gt$pk){$pk=$eq};$d=($pk-$eq)/$pk*100;if($d-gt$dd){$dd=$d}}
    $yearRows.Add([PSCustomObject]@{Year=$y;Trades=$cnt;ProfitFactor=[Math]::Round($pf,4);Expectancy=[Math]::Round($avg,4);WinRate=[Math]::Round($wr,1);Sharpe=[Math]::Round($sh,4);Drawdown=[Math]::Round($dd,2)})
    $yearMeans+=$avg
    Write-Host ("  " + $y + ": trades=" + $cnt + " PF=" + [Math]::Round($pf,4) + " Exp=" + [Math]::Round($avg,4) + " WR=" + [Math]::Round($wr,1) + "% Sharpe=" + [Math]::Round($sh,4))
}
$yearRows|Export-Csv (Join-Path $OutputDir "edge_decay_yearly.csv") -NoTypeInformation

# Check trend: compare first half vs second half of yearly expectations
$yHalf=[Math]::Floor($yearMeans.Count/2)
if($yHalf-ge1){
    $earlyAvg=($yearMeans[0..($yHalf-1)]|Measure -Average).Average
    $lateAvg=($yearMeans[($yearMeans.Count-$yHalf)..($yearMeans.Count-1)]|Measure -Average).Average
    $yTrend=$lateAvg-$earlyAvg
}else{$yTrend=0}
Write-Host ("Yearly trend (late half - early half): " + [Math]::Round($yTrend,4))

# ===== PHASE 16.2 — ROLLING 6-MONTH =====
Write-Host "`n=== PHASE 16.2: ROLLING WINDOWS ==="
# ~6 months of 30m bars = ~8640 bars (6*30*24*2)
$windowBars=8640;$stepBars=720; # monthly step
$rRows=New-Object 'Collections.Generic.List[PSObject]';$rSharpe=@()
for($ws=0;$ws+$windowBars-lt$n;$ws+=$stepBars){
    $we=$ws+$windowBars
    $rRets=New-Object 'Collections.Generic.List[double]'
    foreach($t in $tradeArr){if($t.EntryIdx-ge$ws-and$t.EntryIdx-lt$we){$rRets.Add($t.ReturnPct)}}
    if($rRets.Count-lt3){continue}
    $ra=$rRets.ToArray();$cnt=$ra.Count
    $avg=($ra|Measure -Average).Average
    $g=($ra|?{$_-gt0}|Measure -Sum).Sum;$ls=($ra|?{$_-lt0}|Measure -Sum).Sum;$pf=if($ls-ne0){[Math]::Abs($g/$ls)}else{999}
    $sdSum=0.0;foreach($x in $ra){$d=$x-$avg;$sdSum+=$d*$d};$sd=[Math]::Sqrt($sdSum/($cnt-1));$sh=if($sd-gt0){[Math]::Round($avg/$sd,4)}else{0}
    $dd=0.0;$eq=1.0;$pk=1.0;foreach($x in $ra){$eq*=(1+$x/100);if($eq-gt$pk){$pk=$eq};$d=($pk-$eq)/$pk*100;if($d-gt$dd){$dd=$d}}
    $rRows.Add([PSCustomObject]@{WindowStart=$dates[$ws];WindowEnd=$dates[($we-1)];Trades=$cnt;ProfitFactor=[Math]::Round($pf,4);Expectancy=[Math]::Round($avg,4);Sharpe=$sh;Drawdown=[Math]::Round($dd,2)})
    $rSharpe+=$sh
}
$rRows|Export-Csv (Join-Path $OutputDir "edge_decay_rolling.csv") -NoTypeInformation
Write-Host ("Windows: " + $rRows.Count)

# Check downward trend in rolling windows
if($rSharpe.Count-ge4){
    $rHalf=[Math]::Floor($rSharpe.Count/2)
    $rEarly=($rSharpe[0..($rHalf-1)]|Measure -Average).Average
    $rLate=($rSharpe[($rSharpe.Count-$rHalf)..($rSharpe.Count-1)]|Measure -Average).Average
    $rTrend=$rLate-$rEarly
}else{$rTrend=0}
Write-Host ("Rolling trend (late half - early half): " + [Math]::Round($rTrend,4))

# ===== PHASE 16.3 — REGIME ATTRIBUTION =====
Write-Host "`n=== PHASE 16.3: REGIME ATTRIBUTION ==="
# Regime classification WITHOUT new indicators: use price action only
# Compute simple regime per bar based on last 20 bars
$regime=New-Object 'string[]' $n
for($i=20;$i-lt$n;$i++){
    $chg=$cl[$i]-$cl[$i-20]
    $rangeSum=0.0;for($j=$i-19;$j-le$i;$j++){$rangeSum+=($hi[$j]-$lo[$j])/$cl[$j]*100}
    $avgRange=$rangeSum/20
    $curRange=($hi[$i]-$lo[$i])/$cl[$i]*100
    
    if($curRange -gt $avgRange*1.5){$regime[$i]="HIGH_VOL"}
    elseif($chg -gt 0 -and ($hi[$i]-$lo[$i]) -lt $avgRange*1.2){$regime[$i]="UP_TREND"}
    elseif($chg -lt 0 -and ($hi[$i]-$lo[$i]) -lt $avgRange*1.2){$regime[$i]="DOWN_TREND"}
    else{$regime[$i]="RANGING"}
}

$regBuckets=@{}
foreach($t in $tradeArr){
    $r=$regime[$t.EntryIdx]
    if(-not$r-or$r-eq""){$r="STARTUP"}
    if(-not$regBuckets.ContainsKey($r)){$regBuckets[$r]=New-Object 'Collections.Generic.List[double]'}
    $regBuckets[$r].Add($t.ReturnPct)
}
$regRows=New-Object 'Collections.Generic.List[PSObject]'
foreach($r in ($regBuckets.Keys|Sort-Object)){
    $ra=$regBuckets[$r].ToArray();$cnt=$ra.Count;if($cnt-lt2){continue}
    $avg=($ra|Measure -Average).Average
    $g=($ra|?{$_-gt0}|Measure -Sum).Sum;$ls=($ra|?{$_-lt0}|Measure -Sum).Sum;$pf=if($ls-ne0){[Math]::Abs($g/$ls)}else{999}
    $wins=($ra|?{$_-gt0}).Count
    $regRows.Add([PSCustomObject]@{Regime=$r;Trades=$cnt;NetPnL=[Math]::Round($g+$ls,4);Expectancy=[Math]::Round($avg,4);ProfitFactor=[Math]::Round($pf,4);Wins=$wins;Losses=$cnt-$wins})
    Write-Host ("  " + $r + ": trades=" + $cnt + " Net=" + [Math]::Round($g+$ls,4) + " Exp=" + [Math]::Round($avg,4) + " PF=" + [Math]::Round($pf,4))
}
$regRows|Export-Csv (Join-Path $OutputDir "regime_profit_attribution.csv") -NoTypeInformation

# ===== PHASE 16.4 — TRADE LIFECYCLE =====
Write-Host "`n=== PHASE 16.4: TRADE LIFECYCLE ==="
$lifeRows=New-Object 'Collections.Generic.List[PSObject]'
$wMae=New-Object 'Collections.Generic.List[double]';$lMae=New-Object 'Collections.Generic.List[double]'
$wMfe=New-Object 'Collections.Generic.List[double]';$lMfe=New-Object 'Collections.Generic.List[double]'
$wHold=New-Object 'Collections.Generic.List[int]';$lHold=New-Object 'Collections.Generic.List[int]'
$wVol=New-Object 'Collections.Generic.List[double]';$lVol=New-Object 'Collections.Generic.List[double]'
$wVolu=New-Object 'Collections.Generic.List[double]';$lVolu=New-Object 'Collections.Generic.List[double]'

foreach($t in $tradeArr){
    $entry=$t.EntryPrice;$mae=0.0;$mfe=0.0
    $holdStart=$t.EntryIdx;$holdEnd=$t.ExitIdx
    $barsHeld=$holdEnd-$holdStart
    for($b=$holdStart;$b-le$holdEnd;$b++){
        $adv=($hi[$b]-$entry)/$entry*100
        $fav=($lo[$b]-$entry)/$entry*100
        if($fav-lt$mae){$mae=$fav}
        if($adv-gt$mfe){$mfe=$adv}
    }
    # Entry volatility: ATR-like measure of the entry bar
    $entryVol=($hi[$holdStart]-$lo[$holdStart])/$entry*100
    $entryVolu=$vo[$holdStart]
    
    $lifeRows.Add([PSCustomObject]@{
        EntryDate=$t.EntryDate;ReturnPct=$t.ReturnPct;HoldingBars=$barsHeld
        MAE=[Math]::Round($mae,4);MFE=[Math]::Round($mfe,4);EntryVolatility=[Math]::Round($entryVol,4);EntryVolume=[Math]::Round($entryVolu,0)
        WinFlag=if($t.ReturnPct-gt0){"WIN"}else{"LOSS"}
    })
    
    if($t.ReturnPct-gt0){
        $wMae.Add($mae);$wMfe.Add($mfe);$wHold.Add($barsHeld);$wVol.Add($entryVol);$wVolu.Add($entryVolu)
    }else{
        $lMae.Add($mae);$lMfe.Add($mfe);$lHold.Add($barsHeld);$lVol.Add($entryVol);$lVolu.Add($entryVolu)
    }
}
$lifeRows|Export-Csv (Join-Path $OutputDir "trade_lifecycle.csv") -NoTypeInformation

function avgL{param($a)if($a.Count-lt1){return 0}($a|Measure -Average).Average}

Write-Host ("  Winners: " + $wMae.Count + " AvgMAE=" + [Math]::Round((avgL $wMae),4) + " AvgMFE=" + [Math]::Round((avgL $wMfe),4) + " AvgHold=" + [Math]::Round((avgL $wHold),1) + " bars AvgVol=" + [Math]::Round((avgL $wVol),4) + "%")
Write-Host ("  Losers: " + $lMae.Count + " AvgMAE=" + [Math]::Round((avgL $lMae),4) + " AvgMFE=" + [Math]::Round((avgL $lMfe),4) + " AvgHold=" + [Math]::Round((avgL $lHold),1) + " bars AvgVol=" + [Math]::Round((avgL $lVol),4) + "%")

# ===== PHASE 16.5 — SIGNAL TYPE ANALYSIS (for behavior identification) =====
Write-Host "`n=== PHASE 16.5: SIGNAL TYPE ANALYSIS ==="
# Separate oversold (long) and overbought (short) signals based on Stoch at signal bar
# Signal array is offset: sig[i] corresponds to st[i+10] (k=5,d=5 offset)
$st2=Calc-Stoch $hi $lo $cl 5 5
$osCount2=0;$obCount2=0;$otherCount=0
$osRet2=New-Object 'Collections.Generic.List[double]';$obRet2=New-Object 'Collections.Generic.List[double]';$otherRet=New-Object 'Collections.Generic.List[double]'
foreach($t in $tradeArr){
    $ix=$t.EntryIdx
    # Signal for entry at ix fires at bar ix+10 (signal array offset)
    $signalBar=$ix+10
    if($signalBar-ge$st2.Count-or$signalBar-lt0){$otherCount++;$otherRet.Add($t.ReturnPct);continue}
    $sv=$st2[$signalBar]
    if($sv -lt 10){$osCount2++;$osRet2.Add($t.ReturnPct)}
    elseif($sv -gt 80){$obCount2++;$obRet2.Add($t.ReturnPct)}
    else{$otherCount++;$otherRet.Add($t.ReturnPct)}
}
Write-Host ("  Oversold signals (Stoch < 10): " + $osCount2 + " trades")
if($osRet2.Count-ge3){
    $oa=($osRet2|Measure -Average).Average
    $og=($osRet2|?{$_-gt0}|Measure -Sum).Sum;$ol=($osRet2|?{$_-lt0}|Measure -Sum).Sum;$opf=if($ol-ne0){[Math]::Abs($og/$ol)}else{999}
    $ow=($osRet2|?{$_-gt0}).Count;$owr=$ow/$osRet2.Count*100
    Write-Host ("    Avg=" + [Math]::Round($oa,4) + " PF=" + [Math]::Round($opf,4) + " WR=" + [Math]::Round($owr,1) + "%")
}
Write-Host ("  Overbought signals (Stoch > 80): " + $obCount2 + " trades")
if($obRet2.Count-ge3){
    $oa=($obRet2|Measure -Average).Average
    $og=($obRet2|?{$_-gt0}|Measure -Sum).Sum;$ol=($obRet2|?{$_-lt0}|Measure -Sum).Sum;$opf=if($ol-ne0){[Math]::Abs($og/$ol)}else{999}
    $ow=($obRet2|?{$_-gt0}).Count;$owr=$ow/$obRet2.Count*100
    Write-Host ("    Avg=" + [Math]::Round($oa,4) + " PF=" + [Math]::Round($opf,4) + " WR=" + [Math]::Round($owr,1) + "%")
}
Write-Host ("  Other (Stoch 10-80): " + $otherCount + " trades")
if($otherRet.Count-ge3){
    $oa=($otherRet|Measure -Average).Average
    $og=($otherRet|?{$_-gt0}|Measure -Sum).Sum;$ol=($otherRet|?{$_-lt0}|Measure -Sum).Sum;$opf=if($ol-ne0){[Math]::Abs($og/$ol)}else{999}
    $ow=($otherRet|?{$_-gt0}).Count;$owr=$ow/$otherRet.Count*100
    Write-Host ("    Avg=" + [Math]::Round($oa,4) + " PF=" + [Math]::Round($opf,4) + " WR=" + [Math]::Round($owr,1) + "%")
}

# Also analyze winners vs losers
$wRets=New-Object 'Collections.Generic.List[double]';$lRets=New-Object 'Collections.Generic.List[double]'
foreach($t in $tradeArr){
    if($t.ReturnPct -gt 0){$wRets.Add($t.ReturnPct)}else{$lRets.Add($t.ReturnPct)}
}
Write-Host ("  Winners: " + $wRets.Count + " Avg=" + [Math]::Round(($wRets|Measure -Average).Average,4))
Write-Host ("  Losers: " + $lRets.Count + " Avg=" + [Math]::Round(($lRets|Measure -Average).Average,4))

# Check if signal clusters dominate (consecutive signals)
Write-Host "`n  === Signal Clustering ==="
$clusterCount=0;$singleCount=0;$maxCluster=0;$curCluster=0
for($i=1;$i-lt$sig.Count;$i++){
    if($sig[$i]-and$sig[$i-1]){$curCluster++}
    elseif($sig[$i]){$singleCount++;if($curCluster-gt0){$clusterCount+=$curCluster};$curCluster=0}
}
Write-Host ("  Single isolated signals: " + $singleCount)
Write-Host ("  Clustered signals (consecutive): " + $clusterCount)

# ===== PHASE 16.6 — FRAGILITY TEST =====
Write-Host "`n=== PHASE 16.6: FRAGILITY TEST ==="
$rand=new-object System.Random
$fragRows=New-Object 'Collections.Generic.List[PSObject]'
$allRets=$tradeArr|%{$_.ReturnPct}
$baseAvg=($allRets|Measure -Average).Average
$baseG=($allRets|?{$_-gt0}|Measure -Sum).Sum;$baseL=($allRets|?{$_-lt0}|Measure -Sum).Sum;$basePf=if($baseL-ne0){[Math]::Abs($baseG/$baseL)}else{999}
Write-Host ("  Baseline: PF=" + [Math]::Round($basePf,4) + " Exp=" + [Math]::Round($baseAvg,4))

foreach($pct in @(5,10,15)){
    for($iter=0;$iter-lt5;$iter++){
        $keep=New-Object 'Collections.Generic.List[double]'
        $tempRets=New-Object 'System.Collections.ArrayList';$tempRets.AddRange($allRets)
        $removeCount=[Math]::Max(1,[Math]::Floor($allRets.Count*$pct/100))
        for($r=0;$r-lt$removeCount;$r++){$idx=$rand.Next($tempRets.Count);$tempRets.RemoveAt($idx)}
        $ra=$tempRets.ToArray()
        $avg=($ra|Measure -Average).Average
        $g=($ra|?{$_-gt0}|Measure -Sum).Sum;$ls=($ra|?{$_-lt0}|Measure -Sum).Sum;$pf=if($ls-ne0){[Math]::Abs($g/$ls)}else{999}
        $fragRows.Add([PSCustomObject]@{RemovePct=$pct;Iteration=$iter+1;Trades=$ra.Count;ProfitFactor=[Math]::Round($pf,4);Expectancy=[Math]::Round($avg,4)})
    }
}
# Average by removal pct
$fragAvg=@{}
foreach($fr in $fragRows){
    $key=$fr.RemovePct
    if(-not$fragAvg.ContainsKey($key)){$fragAvg[$key]=New-Object 'Collections.Generic.List[double]'}
    $fragAvg[$key].Add($fr.ProfitFactor)
}
foreach($key in ($fragAvg.Keys|Sort-Object)){
    $vals=$fragAvg[$key].ToArray()
    $avgPf=($vals|Measure -Average).Average;$minPf=($vals|Measure -Minimum).Minimum
    Write-Host ("  Remove " + $key + "%: avg PF=" + [Math]::Round($avgPf,4) + " min PF=" + [Math]::Round($minPf,4))
}
$fragRows|Export-Csv (Join-Path $OutputDir "fragility_test.csv") -NoTypeInformation

Write-Host "`n=== PHASE 16 COMPLETE ==="
