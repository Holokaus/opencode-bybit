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

Write-Output "=== CONTINUING: 6h, 12h, 1d, 2d ==="
$tfs = @(@{n="6h"; i="360"}, @{n="12h"; i="720"}, @{n="1d"; i="D"}, @{n="2d"; i="2"})
foreach ($tf in $tfs) {
    Write-Output "`nScanning $($tf.n)..."
    $klines = Get-Klines -int $tf.i -lim 300
    if (-not $klines -or $klines.Count -lt 50) { Write-Output "  No data"; continue }
    $close = $klines | ForEach-Object { [double]$_[4] }
    $best = $null; $bestScore = 0
    foreach ($per in (2..50)) {
        $rsi = Calculate-RSI -prices $close -period $per
        if ($rsi.Count -eq 0) { continue }
        $valid = $rsi | Where-Object { $_ -ne $null }
        $min = ($valid | Measure-Object -Minimum).Minimum
        $max = ($valid | Measure-Object -Maximum).Maximum
        $avg = ($valid | Measure-Object -Average).Average
        $std = [Math]::Sqrt(($valid | ForEach-Object { ($_ - $avg)*($_ - $avg) } | Measure-Object -Sum).Sum / ($valid.Count-1))
        $ob = [Math]::Round($avg + 1.2*$std, 0)
        $os = [Math]::Round($avg - 1.2*$std, 0)
        if ($ob -gt 100) { $ob = 85 }; if ($os -lt 0) { $os = 15 }
        $obHits = ($valid | Where-Object { $_ -ge $ob }).Count
        $osHits = ($valid | Where-Object { $_ -le $os }).Count
        $totalSigHits = $obHits + $osHits
        if ($totalSigHits -ge 5) { 
            $score = $totalSigHits  # More signals = more data = more reliable
            if ($score -gt $bestScore) {
                $bestScore = $score; $best = @{period=$per; ob=$ob; os=$os; obHits=$obHits; osHits=$osHits; total=$totalSigHits; lastRsi=[Math]::Round($rsi[-1],1); avg=[Math]::Round($avg,1)}
            }
        }
    }
    if ($best) { Write-Output "  RSI($($best.period)) OB=$($best.ob) OS=$($best.os) | last RSI=$($best.lastRsi) | avg=$($best.avg) | $($best.total) signal zones | OB hits=$($best.obHits) OS hits=$($best.osHits)" }
}
