# ============================================================
#  ICP 12h ADX>25 LONG-only Ã¢â‚¬â€ Focused Backtest
#  Phase 3: TP/SL optimization + Walk-forward validation
# ============================================================

Write-Output "========================================"
Write-Output "  ICP 12h ADX>25 LONG-only Backtest"
Write-Output "========================================"

# ===== RSA API (from bybit_info.ps1) =====
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
    if ($data[$offset.Value] -ne 0x02) { throw "Expected INTEGER" }
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

$pem = Get-Content -Raw $env:BYBIT_PRIVATE_KEY_PATH
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0
if ($der[$off] -ne 0x30) { throw "Not a SEQUENCE" }; $off++
$seqLen = Read-DerLength -data $der -offset ([ref]$off)
$params = New-Object System.Security.Cryptography.RSAParameters
$version = Read-DerInteger -data $der -offset ([ref]$off)
$params.Modulus = Read-DerInteger -data $der -offset ([ref]$off)
$params.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
$params.D = Read-DerInteger -data $der -offset ([ref]$off)
$params.P = Read-DerInteger -data $der -offset ([ref]$off)
$params.Q = Read-DerInteger -data $der -offset ([ref]$off)
$params.DP = Read-DerInteger -data $der -offset ([ref]$off)
$params.DQ = Read-DerInteger -data $der -offset ([ref]$off)
$params.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($params)
$apiKey = $env:BYBIT_API_KEY
$recvWindow = "5000"
$baseUrl = "https://api.bybit.com"

function Call-Bybit {
    param($endpoint, $query)
    $timestamp = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $paramStr = "${timestamp}${apiKey}${recvWindow}${query}"
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($paramStr)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $sigBytes = $rsa.SignData($dataBytes, $hasher)
    $signature = [System.Convert]::ToBase64String($sigBytes)
    $headers = @{
        "X-BAPI-API-KEY" = $apiKey; "X-BAPI-TIMESTAMP" = "$timestamp"
        "X-BAPI-SIGN" = $signature; "X-BAPI-RECV-WINDOW" = $recvWindow
        "X-BAPI-SIGN-TYPE" = "2"; "User-Agent" = "bybit-skill/1.4.2"
        "X-Referer" = "bybit-skill"
    }
    try {
        $resp = Invoke-WebRequest -Uri "$baseUrl$endpoint`?$query" -Headers $headers -UseBasicParsing -TimeoutSec 60
        return $resp.Content | ConvertFrom-Json
    } catch { return $null }
}

function Get-K {
    param($interval, $limit)
    $r = Call-Bybit -endpoint "/v5/market/kline" -query "category=spot&symbol=ICPUSDT&interval=$interval&limit=$limit"
    if ($r -and $r.retCode -eq 0 -and $r.result -and $r.result.list) {
        $k = $r.result.list; [Array]::Reverse($k); return $k
    }
    return $null
}

# ===== Indicators =====
function Calc-EMA {
    param($p, $per)
    $e = [double[]]::new($p.Count); $e[0] = $p[0]; $m = 2/($per+1)
    for ($i = 1; $i -lt $p.Count; $i++) { $e[$i] = $p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}
function Calc-ADX {
    param($h, $l, $c, $per)
    $tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
    for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))
        $u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per
    $dx=[double[]]::new($c.Count)
    for($i=$per;$i-lt$c.Count;$i++){$pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100;$dx[$i]=if(($pdi+$ndi)-eq0){0}else{[Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100}}
    return (Calc-EMA $dx $per)
}

# ===== TP/SL Simulator =====
function Test-TP-SL {
    param($c, $h, $l, $entryIdx, $tpPct, $slPct, $feePct)
    $ep = $c[$entryIdx]
    $tp = $ep * (1 + $tpPct/100)
    $sl = $ep * (1 - $slPct/100)
    for ($i = $entryIdx+1; $i -lt $c.Count; $i++) {
        if ($h[$i] -ge $tp) {
            $exitPrice = [Math]::Min($tp, $c[$i])
            $grossPnl = $ep * $tpPct / 100
            $fee = $ep*$feePct/100 + $exitPrice*$feePct/100
            return @{result="TP"; exitIdx=$i; pnl=[Math]::Round($grossPnl-$fee,6); exitPrice=$exitPrice}
        }
        if ($l[$i] -le $sl) {
            $exitPrice = $sl
            $grossPnl = -$ep * $slPct / 100
            $fee = $ep*$feePct/100 + $exitPrice*$feePct/100
            return @{result="SL"; exitIdx=$i; pnl=[Math]::Round($grossPnl-$fee,6); exitPrice=$exitPrice}
        }
    }
    return $null
}

# ===== Phase 1: Fetch =====
Write-Output "`nFetching 800 candles ICPUSDT 12h..."
$klines = Get-K 720 800
if (-not $klines) { Write-Output "FETCH FAILED" exit 1 }
Write-Output "Got $($klines.Count) candles"

$c = $klines | % { [double]$_[4] }
$h = $klines | % { [double]$_[2] }
$l = $klines | % { [double]$_[3] }
$o = $klines | % { [double]$_[1] }
$v = $klines | % { [double]$_[5] }
$ts = $klines | % { [long]$_[0] }

Write-Output "Computing ADX(14)..."
$adx = Calc-ADX $h $l $c 14

# ===== Phase 2: Strategy Analysis =====
Write-Output "`n--- Signal Stats ---"
$si = 50
$totalCandles = $c.Count - $si
$sigCount = 0
for ($i = $si; $i -lt $c.Count; $i++) { if ($adx[$i] -gt 25) { $sigCount++ } }
Write-Output "ADX>25 on $sigCount of $totalCandles candles ($([Math]::Round($sigCount/$totalCandles*100,1))%)"

# Check +DI/-DI direction on signal candles
$diLong = 0; $diShort = 0
for ($i = $si; $i -lt $c.Count; $i++) {
    if ($adx[$i] -gt 25) {
        # Recompute DI direction
        $up = 0; $dn = 0; $tr = [Math]::Max($h[$i]-$l[$i], [Math]::Max([Math]::Abs($h[$i]-$c[$i-1]), [Math]::Abs($l[$i]-$c[$i-1])))
        $u = $h[$i]-$h[$i-1]; $d = $l[$i-1]-$l[$i]
        if ($u -gt $d -and $u -gt 0) { $up = $u }
        if ($d -gt $u -and $d -gt 0) { $dn = $d }
        if ($up -gt $dn) { $diLong++ } else { $diShort++ }
    }
}
Write-Output "DI direction on ADX>25 candles: +DI > -DI = $diLong, -DI > +DI = $diShort"

# ===== Phase 3: TP/SL Optimization =====
Write-Output "`n========================================"
Write-Output "  Phase 3: TP/SL Optimization"
Write-Output "========================================"

$tps = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0)
$sls = @(0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0)
$fee = 0.1
$fullResults = @()

foreach ($tp in $tps) {
    foreach ($sl in $sls) {
        $w = 0; $l = 0; $pnl = 0
        for ($rel = 0; $rel -lt $c.Count - $si - 3; $rel++) {
            $idx = $rel + $si
            if ($adx[$idx] -le 25) { continue }
            $r = Test-TP-SL $c $h $l $idx $tp $sl $fee
            if ($r) {
                if ($r.result -eq "TP") { $w++ } else { $l++ }
                $pnl += $r.pnl
            }
        }
        $t = $w + $l
        if ($t -ge 5) {
            $wr = [Math]::Round($w/$t*100, 1)
            $avgPnl = [Math]::Round($pnl/$t, 6)
            $s = [Math]::Round($wr*$t/100, 1)
            $fullResults += @{TP=$tp; SL=$sl; WR=$wr; T=$t; W=$w; L=$l; Pnl=[Math]::Round($pnl,4); AvgPnl=$avgPnl; S=$s}
        }
    }
}
$fullResults = $fullResults | Sort-Object S -Descending

Write-Output "`nTop 15 by S-score (WR x Trades):"
Write-Output ("{0,-6}{1,-6}{2,-8}{3,-8}{4,-10}{5,-10}{6,-8}" -f "TP%","SL%","WR%","Trades","TotalPnL","AvgPnL","S")
$fullResults | Select-Object -First 15 | % {
    Write-Output ("{0,-6}{1,-6}{2,-8}{3,-8}{4,-10}{5,-10}{6,-8}" -f $_.TP,$_.SL,$_.WR,$_.T,$_.Pnl,$_.AvgPnl,$_.S)
}

$rrFull = $fullResults | ? { $_.TP -ge $_.SL } | Sort-Object S -Descending
Write-Output "`nBest 1:1 R:R (TP>=SL) by S-score:"
$rrFull | Select-Object -First 5 | % {
    Write-Output ("  TP={0}% SL={1}% | WR={2}% | T={3} | PnL={4} | S={5}" -f $_.TP,$_.SL,$_.WR,$_.T,$_.Pnl,$_.S)
}

# ===== Walk-Forward: 3-fold =====
Write-Output "`n========================================"
Write-Output "  Walk-Forward (3-fold cross-val)"
Write-Output "========================================"

$folds = @(
    @{name="Fold1 (0-65%)"; trainEnd=[Math]::Floor(($c.Count-$si)*0.5)+$si; testEnd=[Math]::Floor(($c.Count-$si)*0.65)+$si},
    @{name="Fold2 (25-75%)"; trainEnd=[Math]::Floor(($c.Count-$si)*0.625)+$si; testEnd=[Math]::Floor(($c.Count-$si)*0.75)+$si},
    @{name="Fold3 (50-90%)"; trainEnd=[Math]::Floor(($c.Count-$si)*0.75)+$si; testEnd=[Math]::Floor(($c.Count-$si)*0.9)+$si}
)

$allTestW = 0; $allTestL = 0; $allTestPnl = 0

foreach ($fold in $folds) {
    # Train
    $ft = @()
    foreach ($tp in $tps) {
        foreach ($sl in $sls) {
            $w=0;$l=0;$pnl=0
            for ($rel=0; $rel -lt $fold.trainEnd-$si-3; $rel++) {
                $idx = $rel+$si
                if ($adx[$idx] -le 25) { continue }
                $r = Test-TP-SL $c $h $l $idx $tp $sl $fee
                if ($r) { if ($r.result -eq "TP") { $w++ } else { $l++ }; $pnl += $r.pnl }
            }
            $t=$w+$l
            if ($t -ge 5) {
                $wr=[Math]::Round($w/$t*100,1); $s=[Math]::Round($wr*$t/100,1)
                $ft += @{TP=$tp;SL=$sl;WR=$wr;T=$t;S=$s;Pnl=[Math]::Round($pnl,4)}
            }
        }
    }
    $bestF = $ft | Sort-Object S -Descending | Select-Object -First 1
    if (-not $bestF) { Write-Output "$($fold.name): No training config found"; continue }

    # Test
    $tw=0;$tl=0;$tpnl=0
    for ($i=$fold.trainEnd; $i -lt [Math]::Min($fold.testEnd, $c.Count-3); $i++) {
        if ($adx[$i] -le 25) { continue }
        $r = Test-TP-SL $c $h $l $i $bestF.TP $bestF.SL $fee
        if ($r) { if ($r.result -eq "TP") { $tw++ } else { $tl++ }; $tpnl += $r.pnl }
    }
    $tt=$tw+$tl
    $twr=if($tt){[Math]::Round($tw/$tt*100,1)}else{0}
    Write-Output ("{0,-20} Train: TP={1}% SL={2}% (S={3}, T={4}) | Test: {5}t WR={6}% PnL={7}" -f
        $fold.name,$bestF.TP,$bestF.SL,$bestF.S,$bestF.T,$tt,$twr,[Math]::Round($tpnl,4))
    $allTestW+=$tw; $allTestL+=$tl; $allTestPnl+=$tpnl
}
$allTestT=$allTestW+$allTestL
$allTestWR=if($allTestT){[Math]::Round($allTestW/$allTestT*100,1)}else{0}
Write-Output ("TOTAL: {0}t WR={1}% PnL={2}" -f $allTestT,$allTestWR,[Math]::Round($allTestPnl,4)) -ForegroundColor Cyan

# ===== 3-Month Forward =====
Write-Output "`n========================================"
Write-Output "  3-Month Forward Simulation"
Write-Output "========================================"

$fwdStart = [Math]::Max(0, $c.Count - 180)

# Train on data before forward period
$fwdTrain = @()
foreach ($tp in $tps) {
    foreach ($sl in $sls) {
        $w=0;$l=0;$pnl=0
        for ($rel=0; $rel -lt $fwdStart-$si-3; $rel++) {
            $idx = $rel+$si
            if ($adx[$idx] -le 25) { continue }
            $r = Test-TP-SL $c $h $l $idx $tp $sl $fee
            if ($r) { if ($r.result -eq "TP") { $w++ } else { $l++ }; $pnl += $r.pnl }
        }
        $t=$w+$l
        if ($t -ge 5) {
            $wr=[Math]::Round($w/$t*100,1); $s=[Math]::Round($wr*$t/100,1)
            $fwdTrain += @{TP=$tp;SL=$sl;WR=$wr;T=$t;S=$s;Pnl=[Math]::Round($pnl,4)}
        }
    }
}
$bestFwd = $fwdTrain | Sort-Object S -Descending | Select-Object -First 1
if (-not $bestFwd) { $bestFwd = $fullResults[0]; Write-Output "Not enough training, using full-sample best" }

Write-Output "Training TP=$($bestFwd.TP)% SL=$($bestFwd.SL)% (trained on $($fwdStart-$si) candles)"

$fwdCap=100.0; $fwdPeak=100.0; $fwdTrades=@(); $fwdSkip=$false
for ($i=$fwdStart; $i -lt $c.Count-3; $i++) {
    if ($fwdSkip) { $fwdSkip=$false; continue }
    if ($adx[$i] -gt 25) {
        $r = Test-TP-SL $c $h $l $i $bestFwd.TP $bestFwd.SL $fee
        if ($r) {
            $fwdCap += $r.pnl
            if ($fwdCap -gt $fwdPeak) { $fwdPeak = $fwdCap }
            $fwdTrades += @{entry=$c[$i]; exit=$r.exitPrice; result=$r.result; pnl=$r.pnl; entryTs=$ts[$i]; exitTs=$ts[$r.exitIdx]}
            if ($r.result -eq "SL") { $fwdSkip = $true }
        }
    }
}

$fwdW = ($fwdTrades | ? { $_.result -eq "TP" } | Measure-Object).Count
$fwdL = ($fwdTrades | ? { $_.result -eq "SL" } | Measure-Object).Count
$fwdT = $fwdTrades.Count
$fwdWR = if ($fwdT) { [Math]::Round($fwdW/$fwdT*100,1) } else { 0 }
$fwdRet = [Math]::Round(($fwdCap/100-1)*100, 2)

Write-Output "3-Month Forward: $fwdT trades, WR=$fwdWR%, Return=$fwdRet%"

# ===== SUMMARY =====
Write-Output "`n========================================"
Write-Output "  SUMMARY"
Write-Output "========================================"
Write-Output "Strategy: ICP 12h ADX>25 LONG-only (no direction filter)"
Write-Output ""

Write-Output "Full-sample best TP/SL:"
$fullResults[0..3] | % { Write-Output "  TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | T=$($_.T) | PnL=$($_.Pnl) | S=$($_.S)" }

Write-Output "`nRecommended:"
Write-Output "  TP=$($fullResults[0].TP)% SL=$($fullResults[0].SL)%"
Write-Output "  (Highest S-score, full-sample)"

Write-Output "`nWalk-forward validation:"
Write-Output "  $allTestT trades total, WR=$allTestWR%, PnL=$([Math]::Round($allTestPnl,4))"
Write-Output "  3-month forward: $fwdT trades, WR=$fwdWR%, Return=$fwdRet%"

# Best TP>=SL recommended
$bestRR = $rrFull[0]
if ($bestRR) {
    Write-Output "`nBest 1:1 R:R config:"
    Write-Output "  TP=$($bestRR.TP)% SL=$($bestRR.SL)% | WR=$($bestRR.WR)% | T=$($bestRR.T) | S=$($bestRR.S)"
}
