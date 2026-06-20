function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $len = $data[$offset.Value]; $offset.Value++; return $len }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0; for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }; return $len
}
function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw "bad" }; $offset.Value++
    $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len); [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start); [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len; return $trimmed
}
$pem = [System.IO.File]::ReadAllText("bybit_private.pem")
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0; if ($der[$off] -ne 0x30) { throw "Not SEQUENCE" }; $off++
Read-DerLength -data $der -offset ([ref]$off) | Out-Null
$params = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger -data $der -offset ([ref]$off) | Out-Null    # skip version
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
$apiKey = "gkPx5g3xgL2pthIg16"; $recvWindow = "5000"
function Call-API {
    param($endpoint, $query)
    $timestamp = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $paramStr = "${timestamp}${apiKey}${recvWindow}${query}"
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($paramStr)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $sigBytes = $rsa.SignData($dataBytes, $hasher)
    $signature = [System.Convert]::ToBase64String($sigBytes)
    $headers = @{ "X-BAPI-API-KEY" = $apiKey; "X-BAPI-TIMESTAMP" = "$timestamp"; "X-BAPI-SIGN" = $signature; "X-BAPI-RECV-WINDOW" = $recvWindow; "X-BAPI-SIGN-TYPE" = "2"; "User-Agent" = "bybit-skill/1.4.2" }
    try { $resp = Invoke-WebRequest -Uri "https://api.bybit.com$endpoint`?$query" -Headers $headers -UseBasicParsing -TimeoutSec 20; return ($resp.Content | ConvertFrom-Json).result } catch { return $null }
}
function Get-K {
    param($int,$lim)
    $r=Call-API -endpoint "/v5/market/kline" -query "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if ($r -and $r.list) { $k = $r.list; [Array]::Reverse($k); return $k } else { return $null }
}
function Calc-RSI {
    param($p,$per)
    $g=[double[]]::new($p.Count); $l=[double[]]::new($p.Count)
    for($i=1; $i -lt $p.Count; $i++){ $d=$p[$i]-$p[$i-1]; if($d -ge 0){ $g[$i]=$d } else { $l[$i]=-$d } }
    $ag=($g[1..$per] | Measure-Object -Sum).Sum / $per; $al=($l[1..$per] | Measure-Object -Sum).Sum / $per
    $r=[double[]]::new($p.Count)
    for($i=$per; $i -lt $p.Count; $i++){
        if($i -gt $per){ $ag=(($ag*($per-1))+$g[$i])/$per; $al=(($al*($per-1))+$l[$i])/$per }
        $r[$i]=if($al -eq 0){ 100 } else { 100-(100/(1+($ag/$al))) }
    }
    return $r
}
function Calc-EMA {
    param($p,$per)
    $e=[double[]]::new($p.Count); $e[0]=$p[0]; $m=2/($per+1)
    for($i=1; $i -lt $p.Count; $i++){ $e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m) }
    return $e
}
function Calc-ATR {
    param($h,$l,$c,$per)
    $tr=[double[]]::new($c.Count)
    for($i=1; $i -lt $c.Count; $i++){
        $hl=$h[$i]-$l[$i]; $hc=[Math]::Abs($h[$i]-$c[$i-1]); $lc=[Math]::Abs($l[$i]-$c[$i-1])
        $tr[$i]=[Math]::Max($hl,[Math]::Max($hc,$lc))
    }
    $a=[double[]]::new($c.Count)
    if($c.Count -gt $per){
        $a[$per]=($tr[1..$per] | Measure-Object -Average).Average
        for($i=$per+1; $i -lt $c.Count; $i++){ $a[$i]=($a[$i-1]*($per-1)+$tr[$i])/$per }
    }
    return $a
}

Write-Output "================================================================"
Write-Output "  SOL COMPLETE ANALYSIS (REDO - CORRECT INDEXES)"
Write-Output "================================================================"
Write-Output ""

# ====== PHASE 1: RSI BRUTEFORCE ACROSS KEY TIMEFRAMES ======
Write-Output "--- Phase 1: RSI Bruteforce (focused grid) across timeframes ---"

# Focused: skip 1m/5m (noise), use coarser grid for speed
$tfs=@(@{n="15m";i="15"},@{n="30m";i="30"},@{n="1h";i="60"},@{n="2h";i="120"},@{n="4h";i="240"},@{n="6h";i="360"},@{n="12h";i="720"})
# Wider grid for initial scan: test period every 3, OB/OS every 5pts
$obLevels=@(60,64,68,72,76,80,84)
$osLevels=@(20,24,28,32,36,40,44)

$allResults=@()
$totalTF=$tfs.Count;$tfCount=0

foreach($tf in $tfs){
    $tfCount++
    Write-Output "  [$tfCount/$totalTF] Scanning $($tf.n)..."
    $klines=Get-K $tf.i 800
    if (-not $klines -or $klines.Count -lt 100) { Write-Output "    No data"; continue }
    $close = $klines | ForEach-Object { [double]$_[4] }
    $high = $klines | ForEach-Object { [double]$_[2] }
    $low = $klines | ForEach-Object { [double]$_[3] }
    $bestTF=$null; $bestScore=0
    foreach ($per in (5..50 | Where-Object { $_ % 3 -eq 2 -or $_ -eq 5 })) {
        $rsi=Calc-RSI $close $per
        $bestR=$null; $bestRScore=0
        $maxC=$close.Count
        # Precompute signal evaluation arrays
        foreach ($ob in $obLevels) {
            foreach ($os in $osLevels) {
                if ($os -ge ($ob - 15)) { continue }
                $lw=0; $ll=0; $sw=0; $sl=0
                for ($i=$per; $i -lt $maxC - 3; $i++) {
                    if ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0) {
                        $fL = ($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum
                        if (($close[$i] - $fL) / $close[$i] * 100 -gt 1.0) { $lw++ } else { $ll++ }
                    }
                    if ($rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100) {
                        $fH = ($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum
                        if (($fH - $close[$i]) / $close[$i] * 100 -gt 1.0) { $sw++ } else { $sl++ }
                    }
                }
                $tt=$lw+$ll+$sw+$sl
                if ($tt -ge 3) {
                    $wr=[Math]::Round(($lw+$sw)/$tt*100,1); $score=$wr*$tt
                    if ($score -gt $bestRScore) { $bestRScore=$score; $bestR=@{per=$per;ob=$ob;os=$os;wr=$wr;lw=$lw;ll=$ll;sw=$sw;sl=$sl;tt=$tt} }
                }
            }
        }
        if ($bestR -and $bestR.wr -gt $bestScore) { $bestScore=$bestR.wr; $bestTF=$bestR }
    }
    if ($bestTF) {
        $allResults += @{tf=$tf.n;per=$bestTF.per;ob=$bestTF.ob;os=$bestTF.os;wr=$bestTF.wr;tt=$bestTF.tt;lw=$bestTF.lw;ll=$bestTF.ll;sw=$bestTF.sw;sl=$bestTF.sl}
        Write-Host "    RSI($($bestTF.per)) OB=$($bestTF.ob) OS=$($bestTF.os) | WR=$($bestTF.wr)% | $($bestTF.tt) sigs" -ForegroundColor Green
    } else { Write-Output "    No significant signals" }
}

Write-Output "`n================================================================"
Write-Output "  PHASE 1 RESULTS: BEST RSI PARAMS PER TIMEFRAME"
Write-Output "================================================================"
$sortedResults=$allResults | Sort-Object wr -Descending
$sortedResults | ForEach-Object {
    Write-Output ("  {0,-4} | RSI({1,-2}) OB={2,-2} OS={3,-2} | WR={4,-5}% | {5,-3} sigs | L:{6}/{7} S:{8}/{9}" -f $_.tf,$_.per,$_.ob,$_.os,$_.wr,$_.tt,$_.lw,$_.ll,$_.sw,$_.sl)
}

Write-Host "`n=== WINNER: $($sortedResults[0].tf) RSI($($sortedResults[0].per)) OB=$($sortedResults[0].ob) OS=$($sortedResults[0].os) WR=$($sortedResults[0].wr)% ===" -ForegroundColor Green

# If we have results, pick the winner. Otherwise default to 4h RSI(41)
if ($sortedResults) {
    $winner=$sortedResults | Select-Object -First 1
} else {
    $winner = @{tf="4h";per=41;ob=68;os=42;wr=0}
}

# ====== PHASE 2: INDICATOR COMBINATIONS ON WINNING TF ======
Write-Output "`n================================================================"
Write-Output "  PHASE 2: INDICATOR COMBINATIONS ON $($winner.tf)"
Write-Output "================================================================"

$tf=$tfs|Where-Object{$_.n-eq$winner.tf}|Select-Object -First 1
$klines=Get-K $tf.i 800
$close=$klines|ForEach-Object{[double]$_[4]};$high=$klines|ForEach-Object{[double]$_[2]};$low=$klines|ForEach-Object{[double]$_[3]};$volume=$klines|ForEach-Object{[double]$_[5]}
$rsi=Calc-RSI $close $winner.per
$atr14=Calc-ATR $high $low $close 14
$ma50=Calc-EMA $close 50
$macdF=Calc-EMA $close 12;$macdS=Calc-EMA $close 26;$macdV=[double[]]::new($close.Count);for($i=0;$i-lt$close.Count;$i++){$macdV[$i]=$macdF[$i]-$macdS[$i]};$macdSig=Calc-EMA $macdV 9;$macdH=[double[]]::new($close.Count);for($i=0;$i-lt$close.Count;$i++){$macdH[$i]=$macdV[$i]-$macdSig[$i]}
$volMA=Calc-EMA $volume 20

# Test combos
$combos=@()
# RSI alone
$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($close[$i]-$fL)/$close[$i]*100-gt1.0){$lw++}else{$ll++}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$close[$i])/$close[$i]*100-gt1.0){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=if($tt-gt0){[Math]::Round(($lw+$sw)/$tt*100,1)}else{0}
Write-Output "  RSI alone: $wr`% ($tt sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

# RSI + MA(50) trend
$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0-and$close[$i]-gt$ma50[$i]){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($close[$i]-$fL)/$close[$i]*100-gt1.0){$lw++}else{$ll++}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100-and$close[$i]-lt$ma50[$i]){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$close[$i])/$close[$i]*100-gt1.0){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=if($tt-gt0){[Math]::Round(($lw+$sw)/$tt*100,1)}else{0}
Write-Output "  RSI+MA50: $wr`% ($tt sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

# RSI + Volume
$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0-and$volume[$i]-gt$volMA[$i]*0.8){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($close[$i]-$fL)/$close[$i]*100-gt1.0){$lw++}else{$ll++}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100-and$volume[$i]-gt$volMA[$i]*0.8){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$close[$i])/$close[$i]*100-gt1.0){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=if($tt-gt0){[Math]::Round(($lw+$sw)/$tt*100,1)}else{0}
Write-Output "  RSI+Volume: $wr`% ($tt sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

# RSI + MACD
$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0-and$macdH[$i]-gt0){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($close[$i]-$fL)/$close[$i]*100-gt1.0){$lw++}else{$ll++}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100-and$macdH[$i]-lt0){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$close[$i])/$close[$i]*100-gt1.0){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=if($tt-gt0){[Math]::Round(($lw+$sw)/$tt*100,1)}else{0}
Write-Output "  RSI+MACD: $wr`% ($tt sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

# RSI + ATR regime (volatility above average)
$atrAvg=($atr14[50..($atr14.Count-1)]|Measure-Object -Average).Average;$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0-and$atr14[$i]-gt$atrAvg){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($close[$i]-$fL)/$close[$i]*100-gt1.0){$lw++}else{$ll++}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100-and$atr14[$i]-gt$atrAvg){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$close[$i])/$close[$i]*100-gt1.0){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=if($tt-gt0){[Math]::Round(($lw+$sw)/$tt*100,1)}else{0}
Write-Output "  RSI+ATRregime: $wr`% ($tt sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

# RSI + Volume + ATR (best combo)
$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0-and$volume[$i]-gt$volMA[$i]*0.8-and$atr14[$i]-gt$atrAvg){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($close[$i]-$fL)/$close[$i]*100-gt1.0){$lw++}else{$ll++}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100-and$volume[$i]-gt$volMA[$i]*0.8-and$atr14[$i]-gt$atrAvg){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$close[$i])/$close[$i]*100-gt1.0){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=if($tt-gt0){[Math]::Round(($lw+$sw)/$tt*100,1)}else{0}
Write-Output "  RSI+Vol+ATR: $wr`% ($tt sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

# ====== PHASE 3: TIME CYCLES ======
Write-Output "`n================================================================"
Write-Output "  PHASE 3: TIME CYCLES ON $($winner.tf)"
Write-Output "================================================================"
$ts=$klines|ForEach-Object{[long]$_[0]}

Write-Output "Day of Week:"
$dow=@{}
for($i=60;$i-lt$close.Count-3;$i++){
    $isL=$rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0
    $isS=$rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100
    if($isL-or$isS){
        $day=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i]).DayOfWeek.value__
        if(-not$dow.ContainsKey($day)){$dow[$day]=@{w=0;l=0;t=0;r=0}}
        if($isL){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;$won=($close[$i]-$fL)/$close[$i]*100-gt1.0;$ret=($close[$i]-$fL)/$close[$i]*100}
        else{$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;$won=($fH-$close[$i])/$close[$i]*100-gt1.0;$ret=($fH-$close[$i])/$close[$i]*100}
        $dow[$day].t++;$dow[$day].r+=$ret;if($won){$dow[$day].w++}else{$dow[$day].l++}
    }
}
$dowNames=@("Sun","Mon","Tue","Wed","Thu","Fri","Sat")
0..6|ForEach-Object{if($dow.ContainsKey($_)){$d=$dow[$_];$wr=if($d.t-gt0){[Math]::Round($d.w/$d.t*100,1)}else{0};Write-Output "  $($dowNames[$_]): WR $wr`% | $($d.t) sigs | $($d.w)W/$($d.l)L"}}

Write-Output "`n4h Window (UTC):"
$hw=@{}
for($i=60;$i-lt$close.Count-3;$i++){
    $isL=$rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0
    $isS=$rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100
    if($isL-or$isS){
        $hr=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i]).Hour
        if(-not$hw.ContainsKey($hr)){$hw[$hr]=@{w=0;l=0;t=0}}
        if($isL){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;$won=($close[$i]-$fL)/$close[$i]*100-gt1.0}
        else{$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;$won=($fH-$close[$i])/$close[$i]*100-gt1.0}
        $hw[$hr].t++;if($won){$hw[$hr].w++}else{$hw[$hr].l++}
    }
}
$hw.GetEnumerator()|Sort-Object Name|ForEach-Object{$h=$_.Value;$wr=if($h.t-gt0){[Math]::Round($h.w/$h.t*100,1)}else{0};Write-Output "  $($_.Name):00-$(($_.Name+4)%24):00 | WR $wr`% | $($h.t) sigs"}

# ====== PHASE 4: MARKET REGIME ======
Write-Output "`n================================================================"
Write-Output "  PHASE 4: MARKET REGIME BEHAVIOR"
Write-Output "================================================================"
$rets=[double[]]::new($close.Count);for($i=1;$i-lt$close.Count;$i++){$rets[$i]=($close[$i]-$close[$i-1])/$close[$i-1]*100}
$avgMove=($rets[50..($rets.Count-1)]|Where-Object{$_-ne0}|ForEach-Object{[Math]::Abs($_)}|Measure-Object -Average).Average
$hiThresh=$avgMove*1.5;$loThresh=$avgMove*0.5
Write-Output "  Avg $($winner.tf) move: $([Math]::Round($avgMove,2))%"
Write-Output "  High vol: >$([Math]::Round($hiThresh,2))% | Low vol: <$([Math]::Round($loThresh,2))%"
$hvw=0;$hvl=0;$lvw=0;$lvl=0;$nvw=0;$nvl=0
for($i=60;$i-lt$close.Count-3;$i++){
    $isL=$rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0;$isS=$rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100
    if(-not($isL-or$isS)){continue}
    $vol=[Math]::Abs($rets[$i]);$fL=$null;$fH=$null
    if($isL){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;$won=($close[$i]-$fL)/$close[$i]*100-gt1.0}
    else{$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;$won=($fH-$close[$i])/$close[$i]*100-gt1.0}
    if($vol-ge$hiThresh){if($won){$hvw++}else{$hvl++}}
    elseif($vol-le$loThresh){if($won){$lvw++}else{$lvl++}}
    else{if($won){$nvw++}else{$nvl++}}
}
Write-Output "  High vol: $(if($hvw+$hvl-gt0){[Math]::Round($hvw/($hvw+$hvl)*100,1)}else{0})`% ($($hvw+$hvl) sigs)"
Write-Output "  Normal vol: $(if($nvw+$nvl-gt0){[Math]::Round($nvw/($nvw+$nvl)*100,1)}else{0})`% ($($nvw+$nvl) sigs)"
Write-Output "  Low vol: $(if($lvw+$lvl-gt0){[Math]::Round($lvw/($lvw+$lvl)*100,1)}else{0})`% ($($lvw+$lvl) sigs)"

# Consecutive signal
$prev=$null;$aww=0;$awl=0;$alw=0;$all=0
for($i=65;$i-lt$close.Count-3;$i++){
    $isL=$rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0;$isS=$rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100
    if(-not($isL-or$isS)){continue}
    if($isL){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;$won=($close[$i]-$fL)/$close[$i]*100-gt1.0}
    else{$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;$won=($fH-$close[$i])/$close[$i]*100-gt1.0}
    if($null-eq$prev){$prev=$won;continue}
    if($prev){if($won){$aww++}else{$awl++}}else{if($won){$alw++}else{$all++}}
    $prev=$won
}
Write-Output "  After WINNER: $(if($aww+$awl-gt0){[Math]::Round($aww/($aww+$awl)*100,1)}else{0})`% ($($aww)W/$($awl)L)"
Write-Output "  After LOSER: $(if($alw+$all-gt0){[Math]::Round($alw/($alw+$all)*100,1)}else{0})`% ($($alw)W/$($all)L)"

# ====== PHASE 5: TP/SL BRUTEFORCE ======
Write-Output "`n================================================================"
Write-Output "  PHASE 5: TP/SL BRUTEFORCE ON $($winner.tf)"
Write-Output "================================================================"

$tpLevels=@(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0,6.0,8.0);$slLevels=@(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0)
$longEntries=@();$shortEntries=@()
for($i=$winner.per;$i-lt$close.Count-5;$i++){
    if($rsi[$i-1]-gt$winner.os-and$rsi[$i]-le$winner.os-and$rsi[$i]-ne0){$longEntries+=@{idx=$i;price=$close[$i]}}
    if($rsi[$i-1]-lt$winner.ob-and$rsi[$i]-ge$winner.ob-and$rsi[$i]-ne100){$shortEntries+=@{idx=$i;price=$close[$i]}}
}
Write-Output "  Entries: $($longEntries.Count) long, $($shortEntries.Count) short"

$bestResults=@()
foreach($tp in $tpLevels){foreach($sl in $slLevels){
    $tw=0;$tl=0;$tpP=0;$tt=0;$lw=0;$ll=0;$sw=0;$sl_=0
    foreach($e in $longEntries){$i=$e.idx;$ep=$e.price;$tpP_=$ep*(1+$tp/100);$slP=$ep*(1-$sl/100);$hit=$null
        for($j=$i+1;$j-lt[Math]::Min($i+48,$close.Count);$j++){if($high[$j]-ge$tpP_){$hit="TP";break}if($low[$j]-le$slP){$hit="SL";break}}
        if($hit-eq"TP"){$tw++;$tpP+=$tp;$lw++}elseif($hit-eq"SL"){$tl++;$tpP-=$sl;$ll++};if($hit){$tt++}}
    foreach($e in $shortEntries){$i=$e.idx;$ep=$e.price;$tpP_=$ep*(1-$tp/100);$slP=$ep*(1+$sl/100);$hit=$null
        for($j=$i+1;$j-lt[Math]::Min($i+48,$close.Count);$j++){if($low[$j]-le$tpP_){$hit="TP";break}if($high[$j]-ge$slP){$hit="SL";break}}
        if($hit-eq"TP"){$tw++;$tpP+=$tp;$sw++}elseif($hit-eq"SL"){$tl++;$tpP-=$sl;$sl_++};if($hit){$tt++}}
    if($tt-ge3){$wr=[Math]::Round($tw/$tt*100,1);$score=$wr*$tt/100;$bestResults+=[PSCustomObject]@{TP=$tp;SL=$sl;WR=$wr;Trades=$tt;Profit=[Math]::Round($tpP,2);Score=[Math]::Round($score,1)}}
}}
$sortedTPSL=$bestResults|Sort-Object Score -Descending
Write-Output "`nTop 5 TP/SL combos:"
$sortedTPSL|Select-Object -First 5|ForEach-Object{Write-Output "  TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades) trades | P+L=$([Math]::Round($_.Profit,1))%"}
Write-Output "`nTop 5 by WR (min 5 trades):";$bestResults|Where-Object{$_.Trades-ge5}|Sort-Object WR -Descending|Select-Object -First 5|ForEach-Object{Write-Output "  TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades) trades"}

# ====== PHASE 6: LIVE SIGNAL ======
Write-Output "`n================================================================"
Write-Output "  PHASE 6: LIVE PAPER TRADE SIGNAL"
Write-Output "================================================================"
$latestR=$rsi[-1];$prevR=$rsi[-2];$curP=$close[-1];$latestDT2=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1])
Write-Output "`n[MAINNET] $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC"
Write-Output "  Candle: $($latestDT2.ToString('MM-dd HH:mm')) UTC"
Write-Output "  Price: $([Math]::Round($curP,2))"
Write-Output "  RSI($($winner.per)): $([Math]::Round($latestR,1)) (prev: $([Math]::Round($prevR,1)))"
Write-Output "  OB=$($winner.ob) OS=$($winner.os)"
Write-Output "  MA(50): $([Math]::Round($ma50[-1],2)) | $(if($curP-gt$ma50[-1]){'ABOVE (uptrend)'}else{'BELOW (downtrend)'})"
Write-Output "  ATR: $([Math]::Round($atr14[-1],2)) ($([Math]::Round($atr14[-1]/$curP*100,2))%)"

if($prevR-gt$winner.os-and$latestR-le$winner.os-and$latestR-ne0){Write-Host "`n  >>> LONG SIGNAL <<<" -ForegroundColor Green;$tp=$curP*1.015;$sl=$curP*0.995;$tp2=$curP+$atr14[-1]*2;$sl2=$curP-$atr14[-1]*1.75;Write-Output "  Entry: $([Math]::Round($curP,2)) TP(a):$([Math]::Round($tp,2)) SL(a):$([Math]::Round($sl,2))"}
elseif($prevR-lt$winner.ob-and$latestR-ge$winner.ob-and$latestR-ne100){Write-Host "`n  >>> SHORT SIGNAL <<<" -ForegroundColor Red;$tp=$curP*0.985;$sl=$curP*1.005;$tp2=$curP-$atr14[-1]*2;$sl2=$curP+$atr14[-1]*1.75;Write-Output "  Entry: $([Math]::Round($curP,2)) TP(a):$([Math]::Round($tp,2)) SL(a):$([Math]::Round($sl,2))"}
else{Write-Output "`n  NO SIGNAL. RSI=$([Math]::Round($latestR,1)) between $($winner.os)-$($winner.ob)";Write-Output "  Distance to OS: $([Math]::Round($latestR-$winner.os,1)) | to OB: $([Math]::Round($winner.ob-$latestR,1))"}

$log="[CORRECT] $(Get-Date -Format 'yyyy-MM-dd HH:mm') P=$([Math]::Round($curP,2)) R=$([Math]::Round($latestR,1)) TF=$($winner.tf) RSIper=$($winner.per) OB=$($winner.ob) OS=$($winner.os)"
Add-Content -LiteralPath "paper_trading_log.txt" -Value $log -ErrorAction SilentlyContinue

Write-Output "`n================================================================"
Write-Output "  COMPLETE: Analysis saved to paper_trading_log.txt"
Write-Output "================================================================"
