# EdgeDiscovery.psm1 — Asset-Specific Edge Discovery Framework
# Discovers how each asset behaves, then derives indicator settings from that behavior.
# Does NOT optimize for maximum historical profit.

# ===== INTERNAL STATE =====
$script:Indicators = @{}
$script:ApiBase = "https://api.bybit.com"

# ============================================================
#  RSA AUTH (reused from paper_trader.ps1 — proven working)
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
function Initialize-RsaAuth {
    $keyFile = if ($env:BYBIT_PRIVATE_KEY_PATH) { $env:BYBIT_PRIVATE_KEY_PATH } else { Join-Path (Join-Path $PSScriptRoot "..") "bybit_private.pem" }
    if (-not (Test-Path $keyFile)) { throw "RSA key not found at $keyFile" }
    $pem = Get-Content -Raw $keyFile; $b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
    $der = [System.Convert]::FromBase64String($b64); $off = 0
    if ($der[$off] -ne 0x30) { throw "Not SEQUENCE" }; $off++
    $seqLen = Read-DerLength -data $der -offset ([ref]$off)
    $p = New-Object System.Security.Cryptography.RSAParameters
    $version = Read-DerInteger -data $der -offset ([ref]$off)
    $p.Modulus = Read-DerInteger -data $der -offset ([ref]$off); $p.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
    $p.D = Read-DerInteger -data $der -offset ([ref]$off); $p.P = Read-DerInteger -data $der -offset ([ref]$off)
    $p.Q = Read-DerInteger -data $der -offset ([ref]$off); $p.DP = Read-DerInteger -data $der -offset ([ref]$off)
    $p.DQ = Read-DerInteger -data $der -offset ([ref]$off); $p.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
    $script:Rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $script:Rsa.ImportParameters($p)
}

# ============================================================
#  API
# ============================================================
function Call-Bybit {
    param($method, $endpoint, $query, $body)
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $apiKey = $env:BYBIT_API_KEY
    if (-not $apiKey) { throw "BYBIT_API_KEY env var not set" }
    $recv = "5000"; $tsStr = "$ts$apiKey$recv"
    $payload = if ($method -eq "GET") { "$tsStr$query" } else { "$tsStr$body" }
    $dataBytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $sha = [Security.Cryptography.SHA256]::Create()
    $sigBytes = $script:Rsa.SignData($dataBytes, $sha); $sig = [Convert]::ToBase64String($sigBytes)
    $hd = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sig;"X-BAPI-RECV-WINDOW"=$recv;"X-BAPI-SIGN-TYPE"="2"}
    try {
        if ($method -eq "GET") { $r = Invoke-WebRequest -Uri "$script:ApiBase$endpoint`?$query" -Headers $hd -UseBasicParsing -TimeoutSec 30 }
        else { $r = Invoke-WebRequest -Uri "$script:ApiBase$endpoint" -Method POST -Headers $hd -Body $body -ContentType "application/json" -UseBasicParsing -TimeoutSec 30 }
        return ($r.Content | ConvertFrom-Json)
    } catch { Write-Warning "API $endpoint : $_"; return $null }
}

function Get-Klines {
    param($symbol, $interval, $limit, [int]$retry = 3)
    for ($r = 0; $r -lt $retry; $r++) {
        $q = "category=spot&symbol=$symbol&interval=$interval&limit=$limit"
        $data = Call-Bybit "GET" "/v5/market/kline" $q ""
        if ($data -and $data.retCode -eq 0 -and $data.result -and $data.result.list) {
            $k = $data.result.list; [Array]::Reverse($k); return $k
        }
        if ($r -lt $retry-1) { Start-Sleep -Seconds 3 }
    }
    return $null
}

# ============================================================
#  INDICATORS (reused from paper_trader.ps1)
# ============================================================
function Calc-EMA { param($p, $per)
    $e = [double[]]::new($p.Count); $e[0] = $p[0]; $m = 2/($per+1)
    for ($i = 1; $i -lt $p.Count; $i++) { $e[$i] = $p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}
function Calc-ATR { param($h, $l, $c, $per)
    $tr = [double[]]::new($c.Count)
    for ($i = 1; $i -lt $c.Count; $i++) { $tr[$i] = [Math]::Max($h[$i]-$l[$i], [Math]::Max([Math]::Abs($h[$i]-$c[$i-1]), [Math]::Abs($l[$i]-$c[$i-1]))) }
    if ($c.Count -le $per) { return @($tr) }
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
function Calc-SMI { param($h,$l,$c,$prdK,$prdD)
    $n=$c.Count;$highest=[double[]]::new($n);$lowest=[double[]]::new($n);$hl=[double[]]::new($n)
    for($i=0;$i-lt$n;$i++){$hh=-1e10;$ll=1e10
        for($j=[Math]::Max(0,$i-$prdK+1);$j-le$i;$j++){if($c[$j]-gt$hh){$hh=$c[$j]};if($c[$j]-lt$ll){$ll=$c[$j]}}
        $highest[$i]=$hh;$lowest[$i]=$ll;$hl[$i]=$highest[$i]-$lowest[$i]}
    $cL=[double[]]::new($n);for($i=0;$i-lt$n;$i++){$cL[$i]=$c[$i]-($highest[$i]+$lowest[$i])/2}
    $s1=Calc-EMA $cL $prdD;$s2=Calc-EMA $s1 $prdD;$s3=Calc-EMA $hl $prdD;$s4=Calc-EMA $s3 $prdD
    $smi=[double[]]::new($n);for($i=0;$i-lt$n;$i++){$smi[$i]=if($s4[$i]-eq0){0}else{$s2[$i]/($s4[$i]/2)*100}};return $smi}
function Calc-VolumeProfile { param($h,$l,$v,$lookback)
    $n=$h.Count;$poc=[double[]]::new($n);$vaHigh=[double[]]::new($n);$vaLow=[double[]]::new($n)
    for ($i=$lookback;$i-lt$n;$i++) {
        $minP=1e10;$maxP=-1e10
        for($j=$i-$lookback+1;$j-le$i;$j++){if($l[$j]-lt$minP){$minP=$l[$j]};if($h[$j]-gt$maxP){$maxP=$h[$j]}}
        $bins=50;$binSize=($maxP-$minP)/$bins;if($binSize-le0){continue}
        $vol=@{};for($b=0;$b-lt$bins;$b++){$vol[$b]=0}
        for($j=$i-$lookback+1;$j-le$i;$j++){$bin=[Math]::Floor(($h[$j]+$l[$j])/2/$binSize);if($bin-ge$bins){$bin=$bins-1};$vol[$bin]+=$v[$j]}
        $maxVol=0;$pocBin=0;for($b=0;$b-lt$bins;$b++){if($vol[$b]-gt$maxVol){$maxVol=$vol[$b];$pocBin=$b}}
        $totalVol=($vol.Values|Measure-Object-Sum).Sum;$cumVol=0;$vLow=$vHigh=0;$foundLow=$false
        for($b=0;$b-lt$bins;$b++){$cumVol+=$vol[$b];if(-not$foundLow-and$cumVol-ge$totalVol*0.3){$vLow=$minP+$b*$binSize;$foundLow=$true}
            if($cumVol-ge$totalVol*0.7){$vHigh=$minP+$b*$binSize;break}}
        $poc[$i]=$minP+$pocBin*$binSize;$vaLow[$i]=$vLow;$vaHigh[$i]=$vHigh}
    return @{poc=$poc;vaHigh=$vaHigh;vaLow=$vaLow} }

# ============================================================
#  HELPER
# ============================================================
function Get-StdDev { param($arr)
    if ($arr.Count -lt 2) { return 0 }
    $m = ($arr | Measure-Object -Average).Average
    $sum = 0.0; foreach ($v in $arr) { $d = $v - $m; $sum += $d * $d }
    return [Math]::Sqrt($sum / ($arr.Count - 1))
}
function Normalize-Array { param($arr)
    $m = ($arr | Measure-Object -Average).Average; $s = Get-StdDev $arr
    if ($s -eq 0) { return @($arr | % { 0.0 }) }
    return @($arr | % { [double]($_ - $m) / $s })
}

# ============================================================
#  STEP 1: MARKET CHARACTERIZATION
# ============================================================
function Get-AssetCharacteristics {
    param($symbol, $tfs = @("240"))
    $results = @()
    foreach ($tf in $tfs) {
        $klines = Get-Klines $symbol $tf 1000
        if (-not $klines -or $klines.Count -lt 200) { continue }
        $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$v=$klines|%{[double]$_[5]}
        $n=$c.Count
        $logRets=@();for($i=1;$i-lt$n;$i++){$logRets+=[Math]::Log($c[$i]/$c[$i-1])}

        $adxArr,$duArr,$ddArr = Calc-ADX $h $l $c 14
        if (-not $adxArr -or $adxArr.Count -lt 250) { continue }
        $lookback = [Math]::Min(200, $adxArr.Count - 50)
        $start = $adxArr.Count - $lookback

        $adxSlice = $adxArr[$start..($adxArr.Count-1)] | Where-Object { $_ -gt 0 }
        $avgAdx = if ($adxSlice.Count -gt 0) { ($adxSlice | Measure-Object -Average).Average } else { 0 }
        $pctAbove25 = if ($adxSlice.Count -gt 0) { @($adxSlice | Where-Object { $_ -gt 25 }).Count / $adxSlice.Count * 100 } else { 0 }

        $trendLen=@();$curDir=0;$curLen=0
        for($i=$start;$i-lt$adxArr.Count;$i++){$dir=0
            if($duArr[$i]-gt$ddArr[$i]){$dir=1}elseif($ddArr[$i]-gt$duArr[$i]){$dir=-1}
            if($dir-eq$curDir-and$dir-ne0){$curLen++}else{if($curLen-gt0-and$curDir-ne0){$trendLen+=$curLen};$curLen=1;$curDir=$dir}}
        if($curLen-gt0){$trendLen+=$curLen}
        $avgTrendLen=if($trendLen.Count-gt0){($trendLen|Measure-Object -Average).Average}else{0}

        $tsArr=@();for($i=$start;$i-lt$adxArr.Count;$i++){$tsArr+= [Math]::Abs($duArr[$i]-$ddArr[$i])}
        $avgTrendStrength=if($tsArr.Count-gt0){($tsArr|Measure-Object -Average).Average}else{0}

        $atr=Calc-ATR $h $l $c 14
        if ($atr.Count -gt 100) {
            $atrRets=@();for($i=100;$i-lt$atr.Count;$i++){$atrRets+= [Math]::Log($atr[$i]/$atr[$i-1])}
            $vClust=if($atrRets.Count-gt20){Get-Autocorrelation $atrRets 1}else{0}
        } else { $vClust = 0 }

        $retAuto=Get-Autocorrelation $logRets 1

        $ma=Calc-EMA $c 20
        $sd=[double[]]::new($n);for($i=20;$i-lt$n;$i++){$sq=0.0;for($j=$i-19;$j-le$i;$j++){$sq+=($c[$j]-$ma[$j])*($c[$j]-$ma[$j])};$sd[$i]=[Math]::Sqrt($sq/20)}
        $bbTouch=0;$bbTotal=0
        for($i=50;$i-lt$n;$i++){if($sd[$i]-eq0){continue}$bbTotal++
            if($c[$i]-ge$ma[$i]+2*$sd[$i]-or$c[$i]-le$ma[$i]-2*$sd[$i]){$bbTouch++}}
        $meanRevPct=if($bbTotal-gt0){$bbTouch/$bbTotal*100}else{0}

        $atrVal = $atr[$n-1]
        $bFreq=0;$bCont=0;$bFail=0;$bTotal=0
        for($i=50;$i-lt$n-5;$i++){$rng=$h[$i]-$l[$i]
            if($rng-gt$atr[$i]*1.5){$bTotal++
                $nDir=[Math]::Sign($c[$i+3]-$c[$i]);$bDir=[Math]::Sign($c[$i]-$c[$i-3])
                if($nDir-eq$bDir-and$bDir-ne0){$bCont++}
                elseif($nDir-ne0-and$bDir-ne0){$bFail++}}
        }
        $breakFreq=if($bTotal-gt0){$bTotal/($n-50)*100}else{0}
        $breakContPct=if($bTotal-gt0){$bCont/$bTotal*100}else{0}
        $breakFailPct=if($bTotal-gt0){$bFail/$bTotal*100}else{0}
        $hLast=$h[$n-1];$lLast=$l[$n-1];$cLast=$c[$n-1]
        $rangePct = if ($cLast -gt 0) { ($hLast - $lLast) / $cLast * 100 } else { 0 }

        $results += [PSCustomObject]@{
            Symbol=$symbol;TF=$tf;Samples=$n
            AvgADX=[Math]::Round($avgAdx,2)
            PctAbove25=[Math]::Round($pctAbove25,1)
            AvgTrendLen=[Math]::Round($avgTrendLen,1)
            AvgTrendStrength=[Math]::Round($avgTrendStrength,2)
            VolClustering=[Math]::Round($vClust,4)
            ReturnAutocorr=[Math]::Round($retAuto,4)
            MeanRevBBPct=[Math]::Round($meanRevPct,1)
            BreakoutFreq=[Math]::Round($breakFreq,2)
            BreakoutContPct=[Math]::Round($breakContPct,1)
            BreakoutFailPct=[Math]::Round($breakFailPct,1)
            DailyRangePct=[Math]::Round($rangePct,2)
            AvgATR=[Math]::Round($atrVal,6)
        }
    }
    return $results
}

function Get-Autocorrelation { param($data, $lag)
    $n = $data.Count; if ($n -le $lag + 2) { return 0 }
    $x = $data[0..($n-$lag-1)]; $y = $data[$lag..($n-1)]
    $mx = ($x | Measure-Object -Average).Average; $my = ($y | Measure-Object -Average).Average
    $num=0.0;$dx=0.0;$dy=0.0
    for ($i=0;$i-lt$x.Count;$i++){$xd=$x[$i]-$mx;$yd=$y[$i]-$my;$num+=$xd*$yd;$dx+=$xd*$xd;$dy+=$yd*$yd}
    $den=[Math]::Sqrt($dx*$dy);if($den-eq0){return 0};return ($num/$den)
}

# ============================================================
#  STEP 2: INDICATOR RESPONSE SURFACE
# ============================================================
function Get-IndicatorResponseSurface {
    param($symbol, $klines, $lookahead = 5)
    $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$v=$klines|%{[double]$_[5]};$n=$c.Count
    $results = @()
    Write-Host "  Evaluating RSI surface..." -NoNewline
    $results += Get-RSISurface $c $h $l $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating ADX surface..." -NoNewline
    $results += Get-ADXSurface $c $h $l $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating EMA cross surface..." -NoNewline
    $results += Get-EMACrossSurface $c $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating Stochastic surface..." -NoNewline
    $results += Get-StochSurface $c $h $l $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating CCI surface..." -NoNewline
    $results += Get-CCISurface $c $h $l $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating CMF surface..." -NoNewline
    $results += Get-CMFSurface $c $h $l $v $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating OBV surface..." -NoNewline
    $results += Get-OBVSurface $c $v $lookahead; Write-Host " $($results.Count) configs"
    Write-Host "  Evaluating SMI surface..." -NoNewline
    $results += Get-SMISurface $c $h $l $lookahead; Write-Host " $($results.Count) configs"
    return $results
}

function Measure-SignalQuality {
    param($signals, $c, $lookahead)
    $sigIdx=@();for($i=0;$i-lt$signals.Count;$i++){if($signals[$i]){$sigIdx+=$i}}
    if ($sigIdx.Count -lt 5) { return $null }
    $fwdRets=@();$advEx=@();$daysPerBar = 1.0
    foreach ($idx in $sigIdx) {
        if ($idx + $lookahead -ge $c.Count) { continue }
        $fwd = ($c[$idx+$lookahead] - $c[$idx]) / $c[$idx] * 100
        $fwdRets += $fwd
        if ($fwd -ge 0) { $adverse = 0.0
            for ($j=1;$j -lt $lookahead;$j++) { $move=($c[$idx+$j]-$c[$idx])/$c[$idx]*100; if ($move -lt $adverse) { $adverse = $move } }
        } else { $adverse = 0.0
            for ($j=1;$j -lt $lookahead;$j++) { $move=($c[$idx+$j]-$c[$idx])/$c[$idx]*100; if ($move -gt $adverse) { $adverse = $move } }
        }
        $advEx += [Math]::Abs($adverse)
    }
    if ($fwdRets.Count -lt 3) { return $null }
    $avgFwd = ($fwdRets | Measure-Object -Average).Average
    $stdFwd = Get-StdDev $fwdRets
    $avgAdv = ($advEx | Measure-Object -Average).Average
    $stability = if ($stdFwd -gt 0) { $avgFwd / $stdFwd } else { 0 }
    $signalFreq = $sigIdx.Count / $c.Count * 100
    return @{ AvgMove=$avgFwd; AvgAdverse=$avgAdv; Stability=$stability; SignalFreq=$signalFreq; SignalCount=$sigIdx.Count }
}

function Get-RSISurface { param($c, $h, $l, $la)
    $res=@();$lengths=@(5,9,14,21,30,50);$obLevels=@(70,75,80,85,90);$osLevels=@(10,15,20,25,30)
    foreach ($len in $lengths) { $rsi=Calc-RSI $c $len
        foreach ($ob in $obLevels) { foreach ($os in $osLevels) { if ($ob -le $os+20) { continue }
                $sig=@();for($i=$len;$i-lt$c.Count;$i++){$sig+=$rsi[$i]-gt$ob-or$rsi[$i]-lt$os}
                $q=Measure-SignalQuality $sig $c $la
                if($q){$res+=[PSCustomObject]@{Indicator="RSI";Params="len=$len,ob=$ob,os=$os";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}}
    return $res
}

function Get-ADXSurface { param($c, $h, $l, $la)
    $res=@();$lengths=@(5,7,10,14,21,30,50);$thresholds=@(15,20,25,30,40,50)
    foreach ($len in $lengths) { $adx,$du,$dd = Calc-ADX $h $l $c $len
        foreach ($thresh in $thresholds) {
            $sig=@();for($i=$len;$i-lt$c.Count;$i++){$sig+=$adx[$i]-gt$thresh}
            $q=Measure-SignalQuality $sig $c $la
            if($q){$res+=[PSCustomObject]@{Indicator="ADX";Params="len=$len,thresh=$thresh";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}
    return $res
}

function Get-EMACrossSurface { param($c, $la)
    $res=@();$fasts=@(3,5,8,13,21,34);$slows=@(10,21,34,55,89,144)
    foreach ($f in $fasts) { foreach ($s in $slows) { if ($f -ge $s) { continue }
            $ef=Calc-EMA $c $f;$es=Calc-EMA $c $s
            $sig=@();for($i=$s;$i-lt$c.Count;$i++){$sig+=$ef[$i]-gt$es[$i]-and$ef[$i-1]-le$es[$i-1]}
            $q=Measure-SignalQuality $sig $c $la
            if($q){$res+=[PSCustomObject]@{Indicator="EMACross";Params="fast=$f,slow=$s";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}
    return $res
}

function Get-StochSurface { param($c, $h, $l, $la)
    $res=@();$kList=@(5,9,14,21);$dList=@(3,5,9);$obList=@(80,85,90);$osList=@(10,15,20)
    foreach ($k in $kList) { foreach ($d in $dList) { $st=Calc-Stoch $h $l $c $k $d
            foreach ($ob in $obList) { foreach ($os in $osList) { if ($ob -le $os+20) { continue }
                $sig=@();for($i=$k+$d;$i-lt$c.Count;$i++){$sig+=$st[$i]-gt$ob-or$st[$i]-lt$os}
                $q=Measure-SignalQuality $sig $c $la
                if($q){$res+=[PSCustomObject]@{Indicator="Stoch";Params="k=$k,d=$d,ob=$ob,os=$os";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}}}
    return $res
}

function Get-CCISurface { param($c, $h, $l, $la)
    $res=@();$lengths=@(5,10,14,20,30,50);$obList=@(100,150,200);$osList=@(-200,-150,-100)
    foreach ($len in $lengths) { $cci=Calc-CCI $h $l $c $len
        foreach ($ob in $obList) { foreach ($os in $osList) { if ($ob -ge -$os) { continue }
                $sig=@();for($i=$len;$i-lt$c.Count;$i++){$sig+=$cci[$i]-gt$ob-or$cci[$i]-lt$os}
                $q=Measure-SignalQuality $sig $c $la
                if($q){$res+=[PSCustomObject]@{Indicator="CCI";Params="len=$len,ob=$ob,os=$os";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}}
    return $res
}

function Get-CMFSurface { param($c, $h, $l, $v, $la)
    $res=@();$lengths=@(10,14,21,30,50);$thresh=@(-0.1,-0.05,0,0.05,0.1)
    foreach ($len in $lengths) { $cmf=Calc-CMF $h $l $c $v $len
        foreach ($t in $thresh) {
            $sig=@();for($i=$len;$i-lt$c.Count;$i++){$sig+=$cmf[$i]-gt$t}
            $q=Measure-SignalQuality $sig $c $la
            if($q){$res+=[PSCustomObject]@{Indicator="CMF";Params="len=$len,thresh=$t";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}
    return $res
}

function Get-OBVSurface { param($c, $v, $la)
    $res=@();$mas=@(10,20,30,50,100)
    $obv=Calc-OBV $c $v
    foreach ($maLen in $mas) { $obvMa=Calc-EMA $obv $maLen
        $sig=@();for($i=$maLen;$i-lt$c.Count;$i++){$sig+=$obv[$i]-gt$obvMa[$i]}
        $q=Measure-SignalQuality $sig $c $la
        if($q){$res+=[PSCustomObject]@{Indicator="OBV";Params="ma=$maLen";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }
    return $res
}

function Get-SMISurface { param($c, $h, $l, $la)
    $res=@();$kList=@(5,10,14);$dList=@(3,5,9);$obList=@(40,50,60);$osList=@(-60,-50,-40)
    foreach ($k in $kList) { foreach ($d in $dList) { $smi=Calc-SMI $h $l $c $k $d
            foreach ($ob in $obList) { foreach ($os in $osList) { if ($ob -ge -$os) { continue }
                $sig=@();for($i=$k+$d;$i-lt$c.Count;$i++){$sig+=$smi[$i]-gt$ob-or$smi[$i]-lt$os}
                $q=Measure-SignalQuality $sig $c $la
                if($q){$res+=[PSCustomObject]@{Indicator="SMI";Params="k=$k,d=$d,ob=$ob,os=$os";SignalFreq=$q.SignalFreq;AvgMove=$q.AvgMove;AvgAdverse=$q.AvgAdverse;Stability=$q.Stability;SignalCount=$q.SignalCount}}
    }}}}
    return $res
}

# ============================================================
#  STEP 3: REGIME DETECTION
# ============================================================
function Get-RegimeLabels {
    param($klines)
    if (-not $klines -or $klines.Count -lt 100) { return $null }
    $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$n=$c.Count
    $adx,$du,$dd = Calc-ADX $h $l $c 14
    $atr = Calc-ATR $h $l $c 14
    $ma = Calc-EMA $c 50
    $ma20 = Calc-EMA $c 20

    # Normalize ATR as % of price
    $atrPct = @(for($i=0;$i-lt$n;$i++){if($c[$i]-gt0){$atr[$i]/$c[$i]*100}else{0}})
    $atrMean = ($atrPct[100..($n-1)] | Measure-Object -Average).Average
    $atrSlice = $atrPct[100..($n-1)]; $atrStd = Get-StdDev $atrSlice

    $regimes = @()
    for ($i=100; $i -lt $n; $i++) {
        if ($adx[$i] -gt 25) { $trending = $true } else { $trending = $false }
        $bandWidth = [Math]::Abs(($ma20[$i] - $ma[$i]) / $ma[$i] * 100)
        $ranging = (-not $trending) -and $bandWidth -lt 2.0
        $volRegime = if ($atrPct[$i] -gt $atrMean + $atrStd) { "HIGH_VOL" } else { "LOW_VOL" }

        if ($trending -and $volRegime -eq "HIGH_VOL") { $label = "TRENDING_HIGH_VOL" }
        elseif ($trending) { $label = "TRENDING" }
        elseif ($ranging -and $volRegime -eq "HIGH_VOL") { $label = "RANGING_HIGH_VOL" }
        elseif ($ranging) { $label = "RANGING" }
        elseif ($volRegime -eq "HIGH_VOL") { $label = "CHOPPY_HIGH_VOL" }
        else { $label = "CHOPPY_LOW_VOL" }

        $regimes += [PSCustomObject]@{
            Index=$i;Regime=$label;ADX=$adx[$i];ATR=$atrPct[$i];Close=$c[$i]
            AboveMA50=if($c[$i]-gt$ma[$i]){$true}else{$false}
        }
    }
    return $regimes
}

function Get-RegimeIndicatorMap {
    param($symbol, $klines, $indicatorResults)
    $regimes = Get-RegimeLabels $klines
    if (-not $regimes) { return @() }
    $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$n=$c.Count
    $results = @()

    # For each unique indicator config, evaluate per-regime performance
    $configs = $indicatorResults | Group-Object Indicator,Params | ForEach-Object { $_.Group[0] }
    foreach ($cfg in $configs) {
        $sig = Get-SignalArray $cfg.Indicator $cfg.Params $klines
        if (-not $sig -or $sig.Count -lt 10) { continue }
        $regimeScores = @{}
        foreach ($r in $regimes) {
            $idx = $r.Index; if ($idx -ge $sig.Count) { continue }
            $key = $r.Regime
            if (-not $regimeScores.ContainsKey($key)) { $regimeScores[$key] = @{Sigs=@();Count=0} }
            if ($sig[$idx]) { $regimeScores[$key].Count++
                for ($j=1; $j -le 5; $j++) { if ($idx+$j -lt $c.Count) { $regimeScores[$key].Sigs += ($c[$idx+$j]-$c[$idx])/$c[$idx]*100 } }
            }
        }
        foreach ($kv in $regimeScores.GetEnumerator()) {
            $d = $kv.Value
            if ($d.Count -lt 2) { continue }
            $avg = if ($d.Sigs.Count -gt 0) { ($d.Sigs | Measure-Object -Average).Average } else { 0 }
            $results += [PSCustomObject]@{
                Symbol=$symbol;Indicator=$cfg.Indicator;Params=$cfg.Params
                Regime=$kv.Key;SignalCount=$d.Count;AvgReturn=[Math]::Round($avg,4)
            }
        }
    }
    return $results
}

function Get-SignalArray {
    param($indicator, $params, $klines)
    $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$v=$klines|%{[double]$_[5]};$n=$c.Count
    $parts = $params -split ','
    $map = @{}; foreach ($p in $parts) { $kv = $p -split '='; if ($kv.Count -eq 2) { $map[$kv[0].Trim()] = $kv[1].Trim() } }

    switch ($indicator) {
        "RSI" {
            $len = [int]$map['len']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $rsi = Calc-RSI $c $len
            $sig=@();for($i=$len;$i-lt$n;$i++){$sig+=$rsi[$i]-gt$ob-or$rsi[$i]-lt$os}; return $sig
        }
        "ADX" {
            $len = [int]$map['len']; $thresh = [int]$map['thresh']
            $adx,$du,$dd = Calc-ADX $h $l $c $len
            $sig=@();for($i=$len;$i-lt$n;$i++){$sig+=$adx[$i]-gt$thresh}; return $sig
        }
        "EMACross" {
            $f = [int]$map['fast']; $s = [int]$map['slow']
            $ef=Calc-EMA $c $f;$es=Calc-EMA $c $s
            $sig=@();for($i=$s;$i-lt$n;$i++){$sig+=$ef[$i]-gt$es[$i]-and$ef[$i-1]-le$es[$i-1]}; return $sig
        }
        "Stoch" {
            $k = [int]$map['k']; $d = [int]$map['d']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $st=Calc-Stoch $h $l $c $k $d
            $sig=@();for($i=$k+$d;$i-lt$n;$i++){$sig+=$st[$i]-gt$ob-or$st[$i]-lt$os}; return $sig
        }
        "CCI" {
            $len = [int]$map['len']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $cci=Calc-CCI $h $l $c $len
            $sig=@();for($i=$len;$i-lt$n;$i++){$sig+=$cci[$i]-gt$ob-or$cci[$i]-lt$os}; return $sig
        }
        "CMF" {
            $len = [int]$map['len']; $thresh = [double]$map['thresh']
            $cmf=Calc-CMF $h $l $c $v $len
            $sig=@();for($i=$len;$i-lt$n;$i++){$sig+=$cmf[$i]-gt$thresh}; return $sig
        }
        "OBV" {
            $maLen = [int]$map['ma']
            $obv=Calc-OBV $c $v;$obvMa=Calc-EMA $obv $maLen
            $sig=@();for($i=$maLen;$i-lt$n;$i++){$sig+=$obv[$i]-gt$obvMa[$i]}; return $sig
        }
        "SMI" {
            $k = [int]$map['k']; $d = [int]$map['d']; $ob = [int]$map['ob']; $os = [int]$map['os']
            $smi=Calc-SMI $h $l $c $k $d
            $sig=@();for($i=$k+$d;$i-lt$n;$i++){$sig+=$smi[$i]-gt$ob-or$smi[$i]-lt$os}; return $sig
        }
    }
    return $null
}

# ============================================================
#  STEP 4: FREQUENCY FILTERING
# ============================================================
function Get-FrequencyFilteredConfigs {
    param($indicatorResults, $barsPerDay)
    $targetMin = 1.5; $targetMax = 30.0
    $filtered = $indicatorResults | Where-Object {
        $dailyFreq = $_.SignalFreq * $barsPerDay / 100.0
        $dailyFreq -ge $targetMin -and $dailyFreq -le $targetMax
    } | ForEach-Object {
        $dailyFreq = $_.SignalFreq * $barsPerDay / 100.0
        $_ | Select-Object *, @{N='DailyFreq';E={[Math]::Round($dailyFreq,2)}}
    }
    return $filtered
}

# ============================================================
#  STEP 5: ROBUSTNESS RANKING
# ============================================================
function Get-RobustConfigRankings {
    param(
        $filteredConfigs,
        $klines,
        $regimeMap,
        [int]$maxConfigs = 100
    )
    $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$v=$klines|%{[double]$_[5]};$n=$c.Count
    $ranked = @()

    # Sort by composite score already (Stability * SignalFreq)
    $top = $filteredConfigs | Sort-Object { [Math]::Abs($_.AvgMove) * $_.Stability } -Descending | Select-Object -First $maxConfigs

    foreach ($cfg in $top) {
        $sig = Get-SignalArray $cfg.Indicator $cfg.Params $klines
        if (-not $sig) { continue }

        # Walk-forward stability score
        $wfScores = @()
        $windowSize = [Math]::Floor($n / 5)
        for ($w=0; $w -lt $n - $windowSize; $w += $windowSize) {
            $end = [Math]::Min($w + $windowSize, $n)
            $inSample = $sig[$w..($end-1)] | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
            $inSampleFreq = if ($end - $w -gt 0) { $inSample / ($end - $w) * 100 } else { 0 }
            $wfScores += $inSampleFreq
        }
        $wfStability = if ($wfScores.Count -gt 1) {
            $m = ($wfScores | Measure-Object -Average).Average
            $s = Get-StdDev $wfScores
            if ($m -gt 0) { 1.0 - [Math]::Min(1.0, $s / $m) } else { 0 }
        } else { 0 }

        # Monte Carlo stability: resample signal positions to check consistency
        $mcScores = @()
        $sigPositions = @(for($i=0;$i-lt$sig.Count;$i++){if($sig[$i]){$i}})
        if ($sigPositions.Count -gt 10) {
            for ($m=0; $m -lt 100; $m++) {
                $sample = @()
                for ($s=0; $s -lt $sigPositions.Count; $s++) { $sample += $c[$sigPositions[$s]] }
                $sampleAvg = ($sample | Measure-Object -Average).Average
                $mcScores += $sampleAvg
            }
            $mcMean = ($mcScores | Measure-Object -Average).Average
            $mcStd = Get-StdDev $mcScores
            $mcStability = if ($mcMean -gt 0) { 1.0 - [Math]::Min(1.0, $mcStd / $mcMean) } else { 0 }
        } else { $mcStability = 0 }

        # Drawdown estimate (max consecutive losing signals)
        $maxDD = 0;$curDD=0
        for ($i=1;$i-lt$sig.Count;$i++) {
            if ($sig[$i]) { if ($c[$i+5] -lt $c[$i]) { $curDD++ } else { $curDD = 0 }; if ($curDD -gt $maxDD) { $maxDD = $curDD } }
        }

        # Expectancy
        $expectancy = $cfg.AvgMove * $cfg.SignalFreq / 100.0

        # Composite robustness score
        $robustScore = $wfStability * 0.30 + $mcStability * 0.25 + [Math]::Max(0, 1.0 - $maxDD/20) * 0.15 +
                        [Math]::Min(1.0, [Math]::Abs($expectancy)/2) * 0.15 + [Math]::Min(1.0, $cfg.DailyFreq/10) * 0.15

        $ranked += [PSCustomObject]@{
            Indicator=$cfg.Indicator;Params=$cfg.Params
            DailyFreq=$cfg.DailyFreq;AvgMove=$cfg.AvgMove;Stability=$cfg.Stability
            WFStability=[Math]::Round($wfStability,4)
            MCStability=[Math]::Round($mcStability,4)
            MaxConsecLosses=$maxDD
            Expectancy=[Math]::Round($expectancy,4)
            RobustScore=[Math]::Round($robustScore,4)
        }
    }

    return $ranked | Sort-Object RobustScore -Descending
}

# ============================================================
#  STEP 6: FINAL REPORT
# ============================================================
function Get-EdgeDiscoveryReport {
    param($characteristics, $robustRankings, $regimeMap, $symbol)

    $trendTypes = @("ADX","EMACross","OBV")
    $mrTypes = @("RSI","Stoch","CCI","SMI","CMF")
    $bestTrend = $robustRankings | Where-Object { $trendTypes -contains $_.Indicator } | Select-Object -First 2
    $bestMR = $robustRankings | Where-Object { $mrTypes -contains $_.Indicator } | Select-Object -First 2
    $avgFreq = if ($robustRankings.Count -gt 0) { ($robustRankings | ForEach-Object { $_.DailyFreq } | Measure-Object -Average).Average } else { 0 }
    $avgDD = if ($robustRankings.Count -gt 0) { ($robustRankings | ForEach-Object { $_.MaxConsecLosses } | Measure-Object -Average).Average } else { 0 }
    $charRow = $characteristics | Where-Object { $_.TF -eq "240" } | Select-Object -First 1

    $t1i = if ($bestTrend.Count -gt 0) { $bestTrend[0].Indicator } else { "N/A" }
    $t1p = if ($bestTrend.Count -gt 0) { $bestTrend[0].Params } else { "N/A" }
    $t1s = if ($bestTrend.Count -gt 0) { $bestTrend[0].RobustScore } else { 0 }
    $t2i = if ($bestTrend.Count -gt 1) { $bestTrend[1].Indicator } else { "N/A" }
    $t2p = if ($bestTrend.Count -gt 1) { $bestTrend[1].Params } else { "N/A" }
    $t2s = if ($bestTrend.Count -gt 1) { $bestTrend[1].RobustScore } else { 0 }
    $m1i = if ($bestMR.Count -gt 0) { $bestMR[0].Indicator } else { "N/A" }
    $m1p = if ($bestMR.Count -gt 0) { $bestMR[0].Params } else { "N/A" }
    $m1s = if ($bestMR.Count -gt 0) { $bestMR[0].RobustScore } else { 0 }
    $m2i = if ($bestMR.Count -gt 1) { $bestMR[1].Indicator } else { "N/A" }
    $m2p = if ($bestMR.Count -gt 1) { $bestMR[1].Params } else { "N/A" }
    $m2s = if ($bestMR.Count -gt 1) { $bestMR[1].RobustScore } else { 0 }

    return [PSCustomObject]@{
        Symbol=$symbol
        AvgADX=$charRow.AvgADX; TrendPersistence=$charRow.PctAbove25
        AvgTrendLen=$charRow.AvgTrendLen; AvgTrendStrength=$charRow.AvgTrendStrength
        VolClustering=$charRow.VolClustering; ReturnAutocorr=$charRow.ReturnAutocorr; MeanRevBias=$charRow.MeanRevBBPct
        BestTrendIndicator1=$t1i; BestTrendParams1=$t1p; BestTrendScore1=$t1s
        BestTrendIndicator2=$t2i; BestTrendParams2=$t2p; BestTrendScore2=$t2s
        BestMeanRevIndicator1=$m1i; BestMeanRevParams1=$m1p; BestMeanRevScore1=$m1s
        BestMeanRevIndicator2=$m2i; BestMeanRevParams2=$m2p; BestMeanRevScore2=$m2s
        ExpectedTradeFreq=[Math]::Round($avgFreq,2)
        ExpectedMaxConsecLosses=[Math]::Round($avgDD,1)
        TopConfigsCount=$robustRankings.Count
    }
}

Export-ModuleMember -Function Initialize-RsaAuth, Call-Bybit, Get-Klines
Export-ModuleMember -Function Get-AssetCharacteristics
Export-ModuleMember -Function Get-IndicatorResponseSurface
Export-ModuleMember -Function Get-RegimeLabels, Get-RegimeIndicatorMap
Export-ModuleMember -Function Get-FrequencyFilteredConfigs
Export-ModuleMember -Function Get-RobustConfigRankings
Export-ModuleMember -Function Get-EdgeDiscoveryReport
