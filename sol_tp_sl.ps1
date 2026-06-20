function Read-DerLength($d, [ref]$o) {
    if ($d[$o.Value] -lt 0x80) { $l = $d[$o.Value]; $o.Value++; return $l }
    $n = $d[$o.Value] -band 0x7F; $o.Value++
    $len = 0; for ($i = 0; $i -lt $n; $i++) { $len = ($len -shl 8) -bor $d[$o.Value]; $o.Value++ }
    return $len
}
function Read-DerInteger($d, [ref]$o) {
    if ($d[$o.Value] -ne 0x02) { throw "bad" }; $o.Value++
    $l = Read-DerLength $d $o
    $v = [byte[]]::new($l); [Array]::Copy($d, $o.Value, $v, 0, $l)
    $s = if ($v.Length -gt 1 -and $v[0] -eq 0) {1} else {0}
    $t = [byte[]]::new($v.Length - $s); [Array]::Copy($v, $s, $t, 0, $t.Length)
    $o.Value += $l; return $t
}
$pem = [System.IO.File]::ReadAllText("bybit_private.pem")
$b64 = ($pem -replace '-----[A-Z ]+-----', '') -replace '\s', ''
$der = [System.Convert]::FromBase64String($b64)
$o = 0; if ($der[$o] -ne 0x30) { throw "bad" }; $o++; Read-DerLength $der ([ref]$o) | Out-Null
$rsaP = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger $der ([ref]$o) | Out-Null
$rsaP.Modulus = Read-DerInteger $der ([ref]$o); $rsaP.Exponent = Read-DerInteger $der ([ref]$o)
$rsaP.D = Read-DerInteger $der ([ref]$o); $rsaP.P = Read-DerInteger $der ([ref]$o)
$rsaP.Q = Read-DerInteger $der ([ref]$o); $rsaP.DP = Read-DerInteger $der ([ref]$o)
$rsaP.DQ = Read-DerInteger $der ([ref]$o); $rsaP.InverseQ = Read-DerInteger $der ([ref]$o)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($rsaP)
$apiKey = "gkPx5g3xgL2pthIg16"; $recvWindow = "5000"

function Call-Bybit-GET($ep, $q) {
    $ts = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = [System.Text.Encoding]::UTF8.GetBytes("${ts}${apiKey}${recvWindow}${q}")
    $h = [System.Security.Cryptography.SHA256]::Create()
    $sg = [System.Convert]::ToBase64String($rsa.SignData($b, $h))
    $hd = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$recvWindow;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
    try { return (Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 30 | ConvertFrom-Json).result }
    catch { return $null }
}
function Get-Klines($int, $lim) {
    $r = Call-Bybit-GET -ep "/v5/market/kline" -q "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if ($r -and $r.list) { return $r.list } else { return $null }
}

function Calculate-RSI($prices, $period) {
    $gains = [double[]]::new($prices.Count); $losses = [double[]]::new($prices.Count)
    for ($i = 1; $i -lt $prices.Count; $i++) {
        $diff = $prices[$i] - $prices[$i-1]
        if ($diff -ge 0) { $gains[$i] = $diff } else { $losses[$i] = -$diff }
    }
    $avgGain = if ($period -le ($prices.Count-1)) { ($gains[1..$period] | Measure-Object -Sum).Sum / $period } else { 0 }
    $avgLoss = if ($period -le ($prices.Count-1)) { ($losses[1..$period] | Measure-Object -Sum).Sum / $period } else { 0 }
    $rsi = [double[]]::new($prices.Count)
    for ($i = $period; $i -lt $prices.Count; $i++) {
        if ($i -gt $period) {
            $avgGain = (($avgGain * ($period-1)) + $gains[$i]) / $period
            $avgLoss = (($avgLoss * ($period-1)) + $losses[$i]) / $period
        }
        if ($avgLoss -eq 0) { $rsi[$i] = 100 } else { $rsi[$i] = 100 - (100 / (1 + ($avgGain / $avgLoss))) }
    }
    return $rsi
}

function Calculate-ATR($highs, $lows, $closes, $period) {
    $tr = [double[]]::new($closes.Count); $atr = [double[]]::new($closes.Count)
    for ($i = 1; $i -lt $closes.Count; $i++) {
        $hl = $highs[$i] - $lows[$i]
        $hc = [Math]::Abs($highs[$i] - $closes[$i-1])
        $lc = [Math]::Abs($lows[$i] - $closes[$i-1])
        $tr[$i] = [Math]::Max($hl, [Math]::Max($hc, $lc))
    }
    if ($closes.Count -gt $period) {
        $atr[$period] = ($tr[1..$period] | Measure-Object -Average).Average
        for ($i = $period+1; $i -lt $closes.Count; $i++) {
            $atr[$i] = ($atr[$i-1]*($period-1) + $tr[$i]) / $period
        }
    }
    return $atr
}

Write-Host "=====================================================================" -ForegroundColor Magenta
Write-Host "  SOL TP/SL BRUTEFORCE - Finding Optimal Exit Parameters" -ForegroundColor Magenta
Write-Host "=====================================================================" -ForegroundColor Magenta

# Fetch 4h data (winning timeframe)
Write-Host "`nFetching 4h data..." -ForegroundColor Yellow
$klines = Get-Klines -int "240" -lim 500
if (-not $klines) { Write-Host "No data"; exit }

$close = $klines | ForEach-Object { [double]$_[4] }
$high = $klines | ForEach-Object { [double]$_[2] }
$low = $klines | ForEach-Object { [double]$_[3] }

# Our winning parameters: 4h RSI(41) OB=68 OS=42
$rsiPeriod = 41; $obLevel = 68; $osLevel = 42
$rsi = Calculate-RSI -prices $close -period $rsiPeriod

# Calculate ATR(14) for reference
$atr14 = Calculate-ATR -highs $high -lows $low -closes $close -period 14
$currentAtr = $atr14[-1]
$currentPrice = $close[-1]
$atrPct = [Math]::Round($currentAtr / $currentPrice * 100, 2)
Write-Host "  Current price: $currentPrice" -ForegroundColor Cyan
Write-Host "  Current ATR(14): $currentAtr ($atrPct%)" -ForegroundColor Cyan

# Find entry signals
$longEntries = @(); $shortEntries = @()
for ($i = $rsiPeriod + 2; $i -lt $rsi.Count - 5; $i++) {
    # Long entry: RSI crosses below OS (42)
    if ($rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel -and $rsi[$i] -ne 0) {
        $longEntries += @{idx=$i; price=$close[$i]; rsi=$rsi[$i]; date=$klines[$i][0]}
    }
    # Short entry: RSI crosses above OB (68)
    if ($rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel -and $rsi[$i] -ne 100) {
        $shortEntries += @{idx=$i; price=$close[$i]; rsi=$rsi[$i]; date=$klines[$i][0]}
    }
}

Write-Host "`nEntry signals found: $($longEntries.Count) long, $($shortEntries.Count) short" -ForegroundColor Yellow

# Test different TP/SL percentage combinations
Write-Host "`n--- Phase 1: Fixed Percentage TP/SL Bruteforce ---" -ForegroundColor Yellow
$tpLevels = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0, 10.0)
$slLevels = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0)

$bestResults = @()
foreach ($tp in $tpLevels) {
    foreach ($sl in $slLevels) {
        $totalWins = 0; $totalLosses = 0; $totalProfit = 0; $totalTrades = 0
        $longWins=0; $longLosses=0; $longProfit=0; $longTrades=0
        $shortWins=0; $shortLosses=0; $shortProfit=0; $shortTrades=0
        
        # Test long entries
        foreach ($entry in $longEntries) {
            $i = $entry.idx; $entryPrice = $entry.price
            $tpPrice = $entryPrice * (1 + $tp/100)
            $slPrice = $entryPrice * (1 - $sl/100)
            $hit = $null
            for ($j = $i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) {
                if ($high[$j] -ge $tpPrice) { $hit = "TP"; break }
                if ($low[$j] -le $slPrice) { $hit = "SL"; break }
            }
            if ($hit -eq "TP") { $longWins++; $totalWins++; $totalProfit += $tp } elseif ($hit -eq "SL") { $longLosses++; $totalLosses++; $totalProfit -= $sl }
            if ($hit) { $totalTrades++; $longTrades++ }
        }
        
        # Test short entries
        foreach ($entry in $shortEntries) {
            $i = $entry.idx; $entryPrice = $entry.price
            $tpPrice = $entryPrice * (1 - $tp/100)
            $slPrice = $entryPrice * (1 + $sl/100)
            $hit = $null
            for ($j = $i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) {
                if ($low[$j] -le $tpPrice) { $hit = "TP"; break }
                if ($high[$j] -ge $slPrice) { $hit = "SL"; break }
            }
            if ($hit -eq "TP") { $shortWins++; $totalWins++; $totalProfit += $tp } elseif ($hit -eq "SL") { $shortLosses++; $totalLosses++; $totalProfit -= $sl }
            if ($hit) { $totalTrades++; $shortTrades++ }
        }
        
        if ($totalTrades -ge 5) {
            $wr = [Math]::Round($totalWins/$totalTrades*100,1)
            $avgProfit = [Math]::Round($totalProfit/$totalTrades, 2)
            $totalProfitPct = [Math]::Round($totalProfit, 2)
            $riskReward = [Math]::Round($tp/$sl, 2)
            $score = $wr * $riskReward * $totalTrades / 100  # Composite score
            
            $bestResults += [PSCustomObject]@{
                TP=$tp; SL=$sl; R_R=$riskReward
                WR=$wr; Trades=$totalTrades
                AvgProfit=$avgProfit; TotalProfit=$totalProfitPct
                Score=[Math]::Round($score,1)
                LongWR=[Math]::Round($longWins/[Math]::Max(1,$longTrades)*100,1)
                ShortWR=[Math]::Round($shortWins/[Math]::Max(1,$shortTrades)*100,1)
                LongT=$longTrades; ShortT=$shortTrades
            }
        }
    }
}

# Sort by composite score
$sorted = $bestResults | Sort-Object Score -Descending

Write-Host "`nTop 10 TP/SL combinations by composite score:" -ForegroundColor Cyan
Write-Host ("  {0,-6} {1,-6} {2,-6} {3,-8} {4,-8} {5,-10} {6,-10} {7,-8} {8,-8}" -f "TP(%)","SL(%)","R:R","WR(%)","Trades","AvgProfit","Total%","LngWR","ShtWR") -ForegroundColor Yellow
$sorted | Select-Object -First 10 | ForEach-Object {
    Write-Host ("  {0,-6} {1,-6} {2,-6} {3,-8} {4,-8} {5,-10} {6,-10} {7,-8} {8,-8}" -f $_.TP, $_.SL, $_.R_R, $_.WR, $_.Trades, $_.AvgProfit, $_.TotalProfit, $_.LongWR, $_.ShortWR)
}

Write-Host "`n--- Phase 2: ATR-Based TP/SL ---" -ForegroundColor Yellow
$atrMultipliers = @(0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0)
$atrResults = @()
foreach ($tpMult in $atrMultipliers) {
    foreach ($slMult in $atrMultipliers) {
        $tw=0; $tl=0; $tpP=0; $tt=0; $lw=0; $ll=0; $sw=0; $sl_=0
        foreach ($entry in $longEntries) {
            $i = $entry.idx; $ep = $entry.price
            $atr = $atr14[$i]; if (-not $atr -or $atr -eq 0) { continue }
            $tpP_ = $ep + $atr * $tpMult; $slP = $ep - $atr * $slMult
            for ($j = $i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) {
                if ($high[$j] -ge $tpP_) { $tw++; $tpP += $tpMult * 100; $tt++; $lw++; break }
                if ($low[$j] -le $slP) { $tl++; $tpP -= $slMult * 100; $tt++; $ll++; break }
            }
        }
        foreach ($entry in $shortEntries) {
            $i = $entry.idx; $ep = $entry.price
            $atr = $atr14[$i]; if (-not $atr -or $atr -eq 0) { continue }
            $tpP_ = $ep - $atr * $tpMult; $slP = $ep + $atr * $slMult
            for ($j = $i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) {
                if ($low[$j] -le $tpP_) { $tw++; $tpP += $tpMult * 100; $tt++; $sw++; break }
                if ($high[$j] -ge $slP) { $tl++; $tpP -= $slMult * 100; $tt++; $sl_++; break }
            }
        }
        if ($tt -ge 5) {
            $wr = [Math]::Round($tw/$tt*100,1)
            $avgP = [Math]::Round($tpP/$tt, 2)
            $rr = [Math]::Round($tpMult/$slMult, 2)
            $score = $wr * $rr * $tt / 100
            $atrResults += [PSCustomObject]@{TP_ATR=$tpMult; SL_ATR=$slMult; R_R=$rr; WR=$wr; Trades=$tt; AvgProfit=$avgP; TotalProfit=[Math]::Round($tpP,2); Score=[Math]::Round($score,1)}
        }
    }
}

$sortedAtr = $atrResults | Sort-Object Score -Descending
Write-Host "`nTop 10 ATR-based TP/SL combinations:" -ForegroundColor Cyan
Write-Host ("  {0,-8} {1,-8} {2,-6} {3,-8} {4,-8} {5,-10} {6,-10}" -f "TP(xATR)","SL(xATR)","R:R","WR(%)","Trades","Avg%","Score") -ForegroundColor Yellow
$sortedAtr | Select-Object -First 10 | ForEach-Object {
    Write-Host ("  {0,-8} {1,-8} {2,-6} {3,-8} {4,-8} {5,-10} {6,-10}" -f $_.TP_ATR, $_.SL_ATR, $_.R_R, $_.WR, $_.Trades, $_.AvgProfit, $_.Score)
}

Write-Host "`n--- Phase 3: Best Risk-Reward Ratio Analysis ---" -ForegroundColor Yellow
$rrGroups = $bestResults | Group-Object R_R | ForEach-Object {
    $g = $_.Group
    $avgWR = [Math]::Round(($g | Measure-Object WR -Average).Average, 1)
    $avgTrades = [Math]::Round(($g | Measure-Object Trades -Average).Average, 0)
    $avgProfit = [Math]::Round(($g | Measure-Object TotalProfit -Average).Average, 2)
    $bestInGroup = $g | Sort-Object Score -Descending | Select-Object -First 1
    [PSCustomObject]@{RR=$_.Name; Count=$_.Count; AvgWR=$avgWR; AvgTrades=$avgTrades; AvgTotalProfit=$avgProfit; BestTP=$bestInGroup.TP; BestSL=$bestInGroup.SL}
} | Sort-Object AvgTotalProfit -Descending

Write-Host ("  {0,-6} {1,-8} {2,-8} {3,-10} {4,-10} {5,-8}" -f "R:R","Combos","AvgWR","AvgTrades","AvgProfit","BestTP/SL") -ForegroundColor Yellow
$rrGroups | Select-Object -First 8 | ForEach-Object {
    Write-Host ("  {0,-6} {1,-8} {2,-8} {3,-10} {4,-10} {5,-8}" -f $_.RR, $_.Count, $_.AvgWR, $_.AvgTrades, $_.AvgTotalProfit, "$($_.BestTP)/$($_.BestSL)")
}

Write-Host "`n--- Phase 4: Dynamic TP/SL (Trailing Stop Simulation) ---" -ForegroundColor Yellow
$trailPcts = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0)
$trailResults = @()
foreach ($trailPct in $trailPcts) {
    foreach ($tpTarget in @(2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0)) {
        $tw=0; $tl=0; $tpP=0; $tt=0
        foreach ($entry in $longEntries) {
            $i = $entry.idx; $ep = $entry.price; $trailSlip = $ep * (1 - $trailPct/100)
            $targetPrice = $ep * (1 + $tpTarget/100)
            $peak = $ep; $exitPrice = $null
            for ($j = $i+1; $j -lt [Math]::Min($i+72, $close.Count); $j++) {
                if ($high[$j] -gt $peak) { $peak = $high[$j]; $trailSlip = $peak * (1 - $trailPct/100) }
                if ($low[$j] -le $trailSlip) { $exitPrice = $low[$j]; break }
                if ($peak -ge $targetPrice) { $exitPrice = $targetPrice; break }
            }
            if ($exitPrice) { $tt++
                if ($exitPrice -gt $ep) { $tw++; $tpP += ($exitPrice-$ep)/$ep*100 }
                else { $tl++; $tpP -= ($ep-$exitPrice)/$ep*100 }
            }
        }
        if ($tt -ge 5) {
            $wr = [Math]::Round($tw/$tt*100,1); $avgP = [Math]::Round($tpP/$tt, 2)
            $trailResults += [PSCustomObject]@{TrailPct=$trailPct; Target=$tpTarget; WR=$wr; Trades=$tt; AvgProfit=$avgP; TotalProfit=[Math]::Round($tpP,2)}
        }
    }
}
$sortedTrail = $trailResults | Sort-Object TotalProfit -Descending
Write-Host "Top 8 trailing stop results (longs only):" -ForegroundColor Cyan
Write-Host ("  {0,-10} {1,-8} {2,-8} {3,-8} {4,-10} {5,-10}" -f "Trail%","Target%","WR(%)","Trades","Avg%","Total%") -ForegroundColor Yellow
$sortedTrail | Select-Object -First 8 | ForEach-Object {
    Write-Host ("  {0,-10} {1,-8} {2,-8} {3,-8} {4,-10} {5,-10}" -f $_.TrailPct, $_.Target, $_.WR, $_.Trades, $_.AvgProfit, $_.TotalProfit)
}

Write-Host "`n================================" -ForegroundColor Magenta
Write-Host "  FINAL VERDICT: SOL TP/SL KEY" -ForegroundColor Magenta
Write-Host "================================" -ForegroundColor Magenta

$topFixed = $sorted | Select-Object -First 3
$topAtr = $sortedAtr | Select-Object -First 3
Write-Host ""
Write-Host "Best Fixed TP/SL:" -ForegroundColor Green
$topFixed | ForEach-Object { Write-Host "  TP=$($_.TP)% SL=$($_.SL)% (R:R $($_.R_R)) | WR=$($_.WR)% | $($_.Trades) trades | Avg +$($_.AvgProfit)% | Score $($_.Score)" -ForegroundColor Cyan }
Write-Host ""
Write-Host "Best ATR-based TP/SL:" -ForegroundColor Green
$topAtr | ForEach-Object { Write-Host "  TP=$($_.TP_ATR)xATR SL=$($_.SL_ATR)xATR (R:R $($_.R_R)) | WR=$($_.WR)% | $($_.Trades) trades | Avg +$($_.AvgProfit)% | Score $($_.Score)" -ForegroundColor Cyan }
Write-Host ""
Write-Host "Current ATR(14): $currentAtr ($atrPct% of price)" -ForegroundColor Gray
