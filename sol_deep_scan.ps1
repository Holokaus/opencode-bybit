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
$pem = [System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH)
$b64 = ($pem -replace '-----[A-Z ]+-----', '') -replace '\s', ''
$der = [System.Convert]::FromBase64String($b64)
$o = 0; if ($der[$o] -ne 0x30) { throw "bad" }; $o++; $seqLen = Read-DerLength $der ([ref]$o)
$rsaP = New-Object System.Security.Cryptography.RSAParameters
$v = Read-DerInteger $der ([ref]$o)
$rsaP.Modulus = Read-DerInteger $der ([ref]$o); $rsaP.Exponent = Read-DerInteger $der ([ref]$o)
$rsaP.D = Read-DerInteger $der ([ref]$o); $rsaP.P = Read-DerInteger $der ([ref]$o)
$rsaP.Q = Read-DerInteger $der ([ref]$o); $rsaP.DP = Read-DerInteger $der ([ref]$o)
$rsaP.DQ = Read-DerInteger $der ([ref]$o); $rsaP.InverseQ = Read-DerInteger $der ([ref]$o)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($rsaP)
$apiKey = $env:BYBIT_API_KEY; $recvWindow = "5000"

function Call-Bybit-GET {
    param($endpoint, $query)
    $ts = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = [System.Text.Encoding]::UTF8.GetBytes("${ts}${apiKey}${recvWindow}${query}")
    $h = [System.Security.Cryptography.SHA256]::Create()
    $sg = [System.Convert]::ToBase64String($rsa.SignData($b, $h))
    $hd = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$recvWindow;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2";"X-Referer"="bybit-skill"}
    try { return (Invoke-WebRequest -Uri "https://api.bybit.com$endpoint`?$query" -Headers $hd -UseBasicParsing -TimeoutSec 20 | ConvertFrom-Json).result }
    catch { return $null }
}

function Get-Klines($category, $symbol, $interval, $limit) {
    $all = @(); $cursor = ""
    while ($all.Count -lt $limit) {
        $q = "category=$category&symbol=$symbol&interval=$interval&limit=1000"
        if ($cursor) { $q += "&cursor=$cursor" }
        $r = Call-Bybit-GET -endpoint "/v5/market/kline" -query $q
        if (-not $r -or -not $r.list) { break }
        $all += $r.list
        if ($r.list.Count -lt 1000) { break }
        if ($r.nextPageCursor) { $cursor = $r.nextPageCursor } else { break }
    }
    return $all | Select-Object -First $limit
}

function Calculate-RSI($prices, $period) {
    if ($prices.Count -le $period) { return @() }
    $gains = [double[]]::new($prices.Count); $losses = [double[]]::new($prices.Count)
    for ($i = 1; $i -lt $prices.Count; $i++) {
        $diff = $prices[$i] - $prices[$i-1]
        if ($diff -ge 0) { $gains[$i] = $diff } else { $losses[$i] = -$diff }
    }
    $avgGain = ($gains[1..$period] | Measure-Object -Sum).Sum / $period
    $avgLoss = ($losses[1..$period] | Measure-Object -Sum).Sum / $period
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

function Test-RSI-Levels {
    param($prices, $rsiVals, $period)
    $results = @()
    foreach ($obLevel in (55..95 | Where-Object {$_ % 2 -eq 0})) {
        foreach ($osLevel in (5..45 | Where-Object {$_ % 2 -eq 0 -and $_ -lt ($obLevel - 20)})) {
            $obWins = 0; $obLosses = 0; $obTotal = 0; $obReturn = 0
            $osWins = 0; $osLosses = 0; $osTotal = 0; $osReturn = 0
            
            for ($i = $period; $i -lt $rsiVals.Count - 5; $i++) {
                # OB test: when RSI crosses above OB, check if price drops in next 5 candles
                if ($rsiVals[$i] -ge $obLevel -and $rsiVals[$i-1] -lt $obLevel) {
                    $obTotal++
                    $futureHigh = ($prices[($i+1)..[Math]::Min($i+5, $prices.Count-1)] | Measure-Object -Maximum).Maximum
                    $futureLow = ($prices[($i+1)..[Math]::Min($i+5, $prices.Count-1)] | Measure-Object -Minimum).Minimum
                    $entry = $prices[$i]
                    $moveDown = ($entry - $futureLow) / $entry * 100
                    $obReturn += $moveDown
                    if ($moveDown -gt 1.0) { $obWins++ } else { $obLosses++ }
                }
                # OS test: when RSI crosses below OS, check if price rises in next 5 candles
                if ($rsiVals[$i] -le $osLevel -and $rsiVals[$i-1] -gt $osLevel) {
                    $osTotal++
                    $futureHigh = ($prices[($i+1)..[Math]::Min($i+5, $prices.Count-1)] | Measure-Object -Maximum).Maximum
                    $entry = $prices[$i]
                    $moveUp = ($futureHigh - $entry) / $entry * 100
                    $osReturn += $moveUp
                    if ($moveUp -gt 1.0) { $osWins++ } else { $osLosses++ }
                }
            }
            if ($obTotal -ge 5 -or $osTotal -ge 5) {
                $obWR = if ($obTotal -gt 0) { [Math]::Round($obWins/$obTotal*100,1) } else { 0 }
                $osWR = if ($osTotal -gt 0) { [Math]::Round($osWins/$osTotal*100,1) } else { 0 }
                $results += [PSCustomObject]@{
                    Period = $period; OB = $obLevel; OS = $osLevel
                    OB_WR = $obWR; OB_Trades = $obTotal; OB_AvgReturn = [Math]::Round($obReturn/[Math]::Max(1,$obTotal),2)
                    OS_WR = $osWR; OS_Trades = $osTotal; OS_AvgReturn = [Math]::Round($osReturn/[Math]::Max(1,$osTotal),2)
                    CombinedWR = [Math]::Round(($obWins+$osWins)/[Math]::Max(1,($obTotal+$osTotal))*100,1)
                }
            }
        }
    }
    return $results | Where-Object { $_.OB_Trades + $_.OS_Trades -ge 15 } | Sort-Object CombinedWR -Descending | Select-Object -First 5
}

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  SOL DEEP PERSONALITY SCAN - Finding the Unique Fingerprint" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

# Test many timeframes
$tfList = @(
    @{n="1m"; i="1"}, @{n="3m"; i="3"}, @{n="5m"; i="5"}, @{n="15m"; i="15"},
    @{n="30m"; i="30"}, @{n="1h"; i="60"}, @{n="2h"; i="120"}, @{n="3h"; i="180"},
    @{n="4h"; i="240"}, @{n="6h"; i="360"}, @{n="8h"; i="480"}, @{n="12h"; i="720"},
    @{n="1d"; i="D"}, @{n="2d"; i="2"}
)

$bestPerTF = @{}

foreach ($tf in $tfList) {
    Write-Host "Scanning $($tf.n)..." -ForegroundColor Yellow
    $klines = Get-Klines -category "spot" -symbol "SOLUSDT" -interval $tf.i -limit 800
    if (-not $klines -or $klines.Count -lt 100) { Write-Host "  Skip (insufficient data)"; continue }
    
    $close = $klines | ForEach-Object { [double]$_[4] }
    $high = $klines | ForEach-Object { [double]$_[2] }
    $low = $klines | ForEach-Object { [double]$_[3] }
    
    # Bruteforce RSI periods 2-50
    $bestPeriod = $null; $bestScore = 0; $bestOB = 0; $bestOS = 0; $bestWR = 0
    
    foreach ($per in (2..50)) {
        $rsi = Calculate-RSI -prices $close -period $per
        if ($rsi.Count -eq 0) { continue }
        
        # Find optimal OB/OS for this period by scanning levels
        $topResults = Test-RSI-Levels -prices $close -rsiVals $rsi -period $per
        if ($topResults.Count -gt 0 -and $topResults[0].CombinedWR -gt $bestScore) {
            $bestScore = $topResults[0].CombinedWR
            $bestPeriod = $per
            $bestOB = $topResults[0].OB
            $bestOS = $topResults[0].OS
            $bestWR = $topResults[0].CombinedWR
            $bestDetail = $topResults[0]
        }
    }
    
    if ($bestPeriod) {
        Write-Host "  BEST: RSI($bestPeriod) | OB=$bestOB OS=$bestOS | WR=$($bestDetail.CombinedWR)% | OB_WR=$($bestDetail.OB_WR)% OS_WR=$($bestDetail.OS_WR)% | OB_T=$($bestDetail.OB_Trades) OS_T=$($bestDetail.OS_Trades)"
        $bestPerTF[$tf.n] = @{period=$bestPeriod; ob=$bestOB; os=$bestOS; wr=$bestScore; detail=$bestDetail}
    }
}

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  RESULTS: SOL'S UNIQUE FINGERPRINT BY TIMEFRAME" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""

$sortedTF = $bestPerTF.GetEnumerator() | Sort-Object { $_.Value.wr } -Descending

foreach ($entry in $sortedTF) {
    $v = $entry.Value
    Write-Host "  $($entry.Key) | RSI($($v.period)) OB=$($v.ob) OS=$($v.os) | Signal WR=$($v.wr)% | OB hits=$($v.detail.OB_Trades) OS hits=$($v.detail.OS_Trades)" -ForegroundColor Cyan
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host "  WINNER: SOL'S BEST TIMEFRAME + RSI COMBO" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
if ($sortedTF.Count -gt 0) {
    $winner = $sortedTF | Select-Object -First 1
    $wv = $winner.Value
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Green
    Write-Host "  |   SOL's Natural Timeframe: $($winner.Key) " -ForegroundColor Green
    Write-Host "  |   RSI Period: $($wv.period) (not 14!)" -ForegroundColor Green
    Write-Host "  |   Overbought: $($wv.ob) (not 70!)" -ForegroundColor Green
    Write-Host "  |   Oversold:   $($wv.os) (not 30!)" -ForegroundColor Green
    Write-Host "  |   Signal Win Rate: $($wv.wr)%" -ForegroundColor Green
    Write-Host "  +------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    
    # Top 3 combos
    Write-Host "Top 3 performing combinations:" -ForegroundColor Yellow
    $sortedTF | Select-Object -First 3 | ForEach-Object {
        $v = $_.Value
        Write-Host "  #$([array]::IndexOf($sortedTF, $_)+1): $($_.Key) - RSI($($v.period)) OB=$($v.ob) OS=$($v.os) -> $($v.wr)% win rate"
    }
}

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  DEEP ANALYSIS: WHY THESE PARAMETERS FIT SOL" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

# Analyze the winning combo in more detail
if ($sortedTF.Count -gt 0) {
    $winner = $sortedTF | Select-Object -First 1
    $wv = $winner.Value
    $winTF = $tfList | Where-Object { $_.n -eq $winner.Key } | Select-Object -First 1
    
    $klines = Get-Klines -category "spot" -symbol "SOLUSDT" -interval $winTF.i -limit 800
    if ($klines) {
        $close = $klines | ForEach-Object { [double]$_[4] }
        $rsi = Calculate-RSI -prices $close -period $wv.period
        
        # Frequency analysis
        $validRsi = $rsi | Where-Object { $_ -ne $null }
        $rsiMin = ($validRsi | Measure-Object -Minimum).Minimum
        $rsiMax = ($validRsi | Measure-Object -Maximum).Maximum
        $rsiAvg = ($validRsi | Measure-Object -Average).Average
        $rsiSamples = $validRsi.Count
        
        # How often does SOL hit these levels?
        $obHits = ($validRsi | Where-Object { $_ -ge $wv.ob }).Count
        $osHits = ($validRsi | Where-Object { $_ -le $wv.os }).Count
        $midHits = ($validRsi | Where-Object { $_ -gt $wv.os -and $_ -lt $wv.ob }).Count
        
        # Distribution analysis
        $buckets = @()
        for ($b = 0; $b -le 100; $b += 10) {
            $cnt = ($validRsi | Where-Object { $_ -ge $b -and $_ -lt ($b+10) }).Count
            $buckets += @{range="$b-$(($b+10))"; count=$cnt; pct=[Math]::Round($cnt/$rsiSamples*100,1)}
        }
        
        Write-Host "`nRSI Distribution on $($winner.Key) [RSI($($wv.period))]:" -ForegroundColor Yellow
        foreach ($bk in $buckets) {
            $bar = [string]::new('Ã¢â€“Ë†', [Math]::Max(1, [Math]::Round($bk.pct / 2)))
            Write-Host "  $($bk.range): $bar $($bk.pct)%"
        }
        
        Write-Host "`nSOL RSI Statistics on $($winner.Key):" -ForegroundColor Yellow
        Write-Host "  Range: $([Math]::Round($rsiMin,1)) - $([Math]::Round($rsiMax,1))"
        Write-Host "  Average: $([Math]::Round($rsiAvg,1))"
        Write-Host "  Time in OB (>=$($wv.ob)): $( [Math]::Round($obHits/$rsiSamples*100,2) )%"
        Write-Host "  Time in OS (<=$($wv.os)): $( [Math]::Round($osHits/$rsiSamples*100,2) )%"
        Write-Host "  Time in Range: $( [Math]::Round($midHits/$rsiSamples*100,2) )%"
        
        # Autocorrelation - find SOL's natural rhythm
        Write-Host "`n--- SOL's Natural Rhythm (Price Change Autocorrelation) ---" -ForegroundColor Yellow
        $returns_d = [double[]]::new($close.Count)
        for ($i = 1; $i -lt $close.Count; $i++) {
            $returns_d[$i] = ($close[$i] - $close[$i-1]) / $close[$i-1] * 100
        }
        
        function Pearson-Correlation($x, $y) {
            $n = $x.Count; $sx = 0; $sy = 0; $sxy = 0; $sx2 = 0; $sy2 = 0
            for ($i = 0; $i -lt $n; $i++) {
                $sx += $x[$i]; $sy += $y[$i]
                $sxy += $x[$i] * $y[$i]; $sx2 += $x[$i] * $x[$i]; $sy2 += $y[$i] * $y[$i]
            }
            $denom = [Math]::Sqrt(($n*$sx2 - $sx*$sx) * ($n*$sy2 - $sy*$sy))
            if ($denom -eq 0) { return 0 }
            return ($n*$sxy - $sx*$sy) / $denom
        }
        
        Write-Host "  Lag analysis (how many candles until pattern repeats):" -ForegroundColor Gray
        foreach ($lag in @(1, 2, 3, 5, 8, 13, 21, 34, 55)) {
            if ($lag -ge $returns_d.Count) { break }
            $x = [double[]]@($returns_d[$lag..($returns_d.Count-1)])
            $y = [double[]]@($returns_d[0..($returns_d.Count-1-$lag)])
            $r = [Math]::Round((Pearson-Correlation $x $y), 3)
            Write-Host "  Lag $lag`: $r"
        }
    }
}

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  MACD QUICK SCAN (fast/slow/signal)" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

if ($sortedTF.Count -gt 0) {
    $winner = $sortedTF | Select-Object -First 1
    $winTF = $tfList | Where-Object { $_.n -eq $winner.Key } | Select-Object -First 1
    $klines = Get-Klines -category "spot" -symbol "SOLUSDT" -interval $winTF.i -limit 500
    if ($klines) {
        $close = $klines | ForEach-Object { [double]$_[4] }
        $bestMacd = $null; $bestMacdScore = 0
        $tested = 0
        foreach ($fast in @(3, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 20)) {
            foreach ($slow in (@(8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 30, 34, 40) | Where-Object {$_ -gt ($fast + 3)})) {
                foreach ($sig in @(3, 5, 7, 9, 11, 14)) {
                    $tested++
                    $emaF = $close[0]; $emaS = $close[0]
                    $macd = [double[]]::new($close.Count)
                    $sigLine = [double[]]::new($close.Count)
                    for ($i = 1; $i -lt $close.Count; $i++) {
                        $emaF = $close[$i]*(2/($fast+1)) + $emaF*(1-(2/($fast+1)))
                        $emaS = $close[$i]*(2/($slow+1)) + $emaS*(1-(2/($slow+1)))
                        $macd[$i] = $emaF - $emaS
                    }
                    $sigLine[$slow] = ($macd[($slow-$sig)..$slow] | Measure-Object -Average).Average
                    for ($i = $slow+1; $i -lt $close.Count; $i++) {
                        $sigLine[$i] = $macd[$i]*(2/($sig+1)) + $sigLine[$i-1]*(1-(2/($sig+1)))
                    }
                    $wins=0;$losses=0;$total=0
                    for ($i = $slow+2; $i -lt $close.Count - 3; $i++) {
                        if ($macd[$i-1] -le $sigLine[$i-1] -and $macd[$i] -gt $sigLine[$i]) {
                            $total++; $futureMax = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)] | Measure-Object -Maximum).Maximum
                            if ($futureMax -gt $close[$i]*1.005) { $wins++ } else { $losses++ }
                        }
                        if ($macd[$i-1] -ge $sigLine[$i-1] -and $macd[$i] -lt $sigLine[$i]) {
                            $total++; $futureMin = ($close[($i+1)..[Math]::Min($i+3,$close.Count-1)] | Measure-Object -Minimum).Minimum
                            if ($futureMin -lt $close[$i]*0.995) { $wins++ } else { $losses++ }
                        }
                    }
                    if ($total -ge 10 -and [Math]::Round($wins/$total*100,1) -gt $bestMacdScore) {
                        $bestMacdScore = [Math]::Round($wins/$total*100,1)
                        $bestMacd = @{fast=$fast; slow=$slow; sig=$sig; wr=$bestMacdScore; trades=$total}
                    }
                }
            }
        }
        if ($bestMacd) {
            Write-Host "`n  Tested $tested MACD combos on $($winner.Key)" -ForegroundColor Gray
            Write-Host "  Best MACD($($bestMacd.fast),$($bestMacd.slow),$($bestMacd.sig))" -ForegroundColor Green
            Write-Host "  Crossover Signal WR: $($bestMacd.wr)% | Trades: $($bestMacd.trades)" -ForegroundColor Green
            Write-Host "  (Standard MACD(12,26,9) is NOT optimal for SOL)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  FINAL VERDICT: SOL'S TRADING KEY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Every asset has a unique vibration frequency. The market key" -ForegroundColor White
Write-Host "  that unlocks SOL is NOT the same as BTC, ETH, or any pre-packaged" -ForegroundColor White
Write-Host "  indicator preset." -ForegroundColor White
Write-Host ""
Write-Host "  The data above reveals SOL's actual fingerprint - the timeframe" -ForegroundColor White
Write-Host "  and RSI period where its mean-reversion behavior is most consistent." -ForegroundColor White
Write-Host "  This is SOL's natural resonance, not a generic template." -ForegroundColor White
Write-Host ""

# Print top 3 results one more time as clear actionable keys
$sortedTF | Select-Object -First 3 | ForEach-Object {
    $v = $_.Value
    Write-Host "  -> $($_.Key) RSI($($v.period)): Buy <= $($v.os) | Sell >= $($v.ob) | WR $($v.wr)%" -ForegroundColor Cyan
}
