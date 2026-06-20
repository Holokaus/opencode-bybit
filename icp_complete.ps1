function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) {
        $len = $data[$offset.Value]; $offset.Value++; return $len
    }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0
    for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }
    return $len
}
function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw }
    $offset.Value++
    $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len)
    [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start)
    [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len
    return $trimmed
}
$pem = [System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH)
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0
if ($der[$off] -ne 0x30) { throw }
$off++
Read-DerLength -data $der -offset ([ref]$off) | Out-Null
$p = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger -data $der -offset ([ref]$off) | Out-Null
$p.Modulus = Read-DerInteger -data $der -offset ([ref]$off)
$p.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
$p.D = Read-DerInteger -data $der -offset ([ref]$off)
$p.P = Read-DerInteger -data $der -offset ([ref]$off)
$p.Q = Read-DerInteger -data $der -offset ([ref]$off)
$p.DP = Read-DerInteger -data $der -offset ([ref]$off)
$p.DQ = Read-DerInteger -data $der -offset ([ref]$off)
$p.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($p)

$apiKey = $env:BYBIT_API_KEY
$recvWindow = "5000"

function Call-API {
    param($ep, $q)
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $body = [Text.Encoding]::UTF8.GetBytes("$ts$apiKey$recvWindow$q")
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $sig = [Convert]::ToBase64String($rsa.SignData($body, $sha256))
    $headers = @{
        "X-BAPI-API-KEY" = $apiKey
        "X-BAPI-TIMESTAMP" = "$ts"
        "X-BAPI-SIGN" = $sig
        "X-BAPI-RECV-WINDOW" = $recvWindow
        "X-BAPI-SIGN-TYPE" = "2"
        "User-Agent" = "bybit-skill/1.4.2"
    }
    try {
        $resp = Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $headers -UseBasicParsing -TimeoutSec 60
        return ($resp.Content | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-K {
    param($interval, $limit)
    $r = Call-API -ep "/v5/market/kline" -q "category=spot&symbol=ICPUSDT&interval=$interval&limit=$limit"
    if ($r -and $r.result -and $r.result.list) {
        $k = $r.result.list
        [Array]::Reverse($k)
        return $k
    }
    return $null
}

function Calc-RSI {
    param($prices, $period)
    $gains = [double[]]::new($prices.Count)
    $losses = [double[]]::new($prices.Count)
    for ($i = 1; $i -lt $prices.Count; $i++) {
        $diff = $prices[$i] - $prices[$i - 1]
        if ($diff -ge 0) { $gains[$i] = $diff } else { $losses[$i] = -$diff }
    }
    $avgGain = ($gains[1..$period] | Measure-Object -Sum).Sum / $period
    $avgLoss = ($losses[1..$period] | Measure-Object -Sum).Sum / $period
    $rsi = [double[]]::new($prices.Count)
    for ($i = $period; $i -lt $prices.Count; $i++) {
        if ($i -gt $period) {
            $avgGain = (($avgGain * ($period - 1)) + $gains[$i]) / $period
            $avgLoss = (($avgLoss * ($period - 1)) + $losses[$i]) / $period
        }
        if ($avgLoss -eq 0) { $rsi[$i] = 100 } else { $rsi[$i] = 100 - (100 / (1 + ($avgGain / $avgLoss))) }
    }
    return $rsi
}

function Calc-EMA {
    param($prices, $period)
    $ema = [double[]]::new($prices.Count)
    $ema[0] = $prices[0]
    $m = 2 / ($period + 1)
    for ($i = 1; $i -lt $prices.Count; $i++) {
        $ema[$i] = $prices[$i] * $m + $ema[$i - 1] * (1 - $m)
    }
    return $ema
}

function Calc-SMA {
    param($prices, $period)
    $sma = [double[]]::new($prices.Count)
    for ($i = 0; $i -lt $prices.Count; $i++) {
        if ($i -ge $period - 1) {
            $sma[$i] = ($prices[($i - $period + 1)..$i] | Measure-Object -Average).Average
        }
    }
    return $sma
}

function Calc-ATR {
    param($high, $low, $close, $period)
    $tr = [double[]]::new($close.Count)
    for ($i = 1; $i -lt $close.Count; $i++) {
        $hl = $high[$i] - $low[$i]
        $hc = [Math]::Abs($high[$i] - $close[$i - 1])
        $lc = [Math]::Abs($low[$i] - $close[$i - 1])
        $tr[$i] = [Math]::Max($hl, [Math]::Max($hc, $lc))
    }
    $atr = [double[]]::new($close.Count)
    if ($close.Count -gt $period) {
        $atr[$period] = ($tr[1..$period] | Measure-Object -Average).Average
        for ($i = $period + 1; $i -lt $close.Count; $i++) {
            $atr[$i] = ($atr[$i - 1] * ($period - 1) + $tr[$i]) / $period
        }
    }
    return $atr
}

function Calc-ADX {
    param($high, $low, $close, $period)
    $tr = [double[]]::new($close.Count)
    $up = [double[]]::new($close.Count)
    $dn = [double[]]::new($close.Count)
    for ($i = 1; $i -lt $close.Count; $i++) {
        $tr[$i] = [Math]::Max($high[$i] - $low[$i], [Math]::Max([Math]::Abs($high[$i] - $close[$i - 1]), [Math]::Abs($low[$i] - $close[$i - 1])))
        $u = $high[$i] - $high[$i - 1]
        $d = $low[$i - 1] - $low[$i]
        $up[$i] = if ($u -gt $d -and $u -gt 0) { $u } else { 0 }
        $dn[$i] = if ($d -gt $u -and $d -gt 0) { $d } else { 0 }
    }
    $atr = Calc-EMA -prices $tr -period $period
    $du = Calc-EMA -prices $up -period $period
    $dd = Calc-EMA -prices $dn -period $period
    $dx = [double[]]::new($close.Count)
    for ($i = $period; $i -lt $close.Count; $i++) {
        $pdi = $du[$i] / $atr[$i] * 100
        $ndi = $dd[$i] / $atr[$i] * 100
        $dx[$i] = if (($pdi + $ndi) -eq 0) { 0 } else { [Math]::Abs($pdi - $ndi) / ($pdi + $ndi) * 100 }
    }
    return (Calc-EMA -prices $dx -period $period)
}

function Calc-StochRSI {
    param($prices, $period)
    $rsi = Calc-RSI -prices $prices -period $period
    $k = [double[]]::new($prices.Count)
    for ($i = $period; $i -lt $prices.Count; $i++) {
        $min = ($rsi[($i - $period + 1)..$i] | Measure-Object -Minimum).Minimum
        $max = ($rsi[($i - $period + 1)..$i] | Measure-Object -Maximum).Maximum
        $k[$i] = if ($max - $min -eq 0) { 50 } else { ($rsi[$i] - $min) / ($max - $min) * 100 }
    }
    return $k
}

function Show-Combo {
    param($name, $lw, $ll, $sw, $sl)
    $total = $lw + $ll + $sw + $sl
    $wr = if ($total) { [Math]::Round(($lw + $sw) / $total * 100, 1) } else { 0 }
    Write-Output ("  {0,-28} WR={1,-5}% | {2} sigs (L:{3}/{4} S:{5}/{6})" -f $name, $wr, $total, $lw, ($lw + $ll), $sw, ($sw + $sl))
}

Write-Output "========================================================"
Write-Output "  ICP COMPLETE ANALYSIS"
Write-Output "========================================================"

# PHASE 1: RSI bruteforce
Write-Output "`n--- PHASE 1: RSI Bruteforce ---"
$timeframes = @(
    @{n = "15m"; i = "15" },
    @{n = "30m"; i = "30" },
    @{n = "1h";  i = "60" },
    @{n = "2h";  i = "120" },
    @{n = "4h";  i = "240" },
    @{n = "6h";  i = "360" },
    @{n = "12h"; i = "720" }
)
$obs = @(60, 64, 68, 72, 76, 80, 84)
$oss = @(20, 24, 28, 32, 36, 40, 44)
$allTf = @()
$tfCount = 0

foreach ($tf in $timeframes) {
    $tfCount++
    Write-Output "  [$tfCount/$($timeframes.Count)] $($tf.n)..."
    $k = Get-K -interval $tf.i -limit 800
    if (-not $k -or $k.Count -lt 100) { Write-Output "    No data"; continue }
    $closes = $k | ForEach-Object { [double]$_[4] }
    $highs  = $k | ForEach-Object { [double]$_[2] }
    $lows   = $k | ForEach-Object { [double]$_[3] }

    $bestPer = $null; $bestOb = $null; $bestOs = $null; $bestWr = 0
    $bestLw = 0; $bestLl = 0; $bestSw = 0; $bestSl = 0; $bestTt = 0

    foreach ($per in (5..50 | Where-Object { $_ % 3 -eq 2 -or $_ -eq 5 })) {
        $r = Calc-RSI -prices $closes -period $per
        $perBestScore = 0; $perBest = $null
        foreach ($ob in $obs) {
            foreach ($os in $oss) {
                if ($os -ge ($ob - 15)) { continue }
                $lw = 0; $ll = 0; $sw = 0; $sl = 0
                for ($i = $per; $i -lt $closes.Count - 3; $i++) {
                    if ($r[$i - 1] -gt $os -and $r[$i] -le $os -and $r[$i] -ne 0) {
                        $fL = ($closes[($i + 1)..($i + 3)] | Measure-Object -Minimum).Minimum
                        if (($closes[$i] - $fL) / $closes[$i] * 100 -gt 1.0) { $lw++ } else { $ll++ }
                    }
                    if ($r[$i - 1] -lt $ob -and $r[$i] -ge $ob -and $r[$i] -ne 100) {
                        $fH = ($closes[($i + 1)..($i + 3)] | Measure-Object -Maximum).Maximum
                        if (($fH - $closes[$i]) / $closes[$i] * 100 -gt 1.0) { $sw++ } else { $sl++ }
                    }
                }
                $total = $lw + $ll + $sw + $sl
                if ($total -ge 3) {
                    $wr = [Math]::Round(($lw + $sw) / $total * 100, 1)
                    $score = $wr * $total
                    if ($score -gt $perBestScore) {
                        $perBestScore = $score; $perBest = @{ per = $per; ob = $ob; os = $os; wr = $wr; lw = $lw; ll = $ll; sw = $sw; sl = $sl; total = $total }
                    }
                }
            }
        }
        if ($perBest -and $perBest.wr -gt $bestWr) {
            $bestWr = $perBest.wr; $bestPer = $perBest.per; $bestOb = $perBest.ob; $bestOs = $perBest.os
            $bestLw = $perBest.lw; $bestLl = $perBest.ll; $bestSw = $perBest.sw; $bestSl = $perBest.sl; $bestTt = $perBest.total
        }
    }
    if ($bestPer) {
        $allTf += @{
            tf = $tf.n; per = $bestPer; ob = $bestOb; os = $bestOs; wr = $bestWr
            total = $bestTt; lw = $bestLw; ll = $bestLl; sw = $bestSw; sl = $bestSl
        }
        Write-Output "    RSI($bestPer) OB=$bestOb OS=$bestOs WR=$bestWr% ($bestTt sigs)"
    }
}

$sorted = $allTf | Sort-Object wr -Descending
Write-Output "`nRankings:"
$sorted | ForEach-Object { Write-Output ("  {0,-4} RSI({1,-2}) OB={2,-2} OS={3,-2} WR={4,-4}% {5,2}sigs" -f $_.tf, $_.per, $_.ob, $_.os, $_.wr, $_.total) }
$win = $sorted[0]
Write-Output "`n=== WINNER: $($win.tf) RSI($($win.per)) OB=$($win.ob) OS=$($win.os) WR=$($win.wr)% ==="

# PHASE 2: Expanded indicator combos
Write-Output "`n--- PHASE 2: Expanded Indicator Combos ---"
$tfSel = $timeframes | Where-Object { $_.n -eq $win.tf } | Select-Object -First 1
$k = Get-K -interval $tfSel.i -limit 800
if (-not $k) { exit 1 }
$closes = $k | ForEach-Object { [double]$_[4] }
$highs  = $k | ForEach-Object { [double]$_[2] }
$lows   = $k | ForEach-Object { [double]$_[3] }
$vols   = $k | ForEach-Object { [double]$_[5] }
$times  = $k | ForEach-Object { [long]$_[0] }

$rsi = Calc-RSI -prices $closes -period $win.per
$atr = Calc-ATR -high $highs -low $lows -close $closes -period 14
$vma = Calc-EMA -prices $vols -period 20
$ma20  = Calc-EMA -prices $closes -period 20
$ma50  = Calc-EMA -prices $closes -period 50
$ma100 = Calc-EMA -prices $closes -period 100
$ma200 = Calc-EMA -prices $closes -period 200
$adx   = Calc-ADX -high $highs -low $lows -close $closes -period 14
$stoch = Calc-StochRSI -prices $closes -period 14

$atrAvg = ($atr[50..($atr.Count - 1)] | Measure-Object -Average).Average

function Test-Cfg {
    param($name, $useVol, $volThr, $useMA, $maArr, $useADX, $adxThr, $useStoch, $stThr, $useATRreg)
    $lw = 0; $ll = 0; $sw = 0; $sl = 0
    $startI = [Math]::Max(70, $script:win.per + 30)
    for ($i = $startI; $i -lt $script:closes.Count - 5; $i++) {
        $vOk = if ($useVol) { $script:vols[$i] -gt $script:vma[$i] * $volThr } else { $true }
        $maOkL = if ($useMA -and $maArr) { $script:closes[$i] -gt $maArr[$i] } else { $true }
        $maOkS = if ($useMA -and $maArr) { $script:closes[$i] -lt $maArr[$i] } else { $true }
        $adxOk = if ($useADX) { $script:adx[$i] -gt $adxThr } else { $true }
        $stOkL = if ($useStoch) { $script:stoch[$i] -lt $stThr } else { $true }
        $stOkS = if ($useStoch) { $script:stoch[$i] -gt (100 - $stThr) } else { $true }
        $atrOkL = if ($useATRreg) { $script:atr[$i] -gt $script:atrAvg } else { $true }
        if ($script:rsi[$i - 1] -gt $script:win.os -and $script:rsi[$i] -le $script:win.os -and $script:rsi[$i] -ne 0 -and $vOk -and $maOkL -and $adxOk -and $stOkL -and $atrOkL) {
            $fL = ($script:closes[($i + 1)..($i + 3)] | Measure-Object -Minimum).Minimum
            if (($script:closes[$i] - $fL) / $script:closes[$i] * 100 -gt 1.0) { $lw++ } else { $ll++ }
        }
        if ($script:rsi[$i - 1] -lt $script:win.ob -and $script:rsi[$i] -ge $script:win.ob -and $script:rsi[$i] -ne 100 -and $vOk -and $maOkS -and $adxOk -and $stOkS -and $atrOkL) {
            $fH = ($script:closes[($i + 1)..($i + 3)] | Measure-Object -Maximum).Maximum
            if (($fH - $script:closes[$i]) / $script:closes[$i] * 100 -gt 1.0) { $sw++ } else { $sl++ }
        }
    }
    Show-Combo -name $name -lw $lw -ll $ll -sw $sw -sl $sl
}

Test-Cfg -name "RSI alone" -useVol $false -useMA $false -useADX $false -useStoch $false -useATRreg $false
Test-Cfg -name "RSI+Vol(thr=0.7)" -useVol $true -volThr 0.7
Test-Cfg -name "RSI+Vol(thr=0.8)" -useVol $true -volThr 0.8
Test-Cfg -name "RSI+Vol(thr=0.9)" -useVol $true -volThr 0.9
Test-Cfg -name "RSI+Vol(thr=1.0)" -useVol $true -volThr 1.0
Test-Cfg -name "RSI+Vol(thr=1.2)" -useVol $true -volThr 1.2
Test-Cfg -name "RSI+Vol+MA20" -useVol $true -volThr 0.8 -useMA $true -maArr $ma20
Test-Cfg -name "RSI+Vol+MA50" -useVol $true -volThr 0.8 -useMA $true -maArr $ma50
Test-Cfg -name "RSI+Vol+MA100" -useVol $true -volThr 0.8 -useMA $true -maArr $ma100
Test-Cfg -name "RSI+Vol+MA200" -useVol $true -volThr 0.8 -useMA $true -maArr $ma200
Test-Cfg -name "RSI+Vol+ADX(20)" -useVol $true -volThr 0.8 -useADX $true -adxThr 20
Test-Cfg -name "RSI+Vol+ADX(25)" -useVol $true -volThr 0.8 -useADX $true -adxThr 25
Test-Cfg -name "RSI+Vol+ADX(30)" -useVol $true -volThr 0.8 -useADX $true -adxThr 30
Test-Cfg -name "RSI+Vol+Stoch(20)" -useVol $true -volThr 0.8 -useStoch $true -stThr 20
Test-Cfg -name "RSI+Vol+Stoch(30)" -useVol $true -volThr 0.8 -useStoch $true -stThr 30
Test-Cfg -name "RSI+Vol+Stoch(40)" -useVol $true -volThr 0.8 -useStoch $true -stThr 40
Test-Cfg -name "RSI+Vol+ATRreg" -useVol $true -volThr 0.8 -useATRreg $true
Test-Cfg -name "RSI+Vol+MA50+ATR" -useVol $true -volThr 0.8 -useMA $true -maArr $ma50 -useATRreg $true
Test-Cfg -name "RSI+Vol+MA50+ADX+Stoch" -useVol $true -volThr 0.8 -useMA $true -maArr $ma50 -useADX $true -adxThr 25 -useStoch $true -stThr 30

# PHASE 3: TP/SL bruteforce
Write-Output "`n--- PHASE 3: TP/SL Bruteforce (with volume filter) ---"
$tps = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0)
$sls = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0)
$longEntries = @(); $shortEntries = @()

for ($i = $win.per + 20; $i -lt $closes.Count - 5; $i++) {
    if ($rsi[$i - 1] -gt $win.os -and $rsi[$i] -le $win.os -and $rsi[$i] -ne 0 -and $vols[$i] -gt $vma[$i] * 0.8) {
        $longEntries += @{ idx = $i; price = $closes[$i] }
    }
    if ($rsi[$i - 1] -lt $win.ob -and $rsi[$i] -ge $win.ob -and $rsi[$i] -ne 100 -and $vols[$i] -gt $vma[$i] * 0.8) {
        $shortEntries += @{ idx = $i; price = $closes[$i] }
    }
}
Write-Output "  $($longEntries.Count) long, $($shortEntries.Count) short entries"

$tpResults = @()
foreach ($tp in $tps) {
    foreach ($sl in $sls) {
        $tw = 0; $tl = 0; $totalPnl = 0; $totalTrades = 0
        foreach ($e in $longEntries) {
            $tpP = $e.price * (1 + $tp / 100)
            $slP = $e.price * (1 - $sl / 100)
            $hit = $null
            for ($j = $e.idx + 1; $j -lt [Math]::Min($e.idx + 48, $closes.Count); $j++) {
                if ($highs[$j] -ge $tpP) { $hit = "TP"; break }
                if ($lows[$j] -le $slP)  { $hit = "SL"; break }
            }
            if ($hit -eq "TP") { $tw++; $totalPnl += $tp }
            elseif ($hit -eq "SL") { $tl++; $totalPnl -= $sl }
            $totalTrades++
        }
        foreach ($e in $shortEntries) {
            $tpP = $e.price * (1 - $tp / 100)
            $slP = $e.price * (1 + $sl / 100)
            $hit = $null
            for ($j = $e.idx + 1; $j -lt [Math]::Min($e.idx + 48, $closes.Count); $j++) {
                if ($lows[$j] -le $tpP) { $hit = "TP"; break }
                if ($highs[$j] -ge $slP) { $hit = "SL"; break }
            }
            if ($hit -eq "TP") { $tw++; $totalPnl += $tp }
            elseif ($hit -eq "SL") { $tl++; $totalPnl -= $sl }
            $totalTrades++
        }
        if ($totalTrades -ge 3) {
            $wr = [Math]::Round($tw / $totalTrades * 100, 1)
            $score = $wr * $totalTrades / 100
            $tpResults += [PSCustomObject]@{
                TP = $tp; SL = $sl; WR = $wr; Trades = $totalTrades
                PnL = [Math]::Round($totalPnl, 2); Score = [Math]::Round($score, 1)
            }
        }
    }
}

Write-Output "  By Score:"
$tpResults | Sort-Object Score -Descending | Select-Object -First 3 |
    ForEach-Object { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades)t | PnL=$($_.PnL)%" }
Write-Output "  By WR (min 5 trades):"
$tpResults | Where-Object { $_.Trades -ge 5 } | Sort-Object WR -Descending | Select-Object -First 3 |
    ForEach-Object { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades)t" }
$bestRR = $tpResults | Where-Object { $_.Trades -ge 5 -and $_.TP -ge $_.SL } | Sort-Object Score -Descending | Select-Object -First 1
if ($bestRR) {
    Write-Output "  Best R:R: TP=$($bestRR.TP)% SL=$($bestRR.SL)% | WR=$($bestRR.WR)% | $($bestRR.Trades)t | PnL=$($bestRR.PnL)%"
}

# PHASE 4: Time cycles (day-of-week)
Write-Output "`n--- PHASE 4: Time Cycles (Day of Week) ---"
$dow = @{}
for ($i = $win.per + 20; $i -lt $closes.Count - 3; $i++) {
    $isLong = $rsi[$i - 1] -gt $win.os -and $rsi[$i] -le $win.os -and $rsi[$i] -ne 0
    $isShort = $rsi[$i - 1] -lt $win.ob -and $rsi[$i] -ge $win.ob -and $rsi[$i] -ne 100
    if (-not ($isLong -or $isShort)) { continue }
    $day = [DateTimeOffset]::FromUnixTimeMilliseconds($times[$i]).DayOfWeek.value__
    if (-not $dow.ContainsKey($day)) { $dow[$day] = @{ wins = 0; total = 0 } }
    if ($isLong) {
        $fL = ($closes[($i + 1)..($i + 3)] | Measure-Object -Minimum).Minimum
        $won = ($closes[$i] - $fL) / $closes[$i] * 100 -gt 1.0
    } else {
        $fH = ($closes[($i + 1)..($i + 3)] | Measure-Object -Maximum).Maximum
        $won = ($fH - $closes[$i]) / $closes[$i] * 100 -gt 1.0
    }
    $dow[$day].total++; if ($won) { $dow[$day].wins++ }
}
$dayNames = @("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")
0..6 | ForEach-Object {
    if ($dow.ContainsKey($_)) {
        $d = $dow[$_]
        $wr = if ($d.total) { [Math]::Round($d.wins / $d.total * 100, 1) } else { 0 }
        Write-Output "  $($dayNames[$_]): WR $wr% ($($d.total) sigs)"
    }
}

# PHASE 5: 3-month simulation (LONG only, TP=0.5% SL=0.5%)
Write-Output "`n--- PHASE 5: 3-Month Simulation (LONG only) ---"
$startDt = [DateTimeOffset]::new(2026, 3, 12, 0, 0, 0, [TimeSpan]::Zero)
$startMs = $startDt.ToUnixTimeMilliseconds()
$startIdx = 0
for ($i = 0; $i -lt $times.Count; $i++) {
    if ($times[$i] -ge $startMs) { $startIdx = $i; break }
}
$capital = 100.0; $wins = 0; $losses = 0; $totalTrades = 0; $tradeLog = @()

for ($i = [Math]::Max($startIdx, $win.per + 20); $i -lt $closes.Count - 5; $i++) {
    if (-not ($rsi[$i - 1] -gt $win.os -and $rsi[$i] -le $win.os -and $rsi[$i] -ne 0 -and $vols[$i] -gt $vma[$i] * 0.8)) { continue }
    $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($times[$i])

    $entry = $closes[$i]
    $tpPrice = $entry * 1.005
    $slPrice = $entry * 0.995
    $hit = $null
    for ($j = $i + 1; $j -lt [Math]::Min($i + 48, $closes.Count); $j++) {
        if ($highs[$j] -ge $tpPrice) { $hit = "TP"; break }
        if ($lows[$j] -le $slPrice)  { $hit = "SL"; break }
    }
    $pnl = 0
    if ($hit -eq "TP") {
        $pnl = ($entry * 0.5 / 100) - ($entry * 0.1 / 100)
        $wins++
    } else {
        $pnl = -($entry * 0.5 / 100) - ($entry * 0.1 / 100)
        $losses++
    }
    $totalTrades++; $capital += $pnl
    $tradeLog += [PSCustomObject]@{
        Date = $dt.ToString('MM-dd')
        Price = [Math]::Round($entry, 4)
        Result = if ($hit -eq "TP") { "TP" } else { "SL" }
        PnL = [Math]::Round($pnl, 4)
        Capital = [Math]::Round($capital, 2)
    }
}
$wr3 = if ($totalTrades) { [Math]::Round($wins / $totalTrades * 100, 1) } else { 0 }
Write-Output "  Trades: $totalTrades ($wins W / $losses L) | WR: $wr3%"
Write-Output "  Start: 100 | Final: $([Math]::Round($capital, 2)) | Return: $([Math]::Round(($capital - 100) / 100 * 100, 2))%"
$tradeLog | Format-Table -AutoSize

# PHASE 6: Live signal
Write-Output "--- PHASE 6: Live Signal ---"
$lastRsi = $rsi[-1]; $prevRsi = $rsi[-2]; $lastPrice = $closes[-1]; $lastDt = [DateTimeOffset]::FromUnixTimeMilliseconds($times[-1])
Write-Output "  $($win.tf) @ $($lastDt.ToString('MM-dd HH:mm')) UTC"
Write-Output "  Price: $([Math]::Round($lastPrice, 4)) | RSI($($win.per)): $([Math]::Round($lastRsi, 1)) (prev $([Math]::Round($prevRsi, 1)))"
Write-Output "  OB=$($win.ob) OS=$($win.os) | Vol vs MA20: $([Math]::Round($vols[-1] / $vma[-1] * 100, 0))%"
if ($prevRsi -gt $win.os -and $lastRsi -le $win.os -and $lastRsi -ne 0 -and $vols[-1] -gt $vma[-1] * 0.8) {
    Write-Output "  >>> LONG SIGNAL <<<"
} elseif ($prevRsi -lt $win.ob -and $lastRsi -ge $win.ob -and $lastRsi -ne 100 -and $vols[-1] -gt $vma[-1] * 0.8) {
    Write-Output "  >>> SHORT SIGNAL <<<"
} else {
    Write-Output "  No signal (RSI=$([Math]::Round($lastRsi, 1)) between $($win.os)-$($win.ob))"
}
Write-Output "`n=== ICP COMPLETE ==="
