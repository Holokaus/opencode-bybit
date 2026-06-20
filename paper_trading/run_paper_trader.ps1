# ============================================================
#  MULTI-STRATEGY PAPER TRADER — VPS Continuous Runner
#  ICP: ADX>25 (12h)  |  SOL: Divergence (4h)
#  Supports demo API order placement (testnet)
# ============================================================
param([switch]$Reset)

# ===== RSA KEY LOAD (from bybit_info.ps1 - proven working) =====
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
$Script:RsaKeyFile = if ($env:BYBIT_PRIVATE_KEY_PATH) { $env:BYBIT_PRIVATE_KEY_PATH } else { "bybit_private.pem" }
$pem = Get-Content -Raw $Script:RsaKeyFile; $b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64); $off = 0
if ($der[$off] -ne 0x30) { throw "Not SEQUENCE" }; $off++
$seqLen = Read-DerLength -data $der -offset ([ref]$off)
$p = New-Object System.Security.Cryptography.RSAParameters
$version = Read-DerInteger -data $der -offset ([ref]$off)
$p.Modulus = Read-DerInteger -data $der -offset ([ref]$off); $p.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
$p.D = Read-DerInteger -data $der -offset ([ref]$off); $p.P = Read-DerInteger -data $der -offset ([ref]$off)
$p.Q = Read-DerInteger -data $der -offset ([ref]$off); $p.DP = Read-DerInteger -data $der -offset ([ref]$off)
$p.DQ = Read-DerInteger -data $der -offset ([ref]$off); $p.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
$Script:Rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $Script:Rsa.ImportParameters($p)

# ===== CONFIG =====
$Script:Config = @{
    CheckIntervalSec = 60
    MaxConcurrent    = 3
    UseDemoApi       = $true              # true = place real orders on testnet
    DemoApiUrl       = "https://api-testnet.bybit.com"
    MainApiUrl       = "https://api.bybit.com"
    ApiKey           = $env:BYBIT_API_KEY
    DemoApiKey       = $env:BYBIT_DEMO_API_KEY
    DemoApiSecret    = $env:BYBIT_DEMO_API_SECRET
    Symbols = @(
        @{ Symbol="ICPUSDT"; Strategy="ADX"; TF="12h"; Interval="720"
           ADXThreshold=25; TP=0.5; SL=0.5; FeePercent=0.1
           UseTrendFilter=$false; BaseCapital=50.0 }
        @{ Symbol="SOLUSDT"; Strategy="DIVERGENCE"; TF="4h"; Interval="240"
           TP=0.5; SL=1.5; FeePercent=0.1
           PivotPeriod=3; MinScore=1; MaxBars=60; MaxPP=5
           UseTrendFilter=$true; BaseCapital=50.0 }
    )
}

$Script:RootDir = Split-Path $PSCommandPath -Parent
$Script:Paths = @{
    StateFile  = Join-Path $Script:RootDir "state.json"
    TradesFile = Join-Path $Script:RootDir "trades.csv"
    EquityFile = Join-Path $Script:RootDir "equity.csv"
    LogFile    = Join-Path $Script:RootDir "paper_trader.log"
}
$Script:FirstRun = $true

# ===== API =====
function Call-Bybit {
    param($method, $endpoint, $query, $body)
    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $url = if ($Script:Config.UseDemoApi) { $Script:Config.DemoApiUrl } else { $Script:Config.MainApiUrl }
    $apiKey = if ($Script:Config.UseDemoApi) { $Script:Config.DemoApiKey } else { $Script:Config.ApiKey }
    $recv = "5000"
    $tsStr = "$ts$apiKey$recv"
    $payload = if ($method -eq "GET") { "$tsStr$query" } else { "$tsStr$body" }
    if ($Script:Config.UseDemoApi) {
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [Text.Encoding]::UTF8.GetBytes($Script:Config.DemoApiSecret)
        $sigBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))
        $sig = [BitConverter]::ToString($sigBytes).Replace("-","").ToLower()
        $sigType = "1"
    } else {
        $dataBytes = [Text.Encoding]::UTF8.GetBytes($payload)
        $sha = [Security.Cryptography.SHA256]::Create()
        $sigBytes = $Script:Rsa.SignData($dataBytes, $sha)
        $sig = [Convert]::ToBase64String($sigBytes)
        $sigType = "2"
    }
    $hd = @{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts"
            "X-BAPI-SIGN"=$sig;"X-BAPI-RECV-WINDOW"=$recv;"X-BAPI-SIGN-TYPE"=$sigType}
    try {
        if ($method -eq "GET") {
            $r = Invoke-WebRequest -Uri "$url$endpoint`?$query" -Headers $hd -UseBasicParsing -TimeoutSec 30
        } else {
            $r = Invoke-WebRequest -Uri "$url$endpoint" -Method POST -Headers $hd -Body $body -ContentType "application/json" -UseBasicParsing -TimeoutSec 30
        }
        return ($r.Content | ConvertFrom-Json)
    } catch {
        Write-Warning ("API {0}: {1}" -f $endpoint, $_.Exception.Message)
        return $null
    }
}

function Get-Klines {
    param($symbol, $interval, $limit, [int]$retry = 3)
    for ($r = 0; $r -lt $retry; $r++) {
        $q = "category=spot&symbol=$symbol&interval=$interval&limit=$limit"
        $data = Call-Bybit "GET" "/v5/market/kline" $q ""
        if ($data -and $data.retCode -eq 0 -and $data.result -and $data.result.list) {
            $k = $data.result.list; [Array]::Reverse($k); return $k
        }
        if ($r -lt $retry-1) { Start-Sleep -Seconds 5 }
    }
    return $null
}

function Get-Balance {
    $q = "accountType=UNIFIED&coin=USDT"
    $data = Call-Bybit "GET" "/v5/account/wallet-balance" $q ""
    if ($data -and $data.retCode -eq 0 -and $data.result) {
        return $data.result.list[0].coin
    }
    return $null
}

function Place-Order {
    param($symbol, $side, $qty)
    if (-not $Script:Config.UseDemoApi) { return "PAPER" }
    $b = '{"category":"linear","symbol":"' + $symbol + '","side":"' + $side + '","orderType":"Market","qty":"' + $qty + '"}'
    $data = Call-Bybit "POST" "/v5/order/create" "" $b
    if ($data -and $data.retCode -eq 0) { return $data.result.orderId }
    Write-Warning ("Order failed: {0} {1}" -f $data.retCode, $data.retMsg)
    return "FAIL"
}

function Cancel-Order {
    param($symbol, $orderId)
    $b = '{"category":"linear","symbol":"' + $symbol + '","orderId":"' + $orderId + '"}'
    $data = Call-Bybit "POST" "/v5/order/cancel" "" $b
    return ($data -and $data.retCode -eq 0)
}

# ===== INDICATORS (shared) =====
function Calc-EMA {
    param($p, $per)
    $e = [double[]]::new($p.Count); $e[0] = $p[0]; $m = 2/($per+1)
    for ($i = 1; $i -lt $p.Count; $i++) { $e[$i] = $p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}

# ===== ADX STRATEGY =====
function Calc-ATR {
    param($h, $l, $c, $per)
    $tr = [double[]]::new($c.Count)
    for ($i = 1; $i -lt $c.Count; $i++) {
        $tr[$i] = [Math]::Max($h[$i]-$l[$i], [Math]::Max([Math]::Abs($h[$i]-$c[$i-1]), [Math]::Abs($l[$i]-$c[$i-1])))
    }
    if ($c.Count -le $per) { return @($tr) }
    $a = [double[]]::new($c.Count); $a[$per] = ($tr[1..$per] | Measure-Object -Average).Average
    for ($i = $per+1; $i -lt $c.Count; $i++) { $a[$i] = ($a[$i-1]*($per-1) + $tr[$i])/$per }
    return $a
}
function Calc-ADX {
    param($h, $l, $c, $per)
    $tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
    for ($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))
        $u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per
    $dx=[double[]]::new($c.Count)
    for ($i=$per;$i-lt$c.Count;$i++){$pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100;$dx[$i]=if(($pdi+$ndi)-eq0){0}else{[Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100}}
    return (Calc-EMA $dx $per)
}
function Get-ADXSignal {
    param($klines, $symCfg)
    $c=$klines|%{[double]$_[4]};$h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$ts=$klines|%{[long]$_[0]}
    if ($c.Count -lt 60) { return $null }
    # Compute ADX + directional indicators
    $per=14;$tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count)
    for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))
        $u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per;$adx=(Calc-ADX $h $l $c $per);$ma50=Calc-EMA $c 50;$i=$c.Count-1
    $pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100
    $adxAbove=$adx[$i]-gt$symCfg.ADXThreshold
    $uptrend=$pdi-gt$ndi;$downTrend=$ndi-gt$pdi
    $long=$adxAbove -and $uptrend -and (-not $symCfg.UseTrendFilter -or $c[$i]-gt$ma50[$i])
    $short=$adxAbove -and $downTrend -and (-not $symCfg.UseTrendFilter -or $c[$i]-lt$ma50[$i])
    return @{SignalLong=$long;SignalShort=$short;Strength=[Math]::Round($adx[$i],1);Price=$c[$i];Timestamp=$ts[$i]
             Detail=("ADX={0:F1} +DI={1:F1} -DI={2:F1}" -f $adx[$i],$pdi,$ndi)}
}

# ===== DIVERGENCE STRATEGY =====
function Calc-RSI {
    param($p, $per)
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
function Calc-MOM { param($c,$per)$m=[double[]]::new($c.Count);for($i=$per;$i-lt$c.Count;$i++){$m[$i]=$c[$i]-$c[$i-$per]};return $m}
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
function Get-PivotSigs { param($lows, $highs, $prd)
    $n=$lows.Count;$pl=[int[]]::new($n);$ph=[int[]]::new($n)
    for($i=2*$prd;$i-lt$n;$i++){$tb=$i-$prd;$isPL=$true;$isPH=$true
        for($j=1;$j-le$prd;$j++){if($lows[$tb]-ge$lows[$tb-$j]-or$lows[$tb]-ge$lows[$tb+$j]){$isPL=$false};if($highs[$tb]-le$highs[$tb-$j]-or$highs[$tb]-le$highs[$tb+$j]){$isPH=$false}}
        if($isPL){$pl[$i]=1};if($isPH){$ph[$i]=1}}
    return @{pl=$pl;ph=$ph} }
function Test-Divergence {
    param($indicator,$price,$plSigs,$phSigs,$prd,$maxBars,$maxPP)
    $n=$indicator.Count;$bull=[int[]]::new($n);$bear=[int[]]::new($n)
    $plPos=@();$plVal=@();$plPrc=@();$phPos=@();$phVal=@();$phPrc=@()
    for ($i=2*$prd;$i-lt$n;$i++) {
        if ($plSigs[$i]-eq1) {$pb=$i-$prd;$np=@{pos=$pb;ind=$indicator[$pb];prc=$price[$pb]}
            for($x=0;$x-lt[Math]::Min($maxPP,$plPos.Count);$x++){$len=$pb-$plPos[$x];if($len-gt$maxBars){break};if($len-le$prd){continue}
                if($np.prc-lt$plPrc[$x]-and$np.ind-gt$plVal[$x]){$v=$true
                    for($y=$plPos[$x]+1;$y-lt$pb;$y++){$t=($y-$plPos[$x])/$len;$il=$plVal[$x]+$t*($np.ind-$plVal[$x]);$pl2=$plPrc[$x]+$t*($np.prc-$plPrc[$x]);if($indicator[$y]-lt$il-or$price[$y]-lt$pl2){$v=$false;break}};if($v){$bull[$i]++;break}}}
            $plPos=@($np.pos)+$plPos;$plVal=@($np.ind)+$plVal;$plPrc=@($np.prc)+$plPrc}
        if ($phSigs[$i]-eq1) {$pb=$i-$prd;$np=@{pos=$pb;ind=$indicator[$pb];prc=$price[$pb]}
            for($x=0;$x-lt[Math]::Min($maxPP,$phPos.Count);$x++){$len=$pb-$phPos[$x];if($len-gt$maxBars){break};if($len-le$prd){continue}
                if($np.prc-gt$phPrc[$x]-and$np.ind-lt$phVal[$x]){$v=$true
                    for($y=$phPos[$x]+1;$y-lt$pb;$y++){$t=($y-$phPos[$x])/$len;$il=$phVal[$x]+$t*($np.ind-$phVal[$x]);$pl2=$phPrc[$x]+$t*($np.prc-$phPrc[$x]);if($indicator[$y]-gt$il-or$price[$y]-gt$pl2){$v=$false;break}};if($v){$bear[$i]++;break}}}
            $phPos=@($np.pos)+$phPos;$phVal=@($np.ind)+$phVal;$phPrc=@($np.prc)+$phPrc}
    }
    return @{bull=$bull;bear=$bear}
}
function Get-DivergenceSignal {
    param($klines, $symCfg)
    $c=$klines|%{[double]$_[4]};$h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$v=$klines|%{[double]$_[5]};$ts=$klines|%{[long]$_[0]}
    if ($c.Count -lt 100) { return $null }
    # Compute all indicators
    $rsi = Calc-RSI $c 14; $macd = Calc-MACD $c 12 26 9
    $stoch = Calc-Stoch $h $l $c 14 3; $cci = Calc-CCI $h $l $c 10
    $mom = Calc-MOM $c 10; $mfi = Calc-MFI $h $l $c $v 14
    $cmf = Calc-CMF $h $l $c $v 21; $obv = Calc-OBV $c $v
    # Active indicators: RSI, MACD, Stoch, MFI (from grid search best config)
    $indData = @($rsi, $macd.macd, $stoch, $mfi)
    $indNames = @("RSI","MACD","Stoch","MFI")
    # Pivot detection
    $piv = Get-PivotSigs $l $h $symCfg.PivotPeriod
    $ii = $c.Count - 1
    # Aggregate divergence scores
    $aggBull = 0; $aggBear = 0
    foreach ($src in $indData) {
        $div = Test-Divergence $src $c $piv.pl $piv.ph $symCfg.PivotPeriod $symCfg.MaxBars $symCfg.MaxPP
        if ($div.bull[$ii] -gt 0) { $aggBull++ }
        if ($div.bear[$ii] -gt 0) { $aggBear++ }
    }
    # Trend filter
    $ma50 = Calc-EMA $c 50
    $long = $aggBull -ge $symCfg.MinScore -and (-not $symCfg.UseTrendFilter -or $c[$ii] -gt $ma50[$ii])
    $short = $aggBear -ge $symCfg.MinScore -and (-not $symCfg.UseTrendFilter -or $c[$ii] -lt $ma50[$ii])
    return @{ SignalLong=$long; SignalShort=$short; Strength=$aggBull; Timestamp=$ts[$ii]; Price=$c[$ii]
              Detail=("DivScore: BULL={0} BEAR={1}" -f $aggBull, $aggBear) }
}

# ===== SIGNAL DISPATCH =====
function Get-Signal {
    param($klines, $symCfg)
    if ($symCfg.Strategy -eq "ADX") { return Get-ADXSignal $klines $symCfg }
    elseif ($symCfg.Strategy -eq "DIVERGENCE") { return Get-DivergenceSignal $klines $symCfg }
    return $null
}

# ===== STATE =====
function New-SymState { param($symCfg)
    return @{ Capital=$symCfg.BaseCapital; PeakCapital=$symCfg.BaseCapital
              TotalTrades=0; Wins=0; Losses=0; ConsecLosses=0
              LastCandleTs=0; LastSignal=$false; Positions=@(); DemoOrderIds=@() } }
function New-DefaultState {
    $syms=@{}; foreach($sc in $Script:Config.Symbols){$syms[$sc.Symbol]=New-SymState $sc}
    $total=($Script:Config.Symbols|%{$_.BaseCapital}|Measure-Object -Sum).Sum
    return @{Version=3;TotalCapital=$total;PeakCapital=$total;Symbols=$syms;FirstRun=$true} }
function Load-State {
    if ((Test-Path $Script:Paths.StateFile) -and -not $Reset) {
        try {
            $j = Get-Content $Script:Paths.StateFile -Raw | ConvertFrom-Json
            if ($j.Version -eq 3) {
                $s = New-DefaultState
                $s.TotalCapital = [double]$j.TotalCapital
                $s.PeakCapital = [double]$j.PeakCapital
                $s.FirstRun = [bool]$j.FirstRun
                foreach ($sym in $j.Symbols.PSObject.Properties) {
                    $sn = $sym.Name; $sv = $sym.Value
                    if ($s.Symbols.ContainsKey($sn)) {
                        $t = $s.Symbols[$sn]
                        $t.Capital = [double]$sv.Capital
                        $t.PeakCapital = [double]$sv.PeakCapital
                        $t.TotalTrades = [int]$sv.TotalTrades
                        $t.Wins = [int]$sv.Wins
                        $t.Losses = [int]$sv.Losses
                        $t.ConsecLosses = [int]$sv.ConsecLosses
                        $t.LastCandleTs = [long]$sv.LastCandleTs
                        $t.LastSignal = [bool]$sv.LastSignal
                        if ($sv.Positions) {
                            foreach ($p in $sv.Positions) {
                                $t.Positions += @{
                                    Side="long"; EntryPrice=[double]$p.EntryPrice; EntryTime=[long]$p.EntryTime
                                    TPPrice=[double]$p.TPPrice; SLPrice=[double]$p.SLPrice
                                    Units=[double]$p.Units; SizeQuote=[double]$p.SizeQuote; OrderId=""
                                }
                            }
                        }
                        if ($sv.DemoOrderIds) {
                            foreach ($oid in $sv.DemoOrderIds) { $t.DemoOrderIds += $oid }
                        }
                    }
                }
                Write-Log ("State v3: TotalCap={0:F2} | {1}" -f $s.TotalCapital,
                    (($s.Symbols.Keys | % {"{0}:{1}t,{2}pos" -f $_, $s.Symbols[$_].TotalTrades, $s.Symbols[$_].Positions.Count}) -join " "))
                return $s
            }
        } catch { Write-Warning ("Load error: {0}" -f $_) }
    }
    $s = New-DefaultState
    Write-Log "Fresh state initialized"
    return $s
}
function Save-State {
    $s=$Script:State;$json=@{Version=3;TotalCapital=[Math]::Round($s.TotalCapital,6);PeakCapital=[Math]::Round($s.PeakCapital,6);FirstRun=$s.FirstRun;Symbols=@{}}
    foreach($sn in $s.Symbols.Keys){$sv=$s.Symbols[$sn]
        $json.Symbols[$sn]=@{Capital=[Math]::Round($sv.Capital,6);PeakCapital=[Math]::Round($sv.PeakCapital,6)
            TotalTrades=$sv.TotalTrades;Wins=$sv.Wins;Losses=$sv.Losses;ConsecLosses=$sv.ConsecLosses
            LastCandleTs=$sv.LastCandleTs;LastSignal=$sv.LastSignal;DemoOrderIds=@($sv.DemoOrderIds)
            Positions=@(foreach($p in $sv.Positions){@{Side="long";EntryPrice=[Math]::Round($p.EntryPrice,8);EntryTime=$p.EntryTime;TPPrice=[Math]::Round($p.TPPrice,8);SLPrice=[Math]::Round($p.SLPrice,8);Units=[Math]::Round($p.Units,8);SizeQuote=[Math]::Round($p.SizeQuote,6);OrderId=$p.OrderId}})}}
    try{$json|ConvertTo-Json -Depth 5|Set-Content $Script:Paths.StateFile -Force}catch{Write-Warning"Save error: $_"}}

# ===== LOGGING =====
function Write-Log {
    param($msg);$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="$ts | $msg"
    Add-Content -Path $Script:Paths.LogFile -Value $line -Force;Write-Output $line }
function Log-Trade {
    param($sym,$side,$entry,$exit,$reason,$pnl,$capAfter,$exitTs,$entryTs,$orderId)
    $line="{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}" -f $sym,$entryTs,$exitTs,$side,
        [Math]::Round($entry,6),[Math]::Round($exit,6),$reason,[Math]::Round($pnl,6),[Math]::Round($capAfter,6),$orderId
    Add-Content -Path $Script:Paths.TradesFile -Value $line -Force }
function Log-Equity {
    param($c);$ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $Script:Paths.EquityFile -Value "$ts,$([Math]::Round($c,6))" -Force }

# ===== POSITIONS =====
function Check-Positions {
    param($symState,$klines)
    $closed=@();$stillOpen=@()
    $h=$klines|%{[double]$_[2]};$l=$klines|%{[double]$_[3]};$c=$klines|%{[double]$_[4]};$ts=$klines|%{[long]$_[0]}
    foreach($pos in $symState.Positions){$ei=-1
        for($i=0;$i-lt$ts.Count;$i++){if($ts[$i]-eq$pos.EntryTime){$ei=$i;break}}
        if($ei-lt0){$ei=0;for($i=1;$i-lt$ts.Count;$i++){if([Math]::Abs($ts[$i]-$pos.EntryTime)-lt[Math]::Abs($ts[$ei]-$pos.EntryTime)){$ei=$i}}}
        $hit=$null
        $isLong = $pos.Side -ne "short"
        for($j=$ei+1;$j-lt$c.Count;$j++){
            if($isLong){$tpHit=$h[$j]-ge$pos.TPPrice;$slHit=$l[$j]-le$pos.SLPrice;$ep=if($tpHit){[Math]::Min($pos.TPPrice,$c[$j])}else{$pos.SLPrice}}
            else{$tpHit=$l[$j]-le$pos.TPPrice;$slHit=$h[$j]-ge$pos.SLPrice;$ep=if($tpHit){[Math]::Max($pos.TPPrice,$c[$j])}else{$pos.SLPrice}}
            if($tpHit){$hit=@{ExitPrice=$ep;Reason="TP";ExitIdx=$j};break}
            if($slHit){$hit=@{ExitPrice=$ep;Reason="SL";ExitIdx=$j};break}}
        if($hit){$closed+=@{Pos=$pos;Exit=$hit}}else{$stillOpen+=$pos}}
    $symState.Positions=$stillOpen;return $closed}
function Enter-Trade {
    param($symState,$symCfg,$price,$timestamp,$signalStr)
    if($symState.Positions.Count-ge$Script:Config.MaxConcurrent){return}
    foreach($p in $symState.Positions){if($p.EntryTime-eq$timestamp){return}}
    $posSize=$symState.Capital/$Script:Config.MaxConcurrent
    $oid="";$qty=[Math]::Round($posSize/$price,6)
    $isLong = $signalStr -eq "LONG"
    if($Script:Config.UseDemoApi-and$qty-gt0){$oid=Place-Order $symCfg.Symbol $(if($isLong){"Buy"}else{"Sell"}) $qty}
    if ($isLong) { $tp=$price*(1+$symCfg.TP/100); $sl=$price*(1-$symCfg.SL/100) } else { $tp=$price*(1-$symCfg.TP/100); $sl=$price*(1+$symCfg.SL/100) }
    $pos=@{Side=if($isLong){"long"}else{"short"};EntryPrice=$price;EntryTime=$timestamp;TPPrice=$tp;SLPrice=$sl;Units=$posSize/$price;SizeQuote=$posSize;OrderId=$oid}
    $symState.Positions+=$pos
    $dtStr=[DateTimeOffset]::FromUnixTimeMilliseconds($timestamp).ToString('yyyy-MM-dd HH:mm')
    $apiStr=if($oid-eq"PAPER"){"PAPER"}elseif($oid-eq"FAIL"){"API_FAIL"}elseif($oid-eq""){"PAPER"}else{"API=$oid"}
    Write-Log("[{0}] >>> {1} at {2} (TP={3:F4} SL={4:F4}) | Size={5:F2} | {6} | {7}"-f
        $symCfg.Symbol,$signalStr,$price,$tp,$sl,$posSize,$signalStr,$apiStr)}
function Close-Trade {
    param($symState,$symCfg,$pos,$exitPrice,$reason,$exitTs)
    $side = $pos.Side
    $grossPnl = if ($reason-eq"TP") {
        if ($side-eq"long") { $pos.Units*$pos.EntryPrice*$symCfg.TP/100 } else { $pos.Units*$pos.EntryPrice*$symCfg.TP/100 }
    } else {
        if ($side-eq"long") { -$pos.Units*$pos.EntryPrice*$symCfg.SL/100 } else { -$pos.Units*$pos.EntryPrice*$symCfg.SL/100 }
    }
    $fee=$pos.SizeQuote*$symCfg.FeePercent/100+($pos.Units*$exitPrice)*$symCfg.FeePercent/100
    $netPnl=$grossPnl-$fee
    if($Script:Config.UseDemoApi-and$pos.OrderId){Cancel-Order $symCfg.Symbol $pos.OrderId|Out-Null}
    $symState.Capital+=$netPnl;if($symState.Capital-gt$symState.PeakCapital){$symState.PeakCapital=$symState.Capital}
    $symState.TotalTrades++
    if($netPnl-ge0){$symState.Wins++;$symState.ConsecLosses=0}else{$symState.Losses++;$symState.ConsecLosses++}
    Log-Trade $symCfg.Symbol $side $pos.EntryPrice $exitPrice $reason $netPnl $symState.Capital $exitTs $pos.EntryTime $pos.OrderId
    $wr=[Math]::Round($symState.Wins/[Math]::Max(1,$symState.TotalTrades)*100,1)
    Write-Log("[{0}] <<< {1} at {2} | PnL={3:F4} | Cap={4:F2} | WR={5}% ({6}/{7})"-f
        $symCfg.Symbol,$reason,$exitPrice,$netPnl,$symState.Capital,$wr,$symState.Wins,$symState.TotalTrades)}

# ===== MAIN =====
if(-not(Test-Path $Script:Paths.TradesFile)){Set-Content $Script:Paths.TradesFile "symbol,entryTime,exitTime,side,entry,exit,reason,pnl,capitalAfter,orderId" -Force}
if(-not(Test-Path $Script:Paths.EquityFile)){Set-Content $Script:Paths.EquityFile "time,capital" -Force}
$Script:State=Load-State;Save-State
try{[Console]::TreatControlCAsInput=$false}catch{};$shutdown=$false
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action{$shutdown=$true}|Out-Null

# Banner
Write-Output"";Write-Output("="*70)
Write-Output "  MULTI-STRATEGY PAPER TRADER"
foreach($sc in $Script:Config.Symbols){$ss=$Script:State.Symbols[$sc.Symbol]
    Write-Output("  {0,-8} {1,-11} | TP={2}% SL={3}% | Cap={4,7:F2} | Trades={5} | Pos={6}"-f
        $sc.Symbol,$sc.Strategy,$sc.TP,$sc.SL,$ss.Capital,$ss.TotalTrades,$ss.Positions.Count)
Write-Output("  Demo API: {0}"-f$Script:Config.UseDemoApi)
Write-Output("="*70)

$loopCount=0
while(-not$shutdown){$loopCount++
    try{
        foreach($sc in $Script:Config.Symbols){$sym=$sc.Symbol;$symState=$Script:State.Symbols[$sym];if(-not$symState){continue}
            $klines=Get-Klines $sym $sc.Interval 200
            if(-not$klines-or$klines.Count-lt80){Write-Log ("[{0}] WARN: klines {1}"-f$sym,$(if($klines){$klines.Count}else{0}));continue}
            $lastTs=[long]$klines[-1][0];$lastClose=[double]$klines[-1][4]

            # Check positions for TP/SL
            $closed=Check-Positions $symState $klines
            foreach($c in $closed){$exitTs=[long]$klines[$c.Exit.ExitIdx][0];Close-Trade $symState $sc $c.Pos $c.Exit.ExitPrice $c.Exit.Reason $exitTs}
            if($closed.Count-gt0){Log-Equity $Script:State.TotalCapital}

            # New candle signal
            $cdt=[DateTimeOffset]::FromUnixTimeMilliseconds($lastTs);$cLabel=$cdt.ToString('MM-dd HH:mm')
            if($lastTs-ne$symState.LastCandleTs){$symState.LastCandleTs=$lastTs
                $signal=Get-Signal $klines $sc
                if($signal){
                    $sigStr=if($signal.SignalLong){"LONG"}elseif($signal.SignalShort){"SHORT"}else{"NONE"};$d=$signal.Detail
                    Write-Log("[{0}] {1} | {2} Price={3} => {4}"-f$sym,$cLabel,$d,$signal.Price,$sigStr)
                    if($Script:FirstRun){Write-Log("[{0}] SKIP entry - first run (recording candle only)"-f$sym);continue}
                    if($symState.Positions.Count-lt$Script:Config.MaxConcurrent){
                        if($signal.SignalLong){Enter-Trade $symState $sc $signal.Price $signal.Timestamp "LONG"}
                        if($signal.SignalShort){Enter-Trade $symState $sc $signal.Price $signal.Timestamp "SHORT"}}}}
        }

        # After first complete cycle, disable first-run lock
        if($Script:FirstRun-and$loopCount-ge1){$Script:FirstRun=$false;Write-Log "First run complete - signal detection enabled"}

        # Recalc total capital
        $newTotal=0.0;foreach($sc in $Script:Config.Symbols){$newTotal+=$Script:State.Symbols[$sc.Symbol].Capital}
        $Script:State.TotalCapital=$newTotal
        if($Script:State.TotalCapital-gt$Script:State.PeakCapital){$Script:State.PeakCapital=$Script:State.TotalCapital}

        # Status line
        if($loopCount%10-eq0){$parts=foreach($sc in $Script:Config.Symbols){$ss=$Script:State.Symbols[$sc.Symbol]
            "{0}:{1}p,{2}t"-f$sc.Symbol.Substring(0,3),$ss.Positions.Count,$ss.TotalTrades}
            Write-Output("[{0}] Cap={1:F2} | {2}"-f(Get-Date -Format 'HH:mm:ss'),$Script:State.TotalCapital,($parts-join" "))}
        Save-State
    }catch{Write-Log ("ERROR: $_");Write-Log ("Stack: $($_.ScriptStackTrace)")}
    Start-Sleep -Seconds $Script:Config.CheckIntervalSec}
Write-Log"=== SHUTDOWN ===";Save-State;Write-Output "State saved."
