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
$o = 0; if ($der[$o] -ne 0x30) { throw "bad" }; $o++; Read-DerLength $der ([ref]$o) | Out-Null
$rsaP = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger $der ([ref]$o) | Out-Null
$rsaP.Modulus = Read-DerInteger $der ([ref]$o); $rsaP.Exponent = Read-DerInteger $der ([ref]$o)
$rsaP.D = Read-DerInteger $der ([ref]$o); $rsaP.P = Read-DerInteger $der ([ref]$o)
$rsaP.Q = Read-DerInteger $der ([ref]$o); $rsaP.DP = Read-DerInteger $der ([ref]$o)
$rsaP.DQ = Read-DerInteger $der ([ref]$o); $rsaP.InverseQ = Read-DerInteger $der ([ref]$o)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($rsaP)
$apiKey = $env:BYBIT_API_KEY; $recvWindow = "5000"

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

function Test-RSI-Signals($prices, $rsiVals, $period) {
    $best = $null; $bestWR = 0
    foreach ($obTest in @(60,62,64,66,68,70,72,74,76,78,80,82,84)) {
        foreach ($osTest in @(16,18,20,22,24,26,28,30,32,34,36,38,40,42,44)) {
            if ($osTest -ge ($obTest-15)) { continue }
            $obWins = 0; $obTotal = 0; $osWins = 0; $osTotal = 0
            for ($i = $period; $i -lt $rsiVals.Count - 3; $i++) {
                if ($rsiVals[$i] -ge $obTest -and $rsiVals[$i-1] -lt $obTest) {
                    $obTotal++
                    $futureLow = ($prices[($i+1)..[Math]::Min($i+3,$prices.Count-1)] | Measure-Object -Minimum).Minimum
                    if (($prices[$i] - $futureLow) / $prices[$i] * 100 -gt 1.0) { $obWins++ }
                }
                if ($rsiVals[$i] -le $osTest -and $rsiVals[$i-1] -gt $osTest) {
                    $osTotal++
                    $futureHigh = ($prices[($i+1)..[Math]::Min($i+3,$prices.Count-1)] | Measure-Object -Maximum).Maximum
                    if (($futureHigh - $prices[$i]) / $prices[$i] * 100 -gt 1.0) { $osWins++ }
                }
            }
            $total = $obTotal + $osTotal
            if ($total -ge 5) {
                $wr = [Math]::Round(($obWins+$osWins)/$total*100,1)
                if ($wr -gt $bestWR) {
                    $bestWR = $wr; $best = @{ob=$obTest; os=$osTest; wr=$wr; obW=$obWins; obT=$obTotal; osW=$osWins; osT=$osTotal; total=$total}
                }
            }
        }
    }
    return $best
}

Write-Output "=== SIGNAL QUALITY TEST: 6h, 12h, 1d ==="
$tfs = @(@{n="6h"; i="360"}, @{n="12h"; i="720"}, @{n="1d"; i="D"})
foreach ($tf in $tfs) {
    Write-Output "`n$($tf.n) - fetching data..."
    $klines = Get-Klines -int $tf.i -lim 350
    if (-not $klines -or $klines.Count -lt 50) { Write-Output "  No data"; continue }
    $close = $klines | ForEach-Object { [double]$_[4] }
    $bestPerTF = $null; $bestScore = 0
    foreach ($per in (3..50)) {
        $rsi = Calculate-RSI -prices $close -period $per
        $result = Test-RSI-Signals -prices $close -rsiVals $rsi -period $per
        if ($result -and $result.wr -gt $bestScore) {
            $bestScore = $result.wr; $bestPerTF = @{period=$per; ob=$result.ob; os=$result.os; wr=$result.wr; obW=$result.obW; obT=$result.obT; osW=$result.osW; osT=$result.osT; total=$result.total}
        }
    }
    if ($bestPerTF) {
        Write-Output "  RSI($($bestPerTF.period)) OB=$($bestPerTF.ob) OS=$($bestPerTF.os)"
        Write-Output "  Combined WR: $($bestPerTF.wr)% | Total signals: $($bestPerTF.total)"
        Write-Output "  OB: $($bestPerTF.obW)/$($bestPerTF.obT) wins | OS: $($bestPerTF.osW)/$($bestPerTF.osT) wins"
    }
}
