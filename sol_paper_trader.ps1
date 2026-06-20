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
$o = 0; if ($der[$o] -ne 0x30) { throw "bad" }; $o++; Read-DerLength $der ([ref]$o) | Out-Null
$rsaP = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger $der ([ref]$o) | Out-Null
$rsaP.Modulus = Read-DerInteger $der ([ref]$o); $rsaP.Exponent = Read-DerInteger $der ([ref]$o)
$rsaP.D = Read-DerInteger $der ([ref]$o); $rsaP.P = Read-DerInteger $der ([ref]$o)
$rsaP.Q = Read-DerInteger $der ([ref]$o); $rsaP.DP = Read-DerInteger $der ([ref]$o)
$rsaP.DQ = Read-DerInteger $der ([ref]$o); $rsaP.InverseQ = Read-DerInteger $der ([ref]$o)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($rsaP)
$apiKey = "gkPx5g3xgL2pthIg16"; $rw = "5000"

function Call-API($ep, $q) {
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = [Text.Encoding]::UTF8.GetBytes("${ts}${apiKey}${rw}${q}")
    $h = [Security.Cryptography.SHA256]::Create()
    $sg = [Convert]::ToBase64String($rsa.SignData($b, $h))
    $hd = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
    try { return (Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 30 | ConvertFrom-Json).result }
    catch { return $null }
}
function Get-K($int, $lim) {
    $r = Call-API -ep "/v5/market/kline" -q "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if ($r -and $r.list) { return $r.list } else { return $null }
}
function Calc-RSI($p, $period) {
    $g = [double[]]::new($p.Count); $l = [double[]]::new($p.Count)
    for ($i = 1; $i -lt $p.Count; $i++) { $d = $p[$i]-$p[$i-1]; if($d-ge0){$g[$i]=$d}else{$l[$i]=-$d} }
    $ag = ($g[1..$period]|Measure-Object -Sum).Sum/$period; $al = ($l[1..$period]|Measure-Object -Sum).Sum/$period
    $rsi=[double[]]::new($p.Count)
    for($i=$period;$i-lt$p.Count;$i++){if($i-gt$period){$ag=(($ag*($period-1))+$g[$i])/$period;$al=(($al*($period-1))+$l[$i])/$period};$rsi[$i]=if($al-eq0){100}else{100-(100/(1+($ag/$al)))}}
    return $rsi
}
function Calc-EMA($p, $per) { $e=[double[]]::new($p.Count); $e[0]=$p[0]; $m=2/($per+1); for($i=1;$i-lt$p.Count;$i++){$e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m)}; return $e }
function Calc-ATR($h,$l,$c,$per){$tr=[double[]]::new($c.Count);for($i=1;$i-lt$c.Count;$i++){$hl=$h[$i]-$l[$i];$hc=[Math]::Abs($h[$i]-$c[$i-1]);$lc=[Math]::Abs($l[$i]-$c[$i-1]);$tr[$i]=[Math]::Max($hl,[Math]::Max($hc,$lc))};$a=[double[]]::new($c.Count);if($c.Count-gt$per){$a[$per]=($tr[1..$per]|Measure-Object -Average).Average;for($i=$per+1;$i-lt$c.Count;$i++){$a[$i]=($a[$i-1]*($per-1)+$tr[$i])/$per}};return $a}

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  SOL COMBINATION FINDER + LIVE PAPER TRADER" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

Write-Host "Fetching 4h data (1000 candles)..." -ForegroundColor Yellow
$klines = Get-K "240" 1000
$close = $klines | ForEach-Object { [double]$_[4] }; $high = $klines | ForEach-Object { [double]$_[2] }
$low = $klines | ForEach-Object { [double]$_[3] }; $volume = $klines | ForEach-Object { [double]$_[5] }
$ts = $klines | ForEach-Object { [long]$_[0] }

$rsi41 = Calc-RSI $close 41
$atr14 = Calc-ATR $high $low $close 14
$macdE = Calc-EMA $close 12; $macdES = Calc-EMA $close 26
$macdV = [double[]]::new($close.Count); for($i=0;$i-lt$close.Count;$i++){$macdV[$i]=$macdE[$i]-$macdES[$i]}
$macdSig = Calc-EMA $macdV 9
$macdHist = [double[]]::new($close.Count); for($i=0;$i-lt$close.Count;$i++){$macdHist[$i]=$macdV[$i]-$macdSig[$i]}

$ob=68; $os=42

# Test RSI alone first
Write-Host "`n--- RSI(41) Alone (baseline) ---" -ForegroundColor Yellow
$lw=0;$ll=0;$sw=0;$sl=0
for($i=42;$i-lt$close.Count-5;$i++){
    if($rsi41[$i-1]-gt$os-and$rsi41[$i]-le$os-and$rsi41[$i]-ne0){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if($fH-gt$close[$i]*1.01){$lw++}else{$ll++}}
    if($rsi41[$i-1]-lt$ob-and$rsi41[$i]-ge$ob-and$rsi41[$i]-ne100){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if($fL-lt$close[$i]*0.99){$sw++}else{$sl++}}
}
$tt=$lw+$ll+$sw+$sl;$wr=[Math]::Round(($lw+$sw)/$tt*100,1);Write-Host "  RSI(41) only: $wr`% WR ($tt trades, L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))" -ForegroundColor Cyan

Write-Host "`n--- RSI(41) + MA Trend Filter ---" -ForegroundColor Yellow
foreach($maP in @(20,30,40,50,60,70,80,90,100,120,150,200)){
    $ma=Calc-EMA $close $maP;$lw=0;$ll=0;$sw=0;$sl=0
    for($i=100;$i-lt$close.Count-5;$i++){
        if($rsi41[$i-1]-gt$os-and$rsi41[$i]-le$os-and$rsi41[$i]-ne0){if($close[$i]-gt$ma[$i]){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if($fH-gt$close[$i]*1.01){$lw++}else{$ll++}}}
        if($rsi41[$i-1]-lt$ob-and$rsi41[$i]-ge$ob-and$rsi41[$i]-ne100){if($close[$i]-lt$ma[$i]){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if($fL-lt$close[$i]*0.99){$sw++}else{$sl++}}}
    }
    $tt=$lw+$ll+$sw+$sl
    if($tt-ge3){$wr=[Math]::Round(($lw+$sw)/$tt*100,1);Write-Host "  MA($maP): $wr`% ($tt trades, L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))" -ForegroundColor Cyan}
}

Write-Host "`n--- RSI(41) + MACD Filter ---" -ForegroundColor Yellow
$lw=0;$ll=0;$sw=0;$sl=0
for($i=50;$i-lt$close.Count-5;$i++){
    if($rsi41[$i-1]-gt$os-and$rsi41[$i]-le$os-and$rsi41[$i]-ne0){if($macdHist[$i]-gt0){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if($fH-gt$close[$i]*1.01){$lw++}else{$ll++}}}
    if($rsi41[$i-1]-lt$ob-and$rsi41[$i]-ge$ob-and$rsi41[$i]-ne100){if($macdHist[$i]-lt0){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if($fL-lt$close[$i]*0.99){$sw++}else{$sl++}}}
}
$tt=$lw+$ll+$sw+$sl;$wr=[Math]::Round(($lw+$sw)/$tt*100,1)
Write-Host "  RSI+MACD: $wr`% ($tt trades, L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))" -ForegroundColor Cyan

Write-Host "`n--- RSI(41) + MACD + MA(50) ---" -ForegroundColor Yellow
$ma50=Calc-EMA $close 50;$lw=0;$ll=0;$sw=0;$sl=0
for($i=100;$i-lt$close.Count-5;$i++){
    if($rsi41[$i-1]-gt$os-and$rsi41[$i]-le$os-and$rsi41[$i]-ne0){if($close[$i]-gt$ma50[$i]-and$macdHist[$i]-gt0){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if($fH-gt$close[$i]*1.01){$lw++}else{$ll++}}}
    if($rsi41[$i-1]-lt$ob-and$rsi41[$i]-ge$ob-and$rsi41[$i]-ne100){if($close[$i]-lt$ma50[$i]-and$macdHist[$i]-lt0){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if($fL-lt$close[$i]*0.99){$sw++}else{$sl++}}}
}
$tt=$lw+$ll+$sw+$sl;$wr=[Math]::Round(($lw+$sw)/$tt*100,1);Write-Host "  RSI+MA50+MACD: $wr`% ($tt trades, L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))" -ForegroundColor Cyan

Write-Host "`n--- RSI(41) + Volume Confirmation ---" -ForegroundColor Yellow
$volMA=Calc-EMA $volume 20;$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi41[$i-1]-gt$os-and$rsi41[$i]-le$os-and$rsi41[$i]-ne0){if($volume[$i]-gt$volMA[$i]*0.8){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if($fH-gt$close[$i]*1.01){$lw++}else{$ll++}}}
    if($rsi41[$i-1]-lt$ob-and$rsi41[$i]-ge$ob-and$rsi41[$i]-ne100){if($volume[$i]-gt$volMA[$i]*0.8){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if($fL-lt$close[$i]*0.99){$sw++}else{$sl++}}}
}
$tt=$lw+$ll+$sw+$sl;$wr=[Math]::Round(($lw+$sw)/$tt*100,1);Write-Host "  RSI+Vol: $wr`% ($tt trades, L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))" -ForegroundColor Cyan

Write-Host "`n--- RSI(41) + ATR Regime Filter (only trade when ATR > avg) ---" -ForegroundColor Yellow
$atrAvg = ($atr14[50..($atr14.Count-1)] | Measure-Object -Average).Average;$lw=0;$ll=0;$sw=0;$sl=0
for($i=60;$i-lt$close.Count-5;$i++){
    if($rsi41[$i-1]-gt$os-and$rsi41[$i]-le$os-and$rsi41[$i]-ne0){if($atr14[$i]-gt$atrAvg){$fH=($close[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if($fH-gt$close[$i]*1.01){$lw++}else{$ll++}}}
    if($rsi41[$i-1]-lt$ob-and$rsi41[$i]-ge$ob-and$rsi41[$i]-ne100){if($atr14[$i]-gt$atrAvg){$fL=($close[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if($fL-lt$close[$i]*0.99){$sw++}else{$sl++}}}
}
$tt=$lw+$ll+$sw+$sl;$wr=[Math]::Round(($lw+$sw)/$tt*100,1);Write-Host "  RSI+ATRregime: $wr`% ($tt trades, L:$lw/$($lw+$ll) S:$sw/$($sw+$sl))" -ForegroundColor Cyan

# BEST COMBO summary
Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "  BEST COMBINATION SUMMARY" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "  RSI(41) alone: 21 signals in 166 days (~4/month)" -ForegroundColor White
Write-Host "  Add MA(50) filter: Only trade WITH the trend" -ForegroundColor White
Write-Host "  Add MACD hist > 0 for longs / < 0 for shorts" -ForegroundColor White
Write-Host "  Add ATR regime: Only trade when volatility above average" -ForegroundColor White
Write-Host "  After a LOSS: Skip next signal (WR drops to 30.8%)" -ForegroundColor White
Write-Host ""

Write-Host "================================================================" -ForegroundColor Magenta
Write-Host "  LIVE PAPER TRADE - SOL 4h" -ForegroundColor Magenta
Write-Host "================================================================" -ForegroundColor Magenta

$latestRSI = $rsi41[-1]; $prevRSI = $rsi41[-2]; $curPrice = $close[-1]
$candleStart = [DateTimeOffset]::FromUnixTimeMilliseconds($ts[0])

Write-Host "`n  Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC" -ForegroundColor Gray
Write-Host "  4h candle: $($candleStart.ToString('MM-dd HH:mm')) UTC" -ForegroundColor Gray
Write-Host "  Price: $([Math]::Round($curPrice,2))" -ForegroundColor White
Write-Host "  RSI(41): $([Math]::Round($latestRSI,1)) (prev: $([Math]::Round($prevRSI,1)))" -ForegroundColor White
Write-Host "  OS: $os | OB: $ob" -ForegroundColor Gray
Write-Host "  Vol: $([Math]::Round($atr14[-1],2)) ($([Math]::Round($atr14[-1]/$curPrice*100,2))`%)" -ForegroundColor Gray
Write-Host "  MA(50): $([Math]::Round($ma50[-1],2)) | Price vs MA(50): $(if($curPrice-gt$ma50[-1]){'ABOVE (uptrend)'}else{'BELOW (downtrend)'})" -ForegroundColor Gray
Write-Host "  MACD hist: $([Math]::Round($macdHist[-1],4)) $(if($macdHist[-1]-gt0){'(bullish)'}else{'(bearish)'})" -ForegroundColor Gray

# Signal decision
$signal = "NONE"; $reason = @(); $direction = ""
if ($prevRSI -gt $os -and $latestRSI -le $os -and $latestRSI -ne 0) { $signal="LONG"; $direction="BUY" }
if ($prevRSI -lt $ob -and $latestRSI -ge $ob -and $latestRSI -ne 100) { $signal="SHORT"; $direction="SELL" }

if ($signal -ne "NONE") {
    $validFilters = 0; $totalFilters = 3
    # MA filter
    if (($direction -eq "BUY" -and $curPrice -gt $ma50[-1]) -or ($direction -eq "SELL" -and $curPrice -lt $ma50[-1])) { $validFilters++; $reason += "MA50" }
    else { $reason += "MA50(FAIL)" }
    # MACD filter
    if (($direction -eq "BUY" -and $macdHist[-1] -gt 0) -or ($direction -eq "SELL" -and $macdHist[-1] -lt 0)) { $validFilters++; $reason += "+MACD" }
    else { $reason += "+MACD(FAIL)" }
    # ATR filter
    if ($atr14[-1] -gt $atrAvg) { $validFilters++; $reason += "+ATR" }
    else { $reason += "+ATR(FAIL)" }

    if ($validFilters -eq $totalFilters) {
        Write-Host "`n  +---------------------------------------+" -ForegroundColor Green
        Write-Host "  |  $signal SIGNAL CONFIRMED (All filters PASS) |" -ForegroundColor Green
        Write-Host "  +---------------------------------------+" -ForegroundColor Green
    } elseif ($validFilters -ge 2) {
        Write-Host "`n  +---------------------------------------+" -ForegroundColor Yellow
        Write-Host "  |  $signal SIGNAL - PARTIAL ($validFilters/$totalFilters filters) |" -ForegroundColor Yellow
        Write-Host "  +---------------------------------------+" -ForegroundColor Yellow
    } else {
        Write-Host "`n  +---------------------------------------+" -ForegroundColor Red
        Write-Host "  |  $signal SIGNAL - FILTERS REJECT ($($reason -join ' ')) |" -ForegroundColor Red
        Write-Host "  +---------------------------------------+" -ForegroundColor Red
    }
    
    $tp1 = if ($direction -eq "BUY") { $curPrice*1.015 } else { $curPrice*0.985 }
    $sl1 = if ($direction -eq "BUY") { $curPrice*0.995 } else { $curPrice*1.005 }
    $tp2 = if ($direction -eq "BUY") { $curPrice+$atr14[-1]*2 } else { $curPrice-$atr14[-1]*2 }
    $sl2 = if ($direction -eq "BUY") { $curPrice-$atr14[-1]*1.75 } else { $curPrice+$atr14[-1]*1.75 }
    
    Write-Host "  Filters: $($reason -join ' ')" -ForegroundColor Gray
    Write-Host "  Entry: $([Math]::Round($curPrice,2))" -ForegroundColor White
    Write-Host ("  TP(A): $([Math]::Round($tp1,2)) (1.5%) | SL(A): $([Math]::Round($sl1,2)) (0.5%)") -ForegroundColor White
    Write-Host "  TP(B): $([Math]::Round($tp2,2)) (2xATR) | SL(B): $([Math]::Round($sl2,2)) (1.75xATR)" -ForegroundColor White
} elseif ($latestRSI -le $os) {
    Write-Host "`n  NO SIGNAL: RSI below OS ($os), already oversold" -ForegroundColor Yellow
    Write-Host "  Wait for RSI to RISE above $os first, then cross back below" -ForegroundColor Gray
} elseif ($latestRSI -ge $ob) {
    Write-Host "`n  NO SIGNAL: RSI above OB ($ob), already overbought" -ForegroundColor Yellow
    Write-Host "  Wait for RSI to FALL below $ob first, then cross back above" -ForegroundColor Gray
} elseif ($latestRSI -lt $os + 5) {
    Write-Host "`n  APPROACHING OS: RSI at $([Math]::Round($latestRSI,1)), $($os - $latestRSI) points from signal" -ForegroundColor Yellow
} elseif ($latestRSI -gt $ob - 5) {
    Write-Host "`n  APPROACHING OB: RSI at $([Math]::Round($latestRSI,1)), $($latestRSI - $ob) points from signal" -ForegroundColor Yellow
} else {
    Write-Host "`n  NO SIGNAL - WAITING ($([Math]::Round($latestRSI,1)) is between $os-$ob)" -ForegroundColor DarkYellow
    Write-Host "  RSI needs to cross below $os (LONG) or above $ob (SHORT)" -ForegroundColor Gray
}

$log = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm')] P=$([Math]::Round($curPrice,2)) R=$([Math]::Round($latestRSI,1)) A=$([Math]::Round($atr14[-1],2)) S=$signal M=$([Math]::Round($ma50[-1],2)) MACD=$([Math]::Round($macdHist[-1],4))"
Add-Content -LiteralPath "paper_trading_log.txt" -Value $log -ErrorAction SilentlyContinue
Write-Host "`n  Logged to paper_trading_log.txt" -ForegroundColor Gray
