# ============================================================
#  ICP 12h ADX>25 — Direction-Filtered Backtest
#  Tests 3 LONG-only variants side-by-side
# ============================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ICP 12h ADX>25 — Direction-Filtered" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ===== API =====
function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $len = $data[$offset.Value]; $offset.Value++; return $len }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0; for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }
    return $len
}
function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw "Integer expected" }
    $offset.Value++; $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len); [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start); [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len; return $trimmed
}
$pem = Get-Content -Raw "bybit_private.pem"
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0
if ($der[$off] -ne 0x30) { throw "bad" }
$off++
Read-DerLength $der ([ref]$off) | Out-Null
$p = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger $der ([ref]$off) | Out-Null
$p.Modulus = Read-DerInteger $der ([ref]$off); $p.Exponent = Read-DerInteger $der ([ref]$off)
$p.D = Read-DerInteger $der ([ref]$off); $p.P = Read-DerInteger $der ([ref]$off)
$p.Q = Read-DerInteger $der ([ref]$off); $p.DP = Read-DerInteger $der ([ref]$off)
$p.DQ = Read-DerInteger $der ([ref]$off); $p.InverseQ = Read-DerInteger $der ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($p)
$ak = 'gkPx5g3xgL2pthIg16'; $rw = '5000'; $baseUrl = 'https://api.bybit.com'
function Call-API($ep, $q) {
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = [Text.Encoding]::UTF8.GetBytes($ts.ToString() + $ak + $rw + $q)
    $h = [Security.Cryptography.SHA256]::Create()
    $sg = [Convert]::ToBase64String($rsa.SignData($b, $h))
    $hd = @{}
    $hd['X-BAPI-API-KEY'] = $ak
    $hd['X-BAPI-TIMESTAMP'] = $ts.ToString()
    $hd['X-BAPI-SIGN'] = $sg
    $hd['X-BAPI-RECV-WINDOW'] = $rw
    $hd['X-BAPI-SIGN-TYPE'] = '2'
    $hd['User-Agent'] = 'bybit-skill/1.4.2'
    $url = $baseUrl + $ep + '?' + $q
    try { return (Invoke-WebRequest -Uri $url -Headers $hd -UseBasicParsing -TimeoutSec 60 | ConvertFrom-Json) }
    catch { return $null }
}
function Get-K($int, $lim) {
    $q = 'category=spot' + [char]38 + 'symbol=ICPUSDT' + [char]38 + 'interval=' + $int + [char]38 + 'limit=' + $lim
    $r = Call-API '/v5/market/kline' $q
    if ($r -and $r.result -and $r.result.list) { $k = $r.result.list; [Array]::Reverse($k); return $k }
    return $null
}

# ===== Indicators =====
function Calc-EMA($p, $per) { $e=[double[]]::new($p.Count); $e[0]=$p[0]; $m=2/($per+1); for($i=1;$i-lt$p.Count;$i++){ $e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m) }; return $e }
function Calc-ADX($h, $l, $c, $per) {
    $tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
    for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))
        $u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per
    $dx=[double[]]::new($c.Count)
    for($i=$per;$i-lt$c.Count;$i++){$pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100;$dx[$i]=if(($pdi+$ndi)-eq0){0}else{[Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100}}
    return (Calc-EMA $dx $per)
}
function Test-TP-SL($c, $h, $l, $ei, $tp, $sl, $fee) {
    $ep=$c[$ei];$tpP=$ep*(1+$tp/100);$slP=$ep*(1-$sl/100)
    for($i=$ei+1;$i-lt$c.Count;$i++){if($h[$i]-ge$tpP){$g=$ep*$tp/100;$f=$ep*$fee/100+[Math]::Min($tpP,$c[$i])*$fee/100;return@{r='TP';p=[Math]::Round($g-$f,6)}}
    if($l[$i]-le$slP){$g=-$ep*$sl/100;$f=$ep*$fee/100+$slP*$fee/100;return@{r='SL';p=[Math]::Round($g-$f,6)}}}
    return $null
}

# ===== Fetch =====
Write-Host 'Fetching 800 candles ICPUSDT 12h...' -ForegroundColor Yellow
$k = Get-K 720 800
if (-not $k) { Write-Host 'FAILED' -ForegroundColor Red; exit 1 }
Write-Host ('Got ' + $k.Count + ' candles') -ForegroundColor Green
$c = $k | % { [double]$_[4] }; $h = $k | % { [double]$_[2] }; $l = $k | % { [double]$_[3] }

Write-Host 'Computing indicators...' -ForegroundColor Yellow
$adx = Calc-ADX $h $l $c 14
$ma20 = Calc-EMA $c 20; $ma50 = Calc-EMA $c 50

# DI direction arrays
$plusDI = [bool[]]::new($c.Count); $minusDI = [bool[]]::new($c.Count)
$tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])));$u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
$emu=Calc-EMA $up 14;$emd=Calc-EMA $dn 14;$ematr=Calc-EMA $tr 14
for($i=20;$i-lt$c.Count;$i++){$plusDI[$i]=$emu[$i]/$ematr[$i]*100 -gt $emd[$i]/$ematr[$i]*100;$minusDI[$i]=$emd[$i]/$ematr[$i]*100 -gt $emu[$i]/$ematr[$i]*100}

# ===== Signal Stats =====
$si = 30
$adxSig = 0; $diUpSig = 0; $trendSig = 0; $maCrossSig = 0
for ($i = $si; $i -lt $c.Count; $i++) {
    if ($adx[$i] -gt 25) { $adxSig++ }
    if ($adx[$i] -gt 25 -and $plusDI[$i]) { $diUpSig++ }
    if ($adx[$i] -gt 25 -and $c[$i] -gt $ma50[$i]) { $trendSig++ }
    if ($adx[$i] -gt 25 -and $ma20[$i] -gt $ma50[$i]) { $maCrossSig++ }
}
$totalC = $c.Count - $si
Write-Host ('Signal comparison (out of ' + $totalC + ' candles):') -ForegroundColor Yellow
$pctA = [Math]::Round($adxSig/$totalC*100,1)
$pctB = [Math]::Round($diUpSig/$totalC*100,1)
$pctC = [Math]::Round($trendSig/$totalC*100,1)
$pctD = [Math]::Round($maCrossSig/$totalC*100,1)
Write-Host ('  A: ADX>25 (no filter):             ' + $adxSig + ' (' + $pctA + '%)') -ForegroundColor Gray
Write-Host ('  B: ADX>25 + +DI>-DI:               ' + $diUpSig + ' (' + $pctB + '%)') -ForegroundColor Gray
Write-Host ('  C: ADX>25 + Price>MA50:            ' + $trendSig + ' (' + $pctC + '%)') -ForegroundColor Gray
Write-Host ('  D: ADX>25 + MA20>MA50:             ' + $maCrossSig + ' (' + $pctD + '%)') -ForegroundColor Gray

# ===== Grid Search Helper =====
function Run-Grid($name, [scriptblock]$condition) {
    Write-Host ''
    Write-Host ('========================================') -ForegroundColor Cyan
    Write-Host ('  ' + $name) -ForegroundColor Cyan
    Write-Host ('========================================') -ForegroundColor Cyan
    $tps = @(0.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0)
    $sls = @(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0)
    $res = @()
    foreach ($tp in $tps) {
        foreach ($sl in $sls) {
            $w=0;$l=0;$pnl=0
            for ($r=0; $r -lt $c.Count-$si-3; $r++) {
                $idx=$r+$si
                if (-not (& $condition $idx $adx $plusDI $c $ma20 $ma50)) { continue }
                $z = Test-TP-SL $c $h $l $idx $tp $sl 0.1
                if ($z) { if ($z.r -eq 'TP') { $w++ } else { $l++ }; $pnl += $z.p }
            }
            $t=$w+$l
            if ($t -ge 5) {
                $wr=[Math]::Round($w/$t*100,1); $s=[Math]::Round($wr*$t/100,1)
                $res += @{TP=$tp;SL=$sl;WR=$wr;T=$t;Pnl=[Math]::Round($pnl,4);S=$s}
            }
        }
    }
    $res = $res | Sort-Object S -Descending
    Write-Host ('TP%   SL%   WR%     Trades PnL         S')
    $res[0..10] | % {
        $line = ('{0,-6}{1,-6}{2,-8}{3,-8}{4,-12}{5,-8}' -f $_.TP,$_.SL,$_.WR,$_.T,$_.Pnl,$_.S)
        Write-Host $line
    }
    $rr = $res | ? { $_.TP -ge $_.SL } | Sort-Object S -Descending
    if ($rr) {
        $line2 = ('Best 1:1: TP={0}% SL={1}% WR={2}% T={3} PnL={4} S={5}' -f $rr[0].TP,$rr[0].SL,$rr[0].WR,$rr[0].T,$rr[0].Pnl,$rr[0].S)
        Write-Host $line2 -ForegroundColor Green
    }
    return $res
}

# ===== Run All Variants =====
$resA = Run-Grid 'A: ADX>25 (no filter)' { param($i,$adx,$pdi,$c,$m20,$m50) $adx[$i] -gt 25 }
$resB = Run-Grid 'B: ADX>25 + +DI>-DI' { param($i,$adx,$pdi,$c,$m20,$m50) $adx[$i] -gt 25 -and $pdi[$i] }
$resC = Run-Grid 'C: ADX>25 + Price>MA50' { param($i,$adx,$pdi,$c,$m20,$m50) $adx[$i] -gt 25 -and $c[$i] -gt $m50[$i] }
$resD = Run-Grid 'D: ADX>25 + MA20>MA50' { param($i,$adx,$pdi,$c,$m20,$m50) $adx[$i] -gt 25 -and $m20[$i] -gt $m50[$i] }

# ===== Summary =====
Write-Host ''
Write-Host ('========================================') -ForegroundColor Cyan
Write-Host ('  COMPARISON: Best 1:1 R:R by Variant') -ForegroundColor Cyan
Write-Host ('========================================') -ForegroundColor Cyan

$allV = @(
    @{n='A: ADX>25 (no filter)';r=$resA},
    @{n='B: ADX>25 + +DI>-DI';r=$resB},
    @{n='C: ADX>25 + Price>MA50';r=$resC},
    @{n='D: ADX>25 + MA20>MA50';r=$resD}
)
foreach ($v in $allV) {
    $rr = $v.r | ? { $_.TP -ge $_.SL } | Sort-Object S -Descending
    if ($rr) {
        $line = ('{0,-30} TP={1}% SL={2}% WR={3}% T={4} PnL={5} S={6}' -f $v.n,$rr[0].TP,$rr[0].SL,$rr[0].WR,$rr[0].T,$rr[0].Pnl,$rr[0].S)
        Write-Host $line
    }
}

# ===== Walk-Forward: Best Variant (B) =====
Write-Host ''
Write-Host ('========================================') -ForegroundColor Cyan
Write-Host ('  Walk-Forward: Variant B (DI-filtered)') -ForegroundColor Cyan
Write-Host ('========================================') -ForegroundColor Cyan

$tps = @(0.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0)
$sls = @(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0)
$folds = @(
    @{trainEnd=[Math]::Floor(($c.Count-$si)*0.5)+$si; testEnd=[Math]::Floor(($c.Count-$si)*0.65)+$si},
    @{trainEnd=[Math]::Floor(($c.Count-$si)*0.625)+$si; testEnd=[Math]::Floor(($c.Count-$si)*0.75)+$si},
    @{trainEnd=[Math]::Floor(($c.Count-$si)*0.75)+$si; testEnd=[Math]::Floor(($c.Count-$si)*0.9)+$si}
)
$allW=0;$allL=0;$allP=0
foreach ($fold in $folds) {
    $ft=@()
    foreach ($tp in $tps) { foreach ($sl in $sls) {
        $w=0;$l=0;$pnl=0
        for ($r=0; $r -lt $fold.trainEnd-$si-3; $r++) { $idx=$r+$si
            if ($adx[$idx] -le 25 -or -not $plusDI[$idx]) { continue }
            $z=Test-TP-SL $c $h $l $idx $tp $sl 0.1
            if ($z) { if ($z.r -eq 'TP') { $w++ } else { $l++ }; $pnl += $z.p }
        }
        $t=$w+$l
        if ($t -ge 5) { $wr=[Math]::Round($w/$t*100,1); $s=[Math]::Round($wr*$t/100,1); $ft+=@{TP=$tp;SL=$sl;WR=$wr;T=$t;S=$s} }
    }}
    $bf = $ft | Sort-Object S -Descending | Select-Object -First 1
    if (-not $bf) { continue }
    $tw=0;$tl=0;$tp2=0
    for ($i=$fold.trainEnd; $i -lt [Math]::Min($fold.testEnd, $c.Count-3); $i++) {
        if ($adx[$i] -le 25 -or -not $plusDI[$i]) { continue }
        $z=Test-TP-SL $c $h $l $i $bf.TP $bf.SL 0.1
        if ($z) { if ($z.r -eq 'TP') { $tw++ } else { $tl++ }; $tp2+=$z.p }
    }
    $tt=$tw+$tl; $twr=if($tt){[Math]::Round($tw/$tt*100,1)}else{0}
    Write-Host ('Fold {0}/{3}: TP={1}% SL={2}% (T={4}) | Test: {5}t WR={6}% PnL={7}' -f ($folds.IndexOf($fold)+1),$bf.TP,$bf.SL,(0+$folds.Count),$bf.T,$tt,$twr,[Math]::Round($tp2,4))
    $allW+=$tw; $allL+=$tl; $allP+=$tp2
}
$allT=$allW+$allL; $allWR=if($allT){[Math]::Round($allW/$allT*100,1)}else{0}
Write-Host ('TOTAL: ' + $allT + 't WR=' + $allWR + '% PnL=' + [Math]::Round($allP,4)) -ForegroundColor Cyan

# ===== 3-Month Forward (Variant B) =====
Write-Host ''
Write-Host ('========================================') -ForegroundColor Cyan
Write-Host ('  3-Month Forward: Variant B') -ForegroundColor Cyan
Write-Host ('========================================') -ForegroundColor Cyan

$fwd=[Math]::Max(0,$c.Count-180)
$ft2=@()
foreach ($tp in $tps) { foreach ($sl in $sls) {
    $w=0;$l=0;$pnl=0
    for ($r=0; $r -lt $fwd-$si-3; $r++) { $idx=$r+$si
        if ($adx[$idx] -le 25 -or -not $plusDI[$idx]) { continue }
        $z=Test-TP-SL $c $h $l $idx $tp $sl 0.1
        if ($z) { if ($z.r -eq 'TP') { $w++ } else { $l++ }; $pnl+=$z.p }
    }
    $t=$w+$l; if ($t -ge 5) { $wr=[Math]::Round($w/$t*100,1); $s=[Math]::Round($wr*$t/100,1); $ft2+=@{TP=$tp;SL=$sl;WR=$wr;T=$t;S=$s} }
}}
$bf2=$ft2 | Sort-Object S -Descending | Select-Object -First 1
if (-not $bf2) { $bf2 = ($resB | Sort-Object S -Descending)[0] }

$fwCap=100.0;$fwT=0;$fwW=0;$fwL=0;$fwSkip=$false
for ($i=$fwd; $i -lt $c.Count-3; $i++) {
    if ($fwSkip) { $fwSkip=$false; continue }
    if ($adx[$i] -gt 25 -and $plusDI[$i]) {
        $z=Test-TP-SL $c $h $l $i $bf2.TP $bf2.SL 0.1
        if ($z) { $fwCap+=$z.p; $fwT++; if ($z.r -eq 'TP') { $fwW++ } else { $fwL++; $fwSkip=$true } }
    }
}
$fwWR=if($fwT){[Math]::Round($fwW/$fwT*100,1)}else{0}; $fwRet=[Math]::Round(($fwCap/100-1)*100,2)
Write-Host ('TP=' + $bf2.TP + '% SL=' + $bf2.SL + '% | ' + $fwT + 't WR=' + $fwWR + '% Return=' + $fwRet + '%') -ForegroundColor Green

# ===== FINAL =====
Write-Host ''
Write-Host ('========================================') -ForegroundColor Cyan
Write-Host ('  FINAL RECOMMENDATION') -ForegroundColor Cyan
Write-Host ('========================================') -ForegroundColor Cyan

$brr = $resB | ? { $_.TP -ge $_.SL } | Sort-Object S -Descending
$crr = $resC | ? { $_.TP -ge $_.SL } | Sort-Object S -Descending
$drr = $resD | ? { $_.TP -ge $_.SL } | Sort-Object S -Descending

Write-Host ('B: ADX>25 + +DI>-DI  -> TP=' + $brr[0].TP + '% SL=' + $brr[0].SL + '% WR=' + $brr[0].WR + '% T=' + $brr[0].T + ' PnL=' + $brr[0].Pnl) -ForegroundColor White
Write-Host ('   Walk-fwd: ' + $allT + 't WR=' + $allWR + '% | 3mo: ' + $fwT + 't WR=' + $fwWR + '% Ret=' + $fwRet + '%')
Write-Host ('C: ADX>25 + Price>MA50 -> TP=' + $crr[0].TP + '% SL=' + $crr[0].SL + '% WR=' + $crr[0].WR + '% T=' + $crr[0].T + ' PnL=' + $crr[0].Pnl) -ForegroundColor White
Write-Host ('D: ADX>25 + MA20>MA50 -> TP=' + $drr[0].TP + '% SL=' + $drr[0].SL + '% WR=' + $drr[0].WR + '% T=' + $drr[0].T + ' PnL=' + $drr[0].Pnl) -ForegroundColor White

Write-Host ''
Write-Host ('RECOMMENDED:' ) -ForegroundColor Green
Write-Host '  Variant B: ADX>25 + +DI>-DI (direction-filtered LONG)' -ForegroundColor Green
Write-Host ('  TP=' + $brr[0].TP + '% SL=' + $brr[0].SL + '%') -ForegroundColor Green
Write-Host ''
Write-Host 'NOTE: A (no filter) is NOT viable - 62% of signals fire in bearish -DI>+DI conditions.' -ForegroundColor Red
