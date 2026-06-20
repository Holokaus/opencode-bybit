function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $len = $data[$offset.Value]; $offset.Value++; return $len }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0
    for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }
    return $len
}
function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw }; $offset.Value++
    $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len); [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start)
    [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len; return $trimmed
}
$pem = [System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH)
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0
if ($der[$off] -ne 0x30) { throw }; $off++
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

$apiKey = $env:BYBIT_API_KEY; $recvWindow = "5000"

function Call-API {
    param($ep, $q)
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $body = [Text.Encoding]::UTF8.GetBytes("$ts$apiKey$recvWindow$q")
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $sig = [Convert]::ToBase64String($rsa.SignData($body, $sha256))
    $headers = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sig;"X-BAPI-RECV-WINDOW"=$recvWindow;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
    try { $resp = Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $headers -UseBasicParsing -TimeoutSec 60; return ($resp.Content | ConvertFrom-Json) } catch { return $null }
}

function Get-K {
    param($interval, $limit)
    $r = Call-API -ep "/v5/market/kline" -q "category=spot&symbol=ICPUSDT&interval=$interval&limit=$limit"
    if ($r -and $r.result -and $r.result.list) { $k = $r.result.list; [Array]::Reverse($k); return $k }
    return $null
}

function Calc-RSI {
    param($prices, $period)
    $gains = [double[]]::new($prices.Count); $losses = [double[]]::new($prices.Count)
    for ($i = 1; $i -lt $prices.Count; $i++) { $d = $prices[$i] - $prices[$i-1]; if ($d -ge 0) { $gains[$i] = $d } else { $losses[$i] = -$d } }
    $avgG = ($gains[1..$period] | Measure-Object -Sum).Sum / $period
    $avgL = ($losses[1..$period] | Measure-Object -Sum).Sum / $period
    $rsi = [double[]]::new($prices.Count)
    for ($i = $period; $i -lt $prices.Count; $i++) {
        if ($i -gt $period) { $avgG = (($avgG * ($period-1)) + $gains[$i]) / $period; $avgL = (($avgL * ($period-1)) + $losses[$i]) / $period }
        $rsi[$i] = if ($avgL -eq 0) { 100 } else { 100 - (100 / (1 + ($avgG / $avgL))) }
    }
    return $rsi
}

function Calc-EMA {
    param($prices, $period)
    $ema = [double[]]::new($prices.Count); $ema[0] = $prices[0]; $m = 2 / ($period + 1)
    for ($i = 1; $i -lt $prices.Count; $i++) { $ema[$i] = $prices[$i] * $m + $ema[$i-1] * (1 - $m) }
    return $ema
}

function Calc-SMA {
    param($prices, $period)
    $sma = [double[]]::new($prices.Count)
    for ($i = 0; $i -lt $prices.Count; $i++) { if ($i -ge $period-1) { $sma[$i] = ($prices[($i-$period+1)..$i] | Measure-Object -Average).Average } }
    return $sma
}

function Calc-ATR {
    param($high, $low, $close, $period)
    $tr = [double[]]::new($close.Count)
    for ($i = 1; $i -lt $close.Count; $i++) { $tr[$i] = [Math]::Max($high[$i] - $low[$i], [Math]::Max([Math]::Abs($high[$i] - $close[$i-1]), [Math]::Abs($low[$i] - $close[$i-1]))) }
    $atr = [double[]]::new($close.Count)
    if ($close.Count -gt $period) { $atr[$period] = ($tr[1..$period] | Measure-Object -Average).Average; for ($i = $period+1; $i -lt $close.Count; $i++) { $atr[$i] = ($atr[$i-1] * ($period-1) + $tr[$i]) / $period } }
    return $atr
}

function Calc-ADX {
    param($high, $low, $close, $period)
    $tr = [double[]]::new($close.Count); $up = [double[]]::new($close.Count); $dn = [double[]]::new($close.Count)
    for ($i = 1; $i -lt $close.Count; $i++) {
        $tr[$i] = [Math]::Max($high[$i]-$low[$i], [Math]::Max([Math]::Abs($high[$i]-$close[$i-1]), [Math]::Abs($low[$i]-$close[$i-1])))
        $u = $high[$i]-$high[$i-1]; $d = $low[$i-1]-$low[$i]
        $up[$i] = if ($u -gt $d -and $u -gt 0) { $u } else { 0 }
        $dn[$i] = if ($d -gt $u -and $d -gt 0) { $d } else { 0 }
    }
    $atr = Calc-EMA $tr $period; $du = Calc-EMA $up $period; $dd = Calc-EMA $dn $period
    $dx = [double[]]::new($close.Count)
    for ($i = $period; $i -lt $close.Count; $i++) { $pdi = $du[$i]/$atr[$i]*100; $ndi = $dd[$i]/$atr[$i]*100; $dx[$i] = if (($pdi+$ndi) -eq 0) { 0 } else { [Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100 } }
    return (Calc-EMA $dx $period)
}

function Calc-StochRSI {
    param($prices, $period)
    $rsi = Calc-RSI $prices $period; $k = [double[]]::new($prices.Count)
    for ($i = $period; $i -lt $prices.Count; $i++) { $mn = ($rsi[($i-$period+1)..$i] | Measure-Object -Minimum).Minimum; $mx = ($rsi[($i-$period+1)..$i] | Measure-Object -Maximum).Maximum; $k[$i] = if ($mx-$mn -eq 0) { 50 } else { ($rsi[$i]-$mn)/($mx-$mn)*100 } }
    return $k
}

function Write-Bar { param($len) Write-Output ("-" * $len) }

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  ICP DEEP DIVE - THOROUGH ANALYSIS" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# Cache all kline data first
Write-Host "`n[0/6] CACHING ALL KLINES..." -ForegroundColor Yellow
$tfDefs = @( @{n="15m";i="15"}, @{n="30m";i="30"}, @{n="1h";i="60"}, @{n="2h";i="120"}, @{n="4h";i="240"}, @{n="6h";i="360"}, @{n="12h";i="720"} )
$klineCache = @{}
foreach ($tf in $tfDefs) {
    Write-Output "  Fetching $($tf.n)..."
    $k = Get-K -interval $tf.i -limit 800
    if ($k -and $k.Count -ge 100) { $klineCache[$tf.n] = $k } else { Write-Output "    No data" }
}
Write-Output "  Cached $($klineCache.Count) timeframes"

# Phase 1: RSI bruteforce (fixed sort)
Write-Host "`n--- PHASE 1: RSI BRUTEFORCE ---" -ForegroundColor Yellow
$obs = @(60,64,68,72,76,80,84); $oss = @(20,24,28,32,36,40,44)
$allTf = @(); $tfNum = 0
Write-Output "  Testing RSI periods 5-50 (step 3) x 7 OB levels x 7 OS levels per timeframe..."

foreach ($tf in $tfDefs) {
    $tfNum++
    $k = $klineCache[$tf.n]
    if (-not $k) { Write-Output "  [$tfNum/7] $($tf.n) -- no data cached"; continue }
    $c = $k | % { [double]$_[4] }; $h = $k | % { [double]$_[2] }; $l = $k | % { [double]$_[3] }
    Write-Output "  [$tfNum/7] $($tf.n) ($($c.Count) candles)..."
    $bestPer = $null; $bestOb = $null; $bestOs = $null; $bestWr = 0; $bestTt = 0
    $bestLw = 0; $bestLl = 0; $bestSw = 0; $bestSl = 0

    foreach ($per in (5..50 | Where-Object { $_ % 3 -eq 2 -or $_ -eq 5 })) {
        $r = Calc-RSI $c $per; $perBestScore = 0; $perBest = $null
        foreach ($ob in $obs) {
            foreach ($os in $oss) {
                if ($os -ge ($ob - 15)) { continue }
                $lw=0;$ll=0;$sw=0;$sl=0
                for ($i = $per; $i -lt $c.Count-3; $i++) {
                    if ($r[$i-1] -gt $os -and $r[$i] -le $os -and $r[$i] -ne 0) {
                        $fL = ($c[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum
                        if (($c[$i]-$fL)/$c[$i]*100 -gt 1.0) { $lw++ } else { $ll++ }
                    }
                    if ($r[$i-1] -lt $ob -and $r[$i] -ge $ob -and $r[$i] -ne 100) {
                        $fH = ($c[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum
                        if (($fH-$c[$i])/$c[$i]*100 -gt 1.0) { $sw++ } else { $sl++ }
                    }
                }
                $total = $lw+$ll+$sw+$sl
                if ($total -ge 3) { $wr = [Math]::Round(($lw+$sw)/$total*100,1); $score = $wr*$total; if ($score -gt $perBestScore) { $perBestScore=$score; $perBest=@{per=$per;ob=$ob;os=$os;wr=$wr;lw=$lw;ll=$ll;sw=$sw;sl=$sl;total=$total} } }
            }
        }
        if ($perBest -and $perBest.wr -gt $bestWr) { $bestWr=$perBest.wr; $bestPer=$perBest.per; $bestOb=$perBest.ob; $bestOs=$perBest.os; $bestLw=$perBest.lw; $bestLl=$perBest.ll; $bestSw=$perBest.sw; $bestSl=$perBest.sl; $bestTt=$perBest.total }
    }
    if ($bestPer) {
        $allTf += [PSCustomObject]@{ tf=$tf.n; per=$bestPer; ob=$bestOb; os=$bestOs; wr=$bestWr; total=$bestTt; lw=$bestLw; ll=$bestLl; sw=$bestSw; sl=$bestSl }
        Write-Host "    => RSI($bestPer) OB=$bestOb OS=$bestOs | WR=$bestWr% ($bestTt sigs)" -ForegroundColor Green
    }
}

# FIXED SORT: use script block, explicitly cast
$sorted = $allTf | Sort-Object { [double]$_.wr } -Descending
Write-Output "`n  Rankings (sorted by WR descending):"
$sorted | % { Write-Output "    $($_.tf): RSI($($_.per)) OB=$($_.ob) OS=$($_.os) WR=$($_.wr)% ($($_.total) sigs)" }

$top3 = $sorted | Select-Object -First 3
Write-Output "`n  Top 3 timeframes: $($top3[0].tf) ($($top3[0].wr)%), $($top3[1].tf) ($($top3[1].wr)%), $($top3[2].tf) ($($top3[2].wr)%)"
Write-Bar 80

# Phase 2: Full indicator combos for each top timeframe
Write-Host "`n--- PHASE 2: INDICATOR COMBOS (TOP 3 TIMEFRAMES) ---" -ForegroundColor Yellow

$allResults = @() # store final config candidates

foreach ($winner in $top3) {
    Write-Host "`n>>> $($winner.tf): RSI($($winner.per)) OB=$($winner.ob) OS=$($winner.os) <<<" -ForegroundColor Cyan
    $k = $klineCache[$winner.tf]; if (-not $k) { continue }
    $c = $k | % { [double]$_[4] }; $h = $k | % { [double]$_[2] }; $l = $k | % { [double]$_[3] }
    $v = $k | % { [double]$_[5] }; $ts = $k | % { [long]$_[0] }

    $rsi  = Calc-RSI $c $winner.per
    $vma  = Calc-EMA $v 20
    $ma20 = Calc-EMA $c 20; $ma50 = Calc-EMA $c 50; $ma100 = Calc-EMA $c 100; $ma200 = Calc-EMA $c 200
    $adx  = Calc-ADX $h $l $c 14
    $stoch = Calc-StochRSI $c 14
    $atr  = Calc-ATR $h $l $c 14
    $atrAvg = ($atr[50..($atr.Count-1)] | Measure-Object -Average).Average

    $startI = [Math]::Max(70, $winner.per + 30)

    function Test-ICPCombo {
        param($tfName, $cfgName, $useVol, $volThr, $useMA, $maArr, $useADX, $adxThr, $useStoch, $stThr, $useATRreg)
        $c=$script:cfgCache[$tfName].c; $h=$script:cfgCache[$tfName].h; $l=$script:cfgCache[$tfName].l
        $v=$script:cfgCache[$tfName].v; $r=$script:cfgCache[$tfName].r; $vm=$script:cfgCache[$tfName].vma
        $a=$script:cfgCache[$tfName].adx; $s=$script:cfgCache[$tfName].stoch; $at=$script:cfgCache[$tfName].atr
        $atAvg=$script:cfgCache[$tfName].atrAvg; $ob=$script:cfgCache[$tfName].ob; $os=$script:cfgCache[$tfName].os
        $si=$script:cfgCache[$tfName].startI; $lw=0;$ll=0;$sw=0;$sl=0
        for ($i = $si; $i -lt $c.Count-5; $i++) {
            $vOk = if ($useVol) { $v[$i] -gt $vm[$i] * $volThr } else { $true }
            $maOkL = if ($useMA -and $maArr) { $c[$i] -gt $maArr[$i] } else { $true }
            $maOkS = if ($useMA -and $maArr) { $c[$i] -lt $maArr[$i] } else { $true }
            $adxOk = if ($useADX) { $a[$i] -gt $adxThr } else { $true }
            $stOkL = if ($useStoch) { $s[$i] -lt $stThr } else { $true }
            $stOkS = if ($useStoch) { $s[$i] -gt (100 - $stThr) } else { $true }
            $atrOk = if ($useATRreg) { $at[$i] -gt $atAvg } else { $true }
            if ($r[$i-1] -gt $os -and $r[$i] -le $os -and $r[$i] -ne 0 -and $vOk -and $maOkL -and $adxOk -and $stOkL -and $atrOk) {
                $fL = ($c[($i+1)..($i+3)] | Measure-Object -Minimum).Minimum
                if (($c[$i]-$fL)/$c[$i]*100 -gt 1.0) { $lw++ } else { $ll++ } }
            if ($r[$i-1] -lt $ob -and $r[$i] -ge $ob -and $r[$i] -ne 100 -and $vOk -and $maOkS -and $adxOk -and $stOkS -and $atrOk) {
                $fH = ($c[($i+1)..($i+3)] | Measure-Object -Maximum).Maximum
                if (($fH-$c[$i])/$c[$i]*100 -gt 1.0) { $sw++ } else { $sl++ } }
        }
        $t = $lw+$ll+$sw+$sl; $wr = if ($t) { [Math]::Round(($lw+$sw)/$t*100,1) } else { 0 }
        Write-Host ("    {0,-30} WR={1,-5}% | {2} sigs (L:{3}/{4} S:{5}/{6})" -f $cfgName, $wr, $t, $lw, ($lw+$ll), $sw, ($sw+$sl))
        return @{ tf=$tfName; cfg=$cfgName; wr=$wr; total=$t; lw=$lw; ll=$ll; sw=$sw; sl=$sl }
    }

    # Cache data for Test-ICPCombo
    $script:cfgCache = @{}
    $script:cfgCache[$winner.tf] = @{ c=$c; h=$h; l=$l; v=$v; r=$rsi; vma=$vma; adx=$adx; stoch=$stoch; atr=$atr; atrAvg=$atrAvg; ob=$winner.ob; os=$winner.os; startI=$startI }

    $comboList = @()
    $comboList += Test-ICPCombo $winner.tf "RSI alone" $false 0.8 $false $null $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol(0.7)" $true 0.7 $false $null $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol(0.8)" $true 0.8 $false $null $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol(0.9)" $true 0.9 $false $null $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol(1.0)" $true 1.0 $false $null $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+MA20" $true 0.8 $true $ma20 $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+MA50" $true 0.8 $true $ma50 $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+MA100" $true 0.8 $true $ma100 $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+MA200" $true 0.8 $true $ma200 $false 0 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+ADX(20)" $true 0.8 $false $null $true 20 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+ADX(25)" $true 0.8 $false $null $true 25 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+ADX(30)" $true 0.8 $false $null $true 30 $false 0 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+Stoch(20)" $true 0.8 $false $null $false 0 $true 20 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+Stoch(30)" $true 0.8 $false $null $false 0 $true 30 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+Stoch(40)" $true 0.8 $false $null $false 0 $true 40 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+ATRreg" $true 0.8 $false $null $false 0 $false 0 $true
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+MA50+ATR" $true 0.8 $true $ma50 $false 0 $false 0 $true
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+MA50+ADX+Stoch" $true 0.8 $true $ma50 $true 25 $true 30 $false
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+ADX(25)+ATR" $true 0.8 $false $null $true 25 $false 0 $true
    $comboList += Test-ICPCombo $winner.tf "RSI+Vol+ADX(30)+ATR" $true 0.8 $false $null $true 30 $false 0 $true

    # Find best combo by score (WR * total)
    $comboList | % { $_ | Add-Member -NotePropertyName score -NotePropertyValue ([Math]::Round($_.wr * $_.total, 1)) }
    $bestCombo = $comboList | Sort-Object score -Descending | Select-Object -First 1
    $bestComboEq = $comboList | Where-Object { $_.total -ge 5 } | Sort-Object score -Descending | Select-Object -First 1
    Write-Output "    ---"
    Write-Host ("    Best overall: {0} -- WR={1}% ({2} sigs) score={3}" -f $bestCombo.cfg, $bestCombo.wr, $bestCombo.total, $bestCombo.score) -ForegroundColor Green
    if ($bestComboEq.cfg -ne $bestCombo.cfg) { Write-Host ("    Best (>=5 sigs): {0} -- WR={1}% ({2} sigs)" -f $bestComboEq.cfg, $bestComboEq.wr, $bestComboEq.total) -ForegroundColor Yellow }

    # Determine the config to use for TP/SL and sim
    $useCfg = if ($bestCombo.total -ge 5) { $bestCombo } else { $bestComboEq }
    $useCfg = if (-not $useCfg) { $bestCombo } else { $useCfg }

    $allResults += @{
        tf = $winner.tf
        rsiCfg = "RSI($($winner.per)) OB=$($winner.ob) OS=$($winner.os)"
        baselineWr = $winner.wr
        baselineTotal = $winner.total
        bestComboName = $bestCombo.cfg
        bestComboWr = $bestCombo.wr
        bestComboTotal = $bestCombo.total
        useCfgName = $useCfg.cfg
        useCfgWr = $useCfg.wr
        useCfgTotal = $useCfg.total
        c = $c; h = $h; l = $l; v = $v; ts = $ts
        rsi = $rsi; vma = $vma
        rsiPer = $winner.per; ob = $winner.ob; os = $winner.os
        userCfgData = $useCfg
    }
    Write-Bar 60
}

# Phase 3: TP/SL for each top timeframe's best combo
Write-Host "`n--- PHASE 3: TP/SL BRUTEFORCE ---" -ForegroundColor Yellow
$tps = @(0.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0)
$sls = @(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0)

foreach ($res in $allResults) {
    Write-Host "`n>>> $($res.tf) with $($res.useCfgName) <<<" -ForegroundColor Cyan
    $c=$res.c; $h=$res.h; $l=$res.l; $v=$res.v; $rsi=$res.rsi; $vma=$res.vma
    $ob=$res.ob; $os=$res.os

    # Determine entry filters from useCfgName
    $useVol = $true; $volThr = 0.8
    if ($res.useCfgName -eq "RSI alone") { $useVol = $false }

    $le=@(); $se=@()
    for ($i = $res.rsiPer + 20; $i -lt $c.Count - 5; $i++) {
        $vOk = if ($useVol) { $v[$i] -gt $vma[$i] * $volThr } else { $true }
        if ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0 -and $vOk) { $le += @{ idx=$i; price=$c[$i] } }
        if ($rsi[$i-1] -lt $ob -and $rsi[$i] -ge $ob -and $rsi[$i] -ne 100 -and $vOk) { $se += @{ idx=$i; price=$c[$i] } }
    }
    Write-Output "  Entries: $($le.Count) long, $($se.Count) short"

    $tpResults = @()
    foreach ($tp in $tps) {
        foreach ($sl in $sls) {
            $tw=0;$tl=0;$tPnl=0;$tT=0
            foreach ($e in $le) {
                $hitPrice=$e.price*(1+$tp/100); $slipPrice=$e.price*(1-$sl/100); $hit=$null
                for ($j=$e.idx+1; $j -lt [Math]::Min($e.idx+48,$c.Count); $j++) { if ($h[$j] -ge $hitPrice) { $hit="TP"; break }; if ($l[$j] -le $slipPrice) { $hit="SL"; break } }
                if ($hit-eq"TP"){$tw++;$tPnl+=$tp}elseif($hit-eq"SL"){$tl++;$tPnl-=$sl};$tT++
            }
            foreach ($e in $se) {
                $hitPrice=$e.price*(1-$tp/100); $slipPrice=$e.price*(1+$sl/100); $hit=$null
                for ($j=$e.idx+1; $j -lt [Math]::Min($e.idx+48,$c.Count); $j++) { if ($l[$j] -le $hitPrice) { $hit="TP"; break }; if ($h[$j] -ge $slipPrice) { $hit="SL"; break } }
                if ($hit-eq"TP"){$tw++;$tPnl+=$tp}elseif($hit-eq"SL"){$tl++;$tPnl-=$sl};$tT++
            }
            if ($tT -ge 3) { $wr = [Math]::Round($tw/$tT*100,1); $score = $wr * $tT / 100; $tpResults += [PSCustomObject]@{TP=$tp;SL=$sl;WR=$wr;T=$tT;PnL=[Math]::Round($tPnl,2);S=[Math]::Round($score,1)} }
        }
    }

    Write-Output "  Top 3 by Score:"
    $tpResults | Sort-Object S -Descending | Select-Object -First 3 | % { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.T)t | PnL=$($_.PnL)%" }
    Write-Output "  Top 3 by WR (>=5 trades):"
    $tpResults | Where-Object { $_.T -ge 5 } | Sort-Object WR -Descending | Select-Object -First 3 | % { Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.T)t" }
    $bestRR = $tpResults | Where-Object { $_.T -ge 5 -and $_.TP -ge $_.SL } | Sort-Object S -Descending | Select-Object -First 1
    if ($bestRR) { Write-Output "  Best 1:1 R:R: TP=$($bestRR.TP)% SL=$($bestRR.SL)% | WR=$($bestRR.WR)% | $($bestRR.T)t | PnL=$($bestRR.PnL)%" }

    $res.tpWr = if ($bestRR) { $bestRR.WR } else { 0 }
    $res.tpPnl = if ($bestRR) { $bestRR.PnL } else { 0 }
    $res.tpTrades = if ($bestRR) { $bestRR.T } else { 0 }
    $res.tp = if ($bestRR) { $bestRR.TP } else { 0 }
    $res.sl = if ($bestRR) { $bestRR.SL } else { 0 }
}

# Phase 4: 3-month simulation for each (LONG only)
Write-Host "`n--- PHASE 4: 3-MONTH SIMULATIONS ---" -ForegroundColor Yellow
$startDt = [DateTimeOffset]::new(2026, 3, 12, 0, 0, 0, [TimeSpan]::Zero)
$startMs = $startDt.ToUnixTimeMilliseconds()

foreach ($res in $allResults) {
    Write-Host "`n>>> $($res.tf) with $($res.useCfgName) <<<" -ForegroundColor Cyan
    $c=$res.c; $h=$res.h; $l=$res.l; $v=$res.v; $ts=$res.ts; $rsi=$res.rsi; $vma=$res.vma
    $ob=$res.ob; $os=$res.os
    $useVol = $res.useCfgName -ne "RSI alone"

    $sIdx = 0; for ($i=0; $i -lt $ts.Count; $i++) { if ($ts[$i] -ge $startMs) { $sIdx=$i; break } }
    $capital=100.0; $wins=0; $losses=0; $tT=0; $log=@()

    for ($i = [Math]::Max($sIdx, $res.rsiPer+20); $i -lt $c.Count - 5; $i++) {
        $vOk = if ($useVol) { $v[$i] -gt $vma[$i] * 0.8 } else { $true }
        if (-not ($rsi[$i-1] -gt $os -and $rsi[$i] -le $os -and $rsi[$i] -ne 0 -and $vOk)) { continue }
        $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i])

        $entry = $c[$i]; $tpP = $entry * 1.005; $slP = $entry * 0.995
        $hit = $null
        for ($j = $i+1; $j -lt [Math]::Min($i+48, $c.Count); $j++) { if ($h[$j] -ge $tpP) { $hit="TP"; break }; if ($l[$j] -le $slP) { $hit="SL"; break } }

        $units = $capital / $entry
        $pnl = 0
        if ($hit -eq "TP") { $pnl = $units * ($entry * 0.5/100) - ($units * $entry * 0.1/100); $wins++ }
        else { $pnl = -$units * ($entry * 0.5/100) - ($units * $entry * 0.1/100); $losses++ }
        $tT++; $capital += $pnl
        $log += [PSCustomObject]@{ D=$dt.ToString('MM-dd'); P=[Math]::Round($entry,4); R=if($hit-eq"TP"){"TP"}else{"SL"}; Pnl=[Math]::Round($pnl,4); Cap=[Math]::Round($capital,2) }
    }
    $wr = if ($tT) { [Math]::Round($wins/$tT*100,1) } else { 0 }
    $ret = [Math]::Round(($capital-100)/100*100,2)
    Write-Output "  Trades: $tT ($wins W / $losses L) | WR: $wr%"
    Write-Output "  Start: 100 | Final: $([Math]::Round($capital,2)) | Return: $ret%"
    $log | Format-Table -AutoSize
    $res.simWr = $wr; $res.simTrades = $tT; $res.simReturn = $ret
}

# Phase 5: Summary
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Output ""
Write-Output ("{0,-6} {1,-22} {2,-8} {3,-8} {4,-13} {5,-8} {6,-10} {7,-8} {8,-8}" -f "TF", "Best Combo", "ComboWR", "Sigs", "TP/SL WR", "Trades", "Sim WR", "Sim Trades", "Sim Ret%")
Write-Output ("-" * 110)
foreach ($res in $allResults) {
    Write-Output ("{0,-6} {1,-22} {2,-7}% {3,-7} {4,-7}% {5,-7} {6,-7}% {7,-9} {8,-7}%" -f $res.tf, $res.useCfgName, $res.useCfgWr, $res.useCfgTotal, $res.tpWr, $res.tpTrades, $res.simWr, $res.simTrades, $res.simReturn)
}

# Rank by combined score
$allResults | % { $_.combinedScore = $_.useCfgWr + $_.tpWr + $_.simWr }
$finalRank = $allResults | Sort-Object combinedScore -Descending
Write-Output "`nFinal ranking (by WR sum):"
$finalRank | % { Write-Output "  $($_.tf): combo=$($_.useCfgWr)% + TP/SL=$($_.tpWr)% + sim=$($_.simWr)% = $($_.combinedScore)" }

$best = $finalRank[0]
Write-Host "`n=== BEST CONFIG: $($best.tf) $($best.useCfgName) ===" -ForegroundColor Green
Write-Host "  RSI: $($best.rsiCfg)" -ForegroundColor Green
Write-Host "  TP=$($best.tp)% SL=$($best.sl)%" -ForegroundColor Green

# Phase 6: Live signal for the best config
Write-Host "`n--- LIVE SIGNAL ($($best.tf) $($best.useCfgName)) ---" -ForegroundColor Yellow
$c=$best.c; $h=$best.h; $l=$best.l; $v=$best.v; $ts=$best.ts; $rsi=$best.rsi; $vma=$best.vma
$ob=$best.ob; $os=$best.os; $lp=$c[-1]; $lr=$rsi[-1]; $pr=$rsi[-2]; $ldt=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1])
Write-Output "  $($best.tf) @ $($ldt.ToString('MM-dd HH:mm')) UTC"
Write-Output "  Price: $([Math]::Round($lp,4)) | RSI($($best.rsiPer)): $([Math]::Round($lr,1)) (prev $([Math]::Round($pr,1)))"
Write-Output "  OB=$ob OS=$os | Vol vs MA20: $([Math]::Round($v[-1]/$vma[-1]*100,0))%"
if ($pr -gt $os -and $lr -le $os -and $lr -ne 0 -and $v[-1] -gt $vma[-1]*0.8) { Write-Host "  >>> LONG SIGNAL <<<" -ForegroundColor Green }
elseif ($pr -lt $ob -and $lr -ge $ob -and $lr -ne 100 -and $v[-1] -gt $vma[-1]*0.8) { Write-Host "  >>> SHORT SIGNAL <<<" -ForegroundColor Red }
else { Write-Output "  No signal (RSI=$([Math]::Round($lr,1)) between $os-$ob)" }

Write-Host "`n=== ICP DEEP DIVE COMPLETE ===" -ForegroundColor Cyan
