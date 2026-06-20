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
$o = 0
if ($der[$o] -ne 0x30) { throw "bad" }; $o++
$seqLen = Read-DerLength $der ([ref]$o)
$rsaP = New-Object System.Security.Cryptography.RSAParameters
$v = Read-DerInteger $der ([ref]$o)
$rsaP.Modulus = Read-DerInteger $der ([ref]$o)
$rsaP.Exponent = Read-DerInteger $der ([ref]$o)
$rsaP.D = Read-DerInteger $der ([ref]$o)
$rsaP.P = Read-DerInteger $der ([ref]$o)
$rsaP.Q = Read-DerInteger $der ([ref]$o)
$rsaP.DP = Read-DerInteger $der ([ref]$o)
$rsaP.DQ = Read-DerInteger $der ([ref]$o)
$rsaP.InverseQ = Read-DerInteger $der ([ref]$o)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($rsaP)

$apiKey = "gkPx5g3xgL2pthIg16"
$recvWindow = "5000"

function Call-Bybit-GET {
    param($endpoint, $query)
    $ts = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $paramStr = "${ts}${apiKey}${recvWindow}${query}"
    $b = [System.Text.Encoding]::UTF8.GetBytes($paramStr)
    $h = [System.Security.Cryptography.SHA256]::Create()
    $sigBytes = $rsa.SignData($b, $h)
    $signature = [System.Convert]::ToBase64String($sigBytes)
    $headers = @{
        "X-BAPI-API-KEY" = $apiKey; "X-BAPI-TIMESTAMP" = "$ts"
        "X-BAPI-SIGN" = $signature; "X-BAPI-RECV-WINDOW" = $recvWindow
        "X-BAPI-SIGN-TYPE" = "2"; "User-Agent" = "bybit-skill/1.4.2"; "X-Referer" = "bybit-skill"
    }
    try {
        $url = "https://api.bybit.com$endpoint`?$query"
        $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 15
        return ($resp.Content | ConvertFrom-Json).result
    } catch { Write-Host "Error: $_"; return $null }
}

function Get-Klines {
    param($category, $symbol, $interval, $limit)
    $q = "category=$category&symbol=$symbol&interval=$interval&limit=$limit"
    $result = Call-Bybit-GET -endpoint "/v5/market/kline" -query $q
    if ($result -and $result.list) { return $result.list }
    return $null
}

function Calculate-RSI {
    param($prices, $period)
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

function Calculate-SMA {
    param($prices, $period)
    $sma = [double[]]::new($prices.Count)
    for ($i = 0; $i -lt $prices.Count; $i++) {
        if ($i -lt $period-1) { $sma[$i] = $null; continue }
        $sum = 0; for ($j = $i-$period+1; $j -le $i; $j++) { $sum += $prices[$j] }
        $sma[$i] = $sum / $period
    }
    return $sma
}

# Fetch data for multiple timeframes
$timeframes = @(
    @{name="15m"; interval="15"}, 
    @{name="1h"; interval="60"}, 
    @{name="4h"; interval="240"}, 
    @{name="1d"; interval="D"}
)

$rsiPeriods = @(7, 10, 14, 20, 25)

foreach ($tf in $timeframes) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  SOLUSDT - $($tf.name) Timeframe" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Cyan
    
    $limit = if ($tf.name -eq "1d") { 200 } elseif ($tf.name -eq "4h") { 300 } elseif ($tf.name -eq "1h") { 200 } else { 200 }
    $klines = Get-Klines -category "spot" -symbol "SOLUSDT" -interval $tf.interval -limit $limit
    
    if (-not $klines) { Write-Host "No data"; continue }
    
    # Parse close prices
    $closePrices = $klines | ForEach-Object { [double]$_[4] }
    $highPrices = $klines | ForEach-Object { [double]$_[2] }
    $lowPrices = $klines | ForEach-Object { [double]$_[3] }
    $dates = $klines | ForEach-Object { 
        $ms = [long]$_[0]
        if ($tf.name -eq "1d") { Get-Date -Date ([System.DateTimeOffset]::FromUnixTimeMilliseconds($ms).DateTime) -Format "yyyy-MM-dd" }
        else { Get-Date -Date ([System.DateTimeOffset]::FromUnixTimeMilliseconds($ms).DateTime) -Format "MM-dd HH:mm" }
    }
    
    $lastClose = $closePrices[-1]
    $lastHigh = $highPrices[-1]
    $lastLow = $lowPrices[-1]
    $currentPrice = $lastClose
    
    Write-Host "Current Price: $currentPrice" -ForegroundColor Green
    Write-Host "  Data points: $($closePrices.Count)"
    Write-Host "  High: $($closePrices | Measure-Object -Maximum).Maximum"
    Write-Host "  Low: $($closePrices | Measure-Object -Minimum).Minimum"
    
    # RSI Analysis for different periods
    Write-Host "`n--- RSI Analysis ---" -ForegroundColor Yellow
    $rsiResults = @{}
    foreach ($per in $rsiPeriods) {
        $rsiVals = Calculate-RSI -prices $closePrices -period $per
        $lastRsi = $rsiVals[-1]
        if (-not $lastRsi) { continue }
        
        # Determine optimal overbought/oversold based on historical levels
        $validRsi = $rsiVals | Where-Object { $_ -ne $null }
        $rsiMin = ($validRsi | Measure-Object -Minimum).Minimum
        $rsiMax = ($validRsi | Measure-Object -Maximum).Maximum
        $rsiAvg = ($validRsi | Measure-Object -Average).Average
        $rsiStd = 0
        if ($validRsi.Count -gt 1) {
            $avg = $rsiAvg; $sqSum = ($validRsi | ForEach-Object { ($_ - $avg) * ($_ - $avg) } | Measure-Object -Sum).Sum
            $rsiStd = [Math]::Sqrt($sqSum / ($validRsi.Count - 1))
        }
        
        # Count touches near 70/30 and 80/20
        $touch70 = ($validRsi | Where-Object { $_ -ge 70 }).Count
        $touch30 = ($validRsi | Where-Object { $_ -le 30 }).Count
        $touch80 = ($validRsi | Where-Object { $_ -ge 80 }).Count
        $touch20 = ($validRsi | Where-Object { $_ -le 20 }).Count
        
        $rsiResults[$per] = @{last=$lastRsi; min=$rsiMin; max=$rsiMax; avg=$rsiAvg; std=$rsiStd; t70=$touch70; t30=$touch30; t80=$touch80; t20=$touch20}
        
        $suggestedOB = [Math]::Round($rsiAvg + 1.5*$rsiStd, 1)
        $suggestedOS = [Math]::Round($rsiAvg - 1.5*$rsiStd, 1)
        if ($suggestedOB -gt 100) { $suggestedOB = 85 }
        if ($suggestedOS -lt 0) { $suggestedOS = 15 }
        
        Write-Host "  RSI($per): last=$([Math]::Round($lastRsi,1)) | range=[$([Math]::Round($rsiMin,1))-$([Math]::Round($rsiMax,1))] | avg=$([Math]::Round($rsiAvg,1))"
        Write-Host "    Suggested OB: ~$suggestedOB (vs std 70) | Suggested OS: ~$suggestedOS (vs std 30)"
    }
    
    # MACD
    Write-Host "`n--- MACD (12,26,9) ---" -ForegroundColor Yellow
    $ema12 = $closePrices[0]
    $ema26 = $closePrices[0]
    $macdLine = [double[]]::new($closePrices.Count)
    $signalLine = [double[]]::new($closePrices.Count)
    
    for ($i = 1; $i -lt $closePrices.Count; $i++) {
        $ema12 = $closePrices[$i] * (2/13) + $ema12 * (11/13)
        $ema26 = $closePrices[$i] * (2/27) + $ema26 * (25/27)
        $macdLine[$i] = $ema12 - $ema26
    }
    # Signal line (9-period EMA of MACD)
    $signalLine[26] = ($macdLine[17..26] | Measure-Object -Average).Average
    for ($i = 27; $i -lt $closePrices.Count; $i++) {
        $signalLine[$i] = $macdLine[$i] * (2/10) + $signalLine[$i-1] * (8/10)
    }
    
    $lastMacd = $macdLine[-1]
    $lastSig = $signalLine[-1]
    $lastHist = $lastMacd - $lastSig
    Write-Host "  MACD: $([Math]::Round($lastMacd,4)) | Signal: $([Math]::Round($lastSig,4)) | Hist: $([Math]::Round($lastHist,4))"
    
    # Moving Average analysis
    Write-Host "`n--- Moving Averages ---" -ForegroundColor Yellow
    $maPeriods = @(7, 20, 50, 100, 200)
    foreach ($maP in $maPeriods) {
        if ($closePrices.Count -le $maP) { continue }
        $sma = Calculate-SMA -prices $closePrices -period $maP
        $lastSma = $sma[-1]
        if ($lastClose -gt $lastSma) { $pos = "ABOVE" } else { $pos = "BELOW" }
        Write-Host "  MA($maP): $([Math]::Round($lastSma,2)) | Price is $pos MA($maP)"
    }
    
    # Support & Resistance levels
    Write-Host "`n--- Key Levels Support/Resistance ---" -ForegroundColor Yellow
    $sortedPrices = $closePrices | Sort-Object -Unique
    $recentPrices = $closePrices[-30..-1]
    $sortedRecent = $recentPrices | Sort-Object
    $s1 = $sortedRecent[ [Math]::Floor($sortedRecent.Count*0.25) ]
    $s2 = $sortedRecent[ [Math]::Floor($sortedRecent.Count*0.10) ]
    $r1 = $sortedRecent[ [Math]::Ceiling($sortedRecent.Count*0.75) ]
    $r2 = $sortedRecent[ [Math]::Ceiling($sortedRecent.Count*0.90) ]
    Write-Host "  S2: $([Math]::Round($s2,2)) | S1: $([Math]::Round($s1,2)) | R1: $([Math]::Round($r1,2)) | R2: $([Math]::Round($r2,2))"
}

Write-Host "`n`n====================================" -ForegroundColor Magenta
Write-Host "  SOL CHARACTER PROFILE SUMMARY" -ForegroundColor Magenta
Write-Host "====================================" -ForegroundColor Magenta

# Fetch daily data for final summary
$dailyKlines = Get-Klines -category "spot" -symbol "SOLUSDT" -interval "D" -limit 365
if ($dailyKlines) {
    $dailyClose = $dailyKlines | ForEach-Object { [double]$_[4] }
    $dailyVol = $dailyKlines | ForEach-Object { [double]$_[5] }
    $avgVol = ($dailyVol | Measure-Object -Average).Average
    $lastVol = $dailyVol[-1]
    
    # Volatility
    $returns = [double[]]::new($dailyClose.Count)
    for ($i = 1; $i -lt $dailyClose.Count; $i++) { $returns[$i] = ($dailyClose[$i] - $dailyClose[$i-1]) / $dailyClose[$i-1] * 100 }
    $avgReturn = ($returns | Where-Object { $_ -ne 0 } | Measure-Object -Average).Average
    $absReturns = $returns | Where-Object { $_ -ne 0 } | ForEach-Object { [Math]::Abs($_) }
    $avgAbsMove = ($absReturns | Measure-Object -Average).Average
    $maxUp = ($returns | Measure-Object -Maximum).Maximum
    $maxDown = ($returns | Measure-Object -Minimum).Minimum
    
    Write-Host "SOL Volatility Profile (Daily):"
    Write-Host "  Avg daily move: $([Math]::Round($avgAbsMove,2))%"
    Write-Host "  Max up day: $([Math]::Round($maxUp,2))%"
    Write-Host "  Max down day: $([Math]::Round($maxDown,2))%"
    
    # Win rate by day of week
    Write-Host "`nDay-of-week performance:"
    for ($d = 0; $d -le 6; $d++) {
        $dayReturns = @()
        for ($i = 1; $i -lt $dailyClose.Count; $i++) {
            $dt = [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$dailyKlines[$i][0]).DateTime
            if ([int]$dt.DayOfWeek -eq $d) { $dayReturns += $returns[$i] }
        }
        if ($dayReturns.Count -gt 0) {
            $winRate = (($dayReturns | Where-Object { $_ -gt 0 }).Count / $dayReturns.Count * 100)
            $avgDayRet = ($dayReturns | Measure-Object -Average).Average
            $dayName = [System.DayOfWeek]$d
            Write-Host "  $($dayName): win $([Math]::Round($winRate,1))% | avg $([Math]::Round($avgDayRet,2))% ($($dayReturns.Count) samples)"
        }
    }
}
