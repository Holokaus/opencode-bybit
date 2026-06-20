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
$apiKey = "gkPx5g3xgL2pthIg16"; $rw = "5000"

function Call-API($ep, $q) {
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = [Text.Encoding]::UTF8.GetBytes("${ts}${apiKey}${rw}${q}")
    $h = [Security.Cryptography.SHA256]::Create()
    $sg = [Convert]::ToBase64String($rsa.SignData($b, $h))
    $hd = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
    try { return (Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 30 | ConvertFrom-Json).result }
    catch { return $null }
}
function Get-K($int, $lim) {
    $all=@(); $cur=""
    while ($all.Count -lt $lim) {
        $q = "category=spot&symbol=SOLUSDT&interval=$int&limit=1000"
        if ($cur) { $q += "&cursor=$cur" }
        $r = Call-API -ep "/v5/market/kline" -q $q
        if (-not $r -or -not $r.list) { break }
        $all += $r.list
        if ($r.list.Count -lt 1000) { break }
        if ($r.nextPageCursor) { $cur = $r.nextPageCursor } else { break }
    }
    return $all | Select-Object -First $lim
}

function Calc-RSI($p, $period) {
    $g = [double[]]::new($p.Count); $l = [double[]]::new($p.Count)
    for ($i = 1; $i -lt $p.Count; $i++) { $d = $p[$i] - $p[$i-1]; if ($d -ge 0) { $g[$i] = $d } else { $l[$i] = -$d } }
    $ag = ($g[1..$period] | Measure-Object -Sum).Sum / $period
    $al = ($l[1..$period] | Measure-Object -Sum).Sum / $period
    $rsi = [double[]]::new($p.Count)
    for ($i = $period; $i -lt $p.Count; $i++) {
        if ($i -gt $period) { $ag = (($ag * ($period-1)) + $g[$i]) / $period; $al = (($al * ($period-1)) + $l[$i]) / $period }
        $rsi[$i] = if ($al -eq 0) { 100 } else { 100 - (100 / (1 + ($ag / $al))) }
    }
    return $rsi
}

function Calc-EMA($p, $period) {
    $ema = [double[]]::new($p.Count); $ema[0] = $p[0]
    $m = 2/($period+1)
    for ($i = 1; $i -lt $p.Count; $i++) { $ema[$i] = $p[$i]*$m + $ema[$i-1]*(1-$m) }
    return $ema
}

function Calc-MACD($p, $fast, $slow, $sig) {
    $ef = Calc-EMA $p $fast; $es = Calc-EMA $p $slow
    $macd = [double[]]::new($p.Count)
    for ($i = 0; $i -lt $p.Count; $i++) { $macd[$i] = $ef[$i] - $es[$i] }
    $sl = Calc-EMA $macd $sig
    return @{macd=$macd; signal=$sl; hist=@(for ($i=0;$i -lt $p.Count;$i++){$macd[$i]-$sl[$i]})}
}

function Calc-ATR($h, $l, $c, $period) {
    $tr = [double[]]::new($c.Count)
    for ($i = 1; $i -lt $c.Count; $i++) { $hl=$h[$i]-$l[$i]; $hc=[Math]::Abs($h[$i]-$c[$i-1]); $lc=[Math]::Abs($l[$i]-$c[$i-1]); $tr[$i]=[Math]::Max($hl,[Math]::Max($hc,$lc)) }
    $atr = [double[]]::new($c.Count)
    if ($c.Count -gt $period) { $atr[$period]=($tr[1..$period]|Measure-Object -Average).Average
        for ($i=$period+1;$i -lt $c.Count;$i++) { $atr[$i]=($atr[$i-1]*($period-1)+$tr[$i])/$period } }
    return $atr
}

function Calc-Bollinger($p, $period, $mult) {
    $ma = Calc-EMA $p $period; $bbu=[double[]]::new($p.Count); $bbl=[double[]]::new($p.Count)
    for ($i = $period; $i -lt $p.Count; $i++) {
        $slice = $p[($i-$period+1)..$i]; $avg = ($slice | Measure-Object -Average).Average
        $std = [Math]::Sqrt(($slice | ForEach-Object { ($_-$avg)*($_-$avg) } | Measure-Object -Sum).Sum / $period)
        $bbu[$i] = $ma[$i] + $std * $mult; $bbl[$i] = $ma[$i] - $std * $mult
    }
    return @{upper=$bbu; middle=$ma; lower=$bbl}
}

function Calc-StochRSI($rsi, $kPeriod, $dPeriod) {
    $k = [double[]]::new($rsi.Count)
    for ($i = $kPeriod; $i -lt $rsi.Count; $i++) {
        $rmax = ($rsi[($i-$kPeriod+1)..$i] | Measure-Object -Maximum).Maximum
        $rmin = ($rsi[($i-$kPeriod+1)..$i] | Measure-Object -Minimum).Minimum
        if ($rmax - $rmin -eq 0) { $k[$i] = 50 } else { $k[$i] = ($rsi[$i] - $rmin) / ($rmax - $rmin) * 100 }
    }
    $d = Calc-EMA $k $dPeriod
    return @{k=$k; d=$d}
}

# ============================================================
# PHASE 1: Trade Frequency + Data Coverage
# ============================================================
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  PHASE 1: TRADE FREQUENCY & DATA COVERAGE" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

Write-Host "Fetching 4h data (up to 2000 candles)..." -ForegroundColor Yellow
$klines = Get-K "240" 2000
$close = $klines | ForEach-Object { [double]$_[4] }
$high = $klines | ForEach-Object { [double]$_[2] }
$low = $klines | ForEach-Object { [double]$_[3] }
$volume = $klines | ForEach-Object { [double]$_[5] }
$timestamps = $klines | ForEach-Object { [long]$_[0] }

$startDate = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamps[-1]).DateTime
$endDate = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamps[0]).DateTime
$totalDays = [Math]::Round(($endDate - $startDate).TotalDays, 1)
Write-Host "  Data span: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd')) ($totalDays days)"
Write-Host "  Candles: $($close.Count)"

$rsi = Calc-RSI $close 41
$obLevel = 68; $osLevel = 42

$longDates=@(); $shortDates=@()
for ($i = 42; $i -lt $close.Count - 3; $i++) {
    if ($rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel -and $rsi[$i] -ne 0) { $longDates += $timestamps[$i] }
    if ($rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel -and $rsi[$i] -ne 100) { $shortDates += $timestamps[$i] }
}

$totalSignals = $longDates.Count + $shortDates.Count
$signalsPerDay = [Math]::Round($totalSignals / $totalDays, 3)
$daysBetweenSignals = [Math]::Round($totalDays / $totalSignals, 1)
$avgPerMonth = [Math]::Round($totalSignals / ($totalDays / 30.44), 1)

Write-Host "`nTrade Frequency:" -ForegroundColor Cyan
Write-Host "  Total signals: $totalSignals ($($longDates.Count) long, $($shortDates.Count) short)"
Write-Host "  Signals per day: $signalsPerDay"
Write-Host "  Days between signals: ~$daysBetweenSignals days"
Write-Host "  Signals per month: ~$avgPerMonth"
Write-Host "  Avg holding time target: 1-3 candles (4-12 hours per trade)" -ForegroundColor Gray

# ============================================================
# PHASE 2: INDICATOR COMBINATION BRUTEFORCE
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  PHASE 2: INDICATOR COMBINATION" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

$atr14 = Calc-ATR $high $low $close 14
$macd = Calc-MACD $close 12 26 9
$stochRsi = Calc-StochRSI $rsi 14 3

$combos = @()

foreach ($maPeriod in @(20, 50, 100, 200)) {
    $ma = Calc-EMA $close $maPeriod
    foreach ($useMACD in @($true, $false)) {
        foreach ($useVolume in @($true, $false)) {
            foreach ($useBollinger in @($true, $false)) {
                $longWins=0; $longLosses=0; $shortWins=0; $shortLosses=0; $totalTrades=0
                for ($i = 100; $i -lt $close.Count - 8; $i++) {
                    # Long signal: RSI crosses OS
                    if ($rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel) {
                        $pass = $true
                        if ($maPeriod -and $close[$i] -lt $ma[$i]) { $pass = $false }  # Price below MA = downtrend, skip long
                        if ($useMACD -and $macd.hist[$i] -lt 0) { $pass = $false }     # MACD negative momentum
                        if ($useVolume -and $volume[$i] -lt ($volume[$i-1]*0.8)) { $pass = $false }  # Low volume
                        if ($pass) {
                            $totalTrades++
                            $futureHigh = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)] | Measure-Object -Maximum).Maximum
                            if ($futureHigh -gt $close[$i]*1.01) { $longWins++ } else { $longLosses++ }
                        }
                    }
                    # Short signal: RSI crosses OB
                    if ($rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel) {
                        $pass = $true
                        if ($maPeriod -and $close[$i] -gt $ma[$i]) { $pass = $false }  # Price above MA = uptrend, skip short
                        if ($useMACD -and $macd.hist[$i] -gt 0) { $pass = $false }
                        if ($useVolume -and $volume[$i] -lt ($volume[$i-1]*0.8)) { $pass = $false }
                        if ($pass) {
                            $totalTrades++
                            $futureLow = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)] | Measure-Object -Minimum).Minimum
                            if ($futureLow -lt $close[$i]*0.99) { $shortWins++ } else { $shortLosses++ }
                        }
                    }
                }
                if ($totalTrades -ge 3) {
                    $wr = [Math]::Round(($longWins+$shortWins)/$totalTrades*100, 1)
                    $filters = @()
                    if ($maPeriod) { $filters += "MA$maPeriod" }
                    if ($useMACD) { $filters += "MACD" }
                    if ($useVolume) { $filters += "Vol" }
                    $filterStr = if ($filters.Count -eq 0) { "RSI only" } else { $filters -join "+" }
                    $combos += [PSCustomObject]@{Filters=$filterStr; Trades=$totalTrades; WR=$wr; LongWR=[Math]::Round($longWins/[Math]::Max(1,$longWins+$longLosses)*100,1); ShortWR=[Math]::Round($shortWins/[Math]::Max(1,$shortWins+$shortLosses)*100,1)}
                }
            }
        }
    }
}

Write-Host "Indicator combinations tested (RSI(41) + filters):" -ForegroundColor Yellow
$sortedCombos = $combos | Sort-Object WR -Descending
Write-Host ("  {0,-25} {1,-8} {2,-8} {3,-10} {4,-10}" -f "Combination", "WR(%)", "Trades", "LongWR", "ShortWR") -ForegroundColor Yellow
$sortedCombos | ForEach-Object {
    Write-Host ("  {0,-25} {1,-8} {2,-8} {3,-10} {4,-10}" -f $_.Filters, $_.WR, $_.Trades, $_.LongWR, $_.ShortWR)
}

# ============================================================
# PHASE 3: TIME CYCLE ANALYSIS
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  PHASE 3: TIME CYCLE ANALYSIS" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

# Hour of day (UTC) - which 4h window performs best
Write-Host "`n4h Window Performance (UTC):" -ForegroundColor Yellow
$windowData = @{}
for ($i = 42; $i -lt $close.Count - 3; $i++) {
    $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamps[$i])
    $window = $dt.Hour  # 0, 4, 8, 12, 16, 20
    if (-not $windowData.ContainsKey($window)) { $windowData[$window] = @{wins=0; losses=0; total=0} }
    $isLong = $rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel
    $isShort = $rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel
    if ($isLong -or $isShort) {
        $windowData[$window].total++
        if ($isLong) { $futureH = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Maximum).Maximum; if($futureH -gt $close[$i]*1.01){$windowData[$window].wins++}else{$windowData[$window].losses++} }
        if ($isShort) { $futureL = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Minimum).Minimum; if($futureL -lt $close[$i]*0.99){$windowData[$window].wins++}else{$windowData[$window].losses++} }
    }
}
$windowData.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $w = $_.Value; $wr = if ($w.total -gt 0) { [Math]::Round($w.wins/$w.total*100,1) } else { 0 }
    Write-Host ("  UTC $($_.Name):00-$([int]$_.Name+4):00  |  WR $wr%  |  $($w.total) signals  |  $($w.wins)W/$($w.losses)L")
}

# Month analysis
Write-Host "`nMonthly Performance:" -ForegroundColor Yellow
$monthData = @{}
for ($i = 42; $i -lt $close.Count - 3; $i++) {
    $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamps[$i])
    $mon = $dt.Month
    if (-not $monthData.ContainsKey($mon)) { $monthData[$mon] = @{wins=0; losses=0; total=0; returns=0} }
    $isLong = $rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel
    $isShort = $rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel
    if ($isLong -or $isShort) {
        $monthData[$mon].total++
        if ($isLong) { $futH = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Maximum).Maximum; $ret=($futH-$close[$i])/$close[$i]*100; if($ret -gt 1){$monthData[$mon].wins++}else{$monthData[$mon].losses++}; $monthData[$mon].returns += $ret }
        if ($isShort) { $futL = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Minimum).Minimum; $ret=($close[$i]-$futL)/$close[$i]*100; if($ret -gt 1){$monthData[$mon].wins++}else{$monthData[$mon].losses++}; $monthData[$mon].returns += $ret }
    }
}
$monthNames = @("","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")
$monthData.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $w = $_.Value; $mn = $monthNames[$_.Name]
    $wr = if ($w.total -gt 0) { [Math]::Round($w.wins/$w.total*100,1) } else { 0 }
    $avgRet = if ($w.total -gt 0) { [Math]::Round($w.returns/$w.total,2) } else { 0 }
    Write-Host ("  $mn  |  WR $wr%  |  $($w.total) signals  |  avg +$avgRet%  |  $($w.wins)W/$($w.losses)L")
}

# ============================================================
# PHASE 4: SOL MARKET REGIME BEHAVIOR
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  PHASE 4: SOL CHARACTER & MARKET REGIME" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

# Volatility clustering analysis
$returns = [double[]]::new($close.Count)
for ($i = 1; $i -lt $close.Count; $i++) { $returns[$i] = ($close[$i] - $close[$i-1]) / $close[$i-1] * 100 }
$avgAbsReturn = ($returns | Where-Object { $_ -ne 0 } | ForEach-Object { [Math]::Abs($_) } | Measure-Object -Average).Average
$highVolThreshold = $avgAbsReturn * 1.5
$lowVolThreshold = $avgAbsReturn * 0.5

Write-Host "SOL Volatility Regime:" -ForegroundColor Yellow
Write-Host "  Avg 4h candle move: $([Math]::Round($avgAbsReturn,2))%"
Write-Host "  High vol threshold: >$([Math]::Round($highVolThreshold,2))%"
Write-Host "  Low vol threshold: <$([Math]::Round($lowVolThreshold,2))%"

# Test signal quality in different volatility regimes
$highVolWins=0; $highVolLosses=0; $lowVolWins=0; $lowVolLosses=0; $normVolWins=0; $normVolLosses=0
for ($i = 42; $i -lt $close.Count - 3; $i++) {
    $isSignal = ($rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel) -or ($rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel)
    if (-not $isSignal) { continue }
    $vol = [Math]::Abs($returns[$i])
    # Determine win
    $isLong = $rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel
    if ($isLong) { $futH = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Maximum).Maximum; $won = $futH -gt $close[$i]*1.01 }
    else { $futL = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Minimum).Minimum; $won = $futL -lt $close[$i]*0.99 }
    if ($vol -ge $highVolThreshold) { if ($won) { $highVolWins++ } else { $highVolLosses++ } }
    elseif ($vol -le $lowVolThreshold) { if ($won) { $lowVolWins++ } else { $lowVolLosses++ } }
    else { if ($won) { $normVolWins++ } else { $normVolLosses++ } }
}
$hvTotal = $highVolWins+$highVolLosses; $lvTotal = $lowVolWins+$lowVolLosses; $nvTotal = $normVolWins+$normVolLosses
Write-Host "  High vol signals: $hvTotal ($([Math]::Round($highVolWins/[Math]::Max(1,$hvTotal)*100,1))% WR)"
Write-Host "  Normal vol signals: $nvTotal ($([Math]::Round($normVolWins/[Math]::Max(1,$nvTotal)*100,1))% WR)"
Write-Host "  Low vol signals: $lvTotal ($([Math]::Round($lowVolWins/[Math]::Max(1,$lvTotal)*100,1))% WR)"

# Consecutive signal behavior
Write-Host "`nSignal Clustering - what happens after a winner vs loser:" -ForegroundColor Yellow
$prevWon = $null; $afterWinWins=0; $afterWinLosses=0; $afterLossWins=0; $afterLossLosses=0
for ($i = 43; $i -lt $close.Count - 3; $i++) {
    $isSignal = ($rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel) -or ($rsi[$i-1] -lt $obLevel -and $rsi[$i] -ge $obLevel)
    if (-not $isSignal -or $prevWon -eq $null) { 
        if ($isSignal) {
            $isLong = $rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel
            if ($isLong) { $fH=($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Maximum).Maximum; $prevWon=$fH -gt $close[$i]*1.01 }
            else { $fL=($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Minimum).Minimum; $prevWon=$fL -lt $close[$i]*0.99 }
        }
        continue 
    }
    $isLong = $rsi[$i-1] -gt $osLevel -and $rsi[$i] -le $osLevel
    if ($isLong) { $fH=($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Maximum).Maximum; $won=$fH -gt $close[$i]*1.01 }
    else { $fL=($close[($i+1)..[Math]::Min($i+3,$close.Count-1)]|Measure-Object -Minimum).Minimum; $won=$fL -lt $close[$i]*0.99 }
    if ($prevWon) { if($won){$afterWinWins++}else{$afterWinLosses++} }
    else { if($won){$afterLossWins++}else{$afterLossLosses++} }
    $prevWon = $won
}
$awTot=$afterWinWins+$afterWinLosses; $alTot=$afterLossWins+$afterLossLosses
Write-Host "  After a WINNER:  $($afterWinWins)W/$($afterWinLosses)L = $(if($awTot-gt0){[Math]::Round($afterWinWins/$awTot*100,1)}else{0})% WR"
Write-Host "  After a LOSER:   $($afterLossWins)W/$($afterLossLosses)L = $(if($alTot-gt0){[Math]::Round($afterLossWins/$alTot*100,1)}else{0})% WR"

# Recovery time analysis
Write-Host "`nAverage Recovery Time (price returning above MA50 after a dip):" -ForegroundColor Yellow
$ma50 = Calc-EMA $close 50
$dipCount=0; $dipCandles=0;$dipRecoveries=0
for ($i = 60; $i -lt $close.Count; $i++) {
    if ($close[$i] -lt $ma50[$i]*0.95 -and $close[$i-1] -ge $ma50[$i-1]*0.95) {
        $dipCount++; $dipStart=$i
        for ($j = $i+1; $j -lt [Math]::Min($i+60, $close.Count); $j++) {
            if ($close[$j] -ge $ma50[$j]) { $dipRecoveries++; $dipCandles+=($j-$dipStart); break }
        }
    }
}
Write-Host "  Dips below MA50: $dipCount"
Write-Host "  Recoveries: $dipRecoveries ($([Math]::Round($dipRecoveries/[Math]::Max(1,$dipCount)*100,1))% recovery rate)"
Write-Host "  Avg candles to recover: $([Math]::Round($dipCandles/[Math]::Max(1,$dipRecoveries),1)) (=$([Math]::Round($dipCandles/[Math]::Max(1,$dipRecoveries)*4,1)) hours)"

# ============================================================
# PHASE 5: LIVE PAPER TRADING SIGNAL
# ============================================================
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  PHASE 5: LIVE PAPER TRADING SIGNAL" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

$latestRSI = $rsi[-1]; $prevRSI = $rsi[-2]
$currentPrice = $close[-1]
$candleTime = [DateTimeOffset]::FromUnixTimeMilliseconds($timestamps[0])

Write-Host "`n[MAINNET] LIVE 4H SOL SIGNAL - $(Get-Date -Format 'yyyy-MM-dd HH:mm UTC')" -ForegroundColor Cyan
Write-Host "  Current 4h candle start: $($candleTime.ToString('MM-dd HH:mm')) UTC" -ForegroundColor Gray
Write-Host "  Current price: $currentPrice" -ForegroundColor White
Write-Host "  RSI(41): $([Math]::Round($latestRSI,1)) (prev: $([Math]::Round($prevRSI,1)))" -ForegroundColor White
Write-Host "  ATR(14): $([Math]::Round($atr14[-1],2)) ($([Math]::Round($atr14[-1]/$close[-1]*100,2))%)" -ForegroundColor Gray

if ($prevRSI -gt $osLevel -and $latestRSI -le $osLevel) {
    Write-Host ("`n  +---- LONG SIGNAL ACTIVE -----+") -ForegroundColor Green
    $tp1 = $currentPrice * 1.015; $sl1 = $currentPrice * 0.995
    $tp2 = $currentPrice + $atr14[-1]*2; $sl2 = $currentPrice - $atr14[-1]*1.75
    Write-Host "  Entry: $([Math]::Round($currentPrice,2))"
    Write-Host ("  TP Option A (1.5`%): $([Math]::Round($tp1,2))")
    Write-Host ("  SL Option A (0.5`%): $([Math]::Round($sl1,2))")
    Write-Host "  TP Option B (2x ATR): $([Math]::Round($tp2,2))"
    Write-Host "  SL Option B (1.75x ATR): $([Math]::Round($sl2,2))"
}
elseif ($prevRSI -lt $obLevel -and $latestRSI -ge $obLevel) {
    Write-Host ("  +---- SHORT SIGNAL ACTIVE -----+") -ForegroundColor Red
    $tp1 = $currentPrice * 0.985; $sl1 = $currentPrice * 1.005
    $tp2 = $currentPrice - $atr14[-1]*2; $sl2 = $currentPrice + $atr14[-1]*1.75
    Write-Host "  Entry: $([Math]::Round($currentPrice,2))"
    Write-Host ("  TP Option A (1.5`%): $([Math]::Round($tp1,2))")
    Write-Host ("  SL Option A (0.5`%): $([Math]::Round($sl1,2))")
    Write-Host "  TP Option B (2x ATR): $([Math]::Round($tp2,2))"
    Write-Host "  SL Option B (1.75x ATR): $([Math]::Round($sl2,2))"
}
else {
    Write-Host "`n  Status: NO SIGNAL - WAITING" -ForegroundColor Yellow
    Write-Host "  RSI needs to cross below $osLevel for LONG or above $obLevel for SHORT"
    Write-Host "  Distance to OS: $([Math]::Round($latestRSI - $osLevel,1)) | Distance to OB: $([Math]::Round($obLevel - $latestRSI,1))"
}

Write-Host "`n================================" -ForegroundColor Magenta
Write-Host "  COMPLETE SOL STRATEGY KEY" -ForegroundColor Magenta
Write-Host "================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Timeframe: 4h" -ForegroundColor Green
Write-Host "  Core signal: RSI(41) crossing OB(68)/OS(42)" -ForegroundColor Green
Write-Host "  Trade frequency: ~$avgPerMonth signals/month (~$daysBetweenSignals days apart)" -ForegroundColor Green
Write-Host "  Best combo: RSI(41) + MA($(($sortedCombos | Select-Object -First 1).Filters))" -ForegroundColor Green
Write-Host "  Best combo WR: $(($sortedCombos | Select-Object -First 1).WR)% on $(($sortedCombos | Select-Object -First 1).Trades) trades" -ForegroundColor Green
if ($highVolWins/$hvTotal -gt $normVolWins/$nvTotal) {
    Write-Host "  SOL performs BEST in: HIGH volatility (hit RSI extreme faster)" -ForegroundColor Cyan
} else {
    Write-Host "  SOL performs BEST in: NORMAL volatility (reversals more reliable)" -ForegroundColor Cyan
}
Write-Host "  Exit: TP=1.5%/SL=0.5% (fixed) or TP=2xATR/SL=1.75xATR (adaptive)" -ForegroundColor Green

# Save paper trading log
$logEntry = @"
[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] PRICE=$([Math]::Round($currentPrice,2)) RSI41=$([Math]::Round($latestRSI,1)) ATR=$([Math]::Round($atr14[-1],2)) 
"@
$logPath = "paper_trading_log.txt"
Add-Content -LiteralPath $logPath -Value $logEntry -ErrorAction SilentlyContinue
Write-Host "`nPaper trading log updated: $logPath" -ForegroundColor Gray
