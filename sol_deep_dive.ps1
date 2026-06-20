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
Read-DerInteger -data $der -offset ([ref]$off) | Out-Null
$params.Modulus = Read-DerInteger -data $der -offset ([ref]$off)
$params.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
$params.D = Read-DerInteger -data $der -offset ([ref]$off)
$params.P = Read-DerInteger -data $der -offset ([ref]$off)
$params.Q = Read-DerInteger -data $der -offset ([ref]$off)
$params.DP = Read-DerInteger -data $der -offset ([ref]$off)
$params.DQ = Read-DerInteger -data $der -offset ([ref]$off)
$params.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $rsa.ImportParameters($params)
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
    try { $resp = Invoke-WebRequest -Uri "https://api.bybit.com$endpoint`?$query" -Headers $headers -UseBasicParsing -TimeoutSec 60; return ($resp.Content | ConvertFrom-Json).result } catch { return $null }
}
function Get-K {
    param($int, $lim)
    $r = Call-API -endpoint "/v5/market/kline" -query "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if ($r -and $r.list) { $k = $r.list; [Array]::Reverse($k); return $k } else { return $null }
}
function Calc-RSI {
    param($p, $per)
    $g=[double[]]::new($p.Count); $l=[double[]]::new($p.Count)
    for ($i=1; $i -lt $p.Count; $i++) { $d=$p[$i]-$p[$i-1]; if ($d -ge 0) { $g[$i]=$d } else { $l[$i]=-$d } }
    $ag=($g[1..$per] | Measure-Object -Sum).Sum / $per; $al=($l[1..$per] | Measure-Object -Sum).Sum / $per
    $r=[double[]]::new($p.Count)
    for ($i=$per; $i -lt $p.Count; $i++) {
        if ($i -gt $per) { $ag=(($ag*($per-1))+$g[$i])/$per; $al=(($al*($per-1))+$l[$i])/$per }
        $r[$i]=if ($al -eq 0) { 100 } else { 100 - (100 / (1 + ($ag/$al))) }
    }
    return $r
}
function Calc-EMA {
    param($p, $per)
    $e=[double[]]::new($p.Count); $e[0]=$p[0]; $m=2/($per+1)
    for ($i=1; $i -lt $p.Count; $i++) { $e[$i]=$p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}
function Calc-ATR {
    param($h, $l, $c, $per)
    $tr=[double[]]::new($c.Count)
    for ($i=1; $i -lt $c.Count; $i++) {
        $hl=$h[$i]-$l[$i]; $hc=[Math]::Abs($h[$i]-$c[$i-1]); $lc=[Math]::Abs($l[$i]-$c[$i-1])
        $tr[$i]=[Math]::Max($hl, [Math]::Max($hc, $lc))
    }
    $a=[double[]]::new($c.Count)
    if ($c.Count -gt $per) {
        $a[$per]=($tr[1..$per] | Measure-Object -Average).Average
        for ($i=$per+1; $i -lt $c.Count; $i++) { $a[$i]=($a[$i-1]*($per-1)+$tr[$i])/$per }
    }
    return $a
}

# ====== FOCUSED DEEP DIVE: TOP CANDIDATES ======
$candidates = @(
    @{tf="6h"; int="360"; per=50; ob=60; os=36},
    @{tf="2h"; int="120"; per=38; ob=60; os=36},
    @{tf="12h"; int="720"; per=26; ob=64; os=44}
)

function Analyze-TF {
    param($tfName, $int, $per, $ob, $os)

    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  DEEP DIVE: $tfName RSI($per) OB=$ob OS=$os" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan

    $klines=Get-K $int 500
    if (-not $klines) { Write-Output "  No data (null)"; return }
    if ($klines.Count -lt 100) { Write-Output "  Only $($klines.Count) candles, skipping"; return }
    $close = $klines | ForEach-Object { [double]$_[4] }
    $high  = $klines | ForEach-Object { [double]$_[2] }
    $low   = $klines | ForEach-Object { [double]$_[3] }
    $vol   = $klines | ForEach-Object { [double]$_[5] }
    $ts    = $klines | ForEach-Object { [long]$_[0] }

    $rsi   = Calc-RSI $close $per
    $atr14 = Calc-ATR $high $low $close 14
    $ma50  = Calc-EMA $close 50
    $volMA = Calc-EMA $vol 20

    Write-Output "  Data: $($close.Count) candles (fetched $($klines.Count) klines)"

    # === INDICATOR COMBOS ===
    Write-Output "`n--- Indicator Combos ---"

    # RSI alone
    $lw=0; $ll=0; $sw=0; $sl=0
    for ($i=$per; $i -lt $close.Count-5; $i++) {
        if (    $rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0) { $fL=($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum; if (($close[$i]-$fL)/$close[$i]*100 -gt 1.0) { $lw++ } else { $ll++ } }
        if (    $rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100) { $fH=($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum; if (($fH-$close[$i])/$close[$i]*100 -gt 1.0) { $sw++ } else { $sl++ } }
    }
    $t=$lw+$ll+$sw+$sl; $w=if($t){[Math]::Round(($lw+$sw)/$t*100,1)}else{0}; Write-Output "  RSI alone:      $w% ($t sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

    # RSI + Volume
    $lw=0; $ll=0; $sw=0; $sl=0
    for ($i=$per+20; $i -lt $close.Count-5; $i++) {
        if ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0 -and $vol[$i] -gt $volMA[$i]*0.8) { $fL=($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum; if (($close[$i]-$fL)/$close[$i]*100 -gt 1.0) { $lw++ } else { $ll++ } }
        if ($rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100 -and $vol[$i] -gt $volMA[$i]*0.8) { $fH=($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum; if (($fH-$close[$i])/$close[$i]*100 -gt 1.0) { $sw++ } else { $sl++ } }
    }
    $t=$lw+$ll+$sw+$sl; $w=if($t){[Math]::Round(($lw+$sw)/$t*100,1)}else{0}; Write-Output "  RSI+Volume:     $w% ($t sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

    # RSI + ATR regime
    $atrAvg=($atr14[50..($atr14.Count-1)] | Measure-Object -Average).Average
    $lw=0; $ll=0; $sw=0; $sl=0
    for ($i=$per+20; $i -lt $close.Count-5; $i++) {
        if ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0 -and $atr14[$i] -gt $atrAvg) { $fL=($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum; if (($close[$i]-$fL)/$close[$i]*100 -gt 1.0) { $lw++ } else { $ll++ } }
        if ($rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100 -and $atr14[$i] -gt $atrAvg) { $fH=($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum; if (($fH-$close[$i])/$close[$i]*100 -gt 1.0) { $sw++ } else { $sl++ } }
    }
    $t=$lw+$ll+$sw+$sl; $w=if($t){[Math]::Round(($lw+$sw)/$t*100,1)}else{0}; Write-Output "  RSI+ATRregime:  $w% ($t sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

    # RSI + MA50
    $lw=0; $ll=0; $sw=0; $sl=0
    for ($i=$per+20; $i -lt $close.Count-5; $i++) {
        if ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0 -and $close[$i] -gt $ma50[$i]) { $fL=($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum; if (($close[$i]-$fL)/$close[$i]*100 -gt 1.0) { $lw++ } else { $ll++ } }
        if ($rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100 -and $close[$i] -lt $ma50[$i]) { $fH=($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum; if (($fH-$close[$i])/$close[$i]*100 -gt 1.0) { $sw++ } else { $sl++ } }
    }
    $t=$lw+$ll+$sw+$sl; $w=if($t){[Math]::Round(($lw+$sw)/$t*100,1)}else{0}; Write-Output "  RSI+MA50:       $w% ($t sigs L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))"

    # === TP/SL BRUTEFORCE ===
    Write-Output "`n--- TP/SL Bruteforce ---"
    $tpLevels=@(0.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0)
    $slLevels=@(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0)
    $longs=@(); $shorts=@()
    for ($i=$per+20; $i -lt $close.Count-5; $i++) {
        if ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0) { $longs += @{idx=$i; price=$close[$i]} }
        if ($rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100) { $shorts += @{idx=$i; price=$close[$i]} }
    }
    Write-Output "  Entries: $($longs.Count) long, $($shorts.Count) short"
    $results=@()
    foreach ($tp in $tpLevels) { foreach ($sl in $slLevels) {
        $tw=0; $tl=0; $pL=0; $tt=0
        foreach ($e in $longs) {
            $i=$e.idx; $ep=$e.price; $tpP=$ep*(1+$tp/100); $slP=$ep*(1-$sl/100); $hit=$null
            for ($j=$i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) { if ($high[$j] -ge $tpP) { $hit="TP"; break }; if ($low[$j] -le $slP) { $hit="SL"; break } }
            if ($hit -eq "TP") { $tw++; $pL+=$tp } elseif ($hit -eq "SL") { $tl++; $pL-=$sl }; $tt++
        }
        foreach ($e in $shorts) {
            $i=$e.idx; $ep=$e.price; $tpP=$ep*(1-$tp/100); $slP=$ep*(1+$sl/100); $hit=$null
            for ($j=$i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) { if ($low[$j] -le $tpP) { $hit="TP"; break }; if ($high[$j] -ge $slP) { $hit="SL"; break } }
            if ($hit -eq "TP") { $tw++; $pL+=$tp } elseif ($hit -eq "SL") { $tl++; $pL-=$sl }; $tt++
        }
        if ($tt -ge 3) { $wr=[Math]::Round($tw/$tt*100,1); $score=$wr*$tt/100; $results+=[PSCustomObject]@{TP=$tp; SL=$sl; WR=$wr; Trades=$tt; PnL=[Math]::Round($pL,1); Score=[Math]::Round($score,1)} }
    }}
    $topByScore=$results | Sort-Object Score -Descending | Select-Object -First 3
    $topByWR=$results | Where-Object { $_.Trades -ge 5 } | Sort-Object WR -Descending | Select-Object -First 3
    Write-Output "  Top by Score:"
    $topByScore | ForEach-Object { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades)t | PnL=$($_.PnL)%" }
    Write-Output "  Top by WR (min 5 trades):"
    $topByWR | ForEach-Object { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades)t" }

    # === BEST R:R COMBO ===
    Write-Output "`n--- Best R:R (min 5 trades, TP >= SL) ---"
    $bestRR=$results | Where-Object { $_.Trades -ge 5 -and $_.TP -ge $_.SL } | Sort-Object Score -Descending | Select-Object -First 3
    if ($bestRR) { $bestRR | ForEach-Object { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.Trades)t | PnL=$($_.PnL)%" } } else { Write-Output "    None found" }

    # === TIME CYCLES ===
    Write-Output "`n--- Day of Week ---"
    $dow=@{}
    for ($i=$per+20; $i -lt $close.Count-3; $i++) {
        $isL=$rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0
        $isS=$rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100
        if (-not ($isL -or $isS)) { continue }
        $day=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i]).DayOfWeek.value__
        if (-not $dow.ContainsKey($day)) { $dow[$day]=@{w=0;l=0;t=0} }
        if ($isL) { $fL=($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum; $won=($close[$i]-$fL)/$close[$i]*100 -gt 1.0 }
        else { $fH=($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum; $won=($fH-$close[$i])/$close[$i]*100 -gt 1.0 }
        $dow[$day].t++; if ($won) { $dow[$day].w++ } else { $dow[$day].l++ }
    }
    $dowNames=@("Sun","Mon","Tue","Wed","Thu","Fri","Sat")
    0..6 | ForEach-Object { if ($dow.ContainsKey($_)) { $d=$dow[$_]; $wr=if($d.t){[Math]::Round($d.w/$d.t*100,1)}else{0}; Write-Output "  $($dowNames[$_]): WR $wr% ($($d.t) sigs)" } }

    # === REGIME ===
    Write-Output "`n--- Consecutive Signals ---"
    $prev=$null; $aww=0; $awl=0; $alw=0; $all=0
    for ($i=$per+25; $i -lt $close.Count-3; $i++) {
        $isL=$rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0
        $isS=$rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100
        if (-not ($isL -or $isS)) { continue }
        if ($isL) { $fL=($close[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum; $won=($close[$i]-$fL)/$close[$i]*100 -gt 1.0 }
        else { $fH=($close[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum; $won=($fH-$close[$i])/$close[$i]*100 -gt 1.0 }
        if ($null -eq $prev) { $prev=$won; continue }
        if ($prev) { if ($won) { $aww++ } else { $awl++ } } else { if ($won) { $alw++ } else { $all++ } }
        $prev=$won
    }
    Write-Output "  After WINNER: $(if($aww+$awl){[Math]::Round($aww/($aww+$awl)*100,1)}else{0})% ($aww W / $awl L)"
    Write-Output "  After LOSER:  $(if($alw+$all){[Math]::Round($alw/($alw+$all)*100,1)}else{0})% ($alw W / $all L)"

    # === LIVE SIGNAL ===
    Write-Output "`n--- Live Signal ---"
    $lr=$rsi[-1]; $pr=$rsi[-2]; $cp=$close[-1]; $dt=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1])
    Write-Output "  Candle: $($dt.ToString('MM-dd HH:mm')) UTC"
    Write-Output "  Price:  $([Math]::Round($cp,2))"
    Write-Output "  RSI($per): $([Math]::Round($lr,1)) (prev $([Math]::Round($pr,1)))"
    Write-Output "  OB=$ob OS=$os"
    if ($pr -gt $os -and $lr -le $os -and $lr -ne 0) { Write-Host "  >>> LONG SIGNAL <<<" -ForegroundColor Green }
    elseif ($pr -lt $ob -and $lr -ge $ob -and $lr -ne 100) { Write-Host "  >>> SHORT SIGNAL <<<" -ForegroundColor Red }
    else { Write-Output "  No signal. RSI at $([Math]::Round($lr,1)) (OS=$os OB=$ob)" }

    Write-Output ""
}

foreach ($c in $candidates) {
    Analyze-TF -tfName $c.tf -int $c.int -per $c.per -ob $c.ob -os $c.os
}
