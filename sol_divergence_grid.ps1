function Read-DerLength { param([byte[]]$d, [ref]$o)
    if ($d[$o.Value] -lt 0x80) { $l = $d[$o.Value]; $o.Value++; return $l }
    $n = $d[$o.Value] -band 0x7F; $o.Value++
    $len = 0; for ($i = 0; $i -lt $n; $i++) { $len = ($len -shl 8) -bor $d[$o.Value]; $o.Value++ }
    return $len
}
function Read-DerInteger { param([byte[]]$d, [ref]$o)
    if ($d[$o.Value] -ne 0x02) { throw "bad" }; $o.Value++
    $l = Read-DerLength $d $o
    $v = [byte[]]::new($l); [Array]::Copy($d, $o.Value, $v, 0, $l)
    $s = if ($v.Length -gt 1 -and $v[0] -eq 0) { 1 } else { 0 }
    $t = [byte[]]::new($v.Length - $s); [Array]::Copy($v, $s, $t, 0, $t.Length)
    $o.Value += $l; return $t
}
$pem = [System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH)
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64); $off = 0
if ($der[$off] -ne 0x30) { throw "Not SEQUENCE" }; $off++
Read-DerLength $der ([ref]$off) | Out-Null
$params = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger $der ([ref]$off) | Out-Null; $params.Modulus = Read-DerInteger $der ([ref]$off)
$params.Exponent = Read-DerInteger $der ([ref]$off); $params.D = Read-DerInteger $der ([ref]$off)
$params.P = Read-DerInteger $der ([ref]$off); $params.Q = Read-DerInteger $der ([ref]$off)
$params.DP = Read-DerInteger $der ([ref]$off); $params.DQ = Read-DerInteger $der ([ref]$off)
$params.InverseQ = Read-DerInteger $der ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $rsa.ImportParameters($params)
$apiKey = $env:BYBIT_API_KEY; $recvWindow = "5000"
function Call-API { param($endpoint, $query)
    $ts = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $paramStr = "${ts}${apiKey}${recvWindow}${query}"
    $b = [System.Text.Encoding]::UTF8.GetBytes($paramStr)
    $h = [System.Security.Cryptography.SHA256]::Create()
    $sigBytes = $rsa.SignData($b, $h); $sig = [System.Convert]::ToBase64String($sigBytes)
    $headers = @{ "X-BAPI-API-KEY" = $apiKey; "X-BAPI-TIMESTAMP" = "$ts"; "X-BAPI-SIGN" = $sig; "X-BAPI-RECV-WINDOW" = $recvWindow; "X-BAPI-SIGN-TYPE" = "2"; "User-Agent" = "bybit-skill/1.4.2" }
    try { $resp = Invoke-WebRequest -Uri "https://api.bybit.com$endpoint`?$query" -Headers $headers -UseBasicParsing -TimeoutSec 30; return ($resp.Content | ConvertFrom-Json).result } catch { return $null }
}
function Get-K { param($int, $lim)
    $r = Call-API -endpoint "/v5/market/kline" -query "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if ($r -and $r.list) { $k = $r.list; [Array]::Reverse($k); return $k } else { return $null }
}

function Calc-RSI { param($p, $per)
    $g = [double[]]::new($p.Count); $l = [double[]]::new($p.Count)
    for ($i = 1; $i -lt $p.Count; $i++) { $d = $p[$i] - $p[$i-1]; if ($d -ge 0) { $g[$i] = $d } else { $l[$i] = -$d } }
    $ag = ($g[1..$per] | Measure-Object -Sum).Sum / $per; $al = ($l[1..$per] | Measure-Object -Sum).Sum / $per
    $r = [double[]]::new($p.Count)
    for ($i = $per; $i -lt $p.Count; $i++) {
        if ($i -gt $per) { $ag = (($ag * ($per-1)) + $g[$i]) / $per; $al = (($al * ($per-1)) + $l[$i]) / $per }
        $r[$i] = if ($al -eq 0) { 100 } else { 100 - (100 / (1 + ($ag / $al))) }
    }
    return $r
}
function Calc-EMA { param($p, $per)
    $e = [double[]]::new($p.Count); $e[0] = $p[0]; $m = 2 / ($per + 1)
    for ($i = 1; $i -lt $p.Count; $i++) { $e[$i] = $p[$i] * $m + $e[$i-1] * (1 - $m) }
    return $e
}
function Calc-ATR { param($h, $l, $c, $per)
    $tr = [double[]]::new($c.Count)
    for ($i = 1; $i -lt $c.Count; $i++) { $hl = $h[$i] - $l[$i]; $hc = [Math]::Abs($h[$i] - $c[$i-1]); $lc = [Math]::Abs($l[$i] - $c[$i-1]); $tr[$i] = [Math]::Max($hl, [Math]::Max($hc, $lc)) }
    $a = [double[]]::new($c.Count)
    if ($c.Count -gt $per) { $a[$per] = ($tr[1..$per] | Measure-Object -Average).Average; for ($i = $per+1; $i -lt $c.Count; $i++) { $a[$i] = ($a[$i-1] * ($per-1) + $tr[$i]) / $per } }
    return $a
}
function Calc-MACD { param($c, $f, $s, $sig)
    $e12 = Calc-EMA $c $f; $e26 = Calc-EMA $c $s; $m = [double[]]::new($c.Count)
    for ($i = 0; $i -lt $c.Count; $i++) { $m[$i] = $e12[$i] - $e26[$i] }
    $sigLine = Calc-EMA $m $sig
    return @{macd = $m; signal = $sigLine; hist = (0..($c.Count-1) | % { $m[$_] - $sigLine[$_] }) }
}
function Calc-Stoch { param($h, $l, $c, $k, $d)
    $st = [double[]]::new($c.Count)
    for ($i = $k-1; $i -lt $c.Count; $i++) {
        $start = $i - $k + 1
        $hh = -1e10; $ll = 1e10
        for ($j = $start; $j -le $i; $j++) { if ($h[$j] -gt $hh) { $hh = $h[$j] }; if ($l[$j] -lt $ll) { $ll = $l[$j] } }
        $st[$i] = if ($hh -eq $ll) { 50 } else { ($c[$i] - $ll) / ($hh - $ll) * 100 }
    }
    return Calc-EMA $st $d
}
function Calc-CCI { param($h, $l, $c, $per)
    $tp = [double[]]::new($c.Count); for ($i = 0; $i -lt $c.Count; $i++) { $tp[$i] = ($h[$i] + $l[$i] + $c[$i]) / 3 }
    $sma = Calc-EMA $tp $per
    $md = [double[]]::new($c.Count)
    for ($i = $per-1; $i -lt $c.Count; $i++) { $sum = 0; for ($j = $i-$per+1; $j -le $i; $j++) { $sum += [Math]::Abs($tp[$j] - $sma[$i]) }; $md[$i] = $sum / $per }
    $cci = [double[]]::new($c.Count)
    for ($i = $per-1; $i -lt $c.Count; $i++) { $cci[$i] = if ($md[$i] -eq 0) { 0 } else { ($tp[$i] - $sma[$i]) / (0.015 * $md[$i]) } }
    return $cci
}
function Calc-MFI { param($h, $l, $c, $v, $per)
    $tp = [double[]]::new($c.Count); for ($i = 0; $i -lt $c.Count; $i++) { $tp[$i] = ($h[$i] + $l[$i] + $c[$i]) / 3 }
    $rmf = [double[]]::new($c.Count); for ($i = 1; $i -lt $c.Count; $i++) { $rmf[$i] = $tp[$i] * $v[$i] }
    $mfi = [double[]]::new($c.Count)
    for ($i = $per; $i -lt $c.Count; $i++) { $pSum = 0; $nSum = 0; for ($j = $i-$per+1; $j -le $i; $j++) { if ($rmf[$j] -gt $rmf[$j-1]) { $pSum += $rmf[$j] } else { $nSum += $rmf[$j] } }; $mfi[$i] = if ($nSum -eq 0) { 100 } else { 100 - (100 / (1 + ($pSum / $nSum))) } }
    return $mfi
}
function Calc-MOM { param($c, $per)
    $m = [double[]]::new($c.Count); for ($i = $per; $i -lt $c.Count; $i++) { $m[$i] = $c[$i] - $c[$i-$per] }; return $m
}
function Calc-CMF { param($h, $l, $c, $v, $per)
    $cmfm = [double[]]::new($c.Count); for ($i = 0; $i -lt $c.Count; $i++) { $cmfm[$i] = if (($h[$i] - $l[$i]) -eq 0) { 0 } else { (($c[$i] - $l[$i]) - ($h[$i] - $c[$i])) / ($h[$i] - $l[$i]) } }
    $cmfv = [double[]]::new($c.Count); for ($i = 0; $i -lt $c.Count; $i++) { $cmfv[$i] = $cmfm[$i] * $v[$i] }
    $cmf1 = Calc-EMA $cmfv $per; $cmf2 = Calc-EMA $v $per
    $cmf = [double[]]::new($c.Count); for ($i = 0; $i -lt $c.Count; $i++) { $cmf[$i] = if ($cmf2[$i] -eq 0) { 0 } else { $cmf1[$i] / $cmf2[$i] } }
    return $cmf
}
function Calc-OBV { param($c, $v)
    $o = [double[]]::new($c.Count); $o[0] = 0
    for ($i = 1; $i -lt $c.Count; $i++) {
        if ($c[$i] -gt $c[$i-1]) { $o[$i] = $o[$i-1] + $v[$i] }
        elseif ($c[$i] -lt $c[$i-1]) { $o[$i] = $o[$i-1] - $v[$i] }
        else { $o[$i] = $o[$i-1] }
    }
    return $o
}

# === SIMPLIFIED DIVERGENCE DETECTION (matches Pine Script logic) ===
function Get-PivotSigs { param($lows, $highs, $prd)
    $n = $lows.Count
    $plSig = [int[]]::new($n)  # 1 if bar is a confirmed pivot low
    $phSig = [int[]]::new($n)  # 1 if bar is a confirmed pivot high
    for ($i = 2*$prd; $i -lt $n; $i++) {
        # pivotlow: check if bar (i-prd) was a low relative to Ã‚Â±prd around it
        $testBar = $i - $prd
        $isPL = $true; $isPH = $true
        for ($j = 1; $j -le $prd; $j++) {
            if ($lows[$testBar] -ge $lows[$testBar - $j] -or $lows[$testBar] -ge $lows[$testBar + $j]) { $isPL = $false }
            if ($highs[$testBar] -le $highs[$testBar - $j] -or $highs[$testBar] -le $highs[$testBar + $j]) { $isPH = $false }
        }
        if ($isPL) { $plSig[$i] = 1 }  # signal at bar i means pivot low at bar i-prd
        if ($isPH) { $phSig[$i] = 1 }
    }
    return @{ pl = $plSig; ph = $phSig }
}

function Test-Divergence { param($indicator, $price, $plSigs, $phSigs, $prd, $maxBars, $maxPP)
    # Returns arrays of bullish/bearish divergence scores at each bar
    $n = $indicator.Count
    $bull = [int[]]::new($n)
    $bear = [int[]]::new($n)

    # Track confirmed pivot positions (where the actual pivot was, not where it was signaled)
    $plPos = @()  # positions of pivot lows
    $plVal = @()  # indicator value at pivot low
    $plPrc = @()  # price value at pivot low
    $phPos = @()
    $phVal = @()
    $phPrc = @()

    for ($i = 2*$prd; $i -lt $n; $i++) {
        $confirmedBar = $i

        # If pivot low confirmed at this bar (pivot at i-prd)
        if ($plSigs[$i] -eq 1) {
            $pivotBar = $i - $prd
            $newPl = @{ pos = $pivotBar; ind = $indicator[$pivotBar]; prc = $price[$pivotBar] }

            # Check bullish divergence with older pivot lows
            for ($x = 0; $x -lt [Math]::Min($maxPP, $plPos.Count); $x++) {
                $len = $pivotBar - $plPos[$x]
                if ($len -gt $maxBars) { break }
                if ($len -le $prd) { continue }

                # Positive Regular: price lower low, indicator higher low
                if ($newPl.prc -lt $plPrc[$x] -and $newPl.ind -gt $plVal[$x]) {
                    # Verify no crossover (straight line check)
                    $valid = $true
                    for ($y = $plPos[$x] + 1; $y -lt $pivotBar; $y++) {
                        $t = ($y - $plPos[$x]) / $len
                        $indLine = $plVal[$x] + $t * ($newPl.ind - $plVal[$x])
                        $prcLine = $plPrc[$x] + $t * ($newPl.prc - $plPrc[$x])
                        if ($indicator[$y] -lt $indLine -or $price[$y] -lt $prcLine) { $valid = $false; break }
                    }
                    if ($valid) { $bull[$i]++; break }
                }

                # Positive Hidden: price higher low, indicator lower low
                if ($newPl.prc -gt $plPrc[$x] -and $newPl.ind -lt $plVal[$x]) {
                    $valid = $true
                    for ($y = $plPos[$x] + 1; $y -lt $pivotBar; $y++) {
                        $t = ($y - $plPos[$x]) / $len
                        $indLine = $plVal[$x] + $t * ($newPl.ind - $plVal[$x])
                        $prcLine = $plPrc[$x] + $t * ($newPl.prc - $plPrc[$x])
                        if ($indicator[$y] -lt $indLine -or $price[$y] -lt $prcLine) { $valid = $false; break }
                    }
                    if ($valid) { $bull[$i]++; break }
                }
            }
            $plPos = @($newPl.pos) + $plPos
            $plVal = @($newPl.ind) + $plVal
            $plPrc = @($newPl.prc) + $plPrc
        }

        # If pivot high confirmed at this bar
        if ($phSigs[$i] -eq 1) {
            $pivotBar = $i - $prd
            $newPh = @{ pos = $pivotBar; ind = $indicator[$pivotBar]; prc = $price[$pivotBar] }

            for ($x = 0; $x -lt [Math]::Min($maxPP, $phPos.Count); $x++) {
                $len = $pivotBar - $phPos[$x]
                if ($len -gt $maxBars) { break }
                if ($len -le $prd) { continue }

                # Negative Regular: price higher high, indicator lower high
                if ($newPh.prc -gt $phPrc[$x] -and $newPh.ind -lt $phVal[$x]) {
                    $valid = $true
                    for ($y = $phPos[$x] + 1; $y -lt $pivotBar; $y++) {
                        $t = ($y - $phPos[$x]) / $len
                        $indLine = $phVal[$x] + $t * ($newPh.ind - $phVal[$x])
                        $prcLine = $phPrc[$x] + $t * ($newPh.prc - $phPrc[$x])
                        if ($indicator[$y] -gt $indLine -or $price[$y] -gt $prcLine) { $valid = $false; break }
                    }
                    if ($valid) { $bear[$i]++; break }
                }

                # Negative Hidden: price lower high, indicator higher high
                if ($newPh.prc -lt $phPrc[$x] -and $newPh.ind -gt $phVal[$x]) {
                    $valid = $true
                    for ($y = $phPos[$x] + 1; $y -lt $pivotBar; $y++) {
                        $t = ($y - $phPos[$x]) / $len
                        $indLine = $phVal[$x] + $t * ($newPh.ind - $phVal[$x])
                        $prcLine = $phPrc[$x] + $t * ($newPh.prc - $phPrc[$x])
                        if ($indicator[$y] -gt $indLine -or $price[$y] -gt $prcLine) { $valid = $false; break }
                    }
                    if ($valid) { $bear[$i]++; break }
                }
            }
            $phPos = @($newPh.pos) + $phPos
            $phVal = @($newPh.ind) + $phVal
            $phPrc = @($newPh.prc) + $phPrc
        }
    }
    return @{ bull = $bull; bear = $bear }
}

function Simulate-Trades { param($c, $h, $l, $bullSigs, $bearSigs, $ema, $ts, $minScore, $useTrend, $tpPct, $slPct, $prd, $n)
    $trades = @()
    for ($i = 100; $i -lt $n - 3; $i++) {
        # Signal is at confirmation bar i. Entry is at next bar open (= close of current bar for simplicity)
        $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i])

        if ($bullSigs[$i] -ge $minScore -and (-not $useTrend -or $c[$i] -gt $ema[$i])) {
            $ep = $c[$i]; $tpP = $ep * (1 + $tpPct/100); $slP = $ep * (1 - $slPct/100); $hit = $null
            $maxJ = [Math]::Min($i + 48, $n)
            for ($j = $i + 1; $j -lt $maxJ; $j++) {
                if ($h[$j] -ge $tpP) { $hit = "TP"; break }
                if ($l[$j] -le $slP) { $hit = "SL"; break }
            }
            if ($hit -eq "TP") { $trades += @{ pnl = $tpPct; hit = 1 } }
            elseif ($hit -eq "SL") { $trades += @{ pnl = -$slPct; hit = 0 } }
        }

        if ($bearSigs[$i] -ge $minScore -and (-not $useTrend -or $c[$i] -lt $ema[$i])) {
            $ep = $c[$i]; $tpP = $ep * (1 - $tpPct/100); $slP = $ep * (1 + $slPct/100); $hit = $null
            $maxJ = [Math]::Min($i + 48, $n)
            for ($j = $i + 1; $j -lt $maxJ; $j++) {
                if ($l[$j] -le $tpP) { $hit = "TP"; break }
                if ($h[$j] -ge $slP) { $hit = "SL"; break }
            }
            if ($hit -eq "TP") { $trades += @{ pnl = $tpPct; hit = 1 } }
            elseif ($hit -eq "SL") { $trades += @{ pnl = -$slPct; hit = 0 } }
        }
    }
    return $trades
}

# === MAIN ===
Write-Output "============================================"
Write-Output "  SOL DIVERGENCE GRID SEARCH v2"
Write-Output "============================================"

$timeframes = @(@{name="2h"; int="120"}, @{name="4h"; int="240"})
$pivotPeriods = @(3, 5, 7)
$minScores = @(1, 2, 3)
$maxPPs = @(5, 8)
$maxBarsVals = @(60, 100)
$useHidden = $false

$indPresets = @(
    @{name="RSI+MACD+Stoch+MFI"; m=@($true,$true,$true,$true,$false,$false,$false,$false,$true)}
    @{name="RSI+MACD+MFI";       m=@($true,$true,$false,$false,$false,$false,$false,$false,$true)}
    @{name="RSI+Stoch+MFI";      m=@($true,$false,$false,$true,$false,$false,$false,$false,$true)}
    @{name="RSI+MACD+Stoch";     m=@($true,$true,$true,$true,$false,$false,$false,$false,$false)}
    @{name="All9";               m=@($true,$true,$true,$true,$true,$true,$true,$true,$true)}
)

$tpLevels = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0)
$slLevels = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0)

$allResults = @()

foreach ($tf in $timeframes) {
    Write-Output "`n===== FETCHING $($tf.name) ====="
    $klines = Get-K $tf.int 600
    if (-not $klines -or $klines.Count -lt 100) { Write-Output "No data"; continue }

    $c = $klines | % { [double]$_[4] }; $h = $klines | % { [double]$_[2] }
    $l = $klines | % { [double]$_[3] }; $v = $klines | % { [double]$_[5] }
    $ts = $klines | % { [long]$_[0] }; $n = $c.Count
    Write-Output "  Candles: $n"

    Write-Output "  Computing indicators..."
    $rsi = Calc-RSI $c 14; $macd = Calc-MACD $c 12 26 9
    $stoch = Calc-Stoch $h $l $c 14 3; $cci = Calc-CCI $h $l $c 10
    $mom = Calc-MOM $c 10; $mfi = Calc-MFI $h $l $c $v 14
    $cmf = Calc-CMF $h $l $c $v 21; $obv = Calc-OBV $c $v
    $indicatorData = @($rsi, $macd.macd, $macd.hist, $stoch, $cci, $mom, $obv, $cmf, $mfi)
    $indNames = @("RSI","MACD","Hist","Stoch","CCI","Mom","OBV","CMF","MFI")

    foreach ($prd in $pivotPeriods) {
        Write-Output "  GetPivotSigs prd=$prd..."
        $pivotSigs = Get-PivotSigs $l $h $prd
        $plCount = ($pivotSigs.pl | Where-Object { $_ -eq 1 }).Count
        $phCount = ($pivotSigs.ph | Where-Object { $_ -eq 1 }).Count
        Write-Output "    PL sigs: $plCount, PH sigs: $phCount"

        foreach ($preset in $indPresets) {
            # Build aggregate bull/bear arrays across all active indicators
            $aggBull = [int[]]::new($n); $aggBear = [int[]]::new($n)
            foreach ($hid in @($false)) {
                foreach ($mb in $maxBarsVals) {
                    foreach ($mpp in $maxPPs) {
                        $aggBull = [int[]]::new($n); $aggBear = [int[]]::new($n)
                        for ($ai = 0; $ai -lt $indicatorData.Count; $ai++) {
                            if (-not $preset.m[$ai]) { continue }
                            $src = $indicatorData[$ai]
                            $divScores = Test-Divergence $src $c $pivotSigs.pl $pivotSigs.ph $prd $mb $mpp
                            for ($bi = 0; $bi -lt $n; $bi++) {
                                $aggBull[$bi] += $divScores.bull[$bi]
                                $aggBear[$bi] += $divScores.bear[$bi]
                            }
                        }
                        $totalBull = ($aggBull | Measure-Object -Sum).Sum
                        $totalBear = ($aggBear | Measure-Object -Sum).Sum
                        $nzB = ($aggBull | Where-Object { $_ -gt 0 }).Count
                        $nzBr = ($aggBear | Where-Object { $_ -gt 0 }).Count
                        Write-Output "  $($tf.name) p$prd pp$mpp b$mb $($preset.name): bull=$totalBull ($nzB sigs) bear=$totalBear ($nzBr sigs)"

                        if ($totalBull -eq 0 -and $totalBear -eq 0) { continue }

                        $ema = Calc-EMA $c 200
                        foreach ($ms in $minScores) {
                            $trades = Simulate-Trades $c $h $l $aggBull $aggBear $ema $ts $ms $true 1.0 1.0 $prd $n
                            $valid = $trades | Where-Object { $_.hit -ne $null }
                            $tw = ($valid | Where-Object { $_.hit -eq 1 }).Count
                            $tl = ($valid | Where-Object { $_.hit -eq 0 }).Count
                            $tt = $tw + $tl
                            if ($tt -lt 3) { continue }
                            $wr = [Math]::Round($tw / $tt * 100, 1)
                            $pnl = ($valid | % { $_.pnl } | Measure-Object -Sum).Sum
                            $score = [Math]::Round($wr * $tt / 100, 1)
                            Write-Output "    s$ms => WR=$wr% T=$tt P=$([Math]::Round($pnl,1))" ($wr -ge 60){'Green'}elseif($wr -ge 50){'Yellow'}else{'Gray'})

                            if ($wr -ge 55) {
                                foreach ($tp in $tpLevels) {
                                    foreach ($sl in $slLevels) {
                                        $t2 = Simulate-Trades $c $h $l $aggBull $aggBear $ema $ts $ms $true $tp $sl $prd $n
                                        $v2 = $t2 | Where-Object { $_.hit -ne $null }
                                        $w2 = ($v2 | Where-Object { $_.hit -eq 1 }).Count; $l2 = ($v2 | Where-Object { $_.hit -eq 0 }).Count
                                        $t2t = $w2 + $l2; if ($t2t -lt 3) { continue }
                                        $wr2 = [Math]::Round($w2 / $t2t * 100, 1)
                                        $pnl2 = ($v2 | % { $_.pnl } | Measure-Object -Sum).Sum
                                        $score2 = [Math]::Round($wr2 * $t2t / 100, 1)
                                        $allResults += [PSCustomObject]@{ TF=$tf.name; Prd=$prd; MinS=$ms; MPP=$mpp; MBar=$mb; Ind=$preset.name; TP=$tp; SL=$sl; WR=$wr2; Trades=$t2t; PnL=[Math]::Round($pnl2,1); Score=$score2 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

Write-Output "`n`n============================================"
Write-Output "  RESULTS SUMMARY"
Write-Output "============================================"

if ($allResults.Count -eq 0) { Write-Output "No results!"; exit }

$topWR = $allResults | Where-Object { $_.Trades -ge 10 } | Sort-Object WR -Descending | Select-Object -First 15
$topScore = $allResults | Sort-Object Score -Descending | Select-Object -First 15
$topPnl = $allResults | Sort-Object PnL -Descending | Select-Object -First 15

Write-Output "`n--- TOP 15 BY WIN RATE (min 10 trades) ---"
$topWR | Format-Table TF, Prd, MinS, Ind, TP, SL, WR, Trades, PnL, Score -AutoSize -Wrap

Write-Output "`n--- TOP 15 BY SCORE ---"
$topScore | Format-Table TF, Prd, MinS, Ind, TP, SL, WR, Trades, PnL, Score -AutoSize -Wrap

Write-Output "`n--- TOP 15 BY PnL ---"
$topPnl | Format-Table TF, Prd, MinS, Ind, TP, SL, WR, Trades, PnL, Score -AutoSize -Wrap

$csvPath = "sol_divergence_results.csv"
$allResults | Export-Csv -Path $csvPath -NoTypeInformation
Write-Output "`nFull results: $csvPath"
Write-Output "Total configs: $($allResults.Count)"

# ===== WALK-FORWARD VALIDATION =====
Write-Output "`n`n============================================"
Write-Output "  WALK-FORWARD VALIDATION (top config)"
Write-Output "============================================"

$bestCfg = $allResults | Sort-Object Score -Descending | Select-Object -First 1
if ($bestCfg) {
    Write-Output "Config: TF=$($bestCfg.TF) Prd=$($bestCfg.Prd) Ind=$($bestCfg.Ind) TP=$($bestCfg.TP) SL=$($bestCfg.SL) MinS=$($bestCfg.MinS)"
    $wfKlines = Get-K $bestCfg.TF 600
    if ($wfKlines -and $wfKlines.Count -ge 200) {
        $wfC = $wfKlines | % { [double]$_[4] }; $wfH = $wfKlines | % { [double]$_[2] }; $wfL = $wfKlines | % { [double]$_[3] }; $wfV = $wfKlines | % { [double]$_[5] }; $wfTs = $wfKlines | % { [long]$_[0] }; $wfN = $wfC.Count
        $wfRsi = Calc-RSI $wfC 14; $wfMacd = Calc-MACD $wfC 12 26 9; $wfStoch = Calc-Stoch $wfH $wfL $wfC 14 3
        $wfCci = Calc-CCI $wfH $wfL $wfC 10; $wfMom = Calc-MOM $wfC 10; $wfMfi = Calc-MFI $wfH $wfL $wfC $wfV 14
        $wfCmf = Calc-CMF $wfH $wfL $wfC $wfV 21; $wfObv = Calc-OBV $wfC $wfV
        $wfIndData = @($wfRsi, $wfMacd.macd, $wfMacd.hist, $wfStoch, $wfCci, $wfMom, $wfObv, $wfCmf, $wfMfi)
        $wfPresetIdx = [Math]::Max(0, $indPresets.IndexOf(($indPresets | Where-Object { $_.name -eq $bestCfg.Ind })))
        if ($wfPresetIdx -ge 0) {
            $wfPreset = $indPresets[$wfPresetIdx]; $wfPivotSigs = Get-PivotSigs $wfL $wfH $bestCfg.Prd
            $wfAggBull = [int[]]::new($wfN); $wfAggBear = [int[]]::new($wfN)
            for ($ai = 0; $ai -lt $wfIndData.Count; $ai++) {
                if (-not $wfPreset.m[$ai]) { continue }
                $wfDiv = Test-Divergence $wfIndData[$ai] $wfC $wfPivotSigs.pl $wfPivotSigs.ph $bestCfg.Prd $bestCfg.MBar $bestCfg.MPP
                for ($bi = 0; $bi -lt $wfN; $bi++) { $wfAggBull[$bi] += $wfDiv.bull[$bi]; $wfAggBear[$bi] += $wfDiv.bear[$bi] }
            }
            $wfEma = Calc-EMA $wfC 200
            $split = $wfN * 0.7
            # In-sample (70%)
            $isTrades = Simulate-Trades $wfC[0..([int]$split)] $wfH[0..([int]$split)] $wfL[0..([int]$split)] $wfAggBull[0..([int]$split)] $wfAggBear[0..([int]$split)] $wfEma[0..([int]$split)] $wfTs[0..([int]$split)] $bestCfg.MinS $true $bestCfg.TP $bestCfg.SL $bestCfg.Prd ([int]$split+1)
            $isV = $isTrades | Where-Object { $_.hit -ne $null }; $isW = ($isV | Where-Object { $_.hit -eq 1 }).Count; $isL = ($isV | Where-Object { $_.hit -eq 0 }).Count
            $isWr = if ($isW+$isL -ge 3) { [Math]::Round($isW/($isW+$isL)*100,1) } else { 0 }
            Write-Output "  In-sample (70%): WR=$isWr% T=$($isW+$isL)"
            # Out-of-sample (30%)
            $osStart = [int]$split + 1; $osLen = $wfN - $osStart
            $osTrades = Simulate-Trades $wfC[$osStart..($wfN-1)] $wfH[$osStart..($wfN-1)] $wfL[$osStart..($wfN-1)] $wfAggBull[$osStart..($wfN-1)] $wfAggBear[$osStart..($wfN-1)] $wfEma[$osStart..($wfN-1)] $wfTs[$osStart..($wfN-1)] $bestCfg.MinS $true $bestCfg.TP $bestCfg.SL $bestCfg.Prd $osLen
            $osV = $osTrades | Where-Object { $_.hit -ne $null }; $osW = ($osV | Where-Object { $_.hit -eq 1 }).Count; $osL = ($osV | Where-Object { $_.hit -eq 0 }).Count
            $osWr = if ($osW+$osL -ge 3) { [Math]::Round($osW/($osW+$osL)*100,1) } else { 0 }
            Write-Output "  Out-of-sample (30%): WR=$osWr% T=$($osW+$osL)" ($osWr -ge $isWr -or $isWr -eq 0) {'Green'}elseif($osWr -ge 50){'Yellow'}else{'Red'})
            if ($osW -ge 2 -and $osWr -ge 40) {
                $osPnl = ($osV | % { $_.pnl } | Measure-Object -Sum).Sum
                Write-Output "  OOS PnL: $([Math]::Round($osPnl,1))"
            }
        }
    }
} else { Write-Output "No best config found" }

# ===== MONTE CARLO SIMULATION =====
Write-Output "`n`n============================================"
Write-Output "  MONTE CARLO SIMULATION (best config)"
Write-Output "============================================"
if ($bestCfg) {
    $mcKlines = Get-K $bestCfg.TF 600
    if ($mcKlines -and $mcKlines.Count -ge 200) {
        $mcC = $mcKlines | % { [double]$_[4] }; $mcH = $mcKlines | % { [double]$_[2] }; $mcL = $mcKlines | % { [double]$_[3] }; $mcV = $mcKlines | % { [double]$_[5] }; $mcTs = $mcKlines | % { [long]$_[0] }; $mcN = $mcC.Count
        $mcRsi = Calc-RSI $mcC 14; $mcMacd = Calc-MACD $mcC 12 26 9; $mcStoch = Calc-Stoch $mcH $mcL $mcC 14 3
        $mcCci = Calc-CCI $mcH $mcL $mcC 10; $mcMom = Calc-MOM $mcC 10; $mcMfi = Calc-MFI $mcH $mcL $mcC $mcV 14
        $mcCmf = Calc-CMF $mcH $mcL $mcC $mcV 21; $mcObv = Calc-OBV $mcC $mcV
        $mcIndData = @($mcRsi, $mcMacd.macd, $mcMacd.hist, $mcStoch, $mcCci, $mcMom, $mcObv, $mcCmf, $mcMfi)
        $mcPresetIdx = [Math]::Max(0, $indPresets.IndexOf(($indPresets | Where-Object { $_.name -eq $bestCfg.Ind })))
        if ($mcPresetIdx -ge 0) {
            $mcPreset = $indPresets[$mcPresetIdx]; $mcPivotSigs = Get-PivotSigs $mcL $mcH $bestCfg.Prd
            $mcAggBull = [int[]]::new($mcN); $mcAggBear = [int[]]::new($mcN)
            for ($ai = 0; $ai -lt $mcIndData.Count; $ai++) {
                if (-not $mcPreset.m[$ai]) { continue }
                $mcDiv = Test-Divergence $mcIndData[$ai] $mcC $mcPivotSigs.pl $mcPivotSigs.ph $bestCfg.Prd $bestCfg.MBar $bestCfg.MPP
                for ($bi = 0; $bi -lt $mcN; $bi++) { $mcAggBull[$bi] += $mcDiv.bull[$bi]; $mcAggBear[$bi] += $mcDiv.bear[$bi] }
            }
            $mcEma = Calc-EMA $mcC 200
            $mcTrades = Simulate-Trades $mcC $mcH $mcL $mcAggBull $mcAggBear $mcEma $mcTs $bestCfg.MinS $true $bestCfg.TP $bestCfg.SL $bestCfg.Prd $mcN
            $mcValid = $mcTrades | Where-Object { $_.hit -ne $null }
            if ($mcValid.Count -ge 10) {
                $mcPnlList = $mcValid | ForEach-Object { [PSCustomObject]@{ PnL = $_.pnl } }
                Write-Output "  Trades captured: $($mcPnlList.Count)"
                Import-Module (Join-Path $PSScriptRoot "Modules\MonteCarlo.psm1") -Force -ErrorAction SilentlyContinue
                if (Get-Command Invoke-MonteCarloSimulation -ErrorAction SilentlyContinue) {
                    $mcResult = Invoke-MonteCarloSimulation -TradeHistory $mcPnlList -Iterations 10000 -InitialCapital 100 -OutputPath "sol_divergence_mc.csv"
                    if ($mcResult -and $mcResult.Summary) {
                        Write-Output "  Monte Carlo (10k iterations, 100 capital):"
                        Write-Output "    Mean return: $($mcResult.Summary.MeanReturn)%" -gt 0){'Green'}else{'Red'})
                        Write-Output "    Median return: $($mcResult.Summary.MedianReturn)%"
                        Write-Output "    Mean max drawdown: $($mcResult.Summary.MeanMaxDrawdown)%"
                        Write-Output "    CI95: [$($mcResult.Summary.Ci95Low), $($mcResult.Summary.Ci95High)]"
                    }
                } else {
                    Write-Output "  MonteCarlo module not loaded — running inline simulation"
                    $mcIterations = 10000; $mcCapital = 100.0
                    $mcRng = [System.Random]::new(); $mcResults2 = @()
                    for ($iter = 0; $iter -lt $mcIterations; $iter++) {
                        $cap = $mcCapital; $peak = $mcCapital; $mdd = 0.0
                        for ($ti = 0; $ti -lt $mcValid.Count; $ti++) {
                            $p = $mcValid[$mcRng.Next(0, $mcValid.Count)].pnl
                            $cap += $p; if ($cap -gt $peak) { $peak = $cap }; $dd2 = ($peak - $cap) / $peak * 100; if ($dd2 -gt $mdd) { $mdd = $dd2 }
                        }
                        $ret = ($cap - $mcCapital) / $mcCapital * 100
                        $mcResults2 += [PSCustomObject]@{ Iteration = $iter+1; FinalCapital = $cap; TotalReturn = $ret; MaxDrawdown = $mdd }
                    }
                    $mcRets2 = $mcResults2 | % { [double]$_.TotalReturn }; $mcSorted2 = $mcRets2 | Sort-Object
                    $mcMean2 = ($mcRets2 | Measure-Object -Average).Average
                    $mcMed2 = $mcSorted2[[Math]::Floor($mcSorted2.Count/2)]
                    $mcDD2 = ($mcResults2 | % { [double]$_.MaxDrawdown } | Measure-Object -Average).Average
                    Write-Output "  Monte Carlo (10k iterations, 100 capital):"
                    Write-Output "    Mean return: $([Math]::Round($mcMean2,2))%" -gt 0){'Green'}else{'Red'})
                    Write-Output "    Median return: $([Math]::Round($mcMed2,2))%"
                    Write-Output "    Mean max drawdown: $([Math]::Round($mcDD2,2))%"
                    $mcCaps2 = $mcResults2 | % { [double]$_.FinalCapital } | Sort-Object
                    $mcCiLow2 = $mcCaps2[[Math]::Floor($mcCaps2.Count*0.025)]
                    $mcCiHigh2 = $mcCaps2[[Math]::Floor($mcCaps2.Count*0.975)]
                    Write-Output "    CI95: [$([Math]::Round($mcCiLow2,2)), $([Math]::Round($mcCiHigh2,2))]"
                }
            } else {
                Write-Output "  Not enough trades for Monte Carlo (need 10, got $($mcValid.Count))"
            }
        }
    }
} else { Write-Output "No best config found" }
