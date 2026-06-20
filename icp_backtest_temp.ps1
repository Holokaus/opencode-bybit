function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $len = $data[$offset.Value]; $offset.Value++; return $len }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0; for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }
    return $len
}
function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw "Expected INTEGER" }
    $offset.Value++; $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len); [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start); [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len; return $trimmed
}
$pem = Get-Content -Raw "bybit_private.pem"
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64); $off = 0
if ($der[$off] -ne 0x30) { throw "Not SEQUENCE" }; $off++
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
$apiKey = "gkPx5g3xgL2pthIg16"; $recvWindow = "5000"; $baseUrl = "https://api.bybit.com"

function Call-Bybit { param($endpoint, $query)
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $paramStr = "${timestamp}${apiKey}${recvWindow}${query}"
    $dataBytes = [Text.Encoding]::UTF8.GetBytes($paramStr)
    $hasher = [Security.Cryptography.SHA256]::Create()
    $sigBytes = $rsa.SignData($dataBytes, $hasher)
    $signature = [Convert]::ToBase64String($sigBytes)
    $headers = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$timestamp";"X-BAPI-SIGN"=$signature;"X-BAPI-RECV-WINDOW"=$recvWindow;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2";"X-Referer"="bybit-skill"}
    try { $resp = Invoke-WebRequest -Uri "$baseUrl$endpoint`?$query" -Headers $headers -UseBasicParsing -TimeoutSec 60; return $resp.Content | ConvertFrom-Json }
    catch { return $null }
}
function Get-K { param($interval, $limit)
    $q = "category=spot" + [char]38 + "symbol=ICPUSDT" + [char]38 + "interval=" + $interval + [char]38 + "limit=" + $limit
    $r = Call-Bybit "/v5/market/kline" $q
    if ($r -and $r.retCode -eq 0 -and $r.result -and $r.result.list) { $k = $r.result.list; [Array]::Reverse($k); return $k }
    return $null
}
function Calc-EMA { param($p, $per)
    $e = [double[]]::new($p.Count); $e[0] = $p[0]; $m = 2/($per+1)
    for ($i = 1; $i -lt $p.Count; $i++) { $e[$i] = $p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}
function Calc-ADX { param($h, $l, $c, $per)
    $tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
    for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))
        $u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per
    $dx=[double[]]::new($c.Count)
    for($i=$per;$i-lt$c.Count;$i++){$pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100;$dx[$i]=if(($pdi+$ndi)-eq0){0}else{[Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100}}
    return (Calc-EMA $dx $per)
}
function Test-TP-SL { param($c, $h, $l, $entryIdx, $tpPct, $slPct, $feePct)
    $ep = $c[$entryIdx]; $tp = $ep * (1 + $tpPct/100); $sl = $ep * (1 - $slPct/100)
    for ($i = $entryIdx+1; $i -lt $c.Count; $i++) {
        if ($h[$i] -ge $tp) { $exitPrice = [Math]::Min($tp, $c[$i]); $grossPnl = $ep * $tpPct / 100; $fee = $ep*$feePct/100 + $exitPrice*$feePct/100; return @{r="TP"; pnl=[Math]::Round($grossPnl-$fee,6)} }
        if ($l[$i] -le $sl) { $exitPrice = $sl; $grossPnl = -$ep * $slPct / 100; $fee = $ep*$feePct/100 + $exitPrice*$feePct/100; return @{r="SL"; pnl=[Math]::Round($grossPnl-$fee,6)} }
    }
    return $null
}

Write-Host "Fetching 900 candles ICPUSDT 12h..." -ForegroundColor Yellow
$k = Get-K 720 900
if (-not $k) { Write-Host "FAILED" -ForegroundColor Red; exit 1 }
Write-Host ("Got " + $k.Count + " candles") -ForegroundColor Green
$c = $k | % { [double]$_[4] }; $h = $k | % { [double]$_[2] }; $l = $k | % { [double]$_[3] }

Write-Host "Computing indicators..." -ForegroundColor Yellow
$adx = Calc-ADX $h $l $c 14
$ma20 = Calc-EMA $c 20; $ma50 = Calc-EMA $c 50; $ma200 = Calc-EMA $c 200

$plusDI = [bool[]]::new($c.Count); $minusDI = [bool[]]::new($c.Count)
$tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])));$u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
$emu=Calc-EMA $up 14;$emd=Calc-EMA $dn 14;$ematr=Calc-EMA $tr 14
for($i=20;$i-lt$c.Count;$i++){$plusDI[$i]=$emu[$i]/$ematr[$i]*100 -gt $emd[$i]/$ematr[$i]*100;$minusDI[$i]=$emd[$i]/$ematr[$i]*100 -gt $emu[$i]/$ematr[$i]*100}

$si = 50; $tps = @(0.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0); $sls = @(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0); $fee = 0.1

function Eval-Strat { param($name, $sigArr)
    $res = @()
    foreach ($tp in $tps) { foreach ($sl in $sls) {
        $w=0;$l=0;$pnl=0
        for ($rel=0; $rel -lt $sigArr.Count-3; $rel++) {
            if (-not $sigArr[$rel]) { continue }
            $idx = $rel + $si
            $z = Test-TP-SL $c $h $l $idx $tp $sl $fee
            if ($z) { if ($z.r -eq "TP") { $w++ } else { $l++ }; $pnl += $z.pnl }
        }
        $t=$w+$l
        if ($t -ge 5) {
            $wr=[Math]::Round($w/$t*100,1); $ev = ($wr/100*$tp) - ((1-$wr/100)*$sl) - (2*$fee)
            $s=[Math]::Round($wr*$t/100,1); $res += @{TP=$tp;SL=$sl;WR=$wr;T=$t;Pnl=[Math]::Round($pnl,4);EV=$ev;S=$s}
        }
    }}
    $res = $res | Sort-Object S -Descending
    $bestEV = ($res | Sort-Object EV -Descending)[0]
    $bestRR = ($res | Where-Object { $_.TP -ge $_.SL } | Sort-Object S -Descending)[0]
    Write-Host ("`n" + $name) -ForegroundColor Cyan
    $res[0..5] | % {
        Write-Host ("  TP=" + $_.TP + " SL=" + $_.SL + " WR=" + $_.WR + " T=" + $_.T + " PnL=" + $_.Pnl + " EV=" + [Math]::Round($_.EV,4) + " S=" + $_.S)
    }
    if ($bestRR) { Write-Host ("  Best 1:1: TP=" + $bestRR.TP + " SL=" + $bestRR.SL + " WR=" + $bestRR.WR + " T=" + $bestRR.T + " PnL=" + $bestRR.Pnl + " EV=" + [Math]::Round($bestRR.EV,4)) -ForegroundColor Yellow }
    if ($bestEV) { Write-Host ("  Best EV: TP=" + $bestEV.TP + " SL=" + $bestEV.SL + " WR=" + $bestEV.WR + " T=" + $bestEV.T + " PnL=" + $bestEV.Pnl + " EV=" + [Math]::Round($bestEV.EV,4)) -ForegroundColor Green }
    return $res
}

Write-Host "Generating signals..." -ForegroundColor Yellow

# A: ADX>25 no filter
$sigA = [bool[]]::new($c.Count-$si)
for ($i = $si; $i -lt $c.Count; $i++) { $sigA[$i-$si] = $adx[$i] -gt 25 }
$resA = Eval-Strat "A: ADX>25 (no filter)" $sigA

# B: ADX>25 + +DI>-DI
$sigB = [bool[]]::new($c.Count-$si)
for ($i = $si; $i -lt $c.Count; $i++) { $sigB[$i-$si] = $adx[$i] -gt 25 -and $plusDI[$i] }
$resB = Eval-Strat "B: ADX>25 + +DI>-DI" $sigB

# C: MA20>MA50 (uptrend pure)
$sigC = [bool[]]::new($c.Count-$si)
for ($i = $si; $i -lt $c.Count; $i++) { $sigC[$i-$si] = $ma20[$i] -gt $ma50[$i] }
$resC = Eval-Strat "C: MA20>MA50 (uptrend)" $sigC

# D: Price>MA50 (uptrend pure)
$sigD = [bool[]]::new($c.Count-$si)
for ($i = $si; $i -lt $c.Count; $i++) { $sigD[$i-$si] = $c[$i] -gt $ma50[$i] }
$resD = Eval-Strat "D: Price>MA50 (uptrend)" $sigD

# E: MA20>MA200 (uptrend pure)
$sigE = [bool[]]::new($c.Count-$si)
for ($i = $si; $i -lt $c.Count; $i++) { $sigE[$i-$si] = $ma20[$i] -gt $ma200[$i] }
$resE = Eval-Strat "E: MA20>MA200 (uptrend)" $sigE

# F: ADX crosses above 25 (event)
$sigF = [bool[]]::new($c.Count-$si)
for ($rel = 1; $rel -lt $c.Count-$si; $rel++) { $i = $rel+$si; $sigF[$rel] = $adx[$i-1] -le 25 -and $adx[$i] -gt 25 }
$resF = Eval-Strat "F: ADX cross>25 (event)" $sigF

# G: +DI crosses above -DI (when ADX>20)
$pdiArr = [double[]]::new($c.Count); $mdiArr = [double[]]::new($c.Count)
for ($i = 20; $i -lt $c.Count; $i++) { $pdiArr[$i] = $emu[$i]/$ematr[$i]*100; $mdiArr[$i] = $emd[$i]/$ematr[$i]*100 }
$sigG = [bool[]]::new($c.Count-$si)
for ($rel = 1; $rel -lt $c.Count-$si; $rel++) { $i = $rel+$si
    $sigG[$rel] = $pdiArr[$i-1] -le $mdiArr[$i-1] -and $pdiArr[$i] -gt $mdiArr[$i] -and $adx[$i] -gt 20
}
$resG = Eval-Strat "G: +DI cross>-DI (ADX>20)" $sigG

# H: +DI crosses above -DI (no ADX req)
$sigH = [bool[]]::new($c.Count-$si)
for ($rel = 1; $rel -lt $c.Count-$si; $rel++) { $i = $rel+$si
    $sigH[$rel] = $pdiArr[$i-1] -le $mdiArr[$i-1] -and $pdiArr[$i] -gt $mdiArr[$i]
}
$resH = Eval-Strat "H: +DI cross>-DI (any)" $sigH

# I: Price crosses above MA50 (event)
$sigI = [bool[]]::new($c.Count-$si)
for ($rel = 1; $rel -lt $c.Count-$si; $rel++) { $i = $rel+$si
    $sigI[$rel] = $c[$i-1] -le $ma50[$i-1] -and $c[$i] -gt $ma50[$i]
}
$resI = Eval-Strat "I: Price cross>MA50 (event)" $sigI

# J: ADX>25 + Price>MA50 (combined)
$sigJ = [bool[]]::new($c.Count-$si)
for ($i = $si; $i -lt $c.Count; $i++) { $sigJ[$i-$si] = $adx[$i] -gt 25 -and $c[$i] -gt $ma50[$i] }
$resJ = Eval-Strat "J: ADX>25 + Price>MA50" $sigJ

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  COMPARISON: Best Config per Strategy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$all = @(
    @{n="A: ADX>25 (none)";r=$resA},@{n="B: ADX+DI dir";r=$resB},@{n="C: MA20>MA50";r=$resC},
    @{n="D: Px>MA50";r=$resD},@{n="E: MA20>MA200";r=$resE},@{n="F: ADX cross";r=$resF},
    @{n="G: DI cross>20";r=$resG},@{n="H: DI cross any";r=$resH},@{n="I: Px cross MA50";r=$resI},
    @{n="J: ADX+PxMA50";r=$resJ}
)

Write-Host ("{0,-20}{1,-8}{2,-8}{3,-8}{4,-10}{5,-10}{6,-10}" -f "Strategy","EV","WR","Trades","PnL","TP/SL","S")
foreach ($s in $all) {
    $be = ($s.r | Sort-Object EV -Descending)[0]
    if ($be) {
        Write-Host ("{0,-20}{1,-8}{2,-8}{3,-8}{4,-10}{5,-10}{6,-10}" -f $s.n,
            [Math]::Round($be.EV,4),$be.WR,$be.T,$be.Pnl,($be.TP.ToString()+"/"+$be.SL.ToString()),$be.S)
    }
}

# Also show best 1:1 R:R per strategy
Write-Host "`nBest 1:1 R:R (TP>=SL) per Strategy:" -ForegroundColor Yellow
foreach ($s in $all) {
    $br = ($s.r | Where-Object { $_.TP -ge $_.SL } | Sort-Object S -Descending)[0]
    if ($br) {
        Write-Host ("{0,-20} TP={1}% SL={2}% WR={3}% T={4} PnL={5} S={6}" -f $s.n,$br.TP,$br.SL,$br.WR,$br.T,$br.Pnl,$br.S)
    }
}
