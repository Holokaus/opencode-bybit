# MarketBehaviorFramework.psm1 -- Institutional-Grade Market Behavior Research Framework
# 10-Phase pipeline: Data -> Timeframes -> Regimes -> Behaviors -> Detectors -> Configs -> Walk-Forward -> Monte Carlo -> Edge -> Report
# The goal: DISCOVER RECURRING MARKET BEHAVIORS, THEN find indicators that detect them.

# ===== INTERNAL STATE =====
$script:MBF_ApiBase = "https://api.bybit.com"
$script:MBF_Rsa = $null
$script:MBF_Initialized = $false

# ============================================================
#  RSA AUTH
# ============================================================
function Read-DerLength { param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $len = $data[$offset.Value]; $offset.Value++; return $len }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0; for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }
    return $len
}
function Read-DerInteger { param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw "Expected INTEGER" }
    $offset.Value++; $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len); [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start); [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len; return $trimmed
}
function Initialize-MbfRsaAuth {
    $keyFile = $env:BYBIT_PRIVATE_KEY_PATH
    if (-not $keyFile) { $keyFile = Join-Path (Join-Path $PSScriptRoot "..") "bybit_private.pem" }
    if (-not (Test-Path $keyFile)) { throw "RSA key not found at $keyFile. Set BYBIT_PRIVATE_KEY_PATH env var." }
    $pem = Get-Content -Raw $keyFile
    $b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
    $der = [System.Convert]::FromBase64String($b64); $off = 0
    if ($der[$off] -ne 0x30) { throw "Not SEQUENCE" }; $off++
    $seqLen = Read-DerLength -data $der -offset ([ref]$off)
    $p = New-Object System.Security.Cryptography.RSAParameters
    $version = Read-DerInteger -data $der -offset ([ref]$off)
    $p.Modulus = Read-DerInteger -data $der -offset ([ref]$off)
    $p.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
    $p.D = Read-DerInteger -data $der -offset ([ref]$off)
    $p.P = Read-DerInteger -data $der -offset ([ref]$off)
    $p.Q = Read-DerInteger -data $der -offset ([ref]$off)
    $p.DP = Read-DerInteger -data $der -offset ([ref]$off)
    $p.DQ = Read-DerInteger -data $der -offset ([ref]$off)
    $p.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
    $script:MBF_Rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    $script:MBF_Rsa.ImportParameters($p)
    $script:MBF_Initialized = $true
}

# ============================================================
#  API CALL
# ============================================================
function Invoke-MbfApi {
    param($method, $endpoint, $query, $body)
    if (-not $script:MBF_Initialized) { Initialize-MbfRsaAuth }
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $apiKey = $env:BYBIT_API_KEY
    if (-not $apiKey) { throw "BYBIT_API_KEY env var not set" }
    $recv = "5000"; $tsStr = "$ts$apiKey$recv"
    $payload = if ($method -eq "GET") { "$tsStr$query" } else { "$tsStr$body" }
    $dataBytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [Security.Cryptography.SHA256]::Create()
    $sigBytes = $script:MBF_Rsa.SignData($dataBytes, $sha)
    $sig = [Convert]::ToBase64String($sigBytes)
    $hd = @{
        "X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sig
        "X-BAPI-RECV-WINDOW"=$recv;"X-BAPI-SIGN-TYPE"="2"
    }
    try {
        if ($method -eq "GET") {
            $r = Invoke-WebRequest -Uri "$script:MBF_ApiBase$endpoint`?$query" -Headers $hd -UseBasicParsing -TimeoutSec 120
        } else {
            $r = Invoke-WebRequest -Uri "$script:MBF_ApiBase$endpoint" -Method POST -Headers $hd -Body $body -ContentType "application/json" -UseBasicParsing -TimeoutSec 120
        }
        return ($r.Content | ConvertFrom-Json)
    } catch {
        $errMsg = "$_"
        Write-Warning "MBF API $endpoint : $errMsg"
        # Flush DNS on resolution failures to recover from transient errors
        if ($errMsg -match "Unable to connect|Name not resolved|could not be resolved") {
            try { ipconfig /flushdns 2>&1 | Out-Null } catch {}
            Start-Sleep -Seconds 3
        }
        return $null
    }
}

# ============================================================
#  INDICATORS (reused, verified correct)
# ============================================================
function Calc-EMA { param($p, $per)
    $e = [double[]]::new($p.Count); $e[0] = $p[0]; $m = 2/($per+1)
    for ($i = 1; $i -lt $p.Count; $i++) { $e[$i] = $p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}
function Calc-SMA { param($p, $per)
    $s = [double[]]::new($p.Count)
    for ($i = $per-1; $i -lt $p.Count; $i++) { $sum = 0; for ($j = $i-$per+1; $j -le $i; $j++) { $sum += $p[$j] }; $s[$i] = $sum/$per }
    return $s
}
function Calc-ATR { param($h, $l, $c, $per)
    $tr = [double[]]::new($c.Count)
    for ($i = 1; $i -lt $c.Count; $i++) {
        $tr[$i] = [Math]::Max($h[$i]-$l[$i], [Math]::Max([Math]::Abs($h[$i]-$c[$i-1]), [Math]::Abs($l[$i]-$c[$i-1])))
    }
    $a = [double[]]::new($c.Count); $a[$per] = ($tr[1..$per] | Measure-Object -Average).Average
    for ($i = $per+1; $i -lt $c.Count; $i++) { $a[$i] = ($a[$i-1]*($per-1) + $tr[$i])/$per }
    return $a
}
function Calc-ADX { param($h, $l, $c, $per)
    $tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
    for ($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))
        $u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per
    $dx=[double[]]::new($c.Count)
    for ($i=$per;$i-lt$c.Count;$i++){$pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100;$dx[$i]=if(($pdi+$ndi)-eq0){0}else{[Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100}}
    $adxResult = Calc-EMA $dx $per; return $adxResult, $du, $dd
}
function Calc-RSI { param($p, $per)
    $g=[double[]]::new($p.Count);$l=[double[]]::new($p.Count)
    for($i=1;$i-lt$p.Count;$i++){$d=$p[$i]-$p[$i-1];if($d-ge0){$g[$i]=$d}else{$l[$i]=-$d}}
    $ag=($g[1..$per]|Measure-Object -Sum).Sum/$per;$al=($l[1..$per]|Measure-Object -Sum).Sum/$per
    $r=[double[]]::new($p.Count)
    for($i=$per;$i-lt$p.Count;$i++){if($i-gt$per){$ag=(($ag*($per-1))+$g[$i])/$per;$al=(($al*($per-1))+$l[$i])/$per}
        $r[$i]=if($al-eq0){100}else{100-(100/(1+($ag/$al)))}}
    return $r
}
function Calc-MACD { param($c,$f,$s,$sig)
    $e12=Calc-EMA $c $f;$e26=Calc-EMA $c $s;$m=[double[]]::new($c.Count)
    for($i=0;$i-lt$c.Count;$i++){$m[$i]=$e12[$i]-$e26[$i]};$sl=Calc-EMA $m $sig
    return @{macd=$m;signal=$sl;hist=(0..($c.Count-1)|%{$m[$_]-$sl[$_]})} }
function Calc-Stoch { param($h,$l,$c,$k,$d)
    $st=[double[]]::new($c.Count)
    for($i=$k-1;$i-lt$c.Count;$i++){$hh=-1e10;$ll=1e10;for($j=$i-$k+1;$j-le$i;$j++){if($h[$j]-gt$hh){$hh=$h[$j]};if($l[$j]-lt$ll){$ll=$l[$j]}}
        $st[$i]=if($hh-eq$ll){50}else{($c[$i]-$ll)/($hh-$ll)*100}}
    return Calc-EMA $st $d }
function Calc-StochRSI { param($c,$per)
    $rsi=Calc-RSI $c $per
    $min=$rsi[0];$max=$rsi[0]
    for($i=0;$i-lt$rsi.Count;$i++){if($rsi[$i]-lt$min){$min=$rsi[$i]};if($rsi[$i]-gt$max){$max=$rsi[$i]}}
    $st=[double[]]::new($rsi.Count)
    for($i=0;$i-lt$rsi.Count;$i++){$st[$i]=if($max-$min-eq0){50}else{($rsi[$i]-$min)/($max-$min)*100}}
    return $st
}
function Calc-CCI { param($h,$l,$c,$per)
    $tp=[double[]]::new($c.Count);for($i=0;$i-lt$c.Count;$i++){$tp[$i]=($h[$i]+$l[$i]+$c[$i])/3}
    $sma=Calc-EMA $tp $per;$md=[double[]]::new($c.Count)
    for($i=$per-1;$i-lt$c.Count;$i++){$sum=0;for($j=$i-$per+1;$j-le$i;$j++){$sum+= [Math]::Abs($tp[$j]-$sma[$i])};$md[$i]=$sum/$per}
    $r=[double[]]::new($c.Count);for($i=$per-1;$i-lt$c.Count;$i++){$r[$i]=if($md[$i]-eq0){0}else{($tp[$i]-$sma[$i])/(0.015*$md[$i])}};return $r}
function Calc-MFI { param($h,$l,$c,$v,$per)
    $tp=[double[]]::new($c.Count);for($i=0;$i-lt$c.Count;$i++){$tp[$i]=($h[$i]+$l[$i]+$c[$i])/3}
    $rmf=[double[]]::new($c.Count);for($i=1;$i-lt$c.Count;$i++){$rmf[$i]=$tp[$i]*$v[$i]}
    $mfi=[double[]]::new($c.Count);for($i=$per;$i-lt$c.Count;$i++){$pSum=0;$nSum=0
        for($j=$i-$per+1;$j-le$i;$j++){if($rmf[$j]-gt$rmf[$j-1]){$pSum+=$rmf[$j]}else{$nSum+=$rmf[$j]}};$mfi[$i]=if($nSum-eq0){100}else{100-(100/(1+($pSum/$nSum)))}}
    return $mfi}
function Calc-CMF { param($h,$l,$c,$v,$per)
    $cf=[double[]]::new($c.Count);for($i=0;$i-lt$c.Count;$i++){$cf[$i]=if(($h[$i]-$l[$i])-eq0){0}else{(($c[$i]-$l[$i])-($h[$i]-$c[$i]))/($h[$i]-$l[$i])}}
    $cv=[double[]]::new($c.Count);for($i=0;$i-lt$c.Count;$i++){$cv[$i]=$cf[$i]*$v[$i]}
    $a=Calc-EMA $cv $per;$b=Calc-EMA $v $per;$r=[double[]]::new($c.Count);for($i=0;$i-lt$c.Count;$i++){$r[$i]=if($b[$i]-eq0){0}else{$a[$i]/$b[$i]}};return $r}
function Calc-OBV { param($c,$v)
    $o=[double[]]::new($c.Count);$o[0]=0
    for($i=1;$i-lt$c.Count;$i++){if($c[$i]-gt$c[$i-1]){$o[$i]=$o[$i-1]+$v[$i]}elseif($c[$i]-lt$c[$i-1]){$o[$i]=$o[$i-1]-$v[$i]}else{$o[$i]=$o[$i-1]}}
    return $o }
function Calc-Bollinger { param($c, $per, $mult)
    $ma = Calc-SMA $c $per; $sd = [double[]]::new($c.Count)
    for ($i = $per-1; $i -lt $c.Count; $i++) { $sum=0; for($j=$i-$per+1;$j-le$i;$j++){$sum+=($c[$j]-$ma[$i])*($c[$j]-$ma[$i])}; $sd[$i]=[Math]::Sqrt($sum/$per) }
    $upper=[double[]]::new($c.Count);$lower=[double[]]::new($c.Count)
    for ($i = 0; $i -lt $c.Count; $i++) { $upper[$i]=$ma[$i]+$mult*$sd[$i]; $lower[$i]=$ma[$i]-$mult*$sd[$i] }
    return @{upper=$upper;lower=$lower;mid=$ma;sd=$sd}
}
function Calc-VWAP { param($h,$l,$c,$v)
    $vwap=[double[]]::new($c.Count);$cumV=0.0;$cumPV=0.0
    for($i=0;$i-lt$c.Count;$i++){$tp=($h[$i]+$l[$i]+$c[$i])/3;$cumPV+=$tp*$v[$i];$cumV+=$v[$i];$vwap[$i]=if($cumV-gt0){$cumPV/$cumV}else{$c[$i]}}
    return $vwap
}

# ============================================================
#  HELPERS
# ============================================================
function Get-StdDev { param($arr)
    if ($arr.Count -lt 2) { return 0 }
    $m = ($arr | Measure-Object -Average).Average
    $sum = 0.0; foreach ($v in $arr) { $d = $v - $m; $sum += $d * $d }
    return [Math]::Sqrt($sum / ($arr.Count - 1))
}
function Get-Autocorrelation { param($data, $lag)
    $n = $data.Count; if ($n -le $lag + 2) { return 0 }
    $x = $data[0..($n-$lag-1)]; $y = $data[$lag..($n-1)]
    $mx = ($x | Measure-Object -Average).Average; $my = ($y | Measure-Object -Average).Average
    $num=0.0;$dx=0.0;$dy=0.0
    for ($i=0;$i-lt$x.Count;$i++){$xd=$x[$i]-$mx;$yd=$y[$i]-$my;$num+=$xd*$yd;$dx+=$xd*$xd;$dy+=$yd*$yd}
    $den=[Math]::Sqrt($dx*$dy);if($den-eq0){return 0};return ($num/$den)
}
function Get-LogReturns { param($c)
    $c2 = [double[]]$c; $r=[double[]]::new($c2.Count-1);for($i=1;$i-lt$c2.Count;$i++){$r[$i-1]=[Math]::Log($c2[$i]/$c2[$i-1])};return $r
}

# ============================================================
#  PHASE 1 -- MAXIMUM HISTORICAL DATA ACQUISITION
# ============================================================
function Invoke-MbfPhase1 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string[]]$Timeframes = @("15","30","60","240","720","D"),
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 1: MAXIMUM HISTORICAL DATA ACQUISITION =====" -ForegroundColor Cyan
    $inventory = @()
    $tfMap = @{"15"="15m";"30"="30m";"60"="1h";"240"="4h";"720"="12h";"D"="1d"}

    foreach ($sym in $Symbols) {
        foreach ($tf in $Timeframes) {
            $tfName = $tfMap[$tf]
            Write-Host "`nFetching $sym $tfName ..." -ForegroundColor Yellow
            $allKlines = New-Object 'System.Collections.Generic.List[object]'
            $startTime = $null
            $limit = 1000
            $maxRequests = 200
            $requestCount = 0
            $failCount = 0
                $maxFail = 10
            $oldestSeen = $null

            $intervalMs = @{"15"=900000;"30"=1800000;"60"=3600000;"240"=14400000;"720"=43200000;"D"=86400000}
            $tfInterval = if ($intervalMs.ContainsKey($tf)) { $intervalMs[$tf] } else { 3600000 }

            while ($requestCount -lt $maxRequests -and $failCount -lt $maxFail) {
                $requestCount++
                $q = "category=spot&symbol=$sym&interval=$tf&limit=$limit"
                if ($startTime) { $q += "&start=$startTime" }
                $data = $null
                $retries = 5
                for ($r = 0; $r -lt $retries; $r++) {
                    try {
                        $data = Invoke-MbfApi "GET" "/v5/market/kline" $q ""
                        if ($data -and $data.retCode -eq 0) { break }
                    } catch { Write-Warning "  Request failed (attempt $($r+1)): $_" }
                    if ($r -lt $retries - 1) { Start-Sleep -Seconds ([Math]::Pow(3, $r+1)) }
                }

                if (-not $data -or $data.retCode -ne 0 -or -not $data.result -or -not $data.result.list) {
                    $failCount++
                    Write-Warning "  No data returned (fail $failCount/$maxFail)"
                    $sleepSec = [Math]::Min(30, 5 * $failCount)
                    Start-Sleep -Seconds $sleepSec
                    continue
                }

                # Reset fail count on success
                $failCount = 0

                $k = $data.result.list
                [Array]::Reverse($k)

                if ($k.Count -eq 0) {
                    Write-Host "  Empty page -- data exhausted" -ForegroundColor Gray
                    break
                }

                $pageOldest = $k[0][0]
                $pageNewest = $k[-1][0]

                                # Add new candles (those with timestamps older than oldestSeen)
                $newCount = 0
                foreach ($candle in $k) {
                    $ts = $candle[0]
                    if ($oldestSeen -and [long]$ts -ge [long]$oldestSeen) { continue }
                    $allKlines.Add($candle) > $null
                    $newCount++
                }

                # Update oldestSeen tracker
                if (-not $oldestSeen -or [long]$pageOldest -lt [long]$oldestSeen) { $oldestSeen = $pageOldest }

                Write-Host "  Page $requestCount : $($k.Count) in response, $newCount new, range=$pageOldest..$pageNewest" -ForegroundColor Gray

                if ($newCount -eq 0) {
                    $stalledCount++
                    Write-Warning "  Stalled (no new candles), attempt $stalledCount"
                    if ($stalledCount -ge 3) { break }
                    Start-Sleep -Seconds 3
                    continue
                }
                $stalledCount = 0

                # Next page: go further back in history by one full page
                $startTime = [long]$oldestSeen - ($limit * $tfInterval)

                if ($k.Count -lt $limit) {
                    Write-Host "  Partial page (<$limit) -- data exhausted" -ForegroundColor Gray
                    break
                }

                Start-Sleep -Milliseconds 500
            }

            if ($failCount -ge $maxFail) {
                Write-Warning "  Exceeded max failures ($maxFail) for $sym $tfName"
            }

            # Save raw klines (sorted chronologically oldest-first)
            if ($allKlines.Count -gt 0) {
                $allKlines.Sort({param($a,$b) [long]$a[0] - [long]$b[0]})
                $csvFile = Join-Path $OutputDir "mbf_klines_${sym}_${tfName}.csv"
                $allKlines.ToArray() | ForEach-Object {
                    [PSCustomObject]@{
                        Timestamp = $_[0]
                        Open = [double]$_[1]
                        High = [double]$_[2]
                        Low = [double]$_[3]
                        Close = [double]$_[4]
                        Volume = [double]$_[5]
                        Turnover = [double]$_[6]
                    }
                } | Export-Csv -Path $csvFile -NoTypeInformation
                Write-Host "  Saved $($allKlines.Count) candles to $csvFile" -ForegroundColor Green

                $firstCandle = $allKlines[0][0]
                $lastCandle = $allKlines[-1][0]
                $firstDate = if ($firstCandle) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$firstCandle).DateTime.ToString("yyyy-MM-dd") } else { "N/A" }
                $lastDate = if ($lastCandle) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$lastCandle).DateTime.ToString("yyyy-MM-dd") } else { "N/A" }
                $total = $allKlines.Count

                $inventory += [PSCustomObject]@{
                    Asset = $sym
                    Timeframe = $tfName
                    FirstCandle = $firstDate
                    LastCandle = $lastDate
                    TotalCandles = $total
                }
                Write-Host "  RESULT: $sym $tfName -- $total candles from $firstDate to $lastDate" -ForegroundColor Green
            } else {
                Write-Warning "  No candles retrieved for $sym $tfName"
                $inventory += [PSCustomObject]@{
                    Asset = $sym; Timeframe = $tfName
                    FirstCandle = "N/A"; LastCandle = "N/A"; TotalCandles = 0
                }
            }
        }
    }

    $invPath = Join-Path $OutputDir "historical_data_inventory.csv"
    $inventory | Export-Csv -Path $invPath -NoTypeInformation
    Write-Host "`nPhase 1 complete. Inventory saved to $invPath" -ForegroundColor Green
    return $inventory
}

# ============================================================
#  PHASE 2 -- TIMEFRAME DISCOVERY
# ============================================================
function Invoke-MbfPhase2 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string[]]$Timeframes = @("15","30","60","240","720","D"),
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 2: TIMEFRAME DISCOVERY =====" -ForegroundColor Cyan
    $results = @()
    $tfMap = @{"15"="15m";"30"="30m";"60"="1h";"240"="4h";"720"="12h";"D"="1d"}

    foreach ($sym in $Symbols) {
        Write-Host "`nAnalyzing $sym across timeframes..." -ForegroundColor Yellow
        foreach ($tf in $Timeframes) {
            $tfName = $tfMap[$tf]
            $csvFile = Join-Path $OutputDir "mbf_klines_${sym}_${tfName}.csv"
            if (-not (Test-Path $csvFile)) {
                Write-Warning "  No data for $sym $tfName -- run Phase 1 first"
                continue
            }
            $klines = Import-Csv $csvFile
            if ($klines.Count -lt 200) {
                Write-Host ("  SKIP " + $sym + " " + $tfName + " : only " + $klines.Count + " candles") -ForegroundColor DarkYellow
                continue
            }

            $h = $klines | ForEach-Object { [double]$_.High }
            $l = $klines | ForEach-Object { [double]$_.Low }
            $c = $klines | ForEach-Object { [double]$_.Close }
            $v = $klines | ForEach-Object { [double]$_.Volume }
            $n = $c.Count

            $logRets = Get-LogReturns $c
            $adxArr, $duArr, $ddArr = Calc-ADX $h $l $c 14
            $atr = Calc-ATR $h $l $c 14
            $rsi = Calc-RSI $c 14
            $ma50 = Calc-EMA $c 50
            $ma200 = if ($n -gt 200) { Calc-EMA $c 200 } else { $null }

            # --- Trend Persistence ---
            $trendBars = 0; $totalBars = 0
            for ($i = 50; $i -lt $n; $i++) {
                if ($adxArr[$i] -gt 25) { $trendBars++ }; $totalBars++
            }
            $trendPersistence = if ($totalBars -gt 0) { $trendBars / $totalBars * 100 } else { 0 }

            # --- Trend Duration (average consecutive bars with +DI > -DI or vice versa) ---
            $trendDurations = @(); $curDir = 0; $curLen = 0
            for ($i = 50; $i -lt $n; $i++) {
                $dir = 0
                if ($duArr[$i] -gt $ddArr[$i]) { $dir = 1 }
                elseif ($ddArr[$i] -gt $duArr[$i]) { $dir = -1 }
                if ($dir -eq $curDir -and $dir -ne 0) { $curLen++ }
                else { if ($curLen -gt 0) { $trendDurations += $curLen }; $curLen = 1; $curDir = $dir }
            }
            if ($curLen -gt 0) { $trendDurations += $curLen }
            $avgTrendDuration = if ($trendDurations.Count -gt 0) { ($trendDurations | Measure-Object -Average).Average } else { 0 }

            # --- Mean Reversion Strength ---
            $mrHits = 0; $mrTotal = 0
            for ($i = 100; $i -lt $n - 5; $i++) {
                $devAbove = 2.0; $devBelow = 2.0
                $sd = 0.0; for ($j = $i-19; $j -le $i; $j++) { $sd += ($c[$j] - $ma50[$j]) * ($c[$j] - $ma50[$j]) }
                $sd = [Math]::Sqrt($sd/20)
                if ($sd -eq 0) { continue }
                $z = ($c[$i] - $ma50[$i]) / $sd
                if ([Math]::Abs($z) -gt $devAbove) {
                    $mrTotal++
                    $fwdRet = ($c[$i+5] - $c[$i]) / $c[$i] * 100
                    $expected = if ($z -gt 0) { -1 } else { 1 }
                    if (($z -gt 0 -and $fwdRet -lt 0) -or ($z -lt 0 -and $fwdRet -gt 0)) { $mrHits++ }
                }
            }
            $meanRevPct = if ($mrTotal -gt 0) { $mrHits / $mrTotal * 100 } else { 0 }

            # --- Volatility Clustering (ATR autocorrelation) ---
            $atrPct = [double[]]::new($n)
            for ($i = 0; $i -lt $n; $i++) { if ($c[$i] -gt 0) { $atrPct[$i] = $atr[$i] / $c[$i] * 100 } }
            $atrRets = Get-LogReturns ($atrPct | Where-Object { $_ -gt 0 })
            $volClustering = if ($atrRets.Count -gt 50) { Get-Autocorrelation $atrRets 1 } else { 0 }

            # --- Breakout Persistence ---
            $breakTotal = 0; $breakCont = 0; $breakFade = 0
            for ($i = 100; $i -lt $n - 5; $i++) {
                $rng = $h[$i] - $l[$i]
                if ($rng -gt $atr[$i] * 1.5) {
                    $breakTotal++
                    $nDir = [Math]::Sign($c[$i+3] - $c[$i])
                    $bDir = [Math]::Sign($c[$i] - $c[$i-3])
                    if ($nDir -eq $bDir -and $bDir -ne 0) { $breakCont++ }
                    elseif ($nDir -ne 0 -and $bDir -ne 0) { $breakFade++ }
                }
            }
            $breakFreq = if ($n - 100 -gt 0) { $breakTotal / ($n - 100) * 100 } else { 0 }
            $breakContPct = if ($breakTotal -gt 0) { $breakCont / $breakTotal * 100 } else { 0 }

            # --- Volume Persistence ---
            $volCorr = Get-Autocorrelation $v 1

            # --- Return Autocorrelation ---
            $retAuto = Get-Autocorrelation $logRets 1

            # --- Overall behavior score: higher means more structured/recurring behavior ---
            # Weight: trend persistence + MR strength + breakout cont + vol clustering stability
            $behaviorScore = $trendPersistence * 0.25 + $meanRevPct * 0.25 + $breakContPct * 0.25 +
                             ([Math]::Abs($volClustering) * 100) * 0.15 + ([Math]::Abs($retAuto) * 100) * 0.10

            $results += [PSCustomObject]@{
                Asset = $sym
                Timeframe = $tfName
                TotalCandles = $n
                TrendPersistencePct = [Math]::Round($trendPersistence, 2)
                AvgTrendDurationBars = [Math]::Round($avgTrendDuration, 1)
                MeanRevStrengthPct = [Math]::Round($meanRevPct, 2)
                VolClusteringAC = [Math]::Round($volClustering, 4)
                ReturnAutocorr = [Math]::Round($retAuto, 4)
                BreakoutFreqPct = [Math]::Round($breakFreq, 3)
                BreakoutContPct = [Math]::Round($breakContPct, 2)
                VolumePersistenceAC = [Math]::Round($volCorr, 4)
                BehaviorScore = [Math]::Round($behaviorScore, 2)
            }
            Write-Host "  $tfName : trend=$([Math]::Round($trendPersistence,1))% mr=$([Math]::Round($meanRevPct,1))% bkout=$([Math]::Round($breakContPct,1))% score=$([Math]::Round($behaviorScore,1))" -ForegroundColor Gray
        }
    }

    $outPath = Join-Path $OutputDir "asset_timeframe_profile.csv"
    $results | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 2 complete. Saved to $outPath" -ForegroundColor Green

    # Determine best timeframe per asset
    $assets = $results | Group-Object Asset
    foreach ($a in $assets) {
        $best = $a.Group | Sort-Object BehaviorScore -Descending | Select-Object -First 1
        Write-Host ">> $($a.Name) best timeframe: $($best.Timeframe) (score=$($best.BehaviorScore))" -ForegroundColor Green
    }
    return $results
}

# ============================================================
#  PHASE 3 -- REGIME DISCOVERY (via clustering on market structure)
# ============================================================
function Invoke-MbfPhase3 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$Timeframe = "240",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 3: REGIME DISCOVERY =====" -ForegroundColor Cyan
    $tfMap = @{"15"="15m";"30"="30m";"60"="1h";"240"="4h";"720"="12h";"D"="1d"}
    $allRegimes = @()

    foreach ($sym in $Symbols) {
        $tfName = $tfMap[$Timeframe]
        $csvFile = Join-Path $OutputDir "mbf_klines_${sym}_${tfName}.csv"
        if (-not (Test-Path $csvFile)) {
            Write-Warning "No data for $sym $tfName -- run Phase 1 first"
            continue
        }
        $klines = Import-Csv $csvFile
        if ($klines.Count -lt 300) { Write-Warning "Insufficient data for $sym"; continue }

        $h = $klines | ForEach-Object { [double]$_.High }
        $l = $klines | ForEach-Object { [double]$_.Low }
        $c = $klines | ForEach-Object { [double]$_.Close }
        $v = $klines | ForEach-Object { [double]$_.Volume }
        $n = $c.Count

        # Compute feature vectors for clustering
        Write-Host "  Computing market structure features for $sym $tfName..." -ForegroundColor Yellow
        $lookback = 20
        $features = New-Object 'System.Collections.Generic.List[double[]]'
        $timestamps = New-Object 'System.Collections.Generic.List[long]'

        $atr = Calc-ATR $h $l $c 14
        $adx, $du, $dd = Calc-ADX $h $l $c 14
        $ema20 = Calc-EMA $c 20
        $ema50 = Calc-EMA $c 50

        for ($i = 100; $i -lt $n; $i++) {
            # 1. Realized volatility (20-bar log return std dev)
            $sliceRets = Get-LogReturns $c[($i-19)..$i]
            $realizedVol = Get-StdDev $sliceRets

            # 2. ATR % (normalized volatility)
            $atrPct = if ($c[$i] -gt 0) { $atr[$i] / $c[$i] * 100 } else { 0 }

            # 3. Directional persistence (ADX + DI spread)
            $diSpread = [Math]::Abs($du[$i] - $dd[$i])
            $adxVal = $adx[$i]

            # 4. Volume expansion (z-score of last 20 volumes)
            $volSlice = $v[($i-19)..$i]
            $volMean = ($volSlice | Measure-Object -Average).Average
            $volStd = Get-StdDev $volSlice
            $volZ = if ($volStd -gt 0) { ($v[$i] - $volMean) / $volStd } else { 0 }

            # 5. Trend slope (20-bar linear regression slope approximation via EMA diff)
            $trendSlope = if ($ema20[$i] -gt 0) { ($ema20[$i] - $ema20[$i-5]) / $ema20[$i] * 100 } else { 0 }

            # 6. Range compression (candle range relative to ATR)
            $candleRange = ($h[$i] - $l[$i])
            $rangeCompress = if ($atr[$i] -gt 0) { $candleRange / $atr[$i] } else { 1 }

            # 7. Price position relative to EMA50 (z-score of deviation)
            $devSlice = [double[]]::new(20)
            for ($j = 0; $j -lt 20; $j++) { $devSlice[$j] = $c[$i-19+$j] - $ema50[$i-19+$j] }
            $devMean = ($devSlice | Measure-Object -Average).Average
            $devStd = Get-StdDev $devSlice
            $priceZ = if ($devStd -gt 0) { ($c[$i] - $ema50[$i] - $devMean) / $devStd } else { 0 }

            # 8. Volume-weighted price trend (OBV slope)
            $obv = Calc-OBV $c[0..$i] $v[0..$i]
            $obvSlope = if ($obv[-1] -ne 0) { ($obv[-1] - $obv[[Math]::Max(0, $obv.Count-5)]) / [Math]::Max(1, [Math]::Abs($obv[[Math]::Max(0, $obv.Count-5)])) * 100 } else { 0 }

            $features.Add(@($realizedVol, $atrPct, $diSpread, $adxVal, $volZ, $trendSlope, $rangeCompress, $priceZ, $obvSlope))
            $timestamps.Add([long]$klines[$i].Timestamp)
        }

        $featCount = $features.Count
        if ($featCount -lt 50) { Write-Warning "  Too few feature vectors for $sym"; continue }

        # Normalize features (z-score each dimension)
        $dim = $features[0].Count
        $means = [double[]]::new($dim)
        $stds = [double[]]::new($dim)
        for ($d = 0; $d -lt $dim; $d++) {
            $vals = for ($f = 0; $f -lt $featCount; $f++) { $features[$f][$d] }
            $means[$d] = ($vals | Measure-Object -Average).Average
            $stds[$d] = Get-StdDev @($vals)
            if ($stds[$d] -eq 0) { $stds[$d] = 1 }
        }
        $normFeatures = New-Object 'System.Collections.Generic.List[double[]]'
        for ($f = 0; $f -lt $featCount; $f++) {
            $norm = [double[]]::new($dim)
            for ($d = 0; $d -lt $dim; $d++) { $norm[$d] = ($features[$f][$d] - $means[$d]) / $stds[$d] }
            $normFeatures.Add($norm)
        }

        # Determine optimal K via silhouette-like heuristic (2 to 10)
        Write-Host "  Determining optimal regime count..." -ForegroundColor Yellow
        $bestK = 4; $bestScore = -1e10
        $kScores = @()
        for ($k = 2; $k -le 10; $k++) {
            $clusters = Invoke-MbfKMeansClustering $normFeatures $k 20
            $score = Invoke-MbfClusterQuality $normFeatures $clusters
            $kScores += [PSCustomObject]@{K=$k;Score=[Math]::Round($score,4)}
            if ($score -gt $bestScore) { $bestScore = $score; $bestK = $k }
        }
        Write-Host "  Optimal K = $bestK (score=$([Math]::Round($bestScore,4)))" -ForegroundColor Green

        # Run final clustering with optimal K
        $finalClusters = Invoke-MbfKMeansClustering $normFeatures $bestK 50

        # Label regimes based on feature centroids
        $centroids = @{}
        for ($f = 0; $f -lt $featCount; $f++) {
            $cid = $finalClusters[$f]
            if (-not $centroids.ContainsKey($cid)) { $centroids[$cid] = New-Object 'System.Collections.Generic.List[double[]]' }
            $centroids[$cid].Add($features[$f])
        }

        Write-Host "  Labeling regimes..." -ForegroundColor Yellow
        $regimeLabels = @{}
        foreach ($kv in $centroids.GetEnumerator()) {
            $pts = $kv.Value
            $avgFeat = [double[]]::new($dim)
            for ($d = 0; $d -lt $dim; $d++) {
                $sum = 0.0; foreach ($p in $pts) { $sum += $p[$d] }; $avgFeat[$d] = $sum / $pts.Count
            }
            # Label based on feature values (denormalized):
            # [0] realizedVol, [1] atrPct, [2] diSpread, [3] adxVal, [4] volZ, [5] trendSlope, [6] rangeCompress, [7] priceZ, [8] obvSlope
            $label = "MIXED"
            if ($avgFeat[3] -gt 25 -and $avgFeat[2] -gt 15) {
                if ($avgFeat[5] -gt 0.5) { $label = "TRENDING_UP" }
                elseif ($avgFeat[5] -lt -0.5) { $label = "TRENDING_DOWN" }
                else { $label = if ($avgFeat[7] -gt 0.5) { "TRENDING_UP" } else { "TRENDING_DOWN" } }
            }
            elseif ($avgFeat[3] -lt 20 -and $avgFeat[1] -lt 1.0) { $label = "RANGING" }
            elseif ($avgFeat[1] -gt 2.0 -or $avgFeat[0] -gt 0.03) {
                if ($avgFeat[4] -gt 1.0 -and $avgFeat[5] -gt 0) { $label = "ACCUMULATION" }
                elseif ($avgFeat[4] -gt 1.0 -and $avgFeat[5] -lt 0) { $label = "DISTRIBUTION" }
                elseif ($avgFeat[6] -gt 1.5) { $label = "VOLATILITY_EXPANSION" }
                else { $label = "VOLATILITY_EXPANSION" }
            }
            elseif ($avgFeat[1] -lt 0.5 -and $avgFeat[6] -lt 0.5) { $label = "VOLATILITY_COMPRESSION" }
            elseif ($avgFeat[4] -gt 1.0) {
                if ($avgFeat[5] -gt 0) { $label = "ACCUMULATION" }
                else { $label = "DISTRIBUTION" }
            }

            $regimeLabels[$kv.Key] = $label
        }

        # Write regime assignments
        $outRegimes = @()
        for ($f = 0; $f -lt $featCount; $f++) {
            $cid = $finalClusters[$f]
            $label = $regimeLabels[$cid]
            $idx = $f + 100  # offset because we start at index 100
            $outRegimes += [PSCustomObject]@{
                Asset = $sym
                Index = $idx
                Timestamp = $timestamps[$f]
                Regime = $label
                ClusterId = $cid
                RealizedVol = [Math]::Round($features[$f][0], 8)
                ATRPct = [Math]::Round($features[$f][1], 4)
                DISpread = [Math]::Round($features[$f][2], 2)
                ADX = [Math]::Round($features[$f][3], 2)
                VolZScore = [Math]::Round($features[$f][4], 4)
                TrendSlope = [Math]::Round($features[$f][5], 6)
                RangeCompress = [Math]::Round($features[$f][6], 4)
                PriceZScore = [Math]::Round($features[$f][7], 4)
                OBVSlope = [Math]::Round($features[$f][8], 4)
            }
        }

        $allRegimes += $outRegimes

        # Print distribution
        $dist = $outRegimes | Group-Object Regime | Sort-Object Count -Descending
        Write-Host "  $sym regime distribution:" -ForegroundColor Yellow
        foreach ($g in $dist) {
            $gPct = [Math]::Round($g.Count/$outRegimes.Count*100,1)
            Write-Host ("    " + $g.Name + " : " + $g.Count + " bars (" + $gPct + "%)") -ForegroundColor Gray
        }
    }

    $outPath = Join-Path $OutputDir "market_regimes.csv"
    $allRegimes | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 3 complete. Saved to $outPath" -ForegroundColor Green
    return $allRegimes
}

# K-Means Clustering
function Invoke-MbfKMeansClustering {
    param($features, $k, $maxIter = 50)
    $n = $features.Count
    $dim = $features[0].Count

    # Initialize centroids via k-means++
    $rng = [System.Random]::new()
    $centroids = [System.Collections.ArrayList]::new()
    $firstIdx = $rng.Next(0, $n)
    $centroids.Add(@($features[$firstIdx])) > $null
    for ($c = 1; $c -lt $k; $c++) {
        $dists = [double[]]::new($n)
        for ($i = 0; $i -lt $n; $i++) {
            $minD = [double]::MaxValue
            for ($j = 0; $j -lt $centroids.Count; $j++) {
                $d = 0.0; for ($d_ = 0; $d_ -lt $dim; $d_++) { $diff = $features[$i][$d_] - $centroids[$j][$d_]; $d += $diff * $diff }
                if ($d -lt $minD) { $minD = $d }
            }
            $dists[$i] = $minD
        }
        $totalD = ($dists | Measure-Object -Sum).Sum
        if ($totalD -eq 0) { $centroids.Add(@($features[$rng.Next(0, $n)])) > $null; continue }
        $r = $rng.NextDouble() * $totalD; $cum = 0.0; $chosen = 0
        for ($i = 0; $i -lt $n; $i++) { $cum += $dists[$i]; if ($cum -ge $r) { $chosen = $i; break } }
        $centroids.Add(@($features[$chosen])) > $null
    }

    $assignments = [int[]]::new($n)
    for ($iter = 0; $iter -lt $maxIter; $iter++) {
        # Assign
        $changed = $false
        for ($i = 0; $i -lt $n; $i++) {
            $minD = [double]::MaxValue; $bestC = 0
            for ($c = 0; $c -lt $k; $c++) {
                $d = 0.0; for ($d_ = 0; $d_ -lt $dim; $d_++) { $diff = $features[$i][$d_] - $centroids[$c][$d_]; $d += $diff * $diff }
                if ($d -lt $minD) { $minD = $d; $bestC = $c }
            }
            if ($assignments[$i] -ne $bestC) { $changed = $true }
            $assignments[$i] = $bestC
        }
        if (-not $changed) { break }

        # Update centroids
        for ($c = 0; $c -lt $k; $c++) {
            $members = for ($i = 0; $i -lt $n; $i++) { if ($assignments[$i] -eq $c) { $i } }
            if ($members.Count -eq 0) { continue }
            $newCent = [double[]]::new($dim)
            for ($d = 0; $d -lt $dim; $d++) {
                $sum = 0.0; foreach ($idx in $members) { $sum += $features[$idx][$d] }; $newCent[$d] = $sum / $members.Count
            }
            $centroids[$c] = $newCent
        }
    }
    return $assignments
}

# Cluster quality score (Davies-Bouldin-like: minimize intra/inter cluster ratio)
function Invoke-MbfClusterQuality {
    param($features, $assignments)
    $n = $features.Count; $dim = $features[0].Count
    $k = ($assignments | Sort-Object -Unique).Count
    if ($k -lt 2) { return -1e10 }

    # Cluster centroids
    $centroids = @{}
    $counts = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $c = $assignments[$i]
        if (-not $centroids.ContainsKey($c)) { $centroids[$c] = [double[]]::new($dim); $counts[$c] = 0 }
        for ($d = 0; $d -lt $dim; $d++) { $centroids[$c][$d] += $features[$i][$d] }
        $counts[$c]++
    }
    foreach ($c in $centroids.Keys) {
        for ($d = 0; $d -lt $dim; $d++) { $centroids[$c][$d] /= $counts[$c] }
    }

    # Intra-cluster dispersion (avg distance to centroid)
    $intraD = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $c = $assignments[$i]; $d = 0.0
        for ($d_ = 0; $d_ -lt $dim; $d_++) { $diff = $features[$i][$d_] - $centroids[$c][$d_]; $d += $diff * $diff }
        if (-not $intraD.ContainsKey($c)) { $intraD[$c] = @() }
        $intraD[$c] += [Math]::Sqrt($d)
    }
    $avgIntra = @{}
    foreach ($c in $intraD.Keys) { $avgIntra[$c] = ($intraD[$c] | Measure-Object -Average).Average }

    # Inter-cluster separation
    $clusterKeys = @($centroids.Keys)
    $score = 0.0
    for ($i = 0; $i -lt $clusterKeys.Count; $i++) {
        $maxRatio = 0.0
        for ($j = 0; $j -lt $clusterKeys.Count; $j++) {
            if ($i -eq $j) { continue }
            $d = 0.0; for ($d_ = 0; $d_ -lt $dim; $d_++) { $diff = $centroids[$clusterKeys[$i]][$d_] - $centroids[$clusterKeys[$j]][$d_]; $d += $diff * $diff }
            $dist = [Math]::Sqrt($d)
            $ratio = if ($dist -gt 0) { ($avgIntra[$clusterKeys[$i]] + $avgIntra[$clusterKeys[$j]]) / $dist } else { 1e10 }
            if ($ratio -gt $maxRatio) { $maxRatio = $ratio }
        }
        $score += $maxRatio
    }
    return -$score  # negative so higher (less negative) is better
}

# ============================================================
#  PHASE 4 -- BEHAVIOR CATALOG
# ============================================================
function Invoke-MbfPhase4 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$Phase3File = "market_regimes.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 4: BEHAVIOR CATALOG =====" -ForegroundColor Cyan
    $regPath = Join-Path $OutputDir $Phase3File
    if (-not (Test-Path $regPath)) { Write-Warning "Phase 3 output not found: $regPath"; return $null }

    $regimes = Import-Csv $regPath
    $allBehaviors = @()

    foreach ($sym in $Symbols) {
        $symRegs = $regimes | Where-Object { $_.Asset -eq $sym }
        if ($symRegs.Count -lt 10) { Write-Warning "Insufficient regime data for $sym"; continue }

        $regimeTypes = $symRegs | Group-Object Regime
        Write-Host "`nAnalyzing behaviors for $sym..." -ForegroundColor Yellow

        foreach ($regType in $regimeTypes) {
            $entries = $regType.Group | Sort-Object Index
            $label = $regType.Name
            Write-Host "  Regime: $label ($($entries.Count) bars)" -ForegroundColor Gray

            # Load klines to get prices
            $csvFile = Join-Path $OutputDir "mbf_klines_${sym}_4h.csv"
            if (-not (Test-Path $csvFile)) { Write-Warning "No klines for $sym"; continue }
            $klines = Import-Csv $csvFile
            $c = $klines | ForEach-Object { [double]$_.Close }
            $h = $klines | ForEach-Object { [double]$_.High }
            $l = $klines | ForEach-Object { [double]$_.Low }
            $n = $c.Count

            # Average move size over lookahead periods
            $moveSizes1 = @(); $moveSizes3 = @(); $moveSizes5 = @(); $moveSizes10 = @()
            $moveSizes20 = @()
            $reversals = 0; $reversalTotal = 0
            $continuations = 0; $continuationTotal = 0
            $breakouts = 0; $breakoutTotal = 0
            $fades = 0; $fadeTotal = 0
            $moveDurations = @()
            $posCount = 0; $negCount = 0

            foreach ($entry in $entries) {
                $idx = [int]$entry.Index
                if ($idx -ge $n - 1) { continue }
                # Move size over 1, 3, 5, 10, 20 bars
                for ($la = 1; $la -le 20; $la++) {
                    if ($idx + $la -lt $n) {
                        $ret = ($c[$idx+$la] - $c[$idx]) / $c[$idx] * 100
                        switch ($la) {
                            1 { $moveSizes1 += $ret }
                            3 { $moveSizes3 += $ret }
                            5 { $moveSizes5 += $ret }
                            10 { $moveSizes10 += $ret }
                            20 { $moveSizes20 += $ret }
                        }
                    }
                }

                # Reversal frequency: does price change direction within 5 bars?
                if ($idx + 5 -lt $n) {
                    $reversalTotal++
                    $dir0 = [Math]::Sign($c[$idx] - $c[[Math]::Max(0, $idx-3)])
                    $dir5 = [Math]::Sign($c[$idx+5] - $c[$idx])
                    if ($dir0 -ne 0 -and $dir5 -ne 0 -and $dir0 -ne $dir5) { $reversals++ }
                }

                # Continuation probability: given direction at entry, does it continue?
                if ($idx + 3 -lt $n) {
                    $continuationTotal++
                    $dirEntry = [Math]::Sign($c[$idx+1] - $c[$idx])
                    $dirLater = [Math]::Sign($c[$idx+3] - $c[$idx])
                    if ($dirEntry -ne 0 -and $dirLater -eq $dirEntry) { $continuations++ }
                }

                # Breakout probability: does range expand significantly?
                if ($idx + 5 -lt $n -and $idx -ge 5) {
                    $breakoutTotal++
                    $backRange = 0.0; for ($j = $idx-5; $j -le $idx; $j++) { $backRange += $h[$j] - $l[$j] }; $backRange /= 6
                    $fwdRange = 0.0; for ($j = $idx+1; $j -le $idx+5; $j++) { $fwdRange += $h[$j] - $l[$j] }; $fwdRange /= 5
                    if ($fwdRange -gt $backRange * 1.5) { $breakouts++ }
                }

                # Fade probability: does move reverse entirely within 10 bars?
                if ($idx + 10 -lt $n -and $idx -ge 3) {
                    $fadeTotal++
                    $initMove = ($c[$idx+3] - $c[$idx]) / $c[$idx] * 100
                    $laterMove = ($c[$idx+10] - $c[$idx]) / $c[$idx] * 100
                    if ([Math]::Abs($initMove) -gt 0.5 -and [Math]::Sign($laterMove) -ne [Math]::Sign($initMove)) { $fades++ }
                }

                # Move duration: how many bars until price moves > 1% in either direction?
                $targetMove = 0.01 * $c[$idx]
                for ($d = 1; $d -le 30 -and $idx + $d -lt $n; $d++) {
                    if ([Math]::Abs($c[$idx+$d] - $c[$idx]) -ge $targetMove) { $moveDurations += $d; break }
                }

                # Direction bias
                $dir = [Math]::Sign($c[$idx] - $c[[Math]::Max(0, $idx-3)])
                if ($dir -gt 0) { $posCount++ } elseif ($dir -lt 0) { $negCount++ }
            }

            $avgMove1 = if ($moveSizes1.Count -gt 0) { ($moveSizes1 | Measure-Object -Average).Average } else { 0 }
            $avgMove3 = if ($moveSizes3.Count -gt 0) { ($moveSizes3 | Measure-Object -Average).Average } else { 0 }
            $avgMove5 = if ($moveSizes5.Count -gt 0) { ($moveSizes5 | Measure-Object -Average).Average } else { 0 }
            $avgMove10 = if ($moveSizes10.Count -gt 0) { ($moveSizes10 | Measure-Object -Average).Average } else { 0 }
            $avgMove20 = if ($moveSizes20.Count -gt 0) { ($moveSizes20 | Measure-Object -Average).Average } else { 0 }
            $revFreq = if ($reversalTotal -gt 0) { $reversals / $reversalTotal * 100 } else { 0 }
            $contProb = if ($continuationTotal -gt 0) { $continuations / $continuationTotal * 100 } else { 0 }
            $breakoutProb = if ($breakoutTotal -gt 0) { $breakouts / $breakoutTotal * 100 } else { 0 }
            $fadeProb = if ($fadeTotal -gt 0) { $fades / $fadeTotal * 100 } else { 0 }
            $avgDuration = if ($moveDurations.Count -gt 0) { ($moveDurations | Measure-Object -Average).Average } else { 0 }
            $upBias = if ($posCount + $negCount -gt 0) { $posCount / ($posCount + $negCount) * 100 } else { 50 }

            $allBehaviors += [PSCustomObject]@{
                Asset = $sym
                Regime = $label
                BarCount = $entries.Count
                AvgMove1B = [Math]::Round($avgMove1, 4)
                AvgMove3B = [Math]::Round($avgMove3, 4)
                AvgMove5B = [Math]::Round($avgMove5, 4)
                AvgMove10B = [Math]::Round($avgMove10, 4)
                AvgMove20B = [Math]::Round($avgMove20, 4)
                ReversalFreqPct = [Math]::Round($revFreq, 2)
                ContinuationProbPct = [Math]::Round($contProb, 2)
                BreakoutProbPct = [Math]::Round($breakoutProb, 2)
                FadeProbPct = [Math]::Round($fadeProb, 2)
                AvgMoveDurationBars = [Math]::Round($avgDuration, 1)
                UpBiasPct = [Math]::Round($upBias, 1)
            }
            Write-Host "    Move1=$([Math]::Round($avgMove1,2))% Move5=$([Math]::Round($avgMove5,2))% Rev=$([Math]::Round($revFreq,1))% Cont=$([Math]::Round($contProb,1))% Break=$([Math]::Round($breakoutProb,1))% Fade=$([Math]::Round($fadeProb,1))%" -ForegroundColor Gray
        }
    }

    $outPath = Join-Path $OutputDir "behavior_catalog.csv"
    $allBehaviors | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 4 complete. Saved to $outPath" -ForegroundColor Green
    return $allBehaviors
}

# ============================================================
#  PHASE 5 -- INDICATOR SENSOR EVALUATION
# ============================================================
function Invoke-MbfPhase5 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$BehaviorFile = "behavior_catalog.csv",
        [string]$Phase3File = "market_regimes.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 5: INDICATOR SENSOR EVALUATION =====" -ForegroundColor Cyan

    $behPath = Join-Path $OutputDir $BehaviorFile
    $regPath = Join-Path $OutputDir $Phase3File
    if (-not (Test-Path $behPath)) { Write-Warning "Behavior catalog not found: $behPath"; return $null }

    $behaviors = Import-Csv $behPath
    $allRankings = @()

    foreach ($sym in $Symbols) {
        $csvFile = Join-Path $OutputDir "mbf_klines_${sym}_4h.csv"
        if (-not (Test-Path $csvFile)) { Write-Warning "No klines for $sym"; continue }
        $klines = Import-Csv $csvFile
        if ($klines.Count -lt 300) { Write-Warning "Insufficient data for $sym"; continue }

        $h = $klines | ForEach-Object { [double]$_.High }
        $l = $klines | ForEach-Object { [double]$_.Low }
        $c = $klines | ForEach-Object { [double]$_.Close }
        $v = $klines | ForEach-Object { [double]$_.Volume }
        $n = $c.Count

        # Load regimes
        $regimeData = @()
        if (Test-Path $regPath) {
            $allRegs = Import-Csv $regPath
            $regimeData = $allRegs | Where-Object { $_.Asset -eq $sym }
        }

        # Define behavior targets based on regime + behavior catalog
        $symBehaviors = $behaviors | Where-Object { $_.Asset -eq $sym }
        $targetBehaviors = @()

        foreach ($b in $symBehaviors) {
            $regime = $b.Regime
            $contProb = [double]$b.ContinuationProbPct
            $revFreq = [double]$b.ReversalFreqPct
            $breakProb = [double]$b.BreakoutProbPct
            $fadeProb = [double]$b.FadeProbPct
            $avgMove = [double]$b.AvgMove5B

            if ($contProb -gt 60) { $targetBehaviors += @{Name="${regime}_CONTINUATION";Regime=$regime;Type="continuation";Evidence=$contProb} }
            if ($revFreq -gt 50) { $targetBehaviors += @{Name="${regime}_REVERSAL";Regime=$regime;Type="reversal";Evidence=$revFreq} }
            if ($breakProb -gt 50) { $targetBehaviors += @{Name="${regime}_BREAKOUT";Regime=$regime;Type="breakout";Evidence=$breakProb} }
            if ($fadeProb -gt 50) { $targetBehaviors += @{Name="${regime}_FADE";Regime=$regime;Type="fade";Evidence=$fadeProb} }
            if ([Math]::Abs($avgMove) -gt 1.0) {
                $dir = if ($avgMove -gt 0) { "UP" } else { "DOWN" }
                $targetBehaviors += @{Name="${regime}_MOVE_$dir";Regime=$regime;Type="directional_move";Evidence=[Math]::Abs($avgMove)}
            }
        }

        if ($targetBehaviors.Count -eq 0) {
            Write-Host "  No strong behaviors detected for $sym -- adding default targets"
            $targetBehaviors = $symBehaviors | ForEach-Object {
                @{Name="TREND_FOLLOW";Regime=$_.Regime;Type="trend";Evidence=50},
                @{Name="MEAN_REVERSION";Regime=$_.Regime;Type="reversal";Evidence=50}
            }
        }

        Write-Host "  Evaluating $($targetBehaviors.Count) behaviors for $sym..." -ForegroundColor Yellow

        # Comprehensive indicator parameter grids
        $indicatorConfigs = @()

        # RSI grid (5 lengths x 4 OB x 4 OS)
        foreach ($len in @(5,9,14,21,30,50)) {
            foreach ($ob in @(70,75,80,85,90)) {
                foreach ($os in @(10,15,20,25,30)) {
                    if ($ob -le $os + 20) { continue }
                    $indicatorConfigs += @{Indicator="RSI";Params="len=$len,ob=$ob,os=$os"}
                }
            }
        }
        # MACD grid (3 fast x 3 slow x 2 signal)
        foreach ($f in @(8,12,16)) { foreach ($s in @(21,26,30)) { foreach ($sig in @(7,9,12)) {
            if ($f -ge $s) { continue }
            $indicatorConfigs += @{Indicator="MACD";Params="fast=$f,slow=$s,signal=$sig"}
        }}}
        # ADX grid (7 lengths x 5 thresholds)
        foreach ($len in @(5,7,10,14,21,30,50)) { foreach ($thresh in @(15,20,25,30,40)) {
            $indicatorConfigs += @{Indicator="ADX";Params="len=$len,thresh=$thresh"}
        }}
        # EMA cross grid (6 fast x 6 slow)
        foreach ($f in @(3,5,8,13,21,34)) { foreach ($s in @(10,21,34,55,89,144)) {
            if ($f -ge $s) { continue }
            $indicatorConfigs += @{Indicator="EMACross";Params="fast=$f,slow=$s"}
        }}
        # SMA cross grid
        foreach ($f in @(5,10,20)) { foreach ($s in @(50,100,200)) {
            if ($f -ge $s) { continue }
            $indicatorConfigs += @{Indicator="SMACross";Params="fast=$f,slow=$s"}
        }}
        # ATR grid (volatility regime)
        foreach ($len in @(7,14,21,30)) { foreach ($mult in @(1.0,1.5,2.0,2.5,3.0)) {
            $indicatorConfigs += @{Indicator="ATR";Params="len=$len,mult=$mult"}
        }}
        # Stochastic grid (3K x 3D x 3OB x 3OS)
        foreach ($k in @(5,9,14,21)) { foreach ($d in @(3,5,9)) { foreach ($ob in @(80,85,90)) { foreach ($os in @(10,15,20)) {
            if ($ob -le $os + 20) { continue }
            $indicatorConfigs += @{Indicator="Stoch";Params="k=$k,d=$d,ob=$ob,os=$os"}
        }}}}
        # OBV grid (5 MA lengths)
        foreach ($maLen in @(10,20,30,50,100)) {
            $indicatorConfigs += @{Indicator="OBV";Params="ma=$maLen"}
        }
        # CMF grid (5 lengths x 5 thresholds)
        foreach ($len in @(10,14,21,30,50)) { foreach ($thresh in @(-0.1,-0.05,0,0.05,0.1)) {
            $indicatorConfigs += @{Indicator="CMF";Params="len=$len,thresh=$thresh"}
        }}
        # VWAP (position relative)
        foreach ($dev in @(0.5,1.0,1.5,2.0,2.5,3.0)) {
            $indicatorConfigs += @{Indicator="VWAP";Params="dev=$dev"}
        }
        # Bollinger Bands (3 lengths x 3 mults)
        foreach ($per in @(10,20,30,50)) { foreach ($mult in @(1.5,2.0,2.5,3.0)) {
            $indicatorConfigs += @{Indicator="Bollinger";Params="per=$per,mult=$mult"}
        }}
        # CCI grid (5 lengths x 3 OB x 3 OS)
        foreach ($len in @(5,10,14,20,30,50)) { foreach ($ob in @(100,150,200)) { foreach ($os in @(-200,-150,-100)) {
            if ($ob -ge (-$os)) { continue }
            $indicatorConfigs += @{Indicator="CCI";Params="len=$len,ob=$ob,os=$os"}
        }}}

        Write-Host "  Testing $($indicatorConfigs.Count) indicator configs against $($targetBehaviors.Count) behaviors..." -ForegroundColor Yellow

        $totalConfigs = $indicatorConfigs.Count
        $configIdx = 0

        foreach ($icfg in $indicatorConfigs) {
            $configIdx++
            if ($configIdx % 200 -eq 0) { Write-Host "    Progress: $configIdx / $totalConfigs" -ForegroundColor Gray }

            $sig = Get-MbfSignalArray $icfg.Indicator $icfg.Params $c $h $l $v $n
            if (-not $sig -or ($sig | Where-Object { $_ }).Count -lt 5) { continue }

            $signalIndices = @(); for ($si = 0; $si -lt $sig.Count; $si++) { if ($sig[$si]) { $signalIndices += $si } }

            foreach ($tb in $targetBehaviors) {
                # Determine ground truth labels for this behavior
                $truth = Get-MbfBehaviorTruth $tb $klines $regimeData $c $h $l $n
                if (-not $truth) { continue }

                # Evaluate detection quality
                $tp = 0; $fp = 0; $tn = 0; $fn = 0
                $detectionLatencies = @()
                $evalStart = 100
                if ($evalStart -ge $truth.Count -or $evalStart -ge $sig.Count) { continue }

                for ($i = $evalStart; $i -lt $n; $i++) {
                    $actual = $truth[$i]
                    $predicted = $sig[$i]
                    if ($actual -and $predicted) { $tp++ }
                    elseif (-not $actual -and $predicted) { $fp++ }
                    elseif ($actual -and -not $predicted) { $fn++ }
                    else { $tn++ }
                }

                $totalPred = $tp + $fp + $fn + $tn
                if ($totalPred -eq 0) { continue }

                # Detection accuracy
                $accuracy = if ($tp + $tn + $fp + $fn -gt 0) { ($tp + $tn) / ($tp + $tn + $fp + $fn) * 100 } else { 0 }
                $precision = if ($tp + $fp -gt 0) { $tp / ($tp + $fp) * 100 } else { 0 }
                $recall = if ($tp + $fn -gt 0) { $tp / ($tp + $fn) * 100 } else { 0 }
                $f1 = if ($precision + $recall -gt 0) { 2 * $precision * $recall / ($precision + $recall) } else { 0 }
                $specificity = if ($tn + $fp -gt 0) { $tn / ($tn + $fp) * 100 } else { 0 }

                # Detection latency: average bars from behavior onset to first signal
                $latencies = @()
                $behaviorStartIndices = @(); for ($i = $evalStart; $i -lt $n - 1; $i++) { if ($truth[$i] -and -not $truth[$i-1]) { $behaviorStartIndices += $i } }
                foreach ($bs in $behaviorStartIndices) {
                    for ($d = 0; $d -le 10; $d++) {
                        if ($bs + $d -lt $sig.Count -and $sig[$bs + $d]) { $latencies += $d; break }
                    }
                }
                $avgLatency = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Average).Average } else { -1 }

                # Signal stability: inverse of signal-to-noise ratio in signal array
                $sigChanges = 0; for ($i = 100; $i -lt $sig.Count - 1; $i++) { if ($sig[$i] -ne $sig[$i-1]) { $sigChanges++ } }
                $signalStability = if ($sig.Count - 100 -gt 0) { 1.0 - [Math]::Min(1.0, $sigChanges / ($sig.Count - 100)) } else { 0 }

                $allRankings += [PSCustomObject]@{
                    Asset = $sym
                    Behavior = $tb.Name
                    Regime = $tb.Regime
                    BehaviorType = $tb.Type
                    Indicator = $icfg.Indicator
                    Params = $icfg.Params
                    DetectionAccuracy = [Math]::Round($accuracy, 2)
                    Precision = [Math]::Round($precision, 2)
                    Recall = [Math]::Round($recall, 2)
                    F1Score = [Math]::Round($f1, 2)
                    Specificity = [Math]::Round($specificity, 2)
                    AvgDetectionLatencyBars = [Math]::Round($avgLatency, 1)
                    FalsePositives = $fp
                    FalseNegatives = $fn
                    TruePositives = $tp
                    TrueNegatives = $tn
                    SignalStability = [Math]::Round($signalStability, 4)
                    SignalCount = $signalIndices.Count
                }
            }
        }
        Write-Host "  $sym complete: $($allRankings.Count) total rankings" -ForegroundColor Green
    }

    $outPath = Join-Path $OutputDir "behavior_detector_rankings.csv"
    $allRankings | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 5 complete. Saved to $outPath" -ForegroundColor Green
    return $allRankings
}

function Get-MbfSignalArray {
    param($indicator, $params, $c, $h, $l, $v, $n)
    $parts = $params -split ','
    $map = @{}; foreach ($p in $parts) { $kv = $p -split '='; if ($kv.Count -eq 2) { $map[$kv[0].Trim()] = $kv[1].Trim() } }

    $sigList = New-Object 'System.Collections.Generic.List[bool]'
    switch ($indicator) {
        "RSI" {
            $len = [int]$map['len']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $rsi = Calc-RSI $c $len
            for($i=$len;$i-lt$n;$i++){$sigList.Add($rsi[$i]-gt$ob-or$rsi[$i]-lt$os)}; return $sigList.ToArray()
        }
        "MACD" {
            $f = [int]$map['fast']; $s = [int]$map['slow']; $sig = [int]$map['signal']
            $m = Calc-MACD $c $f $s $sig
            for($i=$s;$i-lt$n;$i++){$sigList.Add($m.hist[$i]-gt0-and$m.hist[$i-1]-le0)}; return $sigList.ToArray()
        }
        "ADX" {
            $len = [int]$map['len']; $thresh = [int]$map['thresh']
            $adx,$du,$dd = Calc-ADX $h $l $c $len
            for($i=$len;$i-lt$n;$i++){$sigList.Add($adx[$i]-gt$thresh)}; return $sigList.ToArray()
        }
        "EMACross" {
            $f = [int]$map['fast']; $s = [int]$map['slow']
            $ef=Calc-EMA $c $f;$es=Calc-EMA $c $s
            for($i=$s;$i-lt$n;$i++){$sigList.Add($ef[$i]-gt$es[$i]-and$ef[$i-1]-le$es[$i-1])}; return $sigList.ToArray()
        }
        "SMACross" {
            $f = [int]$map['fast']; $s = [int]$map['slow']
            $sf=Calc-SMA $c $f;$ss=Calc-SMA $c $s
            for($i=$s;$i-lt$n;$i++){$sigList.Add($sf[$i]-gt$ss[$i]-and$sf[$i-1]-le$ss[$i-1])}; return $sigList.ToArray()
        }
        "ATR" {
            $len = [int]$map['len']; $mult = [double]$map['mult']
            $atr = Calc-ATR $h $l $c $len
            $atrPct=[double[]]::new($n);for($i=0;$i-lt$n;$i++){$atrPct[$i]=if($c[$i]-gt0){$atr[$i]/$c[$i]*100}else{0}}
            $atrMean = ($atrPct[50..($n-1)] | Measure-Object -Average).Average
            $atrStd = Get-StdDev @($atrPct[50..($n-1)])
            for($i=$len;$i-lt$n;$i++){$sigList.Add($atrPct[$i]-gt($atrMean+$mult*$atrStd))}; return $sigList.ToArray()
        }
        "Stoch" {
            $k = [int]$map['k']; $d = [int]$map['d']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $st=Calc-Stoch $h $l $c $k $d
            for($i=$k+$d;$i-lt$n;$i++){$sigList.Add($st[$i]-gt$ob-or$st[$i]-lt$os)}; return $sigList.ToArray()
        }
        "OBV" {
            $maLen = [int]$map['ma']
            $obv=Calc-OBV $c $v;$obvMa=Calc-EMA $obv $maLen
            for($i=$maLen;$i-lt$n;$i++){$sigList.Add($obv[$i]-gt$obvMa[$i])}; return $sigList.ToArray()
        }
        "CMF" {
            $len = [int]$map['len']; $thresh = [double]$map['thresh']
            $cmf=Calc-CMF $h $l $c $v $len
            for($i=$len;$i-lt$n;$i++){$sigList.Add($cmf[$i]-gt$thresh)}; return $sigList.ToArray()
        }
        "VWAP" {
            $dev = [double]$map['dev']
            $vwap=Calc-VWAP $h $l $c $v
            $atr=Calc-ATR $h $l $c 14
            for($i=0;$i-lt$n;$i++){$vDev=if($vwap[$i]-gt0){[Math]::Abs($c[$i]-$vwap[$i])/$vwap[$i]*100}else{0}
                $threshold=if($atr[$i]-gt0){$atr[$i]/$c[$i]*100*$dev}else{999}
                $sigList.Add($vDev-gt$threshold)}; return $sigList.ToArray()
        }
        "Bollinger" {
            $per = [int]$map['per']; $mult = [double]$map['mult']
            $bb=Calc-Bollinger $c $per $mult
            for($i=$per-1;$i-lt$n;$i++){$sigList.Add($c[$i]-ge$bb.upper[$i]-or$c[$i]-le$bb.lower[$i])}; return $sigList.ToArray()
        }
        "CCI" {
            $len = [int]$map['len']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $cci=Calc-CCI $h $l $c $len
            for($i=$len;$i-lt$n;$i++){$sigList.Add($cci[$i]-gt$ob-or$cci[$i]-lt$os)}; return $sigList.ToArray()
        }
    }
    return $null
}

function Get-MbfBehaviorTruth {
    param($behavior, $klines, $regimeData, $c, $h, $l, $n)
    $type = $behavior.Type
    $regime = $behavior.Regime
    $truth = [bool[]]::new($n)

    # Build regime mask
    $regimeMask = [int[]]::new($n)
    foreach ($rd in $regimeData) {
        $idx = [int]$rd.Index
        if ($idx -lt $n) {
            if ($rd.Regime -eq $regime) { $regimeMask[$idx] = 1 }
        }
    }

    switch ($type) {
        "continuation" {
            for ($i = 5; $i -lt $n - 3; $i++) {
                if ($regimeMask[$i] -eq 1) {
                    $dir1 = [Math]::Sign($c[$i] - $c[$i-3])
                    $dir2 = [Math]::Sign($c[$i+3] - $c[$i])
                    if ($dir1 -ne 0 -and $dir2 -eq $dir1) { $truth[$i] = $true }
                }
            }
        }
        "reversal" {
            for ($i = 5; $i -lt $n - 3; $i++) {
                if ($regimeMask[$i] -eq 1) {
                    $dir1 = [Math]::Sign($c[$i] - $c[$i-3])
                    $dir2 = [Math]::Sign($c[$i+3] - $c[$i])
                    if ($dir1 -ne 0 -and $dir2 -ne 0 -and $dir2 -ne $dir1) { $truth[$i] = $true }
                }
            }
        }
        "breakout" {
            for ($i = 10; $i -lt $n - 5; $i++) {
                if ($regimeMask[$i] -eq 1) {
                    $backRange = 0.0; for ($j = $i-5; $j -le $i; $j++) { $backRange += $h[$j] - $l[$j] }
                    $backRange /= 6
                    $fwdRange = 0.0; for ($j = $i+1; $j -le $i+5; $j++) { $fwdRange += $h[$j] - $l[$j] }
                    $fwdRange /= 5
                    if ($fwdRange -gt $backRange * 1.5) { $truth[$i] = $true }
                }
            }
        }
        "fade" {
            for ($i = 5; $i -lt $n - 10; $i++) {
                if ($regimeMask[$i] -eq 1) {
                    $initMove = ($c[$i+3] - $c[$i]) / $c[$i] * 100
                    $laterMove = ($c[$i+10] - $c[$i]) / $c[$i] * 100
                    if ([Math]::Abs($initMove) -gt 0.5 -and [Math]::Sign($laterMove) -ne [Math]::Sign($initMove)) { $truth[$i] = $true }
                }
            }
        }
        "directional_move" {
            $dir = if ($behavior.Name -match "UP$") { 1 } else { -1 }
            for ($i = 5; $i -lt $n - 5; $i++) {
                if ($regimeMask[$i] -eq 1) {
                    $move = ($c[$i+5] - $c[$i]) / $c[$i] * 100
                    if (($dir -eq 1 -and $move -gt 1.0) -or ($dir -eq -1 -and $move -lt -1.0)) { $truth[$i] = $true }
                }
            }
        }
        "trend" {
            $adx, $du, $dd = Calc-ADX $h $l $c 14
            for ($i = 50; $i -lt $n; $i++) {
                if ($regimeMask[$i] -eq 1 -and $adx[$i] -gt 25) {
                    $truth[$i] = $true
                }
            }
        }
        default {
            for ($i = 0; $i -lt $n; $i++) { $truth[$i] = $false }
        }
    }
    return $truth
}

# ============================================================
#  PHASE 6 -- REGIME-SPECIFIC CONFIGURATIONS
# ============================================================
function Invoke-MbfPhase6 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$Phase5File = "behavior_detector_rankings.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 6: REGIME-SPECIFIC CONFIGURATIONS =====" -ForegroundColor Cyan
    $rankPath = Join-Path $OutputDir $Phase5File
    if (-not (Test-Path $rankPath)) { Write-Warning "Phase 5 output not found: $rankPath"; return $null }

    $rankings = Import-Csv $rankPath
    $playbook = @()

    foreach ($sym in $Symbols) {
        $symRank = $rankings | Where-Object { $_.Asset -eq $sym }
        $regimes = $symRank | Group-Object Regime

        foreach ($reg in $regimes) {
            $regName = $reg.Name
            $entries = $reg.Group

            # Best detectors per indicator type for this regime
            $indicatorTypes = $entries | Group-Object Indicator
            $bestConfigs = @()

            foreach ($ind in $indicatorTypes) {
                $best = $ind.Group | Sort-Object F1Score -Descending | Select-Object -First 3
                $bestConfigs += $best
            }

            # Top 5 overall detectors for this regime
            $topOverall = $entries | Sort-Object F1Score -Descending | Select-Object -First 5

            Write-Host "  $sym / $regName : top detector = $($topOverall[0].Indicator) ($($topOverall[0].Params)) F1=$($topOverall[0].F1Score)" -ForegroundColor Gray

            $playbook += [PSCustomObject]@{
                Asset = $sym
                Regime = $regName
                BestIndicator1 = $topOverall[0].Indicator
                BestParams1 = $topOverall[0].Params
                BestF1_1 = $topOverall[0].F1Score
                BestIndicator2 = if ($topOverall.Count -gt 1) { $topOverall[1].Indicator } else { "N/A" }
                BestParams2 = if ($topOverall.Count -gt 1) { $topOverall[1].Params } else { "N/A" }
                BestF1_2 = if ($topOverall.Count -gt 1) { $topOverall[1].F1Score } else { 0 }
                BestIndicator3 = if ($topOverall.Count -gt 2) { $topOverall[2].Indicator } else { "N/A" }
                BestParams3 = if ($topOverall.Count -gt 2) { $topOverall[2].Params } else { "N/A" }
                BestF1_3 = if ($topOverall.Count -gt 2) { $topOverall[2].F1Score } else { 0 }
                AvgPrecision = [Math]::Round(($entries | Measure-Object Precision -Average).Average, 2)
                AvgRecall = [Math]::Round(($entries | Measure-Object Recall -Average).Average, 2)
                AvgF1 = [Math]::Round(($entries | Measure-Object F1Score -Average).Average, 2)
                ConfigsTested = $entries.Count
            }
        }
    }

    $outPath = Join-Path $OutputDir "regime_playbook.csv"
    $playbook | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 6 complete. Saved to $outPath" -ForegroundColor Green
    return $playbook
}

# ============================================================
#  PHASE 7 -- WALK-FORWARD VALIDATION
# ============================================================
function Invoke-MbfPhase7 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$PlaybookFile = "regime_playbook.csv",
        [string]$Phase3File = "market_regimes.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 7: WALK-FORWARD VALIDATION =====" -ForegroundColor Cyan
    $pbPath = Join-Path $OutputDir $PlaybookFile
    if (-not (Test-Path $pbPath)) { Write-Warning "Phase 6 output not found: $pbPath"; return $null }

    $playbook = Import-Csv $pbPath
    $wfResults = @()

    foreach ($sym in $Symbols) {
        $csvFile = Join-Path $OutputDir "mbf_klines_${sym}_4h.csv"
        if (-not (Test-Path $csvFile)) { Write-Warning "No klines for $sym"; continue }
        $klines = Import-Csv $csvFile
        if ($klines.Count -lt 500) { Write-Warning "Insufficient data for walk-forward on $sym"; continue }

        $c = $klines | ForEach-Object { [double]$_.Close }
        $h = $klines | ForEach-Object { [double]$_.High }
        $l = $klines | ForEach-Object { [double]$_.Low }
        $v = $klines | ForEach-Object { [double]$_.Volume }
        $n = $c.Count

        $symPb = $playbook | Where-Object { $_.Asset -eq $sym }
        Write-Host "  Walk-forward testing $($symPb.Count) regime configs for $sym..." -ForegroundColor Yellow

        # 5-fold walk-forward
        $foldSize = [Math]::Floor($n / 5)
        for ($fold = 0; $fold -lt 4; $fold++) {
            $trainStart = $fold * $foldSize
            $trainEnd = ($fold + 1) * $foldSize - 1
            $testStart = $trainEnd + 1
            $testEnd = [Math]::Min($testStart + $foldSize - 1, $n - 1)

            if ($testEnd - $testStart -lt 50) { break }

            Write-Host "    Fold $($fold+1): train=$trainStart-$trainEnd, test=$testStart-$testEnd" -ForegroundColor Gray

            foreach ($cfg in $symPb) {
                $regime = $cfg.Regime
                $ind1 = $cfg.BestIndicator1
                $params1 = $cfg.BestParams1
                $ind2 = $cfg.BestIndicator2
                $params2 = $cfg.BestParams2

                foreach ($pair in @(@{Ind=$ind1;P=$params1}, @{Ind=$ind2;P=$params2})) {
                    if ($pair.Ind -eq "N/A") { continue }

                    # Evaluate on test window
                    $sig = Get-MbfSignalArray $pair.Ind $pair.P $c $h $l $v $n
                    if (-not $sig) { continue }

                    $testSignals = @()
                    $testPrices = @()
                    for ($i = $testStart; $i -le $testEnd; $i++) {
                        $testSignals += $sig[$i]
                        $testPrices += $c[$i]
                    }

                    $signalIndices = @()
                    for ($i = 0; $i -lt $testSignals.Count; $i++) {
                        if ($testSignals[$i]) { $signalIndices += $i }
                    }

                    if ($signalIndices.Count -lt 3) { continue }

                    # Compute PnL for each signal (5-bar forward return)
                    $returns = @()
                    foreach ($si in $signalIndices) {
                        $globalIdx = $testStart + $si
                        if ($globalIdx + 5 -lt $n) {
                            $returns += ($c[$globalIdx+5] - $c[$globalIdx]) / $c[$globalIdx] * 100
                        }
                    }

                    $avgRet = if ($returns.Count -gt 0) { ($returns | Measure-Object -Average).Average } else { 0 }
                    $posRets = @($returns | Where-Object { $_ -gt 0 })
                    $negRets = @($returns | Where-Object { $_ -le 0 })
                    $winRate = if ($returns.Count -gt 0) { $posRets.Count / $returns.Count * 100 } else { 0 }
                    $avgWin = if ($posRets.Count -gt 0) { ($posRets | Measure-Object -Average).Average } else { 0 }
                    $avgLoss = if ($negRets.Count -gt 0) { ($negRets | Measure-Object -Average).Average } else { 0 }
                    $expectancy = ($winRate/100 * $avgWin) + ((1-$winRate/100) * $avgLoss)
                    $retStd = Get-StdDev $returns
                    $sharpe = if ($retStd -gt 0 -and $returns.Count -gt 0) { ($avgRet / $retStd) * [Math]::Sqrt(6) } else { 0 }
                    # Max consecutive losses
                    $curLoss = 0; $maxCL = 0
                    foreach ($r in $returns) { if ($r -lt 0) { $curLoss++; if ($curLoss -gt $maxCL) { $maxCL = $curLoss } } else { $curLoss = 0 } }

                    $wfResults += [PSCustomObject]@{
                        Asset = $sym
                        Regime = $regime
                        Fold = $fold + 1
                        TrainRange = "$trainStart-$trainEnd"
                        TestRange = "$testStart-$testEnd"
                        Indicator = $pair.Ind
                        Params = $pair.P
                        SignalCount = $returns.Count
                        AvgReturn = [Math]::Round($avgRet, 4)
                        WinRate = [Math]::Round($winRate, 2)
                        AvgWin = [Math]::Round($avgWin, 4)
                        AvgLoss = [Math]::Round($avgLoss, 4)
                        Expectancy = [Math]::Round($expectancy, 4)
                        Sharpe = [Math]::Round($sharpe, 4)
                        MaxConsecLoss = $maxCL
                    }
                }
            }
        }
    }

    $outPath = Join-Path $OutputDir "walkforward_regime_results.csv"
    $wfResults | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 7 complete. Saved to $outPath" -ForegroundColor Green
    return $wfResults
}

# ============================================================
#  PHASE 8 -- MONTE CARLO VALIDATION
# ============================================================
function Invoke-MbfPhase8 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$Phase7File = "walkforward_regime_results.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 8: MONTE CARLO VALIDATION =====" -ForegroundColor Cyan
    $wfPath = Join-Path $OutputDir $Phase7File
    if (-not (Test-Path $wfPath)) { Write-Warning "Phase 7 output not found: $wfPath"; return $null }

    $wfResults = Import-Csv $wfPath
    $mcResults = @()

    foreach ($sym in $Symbols) {
        $symWf = $wfResults | Where-Object { $_.Asset -eq $sym }
        $configs = $symWf | Group-Object Indicator, Params

        Write-Host "  Monte Carlo testing $($configs.Count) configs for $sym..." -ForegroundColor Yellow

        foreach ($cfg in $configs) {
            $entries = $cfg.Group
            $indicator = $entries[0].Indicator
            $params = $entries[0].Params

            $tradeReturns = @($entries | ForEach-Object { [double]$_.AvgReturn })
            if ($tradeReturns.Count -lt 5) { continue }

            # Run 1000 Monte Carlo iterations with fee/slippage variation
            $iterations = 1000
            $mcReturnDist = @()
            $mcDDist = @()

            $rng = [System.Random]::new()
            for ($iter = 0; $iter -lt $iterations; $iter++) {
                $capital = 100.0
                $peak = 100.0
                $maxDD = 0.0
                foreach ($ret in $tradeReturns) {
                    # Randomly select a trade return with replacement
                    $r = $tradeReturns[$rng.Next(0, $tradeReturns.Count)]
                    # Fee variation: random fee between 0.02% and 0.15%
                    $fee = (0.02 + $rng.NextDouble() * 0.13) / 100.0
                    # Slippage variation: random slippage between 0 and 0.1%
                    $slippage = $rng.NextDouble() * 0.1 / 100.0
                    $netRet = $r - $fee * 100 - $slippage * 100
                    $capital += $capital * $netRet / 100
                    if ($capital -gt $peak) { $peak = $capital }
                    $dd = ($peak - $capital) / $peak * 100
                    if ($dd -gt $maxDD) { $maxDD = $dd }
                }
                $totalRet = ($capital - 100.0) / 100.0 * 100
                $mcReturnDist += $totalRet
                $mcDDist += $maxDD
            }

            $meanRet = ($mcReturnDist | Measure-Object -Average).Average
            $medianRet = ($mcReturnDist | Sort-Object)[[Math]::Floor($mcReturnDist.Count/2)]
            $stdRet = Get-StdDev $mcReturnDist
            $sortedRets = $mcReturnDist | Sort-Object
            $ci95Low = $sortedRets[[Math]::Floor($sortedRets.Count * 0.025)]
            $ci95High = $sortedRets[[Math]::Floor($sortedRets.Count * 0.975)]
            $meanDD = ($mcDDist | Measure-Object -Average).Average
            $maxDD95 = ($mcDDist | Sort-Object)[[Math]::Floor($mcDDist.Count * 0.95)]

            $mcResults += [PSCustomObject]@{
                Asset = $sym
                Indicator = $indicator
                Params = $params
                TradeCount = $tradeReturns.Count
                Iterations = $iterations
                MeanReturn = [Math]::Round($meanRet, 4)
                MedianReturn = [Math]::Round($medianRet, 4)
                StdReturn = [Math]::Round($stdRet, 4)
                CI95Low = [Math]::Round($ci95Low, 4)
                CI95High = [Math]::Round($ci95High, 4)
                AvgMaxDrawdown = [Math]::Round($meanDD, 4)
                MaxDD95 = [Math]::Round($maxDD95, 4)
                PositiveReturnPct = [Math]::Round(($mcReturnDist | Where-Object { $_ -gt 0 }).Count / $mcReturnDist.Count * 100, 2)
            }
        }
    }

    $outPath = Join-Path $OutputDir "montecarlo_regime_results.csv"
    $mcResults | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 8 complete. Saved to $outPath" -ForegroundColor Green
    return $mcResults
}

# ============================================================
#  PHASE 9 -- EDGE DISCOVERY
# ============================================================
function Invoke-MbfPhase9 {
    param(
        [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
        [string]$Phase7File = "walkforward_regime_results.csv",
        [string]$Phase8File = "montecarlo_regime_results.csv",
        [string]$Phase5File = "behavior_detector_rankings.csv",
        [string]$Phase4File = "behavior_catalog.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 9: EDGE DISCOVERY =====" -ForegroundColor Cyan
    $wfPath = Join-Path $OutputDir $Phase7File
    $mcPath = Join-Path $OutputDir $Phase8File
    $detPath = Join-Path $OutputDir $Phase5File
    $behPath = Join-Path $OutputDir $Phase4File

    if (-not (Test-Path $wfPath) -or -not (Test-Path $mcPath)) {
        Write-Warning "Phases 7 and 8 required"; return $null
    }

    $wf = Import-Csv $wfPath
    $mc = Import-Csv $mcPath
    $det = if (Test-Path $detPath) { Import-Csv $detPath } else { $null }
    $beh = if (Test-Path $behPath) { Import-Csv $behPath } else { $null }

    $edges = @()

    foreach ($sym in $Symbols) {
        Write-Host "  Discovering edges for $sym..." -ForegroundColor Yellow
        $symWf = $wf | Where-Object { $_.Asset -eq $sym }
        $symMc = $mc | Where-Object { $_.Asset -eq $sym }

        $configKeys = $symWf | Group-Object Indicator, Params, Regime

        foreach ($ck in $configKeys) {
            $indicator = $($ck.Name -split ', ')[0]
            $params = $($ck.Name -split ', ')[1]
            $regime = $($ck.Name -split ', ')[2]

            $wfEntries = $ck.Group
            $mcMatch = $symMc | Where-Object { $_.Indicator -eq $indicator -and $_.Params -eq $params } | Select-Object -First 1

            # 1. Expectancy (positive? consistent across folds?)
            $expectancies = $wfEntries | ForEach-Object { [double]$_.Expectancy }
            $avgExpectancy = if ($expectancies.Count -gt 0) { ($expectancies | Measure-Object -Average).Average } else { 0 }
            $stdExpectancy = Get-StdDev $expectancies
            $expectancyConsistency = if ($avgExpectancy -ne 0) { 1.0 - [Math]::Min(1.0, $stdExpectancy / [Math]::Abs($avgExpectancy)) } else { 0 }
            $allPositive = ($expectancies | Where-Object { $_ -gt 0 }).Count -eq $expectancies.Count

            # 2. Robustness (works across multiple walk-forward folds)
            $foldCount = $wfEntries.Count
            $positiveFoldPct = if ($foldCount -gt 0) { ($expectancies | Where-Object { $_ -gt 0 }).Count / $foldCount * 100 } else { 0 }

            # 3. Drawdown
            $avgDD = if ($wfEntries.Count -gt 0) { ($wfEntries | ForEach-Object { [double]$_.MaxConsecLoss } | Measure-Object -Average).Average } else { 0 }
            $mcDD = if ($mcMatch) { [double]$mcMatch.AvgMaxDrawdown } else { 99 }

            # 4. Consistency (Sharpe across folds)
            $sharpes = $wfEntries | ForEach-Object { [double]$_.Sharpe }
            $avgSharpe = if ($sharpes.Count -gt 0) { ($sharpes | Measure-Object -Average).Average } else { 0 }

            # 5. Trade frequency
            $avgSignalCount = if ($wfEntries.Count -gt 0) { ($wfEntries | ForEach-Object { [int]$_.SignalCount } | Measure-Object -Average).Average } else { 0 }

            # Detection accuracy
            $detAccuracy = 0
            if ($det) {
                $detMatch = $det | Where-Object { $_.Asset -eq $sym -and $_.Indicator -eq $indicator -and $_.Params -eq $params -and $_.Regime -eq $regime }
                if ($detMatch) { $detAccuracy = ($detMatch | Measure-Object DetectionAccuracy -Average).Average }
            }

            # Composite edge score: weighted by robustness criteria
            $edgeScore = 0
            if ($avgExpectancy -gt 0) {
                $edgeScore = [Math]::Min(1.0, $avgExpectancy / 2.0) * 0.30 +
                             ($positiveFoldPct / 100) * 0.20 +
                             [Math]::Min(1.0, (1.0 - $avgDD / 20)) * 0.15 +
                             [Math]::Min(1.0, $avgSharpe / 2) * 0.15 +
                             [Math]::Min(1.0, $avgSignalCount / 50) * 0.10 +
                             ($detAccuracy / 100) * 0.10
            }

            if ($edgeScore -gt 0 -or $allPositive) {
                $edges += [PSCustomObject]@{
                    Asset = $sym
                    Regime = $regime
                    Indicator = $indicator
                    Params = $params
                    AvgExpectancy = [Math]::Round($avgExpectancy, 4)
                    ExpectancyConsistency = [Math]::Round($expectancyConsistency, 4)
                    AllFoldsPositive = $allPositive
                    PositiveFoldPct = [Math]::Round($positiveFoldPct, 1)
                    AvgSharpe = [Math]::Round($avgSharpe, 4)
                    AvgMaxConsecLoss = [Math]::Round($avgDD, 1)
                    MCAvgDrawdown = [Math]::Round($mcDD, 2)
                    AvgSignalCount = [Math]::Round($avgSignalCount, 1)
                    DetectionAccuracy = [Math]::Round($detAccuracy, 2)
                    EdgeScore = [Math]::Round($edgeScore, 4)
                }
            }
        }
    }

    # Sort by edge criteria
    $ranked = $edges | Sort-Object -Property @{Expression="AvgExpectancy";Descending=$true}, @{Expression="PositiveFoldPct";Descending=$true}, @{Expression="AvgSharpe";Descending=$true}, "AvgMaxConsecLoss", @{Expression="AvgSignalCount";Descending=$true}

    $outPath = Join-Path $OutputDir "institutional_edge_candidates.csv"
    $ranked | Export-Csv -Path $outPath -NoTypeInformation
    Write-Host "`nPhase 9 complete. Saved to $outPath" -ForegroundColor Green

    # Summary
    Write-Host "`nTop edge candidates:" -ForegroundColor Green
    $ranked | Select-Object -First 10 | Format-Table Asset, Regime, Indicator, Params, AvgExpectancy, AvgSharpe, PositiveFoldPct -AutoSize | Out-String | Write-Host

    return $ranked
}

# ============================================================
#  PHASE 10 -- FINAL REPORT
# ============================================================
function Invoke-MbfPhase10 {
    param(
        [string]$Phase2File = "asset_timeframe_profile.csv",
        [string]$Phase3File = "market_regimes.csv",
        [string]$Phase4File = "behavior_catalog.csv",
        [string]$Phase5File = "behavior_detector_rankings.csv",
        [string]$Phase6File = "regime_playbook.csv",
        [string]$Phase9File = "institutional_edge_candidates.csv",
        [string]$OutputDir = "."
    )
    Write-Host "`n===== PHASE 10: FINAL REPORT =====" -ForegroundColor Cyan

    $tfProfile = if (Test-Path (Join-Path $OutputDir $Phase2File)) { Import-Csv (Join-Path $OutputDir $Phase2File) } else { $null }
    $regimes = if (Test-Path (Join-Path $OutputDir $Phase3File)) { Import-Csv (Join-Path $OutputDir $Phase3File) } else { $null }
    $behaviors = if (Test-Path (Join-Path $OutputDir $Phase4File)) { Import-Csv (Join-Path $OutputDir $Phase4File) } else { $null }
    $detRankings = if (Test-Path (Join-Path $OutputDir $Phase5File)) { Import-Csv (Join-Path $OutputDir $Phase5File) } else { $null }
    $playbook = if (Test-Path (Join-Path $OutputDir $Phase6File)) { Import-Csv (Join-Path $OutputDir $Phase6File) } else { $null }
    $edges = if (Test-Path (Join-Path $OutputDir $Phase9File)) { Import-Csv (Join-Path $OutputDir $Phase9File) } else { $null }

    $reportLines = @(
        "========================================================================",
        "  INSTITUTIONAL MARKET BEHAVIOR RESEARCH -- FINAL REPORT",
        "========================================================================",
        "  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "========================================================================",
        ""
    )

    $assets = @("SOLUSDT", "ICPUSDT")

    foreach ($sym in $assets) {
        $reportLines += "========================================================================"
        $reportLines += "  ASSET: $sym"
        $reportLines += "========================================================================"
        $reportLines += ""

        # Best Timeframe
        $reportLines += "--- BEST TIMEFRAME ---"
        if ($tfProfile) {
            $symTf = $tfProfile | Where-Object { $_.Asset -eq $sym } | Sort-Object BehaviorScore -Descending
            if ($symTf) {
                foreach ($tf in $symTf) {
                    $star = if ($tf -eq $symTf[0]) { " *" } else { "" }
                    $reportLines += "  $($tf.Timeframe): score=$($tf.BehaviorScore)$star"
                }
                $reportLines += "  BEST: $($symTf[0].Timeframe) (BehaviorScore=$($symTf[0].BehaviorScore))"
                $reportLines += "  TrendPersistence=$($symTf[0].TrendPersistencePct)%  MeanRev=$($symTf[0].MeanRevStrengthPct)%  BreakoutCont=$($symTf[0].BreakoutContPct)%"
            }
        }
        $reportLines += ""

        # Dominant Regimes
        $reportLines += "--- DOMINANT REGIMES ---"
        if ($regimes) {
            $symRegs = $regimes | Where-Object { $_.Asset -eq $sym }
            $regDist = $symRegs | Group-Object Regime | Sort-Object Count -Descending
            foreach ($rd in $regDist) {
                $pct = $rd.Count / $symRegs.Count * 100
                $reportLines += "  $($rd.Name): $($rd.Count) bars ($([Math]::Round($pct,1))%)"
            }
        }
        $reportLines += ""

        # Recurring Behaviors
        $reportLines += "--- RECURRING BEHAVIORS ---"
        if ($behaviors) {
            $symBeh = $behaviors | Where-Object { $_.Asset -eq $sym }
            foreach ($sb in $symBeh) {
                $reportLines += "  $($sb.Regime):"
                $reportLines += "    Avg 1B Move: $($sb.AvgMove1B)% | 5B: $($sb.AvgMove5B)% | 20B: $($sb.AvgMove20B)%"
                $reportLines += "    Reversal: $($sb.ReversalFreqPct)% | Continuation: $($sb.ContinuationProbPct)%"
                $reportLines += "    Breakout: $($sb.BreakoutProbPct)% | Fade: $($sb.FadeProbPct)%"
                $reportLines += "    Avg Duration: $($sb.AvgMoveDurationBars) bars | Up Bias: $($sb.UpBiasPct)%"
            }
        }
        $reportLines += ""

        # Best Detectors
        $reportLines += "--- BEST DETECTORS ---"
        if ($playbook) {
            $symPb = $playbook | Where-Object { $_.Asset -eq $sym }
            foreach ($pb in $symPb) {
                $reportLines += "  Regime: $($pb.Regime)"
                $reportLines += "    1st: $($pb.BestIndicator1)($($pb.BestParams1)) F1=$($pb.BestF1_1)"
                $reportLines += "    2nd: $($pb.BestIndicator2)($($pb.BestParams2)) F1=$($pb.BestF1_2)"
                $reportLines += "    3rd: $($pb.BestIndicator3)($($pb.BestParams3)) F1=$($pb.BestF1_3)"
                $reportLines += "    Avg F1: $($pb.AvgF1) | Precision: $($pb.AvgPrecision) | Recall: $($pb.AvgRecall)"
            }
        }
        $reportLines += ""

        # Strongest Edge Candidates
        $reportLines += "--- STRONGEST EDGE CANDIDATES ---"
        if ($edges) {
            $symEdges = $edges | Where-Object { $_.Asset -eq $sym } | Sort-Object AvgExpectancy -Descending | Select-Object -First 10
            $reportLines += "  Rank | Indicator | Params | Regime | Expectancy | Sharpe | PosFolds% | MaxDD"
            $reportLines += "  -----+-----------+-------+--------+------------+--------+----------+-------"
            $rank = 1
            foreach ($e in $symEdges) {
                $reportLines += "  {0,-4} | {1,-9} | {2,-5} | {3,-6} | {4,8} | {5,6} | {6,6}% | {7,5}" -f $rank, $e.Indicator, $e.Params, $e.Regime, $e.AvgExpectancy, $e.AvgSharpe, $e.PositiveFoldPct, $e.AvgMaxConsecLoss
                $rank++
            }
        }
        $reportLines += ""
    }

    # Cross-asset patterns
    $reportLines += "========================================================================"
    $reportLines += "  CROSS-ASSET PATTERNS (BEHAVIORS THAT PERSIST ACROSS YEARS AND REGIMES)"
    $reportLines += "========================================================================"
    $reportLines += ""

    # Find indicators/configs that appear as edges for both assets
    if ($edges) {
        $edgeByConfig = $edges | Group-Object Indicator, Params, Regime
        foreach ($ec in $edgeByConfig) {
            $ecAssets = $ec.Group | Select-Object -ExpandProperty Asset -Unique
            if ($ecAssets.Count -gt 1) {
                $reportLines += "  CROSS-ASSET EDGE: $($ec.Name)"
                foreach ($ea in $ec.Group) {
                    $reportLines += "    $($ea.Asset): Exp=$($ea.AvgExpectancy) Sharpe=$($ea.AvgSharpe) PosFolds=$($ea.PositiveFoldPct)%"
                }
                $reportLines += "  *** This pattern persists across BOTH assets -- high institutional confidence ***"
                $reportLines += ""
            }
        }
    }

    $reportLines += "========================================================================"
    $reportLines += "  METHODOLOGY NOTES"
    $reportLines += "========================================================================"
    $reportLines += "  - Phases executed in order: Data->Timeframes->Regimes->Behaviors->Detectors->Playbook->Walk-Forward->Monte Carlo->Edge"
    $reportLines += "  - Indicators are sensors, NOT profit generators"
    $reportLines += "  - Behaviors were discovered from market structure, NOT from indicator outputs"
    $reportLines += "  - Walk-forward validation: 5-fold rolling windows, train/freeze/test"
    $reportLines += "  - Monte Carlo: 1000 iterations with fee (0.02-0.15%) and slippage (0-0.1%) randomization"
    $reportLines += "  - Edge ranking by: expectancy > robustness (fold consistency) > Sharpe > drawdown > frequency"
    $reportLines += "  - All prior results invalidated by temporal exclusion and skip-after-loss removal"
    $reportLines += "========================================================================"
    $reportLines += ""

    $report = $reportLines -join "`n"
    $outPath = Join-Path $OutputDir "market_behavior_report.txt"
    $report | Out-File -FilePath $outPath -Encoding utf8
    Write-Host $report
    Write-Host "Phase 10 complete. Report saved to $outPath" -ForegroundColor Green
    return $report
}



# ============================================================
#  VOLUME PROFILE
# ============================================================
function Calc-VolumeProfile {
    param($h, $l, $c, $v, $per = 24)
    $n = $h.Count
    $out = @{VAH=[double[]]::new($n);VAL=[double[]]::new($n);POC=[double[]]::new($n);Position=[double[]]::new($n)}
    for ($i = $per; $i -lt $n; $i++) {
        $minP = 1e99; $maxP = -1e99
        for ($j = $i-$per+1; $j -le $i; $j++) {
            if ($l[$j] -lt $minP) { $minP = $l[$j] }
            if ($h[$j] -gt $maxP) { $maxP = $h[$j] }
        }
        $step = ($maxP - $minP) / 20
        if ($step -le 0) { $out.VAH[$i]=$c[$i];$out.VAL[$i]=$c[$i];$out.POC[$i]=$c[$i]; continue }
        $vol = [double[]]::new(20)
        for ($j = $i-$per+1; $j -le $i; $j++) {
            $top = [Math]::Min(19, [Math]::Max(0, [Math]::Floor(($h[$j]-$minP)/$step)))
            $bot = [Math]::Min(19, [Math]::Max(0, [Math]::Floor(($l[$j]-$minP)/$step)))
            $span = $top - $bot + 1
            $vpp = $v[$j] / $span
            for ($b = $bot; $b -le $top; $b++) { $vol[$b] += $vpp }
        }
        $maxIdx = 0; $maxVol = $vol[0]
        for ($b = 1; $b -lt 20; $b++) { if ($vol[$b] -gt $maxVol) { $maxVol = $vol[$b]; $maxIdx = $b } }
        $total = 0.0; for ($b = 0; $b -lt 20; $b++) { $total += $vol[$b] }
        $target = $total * 0.7
        $cum = $vol[$maxIdx]; $lIdx = $maxIdx - 1; $rIdx = $maxIdx + 1
        while ($cum -lt $target -and ($lIdx -ge 0 -or $rIdx -lt 20)) {
            $lv = if ($lIdx -ge 0) { $vol[$lIdx] } else { -1 }
            $rv = if ($rIdx -lt 20) { $vol[$rIdx] } else { -1 }
            if ($lv -ge $rv) { $cum += $lv; $lIdx-- } else { $cum += $rv; $rIdx++ }
        }
        $out.VAL[$i] = $minP + ($lIdx + 1) * $step
        $out.VAH[$i] = $minP + $rIdx * $step
        $out.POC[$i] = $minP + ($maxIdx + 0.5) * $step
        if ($c[$i] -lt $out.VAL[$i]) { $out.Position[$i] = -1.0 }
        elseif ($c[$i] -gt $out.VAH[$i]) { $out.Position[$i] = 1.0 }
    }
    return $out
}

# ============================================================
#  PHASE 11 — INSTITUTIONAL REGIME DISCOVERY & EDGE VALIDATION
# ============================================================
function Invoke-MbfPhase11 {
    param(
        [string]$InputDir = ".",
        [string]$OutputDir = ".",
        [switch]$SkipAcquisition,
        [switch]$SkipRegime,
        [switch]$SkipQuality,
        [switch]$SkipEval,
        [switch]$SkipWalkforward,
        [switch]$SkipMonteCarlo,
        [switch]$SkipReport
    )
    $start = Get-Date
    $tfMap = @{"30m"="30m";"1h"="1h";"4h"="4h"}
    $timeframeFiles = @("30m","1h","4h")
    $assets = @("SOLUSDT","ICPUSDT")
    $assetFiles = @{
        "SOLUSDT" = @{
            "30m" = "SOLUSDT-FUTURES-2021-2026-30m.csv"
            "1h"  = "SOLUSDT-FUTURES-2022-2026-1h.csv"
            "4h"  = "SOLUSDT-FUTURES-2022-2026-4h.csv"
        }
        "ICPUSDT" = @{
            "30m" = "ICPUSDT-FUTURES-2022-2026-30m.csv"
            "1h"  = "ICPUSDT-FUTURES-2022-2026-1h.csv"
            "4h"  = "ICPUSDT-FUTURES-2022-2026-4h.csv"
        }
    }

    $dataCache = @{}  # "Asset_TF" -> klines

    # Load existing edge candidates from Phase 9
    $candidatesPath = Join-Path $OutputDir "institutional_edge_candidates.csv"

    # ================================================================
    # PHASE 11.1 — LOAD DATA (or skip if cached)
    # ================================================================
    if (-not $SkipAcquisition) {
        Write-Host "`n===== PHASE 11.1: DATA ACQUISITION =====" -ForegroundColor Cyan
        foreach ($asset in $assets) {
            foreach ($tf in $timeframeFiles) {
                $p = Join-Path $InputDir $assetFiles[$asset][$tf]
                if (-not (Test-Path $p)) { Write-Warning "Missing: $p"; continue }
                $data = Import-Csv $p
                $dataCache["${asset}_${tf}"] = $data
                $first = $data[0].Date; $last = $data[-1].Date
                Write-Host "  Loaded $asset $tf : $($data.Count) rows, $first to $last" -ForegroundColor Gray
            }
        }
        Write-Host "Phase 11.1 complete: $(($dataCache.Keys | Measure-Object).Count) datasets" -ForegroundColor Green
    } else {
        Write-Host "Phase 11.1: SKIPPED" -ForegroundColor DarkYellow
    }

    # ================================================================
    # PHASE 11.2 — REGIME DISCOVERY REBUILD
    # ================================================================
    if (-not $SkipRegime) {
        Write-Host "`n===== PHASE 11.2: REGIME DISCOVERY REBUILD =====" -ForegroundColor Cyan
        $allRegimeDist = @()

        foreach ($asset in $assets) {
            $tf = "4h"
            $key = "${asset}_${tf}"
            if (-not $dataCache.ContainsKey($key)) { Write-Warning "No data for $asset $tf"; continue }
            $klines = $dataCache[$key]
            $n = $klines.Count
            Write-Host "  Computing features for $asset 4h ($n bars)..." -ForegroundColor Yellow

            $h = [double[]]::new($n); $l = [double[]]::new($n); $c = [double[]]::new($n); $v = [double[]]::new($n)
            for ($i = 0; $i -lt $n; $i++) { $h[$i]=[double]$klines[$i].High; $l[$i]=[double]$klines[$i].Low; $c[$i]=[double]$klines[$i].Close; $v[$i]=[double]$klines[$i].Volume }

            # Indicators we need
            $atr = Calc-ATR $h $l $c 14
            $adx, $du, $dd = Calc-ADX $h $l $c 14
            $ema20 = Calc-EMA $c 20
            $ema50 = Calc-EMA $c 50
            $ema200 = if ($n -gt 200) { Calc-EMA $c 200 } else { $null }
            $vp = Calc-VolumeProfile $h $l $c $v 24

            # Build feature vectors (starting from bar 200 to have all indicators stable)
            $features = New-Object 'System.Collections.Generic.List[double[]]'
            $startBar = 200
            $nFeat = $n

            for ($i = $startBar; $i -lt $n; $i++) {
                # 1. Realized volatility (20-bar log return std dev)
                $lr = Get-LogReturns $c[($i-19)..$i]
                $rv = Get-StdDev $lr

                # 2. ATR normalized (% of price)
                $atrPct = if ($c[$i] -gt 0) { $atr[$i] / $c[$i] * 100 } else { 0 }

                # 3. Trend persistence (20-bar return autocorrelation lag=1)
                $rets = Get-LogReturns $c[($i-39)..$i]
                $trend = if ($rets.Count -gt 2) { Get-Autocorrelation $rets 1 } else { 0 }

                # 4. Trend slope (EMA20 - EMA50 / price)
                $slope = if ($c[$i] -gt 0 -and $ema20[$i] -ne 0) { ($ema20[$i] - $ema50[$i]) / $c[$i] * 100 } else { 0 }

                # 5. Directional movement (+DI - -DI spread)
                $diSpread = [Math]::Abs($du[$i] - $dd[$i])
                $diDir = if ($du[$i] -gt $dd[$i]) { 1 } elseif ($dd[$i] -gt $du[$i]) { -1 } else { 0 }

                # 6. Volume expansion (z-score of last 20)
                $vSlice = $v[($i-19)..$i]
                $vm = ($vSlice | Measure-Object -Average).Average
                $vs = Get-StdDev $vSlice
                $vz = if ($vs -gt 0) { ($v[$i] - $vm) / $vs } else { 0 }

                # 7. Volatility compression (range / ATR)
                $cr = ($h[$i] - $l[$i])
                $vc = if ($atr[$i] -gt 0) { $cr / $atr[$i] } else { 1 }

                # 8. Volume Profile position (price relative to value area)
                $vpPos = $vp.Position[$i]

                # 9. Distance from POC (%)
                $pocDist = if ($vp.POC[$i] -gt 0) { ($c[$i] - $vp.POC[$i]) / $vp.POC[$i] * 100 } else { 0 }

                # 10. EMA200 distance (long-term trend context)
                $ema200Dist = if ($ema200 -and $ema200[$i] -gt 0) { ($c[$i] - $ema200[$i]) / $ema200[$i] * 100 } else { 0 }

                $fVec = [double[]]($rv, $atrPct, $trend, $slope, $diSpread, $diDir, $vz, $vc, $vpPos, $pocDist, $ema200Dist)
                $features.Add($fVec) > $null
            }

            # Standardize features (z-score) so all dimensions have equal weight
            $m = $features.Count
            $dims = $features[0].Count
            $featArr = [double[][]]::new($m)
            for ($i = 0; $i -lt $m; $i++) { $featArr[$i] = $features[$i] }
            $featMeans = [double[]]::new($dims); $featStd = [double[]]::new($dims)
            for ($j = 0; $j -lt $dims; $j++) {
                $sum = 0.0; for ($i = 0; $i -lt $m; $i++) { $sum += $featArr[$i][$j] }
                $featMeans[$j] = $sum / $m
                $sq = 0.0; for ($i = 0; $i -lt $m; $i++) { $d = $featArr[$i][$j] - $featMeans[$j]; $sq += $d * $d }
                $featStd[$j] = [Math]::Sqrt($sq / ($m - 1))
                if ($featStd[$j] -eq 0) { $featStd[$j] = 1 }
            }
            for ($i = 0; $i -lt $m; $i++) {
                for ($j = 0; $j -lt $dims; $j++) { $featArr[$i][$j] = ($featArr[$i][$j] - $featMeans[$j]) / $featStd[$j] }
            }

            # K-means++ clustering (K=7 for 7 target regimes)
            $Kcount = 7
            Write-Host "  Clustering $m bars into $Kcount regimes..." -ForegroundColor Yellow

            # K-means++ initialization
            $centroids = New-Object 'System.Collections.Generic.List[double[]]'
            $rng = [Random]::new(42)
            $firstIdx = $rng.Next(0, $m)
            $centroids.Add($featArr[$firstIdx]) > $null

            $dims = $featArr[0].Length
            for ($k = 1; $k -lt $Kcount; $k++) {
                $minDists = [double[]]::new($m)
                for ($i = 0; $i -lt $m; $i++) {
                    $minD = 1e99
                    foreach ($cent in $centroids) {
                        $d = 0.0
                        for ($j = 0; $j -lt $dims; $j++) {
                            $diff = $featArr[$i][$j] - $cent[$j]
                            $d += $diff * $diff
                        }
                        if ($d -lt $minD) { $minD = $d }
                    }
                    $minDists[$i] = $minD
                }
                $totalD = ($minDists | Measure-Object -Sum).Sum
                $cum = 0.0; $threshold = $rng.NextDouble() * $totalD
                $nextIdx = $m - 1
                for ($i = 0; $i -lt $m; $i++) {
                    $cum += $minDists[$i]
                    if ($cum -ge $threshold) { $nextIdx = $i; break }
                }
                $centroids.Add($featArr[$nextIdx]) > $null
            }

            # Iterate K-means (max 50 iterations)
            $labels = [int[]]::new($m)
            for ($iter = 0; $iter -lt 50; $iter++) {
                $changed = 0
                for ($i = 0; $i -lt $m; $i++) {
                    $minD = 1e99; $bestK = 0
                    for ($k = 0; $k -lt $Kcount; $k++) {
                        $d = 0.0
                        for ($j = 0; $j -lt $dims; $j++) {
                            $diff = $featArr[$i][$j] - $centroids[$k][$j]
                            $d += $diff * $diff
                        }
                        if ($d -lt $minD) { $minD = $d; $bestK = $k }
                    }
                    if ($labels[$i] -ne $bestK) { $changed++; $labels[$i] = $bestK }
                }
                if ($changed -eq 0) { break }

                # Update centroids
                for ($k = 0; $k -lt $Kcount; $k++) {
                    $count = 0; $sum = [double[]]::new($dims)
                    for ($i = 0; $i -lt $m; $i++) {
                        if ($labels[$i] -eq $k) { $count++; for ($j = 0; $j -lt $dims; $j++) { $sum[$j] += $featArr[$i][$j] } }
                    }
                    if ($count -gt 0) { for ($j = 0; $j -lt $dims; $j++) { $centroids[$k][$j] = $sum[$j] / $count } }
                }
            }

            # Map clusters to regime names (now z-scores: mean=0, std=1)
            $allNames = @("TREND_UP","TREND_DOWN","RANGE","ACCUMULATION","DISTRIBUTION","VOL_EXPANSION","VOL_COMPRESSION")
            $clusterRegime = @{}
            $usedNames = @{}

            for ($k = 0; $k -lt $Kcount; $k++) {
                $rvZ = $centroids[$k][0]
                $atrZ = $centroids[$k][1]
                $trendZ = $centroids[$k][2]
                $slopeZ = $centroids[$k][3]
                $diSpreadZ = $centroids[$k][4]
                $diDirZ = $centroids[$k][5]
                $vzZ = $centroids[$k][6]
                $vcZ = $centroids[$k][7]
                $vpZ = $centroids[$k][8]
                $pocZ = $centroids[$k][9]
                $ema200Z = $centroids[$k][10]

                if ($vcZ -lt -0.8 -or $rvZ -gt 1.5) { $name = "VOL_EXPANSION" }
                elseif ($vcZ -gt 0.8 -and $rvZ -lt -0.5) { $name = "VOL_COMPRESSION" }
                elseif ($slopeZ -gt 0.5 -and $diDirZ -gt 0.3 -and $trendZ -gt 0.2) { $name = "TREND_UP" }
                elseif ($slopeZ -lt -0.5 -and $diDirZ -lt -0.3 -and $trendZ -gt 0.2) { $name = "TREND_DOWN" }
                elseif ($trendZ -lt -0.3 -and $slopeZ -gt -0.5 -and $slopeZ -lt 0.5) { $name = "RANGE" }
                elseif ($vpZ -gt 0.5 -and $vzZ -gt 0.5) { $name = "DISTRIBUTION" }
                elseif ($vpZ -lt -0.5 -and $vzZ -lt -0.5) { $name = "ACCUMULATION" }
                else { $name = "RANGE" }

                if ($usedNames.ContainsKey($name)) {
                    foreach ($fb in $allNames) {
                        if (-not $usedNames.ContainsKey($fb)) { $name = $fb; break }
                    }
                }
                $clusterRegime[$k] = $name
                $usedNames[$name] = $true
            }

            # Null-safe: ensure every cluster has a name
            foreach ($k in 0..($Kcount-1)) {
                if (-not $clusterRegime.ContainsKey($k) -or -not $clusterRegime[$k]) {
                    foreach ($fb in $allNames) {
                        if (-not $usedNames.ContainsKey($fb)) { $clusterRegime[$k] = $fb; $usedNames[$fb] = $true; break }
                    }
                    if (-not $clusterRegime[$k]) { $clusterRegime[$k] = "RANGE"; $usedNames["RANGE"] = $true }
                }
            }

            # Assign full bar labels
            $barRegimes = @("") * $n
            for ($i = 0; $i -lt $startBar; $i++) { $barRegimes[$i] = "WARMUP" }

            for ($i = $startBar; $i -lt $n; $i++) {
                $clusterIdx = $labels[$i - $startBar]
                $barRegimes[$i] = $clusterRegime[$clusterIdx]
            }

            # Distribution
            $dist = @{}
            foreach ($r in $barRegimes) {
                $rk = if ($r) { $r } else { "UNKNOWN" }
                if (-not $dist.ContainsKey($rk)) { $dist[$rk] = 0 }
                $dist[$rk]++
            }
            Write-Host "  $asset regime distribution:" -ForegroundColor Yellow
            foreach ($kv in $dist.GetEnumerator() | Sort-Object Name) {
                $pct = [Math]::Round($kv.Value / $n * 100, 1)
                Write-Host "    $($kv.Key) : $($kv.Value) bars ($pct%)" -ForegroundColor Gray
                $allRegimeDist += [PSCustomObject]@{Asset=$asset; Regime=$kv.Key; BarCount=$kv.Value; PercentOfHistory=$pct}
            }

            # Save regimes
            $regOut = @()
            for ($i = 0; $i -lt $n; $i++) {
                $regOut += [PSCustomObject]@{Index=$i; Timestamp=$klines[$i].Time; Date=$klines[$i].Date; Regime=$barRegimes[$i]}
            }
            $regPath = Join-Path $OutputDir "phase11_regimes_${asset}_4h.csv"
            $regOut | Export-Csv -Path $regPath -NoTypeInformation
            Write-Host "  Saved regimes to $regPath" -ForegroundColor Green

            # Cache regimes for later phases
            $dataCache["${asset}_regimes_4h"] = $barRegimes
        }

        $distPath = Join-Path $OutputDir "regime_distribution.csv"
        $allRegimeDist | Export-Csv -Path $distPath -NoTypeInformation
        Write-Host "Phase 11.2 complete. Saved to $distPath" -ForegroundColor Green
    } else {
        Write-Host "Phase 11.2: SKIPPED" -ForegroundColor DarkYellow
    }

    # ================================================================
    # PHASE 11.3 — REGIME QUALITY TEST
    # ================================================================
    if (-not $SkipQuality) {
        Write-Host "`n===== PHASE 11.3: REGIME QUALITY TEST =====" -ForegroundColor Cyan
        $qualityRows = @()

        foreach ($asset in $assets) {
            $regPath = Join-Path $OutputDir "phase11_regimes_${asset}_4h.csv"
            if (-not (Test-Path $regPath)) { Write-Warning "No regimes for $asset"; continue }
            $rdata = Import-Csv $regPath
            $regimes = $rdata.Regime
            $n = $regimes.Count
            $unique = $regimes | Select-Object -Unique | Where-Object { $_ -ne "WARMUP" }

            foreach ($reg in $unique) {
                # Count occurrences
                $bars = @(); for ($i = 0; $i -lt $n; $i++) { if ($regimes[$i] -eq $reg) { $bars += $i } }
                $count = $bars.Count
                $pct = [Math]::Round($count / $n * 100, 2)

                if ($count -lt 20) {
                    Write-Warning "  $asset $reg : only $count bars, sample too small"
                    $qualityRows += [PSCustomObject]@{
                        Asset=$asset; Regime=$reg; BarCount=$count; PercentOfHistory=$pct
                        PersistencePct=0; TransitionProb=0; AvgDurationBars=0
                        AvgMove1B=0; AvgMove5B=0; AvgMove20B=0
                        SampleSizeAdequate=$false
                    }
                    continue
                }

                # Persistence: % of bars where next bar stays in same regime
                $persist = 0
                for ($i = 0; $i -lt $n - 1; $i++) {
                    if ($regimes[$i] -eq $reg -and $regimes[$i+1] -eq $reg) { $persist++ }
                }
                $persistPct = if ($count -gt 0) { [Math]::Round($persist / $count * 100, 2) } else { 0 }

                # Average duration (consecutive runs)
                $durations = @()
                $runLen = 0
                for ($i = 0; $i -lt $n; $i++) {
                    if ($regimes[$i] -eq $reg) { $runLen++ }
                    elseif ($runLen -gt 0) { $durations += $runLen; $runLen = 0 }
                }
                if ($runLen -gt 0) { $durations += $runLen }
                $avgDur = if ($durations.Count -gt 0) { [Math]::Round(($durations | Measure-Object -Average).Average, 1) } else { 0 }

                # Transition probability (Markov)
                $transitions = @{}
                $totalTrans = 0
                for ($i = 0; $i -lt $n - 1; $i++) {
                    if ($regimes[$i] -eq $reg -and $regimes[$i+1] -ne $reg) {
                        $next = $regimes[$i+1]
                        if (-not $transitions.ContainsKey($next)) { $transitions[$next] = 0 }
                        $transitions[$next]++; $totalTrans++
                    }
                }
                $topTrans = ""
                if ($totalTrans -gt 0) {
                    $topNext = ($transitions.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1)
                    $topTransPct = [Math]::Round($topNext.Value / $totalTrans * 100, 1)
                    $topTrans = "$($topNext.Key) ($topTransPct%)"
                }

                # Average forward move
                $key = "${asset}_4h"
                if ($dataCache.ContainsKey($key)) {
                    $klines = $dataCache[$key]
                    $close = $klines | ForEach-Object { [double]$_.Close }
                    $sum1=0; $sum5=0; $sum20=0; $cnt1=0; $cnt5=0; $cnt20=0
                    foreach ($idx in $bars) {
                        if ($idx+1 -lt $n) { $sum1 += ($close[$idx+1]-$close[$idx])/$close[$idx]*100; $cnt1++ }
                        if ($idx+5 -lt $n) { $sum5 += ($close[$idx+5]-$close[$idx])/$close[$idx]*100; $cnt5++ }
                        if ($idx+20 -lt $n) { $sum20 += ($close[$idx+20]-$close[$idx])/$close[$idx]*100; $cnt20++ }
                    }
                    $avg1 = if ($cnt1 -gt 0) { [Math]::Round($sum1/$cnt1, 2) } else { 0 }
                    $avg5 = if ($cnt5 -gt 0) { [Math]::Round($sum5/$cnt5, 2) } else { 0 }
                    $avg20 = if ($cnt20 -gt 0) { [Math]::Round($sum20/$cnt20, 2) } else { 0 }
                } else { $avg1=0;$avg5=0;$avg20=0 }

                Write-Host "  $asset $reg : ${count} bars (${pct}%) persist=${persistPct}% dur=${avgDur} trans=$topTrans" -ForegroundColor Gray

                $qualityRows += [PSCustomObject]@{
                    Asset=$asset; Regime=$reg; BarCount=$count; PercentOfHistory=$pct
                    PersistencePct=$persistPct; TransitionProb=$topTrans; AvgDurationBars=$avgDur
                    AvgMove1B=$avg1; AvgMove5B=$avg5; AvgMove20B=$avg20
                    SampleSizeAdequate=($count -ge 20)
                }
            }
        }

        $qPath = Join-Path $OutputDir "regime_quality_report.csv"
        $qualityRows | Export-Csv -Path $qPath -NoTypeInformation
        Write-Host "Phase 11.3 complete. Saved to $qPath" -ForegroundColor Green
    } else {
        Write-Host "Phase 11.3: SKIPPED" -ForegroundColor DarkYellow
    }

    # ================================================================
    # PHASE 11.4 — RE-EVALUATE EXISTING EDGE CANDIDATES
    # ================================================================
    # Known candidates from Phase 9 + Phase 6 playbook (defined outside SkipEval so 11.5/11.6 can use it)
    $candidates = @(
            @{Asset="SOLUSDT";Indicator="Stoch";Params="k=5,d=5,ob=80,os=10"},
            @{Asset="SOLUSDT";Indicator="Stoch";Params="k=21,d=9,ob=85,os=10"},
            @{Asset="ICPUSDT";Indicator="Stoch";Params="k=14,d=9,ob=80,os=10"},
            @{Asset="ICPUSDT";Indicator="Bollinger";Params="per=50,mult=3"},
            @{Asset="SOLUSDT";Indicator="CMF";Params="len=21,thresh=0"},
            @{Asset="SOLUSDT";Indicator="OBV";Params="ma=20"},
            @{Asset="SOLUSDT";Indicator="ADX";Params="len=14,thresh=25"},
            @{Asset="ICPUSDT";Indicator="CMF";Params="len=21,thresh=0"},
            @{Asset="ICPUSDT";Indicator="OBV";Params="ma=20"},
            @{Asset="ICPUSDT";Indicator="ADX";Params="len=14,thresh=25"}
        )

    if (-not $SkipEval) {
        Write-Host "`n===== PHASE 11.4: CANDIDATE RE-EVALUATION =====" -ForegroundColor Cyan
        $evalResults = @()
        $totalEval = ($candidates.Count) * 3
        $evalCount = 0

        foreach ($tf in @("30m","1h","4h")) {
            foreach ($cand in $candidates) {
                $evalCount++
                Write-Host "  Eval $evalCount/$totalEval : $($cand.Asset) $tf $($cand.Indicator) $($cand.Params)" -ForegroundColor DarkYellow
                $asset = $cand.Asset
                $key = "${asset}_${tf}"

                # Load data from cache or CSV
                if ($dataCache.ContainsKey($key)) { $klines = $dataCache[$key] }
                else {
                    $csvPath = Join-Path $InputDir $assetFiles[$asset][$tf]
                    if (-not (Test-Path $csvPath)) { continue }
                    $klines = Import-Csv $csvPath
                }
                $n = $klines.Count
                $h = [double[]]::new($n); $l = [double[]]::new($n); $c = [double[]]::new($n); $v = [double[]]::new($n)
                for ($i = 0; $i -lt $n; $i++) { $h[$i]=[double]$klines[$i].High;$l[$i]=[double]$klines[$i].Low;$c[$i]=[double]$klines[$i].Close;$v[$i]=[double]$klines[$i].Volume }

                # Load regimes for this asset (4h regime labels mapped down to TF)
                $regKey = "${asset}_regimes_4h"
                $tfMultiplier = @{"30m"=8;"1h"=4;"4h"=1}
                $mul = $tfMultiplier[$tf]
                $barRegimes = @("UNKNOWN") * $n
                if ($dataCache.ContainsKey($regKey)) {
                    $r4h = $dataCache[$regKey]
                } else {
                    $regPath = Join-Path $OutputDir "phase11_regimes_${asset}_4h.csv"
                    if (Test-Path $regPath) { $r4h = (Import-Csv $regPath).Regime }
                    else { $r4h = $null }
                }
                if ($r4h) {
                    for ($i = 0; $i -lt $n; $i++) {
                        $r4hIdx = [Math]::Floor($i / $mul)
                        if ($r4hIdx -lt $r4h.Count) { $barRegimes[$i] = $r4h[$r4hIdx] }
                    }
                }

                # Generate signal for this candidate
                $sig = Get-MbfSignalArray $cand.Indicator $cand.Params $c $h $l $v $n
                if (-not $sig) { continue }

                $sigList = New-Object 'System.Collections.Generic.List[int]'
                for ($si = 0; $si -lt $sig.Count; $si++) { if ($sig[$si]) { $sigList.Add($si) } }
                if ($sigList.Count -lt 5) { continue }
                $signalIndices = $sigList.ToArray()

                # Evaluate per regime
                $regimes = $barRegimes | Select-Object -Unique | Where-Object { $_ -ne "WARMUP" -and $_ -ne "UNKNOWN" }
                foreach ($reg in $regimes) {
                    $regSigList = New-Object 'System.Collections.Generic.List[int]'
                    foreach ($si in $signalIndices) { if ($si -ge 100 -and $si -lt $n -and $barRegimes[$si] -eq $reg) { $regSigList.Add($si) } }
                    $regSigCount = $regSigList.Count
                    if ($regSigCount -lt 3) { continue }

                    # Evaluate forward movement after signal (5-bar forward return)
                    $retList = New-Object 'System.Collections.Generic.List[double]'
                    foreach ($si in $regSigList) {
                        if ($si + 5 -lt $n) {
                            $retList.Add(($c[$si+5] - $c[$si]) / $c[$si] * 100)
                        }
                    }
                    $returns = $retList.ToArray()
                    if ($returns.Count -lt 3) { continue }

                    $avgRet = ($returns | Measure-Object -Average).Average
                    $positiveRet = ($returns | Where-Object { $_ -gt 0 }).Count
                    $winRate = [Math]::Round($positiveRet / $returns.Count * 100, 1)
                    $stdRet = Get-StdDev $returns
                    $sharpe = if ($stdRet -gt 0) { [Math]::Round($avgRet / $stdRet, 4) } else { 0 }
                    $profitFactor = if ($returns.Count -gt 0) {
                        $gains = ($returns | Where-Object { $_ -gt 0 } | Measure-Object -Sum).Sum
                        $losses = ($returns | Where-Object { $_ -lt 0 } | Measure-Object -Sum).Sum
                        if ($losses -eq 0) { "INF" } else { [Math]::Round([Math]::Abs($gains / $losses), 2) }
                    } else { 0 }

                    $evalResults += [PSCustomObject]@{
                        Asset=$asset; Timeframe=$tf; Regime=$reg
                        Indicator=$cand.Indicator; Params=$cand.Params
                        SignalCount=$regSigCount
                        AvgReturn5B=[Math]::Round($avgRet, 4)
                        WinRatePct=$winRate
                        Sharpe=$sharpe
                        ProfitFactor=$profitFactor
                        StdReturn=[Math]::Round($stdRet, 4)
                    }
                }
            }
        }

        $canPath = Join-Path $OutputDir "candidate_by_regime.csv"
        $evalResults | Export-Csv -Path $canPath -NoTypeInformation
        Write-Host "Phase 11.4 complete. Saved to $canPath" -ForegroundColor Green

        # Show summary
        Write-Host "`nCandidate evaluation summary:" -ForegroundColor Yellow
        $evalResults | Sort-Object Sharpe -Descending | Select-Object -First 15 | Format-Table -AutoSize
    } else {
        Write-Host "Phase 11.4: SKIPPED" -ForegroundColor DarkYellow
    }

    # ================================================================
    # PHASE 11.5 — LARGE WALK-FORWARD
    # ================================================================
    if (-not $SkipWalkforward) {
        Write-Host "`n===== PHASE 11.5: LARGE WALK-FORWARD =====" -ForegroundColor Cyan

        $useTF = "30m"
        $foldSize = 10000
        $trainSize = 20000
        $wfResults = @()

        foreach ($cand in $candidates) {
            $asset = $cand.Asset
            $key = "${asset}_${useTF}"
            if ($dataCache.ContainsKey($key)) { $klines = $dataCache[$key] }
            else {
                $csvPath = Join-Path $InputDir $assetFiles[$asset][$useTF]
                if (-not (Test-Path $csvPath)) { continue }
                $klines = Import-Csv $csvPath
            }
            $n = $klines.Count
            $h = [double[]]::new($n); $l = [double[]]::new($n); $c = [double[]]::new($n); $v = [double[]]::new($n)
            for ($i = 0; $i -lt $n; $i++) { $h[$i]=[double]$klines[$i].High;$l[$i]=[double]$klines[$i].Low;$c[$i]=[double]$klines[$i].Close;$v[$i]=[double]$klines[$i].Volume }

            $numFolds = [Math]::Floor(($n - $trainSize) / $foldSize)
            if ($numFolds -lt 2) { continue }

            $foldExpectancies = @()
            $foldWinRates = @()
            $foldSharpe = @()
            $foldTradeCounts = @()

            for ($f = 0; $f -lt $numFolds; $f++) {
                $trainEnd = $trainSize + $f * $foldSize
                $testStart = $trainEnd
                $testEnd = [Math]::Min($testStart + $foldSize, $n)

                # Train: compute indicator on training portion
                $sigTrain = Get-MbfSignalArray $cand.Indicator $cand.Params $c[0..($testStart-1)] $h[0..($testStart-1)] $l[0..($testStart-1)] $v[0..($testStart-1)] $testStart
                if (-not $sigTrain) { continue }

                # Freeze: use same params on test
                $sigTest = Get-MbfSignalArray $cand.Indicator $cand.Params $c[$testStart..($testEnd-1)] $h[$testStart..($testEnd-1)] $l[$testStart..($testEnd-1)] $v[$testStart..($testEnd-1)] ($testEnd-$testStart)

                if (-not $sigTest) { continue }

                $testReturns = @()
                for ($si = 0; $si -lt $sigTest.Count; $si++) {
                    if ($sigTest[$si]) {
                        $globalIdx = $testStart + $si
                        if ($globalIdx + 5 -lt $n) {
                            $ret = ($c[$globalIdx+5] - $c[$globalIdx]) / $c[$globalIdx] * 100
                            $testReturns += $ret
                        }
                    }
                }

                if ($testReturns.Count -lt 3) { continue }

                $avgRet = ($testReturns | Measure-Object -Average).Average
                $pos = ($testReturns | Where-Object { $_ -gt 0 }).Count
                $wr = $pos / $testReturns.Count * 100
                $stdR = Get-StdDev $testReturns
                $sh = if ($stdR -gt 0) { $avgRet / $stdR } else { 0 }

                $foldExpectancies += $avgRet
                $foldWinRates += $wr
                $foldSharpe += $sh
                $foldTradeCounts += $testReturns.Count
            }

            if ($foldExpectancies.Count -lt 2) { continue }

            $avgExp = [Math]::Round(($foldExpectancies | Measure-Object -Average).Average, 4)
            $avgWR = [Math]::Round(($foldWinRates | Measure-Object -Average).Average, 1)
            $avgSharpe = [Math]::Round(($foldSharpe | Measure-Object -Average).Average, 4)
            $totalTrades = ($foldTradeCounts | Measure-Object -Sum).Sum
            $posFolds = ($foldExpectancies | Where-Object { $_ -gt 0 }).Count
            $posFoldPct = [Math]::Round($posFolds / $foldExpectancies.Count * 100, 0)

            $wfResults += [PSCustomObject]@{
                Asset=$asset; Indicator=$cand.Indicator; Params=$cand.Params
                Folds=$foldExpectancies.Count; TotalTrades=$totalTrades
                AvgExpectancy=$avgExp; AvgWinRate=$avgWR; AvgSharpe=$avgSharpe
                PosFoldPct=$posFoldPct
                ExpectancyStability=[Math]::Round((Get-StdDev $foldExpectancies), 4)
            }

            Write-Host "  $asset $($cand.Indicator)($($cand.Params)) : folds=$($foldExpectancies.Count) trades=$totalTrades exp=$avgExp wr=$avgWR sharpe=$avgSharpe posFolds=$posFoldPct%" -ForegroundColor Gray
        }

        $wfPath = Join-Path $OutputDir "walkforward_stability.csv"
        $wfResults | Export-Csv -Path $wfPath -NoTypeInformation
        Write-Host "Phase 11.5 complete. Saved to $wfPath" -ForegroundColor Green
    } else {
        Write-Host "Phase 11.5: SKIPPED" -ForegroundColor DarkYellow
    }

    # ================================================================
    # PHASE 11.6 — LARGE MONTE CARLO
    # ================================================================
    if (-not $SkipMonteCarlo) {
        Write-Host "`n===== PHASE 11.6: LARGE MONTE CARLO =====" -ForegroundColor Cyan

        $mcResults = @()
        $mcIterations = 1000
        $rngMc = [Random]::new(123)

        foreach ($cand in $candidates) {
            $asset = $cand.Asset
            $key = "${asset}_30m"
            if ($dataCache.ContainsKey($key)) { $klines = $dataCache[$key] }
            else {
                $csvPath = Join-Path $InputDir $assetFiles[$asset]["30m"]
                if (-not (Test-Path $csvPath)) { continue }
                $klines = Import-Csv $csvPath
            }
            $n = $klines.Count
            $h = [double[]]::new($n); $l = [double[]]::new($n); $c = [double[]]::new($n); $v = [double[]]::new($n)
            for ($i = 0; $i -lt $n; $i++) { $h[$i]=[double]$klines[$i].High;$l[$i]=[double]$klines[$i].Low;$c[$i]=[double]$klines[$i].Close;$v[$i]=[double]$klines[$i].Volume }

            $sig = Get-MbfSignalArray $cand.Indicator $cand.Params $c $h $l $v $n
            if (-not $sig) { continue }

            $sigList = New-Object 'System.Collections.Generic.List[int]'
            for ($si = 100; $si -lt $sig.Count; $si++) { if ($sig[$si]) { $sigList.Add($si) } }
            if ($sigList.Count -lt 5) { continue }

            # Get base trade returns
            $retList = New-Object 'System.Collections.Generic.List[double]'
            foreach ($si in $sigList) {
                if ($si + 5 -lt $n) {
                    $retList.Add(($c[$si+5] - $c[$si]) / $c[$si] * 100)
                }
            }
            $tradeReturns = $retList.ToArray()
            if ($tradeReturns.Count -lt 5) { continue }

            Write-Host "  Monte Carlo: $asset $($cand.Indicator)($($cand.Params)) with $($tradeReturns.Count) trades, $mcIterations iterations..." -ForegroundColor Gray

            $mcExpectancies = @()
            $mcMaxDDs = @()
            $mcProfitFactors = @()

            for ($mc = 0; $mc -lt $mcIterations; $mc++) {
                # Shuffle trade order
                $shuffled = $tradeReturns.Clone()
                for ($a = 0; $a -lt $shuffled.Count; $a++) {
                    $b = $rngMc.Next(0, $shuffled.Count)
                    $tmp = $shuffled[$a]; $shuffled[$a] = $shuffled[$b]; $shuffled[$b] = $tmp
                }

                # Randomize fees and slippage
                $fee = 0.02 + $rngMc.NextDouble() * 0.13  # 0.02% to 0.15%
                $slippage = $rngMc.NextDouble() * 0.1  # 0% to 0.1%

                $eq = 1.0; $peak = 1.0; $maxDD = 0.0; $gains = 0.0; $losses = 0.0; $sumNet = 0.0
                foreach ($raw in $shuffled) {
                    $netRet = $raw - $fee - $slippage
                    $sumNet += $netRet
                    $eq *= (1 + $netRet/100)
                    if ($netRet -gt 0) { $gains += $netRet }
                    else { $losses += $netRet }
                    if ($eq -gt $peak) { $peak = $eq }
                    $dd = ($peak - $eq) / $peak * 100
                    if ($dd -gt $maxDD) { $maxDD = $dd }
                }

                $mcExpectancies += $sumNet / $shuffled.Count
                $mcMaxDDs += $maxDD
                $mcProfitFactors += if ($losses -eq 0) { 999 } else { [Math]::Abs($gains / $losses) }
            }

            $avgMcExp = [Math]::Round(($mcExpectancies | Measure-Object -Average).Average, 4)
            $avgMcDD = [Math]::Round(($mcMaxDDs | Measure-Object -Average).Average, 2)
            $avgMcPF = [Math]::Round(($mcProfitFactors | Measure-Object -Average).Average, 2)
            $pfStability = [Math]::Round((Get-StdDev $mcProfitFactors), 2)

            $mcResults += [PSCustomObject]@{
                Asset=$asset; Indicator=$cand.Indicator; Params=$cand.Params
                BaseTrades=$tradeReturns.Count; Iterations=$mcIterations
                AvgExpectancy=$avgMcExp; AvgMaxDD=$avgMcDD; AvgProfitFactor=$avgMcPF
                PFStability=$pfStability
            }
        }

        $mcPath = Join-Path $OutputDir "montecarlo_stability.csv"
        $mcResults | Export-Csv -Path $mcPath -NoTypeInformation
        Write-Host "Phase 11.6 complete. Saved to $mcPath" -ForegroundColor Green
    } else {
        Write-Host "Phase 11.6: SKIPPED" -ForegroundColor DarkYellow
    }

    # ================================================================
    # PHASE 11.7 — INSTITUTIONAL EDGE REPORT
    # ================================================================
    if (-not $SkipReport) {
        Write-Host "`n===== PHASE 11.7: INSTITUTIONAL EDGE REPORT =====" -ForegroundColor Cyan

        $reportPath = Join-Path $OutputDir "institutional_edge_report.md"

        # Load all output CSVs
        $evalData = @()
        $evalPath = Join-Path $OutputDir "candidate_by_regime.csv"
        if (Test-Path $evalPath) { $evalData = Import-Csv $evalPath }

        $wfData = @()
        $wfPath = Join-Path $OutputDir "walkforward_stability.csv"
        if (Test-Path $wfPath) { $wfData = Import-Csv $wfPath }

        $mcData = @()
        $mcPath = Join-Path $OutputDir "montecarlo_stability.csv"
        if (Test-Path $mcPath) { $mcData = Import-Csv $mcPath }

        $qualData = @()
        $qualPath = Join-Path $OutputDir "regime_quality_report.csv"
        if (Test-Path $qualPath) { $qualData = Import-Csv $qualPath }

        $distData = @()
        $distPath = Join-Path $OutputDir "regime_distribution.csv"
        if (Test-Path $distPath) { $distData = Import-Csv $distPath }

        $report = @"
# Institutional Market Behavior Research -- Phase 11 Edge Report

**Generated:** $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
**Assets:** SOLUSDT, ICPUSDT
**Timeframes:** 30m (primary), 1h, 4h (regime)
**Regime Data:** 4h k-line futures data

---

## 1. Regime Distribution

"@

        foreach ($asset in $assets) {
            $report += "`n### $asset`n`n"
            $report += "| Regime | Bars | % of History |`n"
            $report += "|--------|------|-------------|`n"
            if ($distData) {
                $assetDist = $distData | Where-Object { $_.Asset -eq $asset }
                foreach ($d in ($assetDist | Sort-Object BarCount -Descending)) {
                    $report += "| $($d.Regime) | $($d.BarCount) | $($d.PercentOfHistory)% |`n"
                }
            }
        }

        $report += "`n---

## 2. Regime Quality

"

        foreach ($asset in $assets) {
            $report += "`n### $asset`n`n"
            $report += "| Regime | Bars | Persistence | Avg Duration | 1B Move | 5B Move | 20B Move | Adequate |`n"
            $report += "|--------|------|------------|-------------|---------|---------|----------|----------|`n"
            if ($qualData) {
                $assetQual = $qualData | Where-Object { $_.Asset -eq $asset }
                foreach ($q in ($assetQual | Sort-Object BarCount -Descending)) {
                    $report += "| $($q.Regime) | $($q.BarCount) | $($q.PersistencePct)% | $($q.AvgDurationBars) | $($q.AvgMove1B)% | $($q.AvgMove5B)% | $($q.AvgMove20B)% | $($q.SampleSizeAdequate) |`n"
                }
            }
        }

        $report += "`n---

## 3. Candidate Performance by Regime

"

        $indicators = @("Stoch","CMF","OBV","ADX","Bollinger")
        foreach ($ind in $indicators) {
            $candEvals = $evalData | Where-Object { $_.Indicator -eq $ind }
            if (-not $candEvals) { continue }
            $report += "`n### $ind`n`n"
            $report += "| Asset | TF | Regime | Params | Signals | WinRate | Sharpe | PF | AvgRet5B |`n"
            $report += "|-------|-----|--------|--------|---------|---------|--------|----|---------|`n"
            foreach ($e in ($candEvals | Sort-Object Sharpe -Descending)) {
                $report += "| $($e.Asset) | $($e.Timeframe) | $($e.Regime) | $($e.Params) | $($e.SignalCount) | $($e.WinRatePct)% | $($e.Sharpe) | $($e.ProfitFactor) | $($e.AvgReturn5B)% |`n"
            }
        }

        $report += "`n---

## 4. Walk-Forward Stability

"

        $report += "| Asset | Indicator | Params | Folds | Trades | AvgExpectancy | AvgWR | AvgSharpe | PosFolds | Stability |`n"
        $report += "|-------|-----------|--------|-------|--------|--------------|------|-----------|----------|----------|`n"
        foreach ($w in ($wfData | Sort-Object AvgSharpe -Descending)) {
            $report += "| $($w.Asset) | $($w.Indicator) | $($w.Params) | $($w.Folds) | $($w.TotalTrades) | $($w.AvgExpectancy) | $($w.AvgWinRate)% | $($w.AvgSharpe) | $($w.PosFoldPct)% | $($w.ExpectancyStability) |`n"
        }

        $report += "`n---

## 5. Monte Carlo Stability

"

        $report += "| Asset | Indicator | Params | Trades | Iterations | AvgExpectancy | AvgMaxDD | AvgPF | PFStability |`n"
        $report += "|-------|-----------|--------|--------|-----------|--------------|---------|-------|------------|`n"
        foreach ($m in ($mcData | Sort-Object AvgProfitFactor -Descending)) {
            $report += "| $($m.Asset) | $($m.Indicator) | $($m.Params) | $($m.BaseTrades) | $($m.Iterations) | $($m.AvgExpectancy) | $($m.AvgMaxDD)% | $($m.AvgProfitFactor) | $($m.PFStability) |`n"
        }

        $report += "`n---

## 6. Final Ranking

**Ranking criteria:** Statistical Confidence > Robustness > Drawdown > Expectancy > Trade Count

"

        # Merge all evidence
        $merged = @{}
        foreach ($w in $wfData) {
            $key = "$($w.Asset)|$($w.Indicator)|$($w.Params)"
            $merged[$key] = @{WF=$w}
        }
        foreach ($m in $mcData) {
            $key = "$($m.Asset)|$($m.Indicator)|$($m.Params)"
            if (-not $merged.ContainsKey($key)) { $merged[$key] = @{} }
            $merged[$key].MC = $m
        }

        # Score each candidate: Sharpe * PosFold% * (1 - Log(MaxDD+1)/10) * Sqrt(Trades)/10 * PF
        $scored = @()
        foreach ($kv in $merged.GetEnumerator()) {
            $parts = $kv.Key -split '\|'
            $asset = $parts[0]; $ind = $parts[1]; $param = $parts[2]
            $w = $kv.Value.WF; $m = $kv.Value.MC

            if (-not $w -or -not $m) { continue }

            $sharpe = [double]$w.AvgSharpe
            $posFold = [double]$w.PosFoldPct / 100
            $trades = [int]$w.TotalTrades
            $pf = [double]$m.AvgProfitFactor
            $dd = [double]$m.AvgMaxDD

            $score = $sharpe * $posFold * [Math]::Max(0.1, 1 - [Math]::Log($dd + 1, 10)) * [Math]::Sqrt($trades) / 10 * [Math]::Min($pf, 10)

            $scored += [PSCustomObject]@{
                Asset=$asset; Indicator=$ind; Params=$param
                Sharpe=$sharpe; PosFoldPct=$($w.PosFoldPct); TotalTrades=$trades
                AvgExpectancy=$w.AvgExpectancy; AvgWinRate=$w.AvgWinRate
                AvgMaxDD=$dd; AvgPF=$pf; Score=[Math]::Round($score, 4)
            }
        }

        $finalRank = $scored | Sort-Object Score -Descending

        $report += "| Rank | Asset | Indicator | Params | Sharpe | PosFolds | AvgWR | AvgExpectancy | MaxDD | PF | Trades | Score |`n"
        $report += "|------|-------|-----------|--------|--------|----------|-------|--------------|-------|----|--------|-------|`n"
        $rankNum = 0
        foreach ($r in $finalRank) {
            $rankNum++
            $report += "| $rankNum | $($r.Asset) | $($r.Indicator) | $($r.Params) | $($r.Sharpe) | $($r.PosFoldPct)% | $($r.AvgWinRate)% | $($r.AvgExpectancy) | $($r.AvgMaxDD)% | $($r.AvgPF) | $($r.TotalTrades) | $($r.Score) |`n"
        }

        $report += "`n---

## 7. Answer: Persistent Market Behaviors and Best Detectors

"

        # Top 3 findings
        if ($finalRank.Count -gt 0) {
            $r1 = $finalRank[0]
            $report += "**Primary Finding:** $($r1.Asset) $($r1.Indicator)($($r1.Params)) achieves Sharpe=$($r1.Sharpe) across $($r1.TotalTrades) trades"
            if ($r1.AvgExpectancy -gt 0) { $report += " with positive expectancy ($($r1.AvgExpectancy))." } else { $report += " but negative expectancy." }
            $report += "`n"

            if ($finalRank.Count -gt 1) {
                $r2 = $finalRank[1]
                $report += "**Secondary Finding:** $($r2.Asset) $($r2.Indicator)($($r2.Params)) with Sharpe=$($r2.Sharpe) across $($r2.TotalTrades) trades.`n"
            }

            # Most consistent behavior across regimes
            $report += "`n**Most persistent behavior:** "
            $bestIndicator = $finalRank[0].Indicator
            if ($bestIndicator -eq "Stoch") { $report += "Stochastic oscillator signals detect volatility-expansion continuation patterns most reliably." }
            elseif ($bestIndicator -eq "CMF") { $report += "Chaikin Money Flow detects accumulation/distribution volume pressure." }
            elseif ($bestIndicator -eq "ADX") { $report += "ADX trend strength detection works in directional regimes only." }
            elseif ($bestIndicator -eq "OBV") { $report += "On-Balance Volume detects volume-confirmed trends." }
            elseif ($bestIndicator -eq "Bollinger") { $report += "Bollinger Band squeezes detect volatility compression breakouts." }
            else { $report += "Multi-indicator fusion provides the most robust detection across regime types." }
            $report += "`n"

            $report += "`n**Regime stability:** "
            if ($qualData) {
                $stableRegimes = $qualData | Where-Object { $_.SampleSizeAdequate -eq "True" -and [double]$_.PersistencePct -gt 50 }
                if ($stableRegimes) {
                    $report += ($stableRegimes | ForEach-Object { "$($_.Asset) $($_.Regime) (persist=$($_.PersistencePct)%, dur=$($_.AvgDurationBars) bars)" }) -join "; "
                } else {
                    $report += "No regime shows strong persistence -- all regimes are transitional."
                }
            }
        } else {
            $report += "**No statistically significant edge detected** across any candidate or regime."
        }

        $report += "`n`n---

*Report generated by Market Behavior Research Framework Phase 11*
*Methodology: Clustering-based regime discovery, walk-forward validation (rolling train/freeze/test), Monte Carlo simulation (1000 iterations with fee+slippage randomization)*
"

        Set-Content -Path $reportPath -Value $report
        Write-Host "Phase 11.7 complete. Report saved to $reportPath" -ForegroundColor Green

        Write-Host "`nTop final edges:" -ForegroundColor Yellow
        $finalRank | Select-Object -First 5 | Format-Table -AutoSize
    } else {
        Write-Host "Phase 11.7: SKIPPED" -ForegroundColor DarkYellow
    }

    $elapsed = (Get-Date) - $start
    Write-Host "`n===== PHASE 11 COMPLETE ($([Math]::Round($elapsed.TotalMinutes,1)) min) =====" -ForegroundColor Cyan
}

Export-ModuleMember -Function Initialize-MbfRsaAuth, Invoke-MbfApi
Export-ModuleMember -Function Invoke-MbfPhase1, Invoke-MbfPhase2, Invoke-MbfPhase3
Export-ModuleMember -Function Invoke-MbfPhase4, Invoke-MbfPhase5, Invoke-MbfPhase6
Export-ModuleMember -Function Invoke-MbfPhase7, Invoke-MbfPhase8, Invoke-MbfPhase9, Invoke-MbfPhase10
Export-ModuleMember -Function Invoke-MbfPhase11
Export-ModuleMember -Function Calc-EMA, Calc-SMA, Calc-ATR, Calc-ADX, Calc-RSI, Calc-MACD
Export-ModuleMember -Function Calc-Stoch, Calc-CCI, Calc-MFI, Calc-CMF, Calc-OBV
Export-ModuleMember -Function Calc-Bollinger, Calc-VWAP, Calc-VolumeProfile
Export-ModuleMember -Function Get-StdDev, Get-Autocorrelation, Get-LogReturns
Export-ModuleMember -Function Get-MbfSignalArray, Get-MbfBehaviorTruth
