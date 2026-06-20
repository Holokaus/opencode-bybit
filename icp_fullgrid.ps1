function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $l=$data[$offset.Value]; $offset.Value++; return $l }
    $n=$data[$offset.Value]-band0x7F;$offset.Value++;$len=0;for($i=0;$i-lt$n;$i++){$len=($len-shl8)-bor$data[$offset.Value];$offset.Value++};return $len
}
function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value]-ne0x02){throw};$offset.Value++
    $l=Read-DerLength -data $data -offset $offset;$v=[byte[]]::new($l);[Array]::Copy($data,$offset.Value,$v,0,$l)
    $s=if($v.Length-gt1-and$v[0]-eq0){1}else{0};$t=[byte[]]::new($v.Length-$s);[Array]::Copy($v,$s,$t,0,$t.Length)
    $offset.Value+=$l;return $t
}
$pem=[System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH);$b64=($pem-replace'-----.+-----',''-replace'\s','');$der=[System.Convert]::FromBase64String($b64);$off=0
if($der[$off]-ne0x30){throw};$off++|Out-Null;Read-DerLength -data $der -offset ([ref]$off)|Out-Null
$p=New-Object System.Security.Cryptography.RSAParameters;$null=Read-DerInteger -data $der -offset ([ref]$off)
$p.Modulus=Read-DerInteger -data $der -offset ([ref]$off);$p.Exponent=Read-DerInteger -data $der -offset ([ref]$off)
$p.D=Read-DerInteger -data $der -offset ([ref]$off);$p.P=Read-DerInteger -data $der -offset ([ref]$off);$p.Q=Read-DerInteger -data $der -offset ([ref]$off)
$p.DP=Read-DerInteger -data $der -offset ([ref]$off);$p.DQ=Read-DerInteger -data $der -offset ([ref]$off);$p.InverseQ=Read-DerInteger -data $der -offset ([ref]$off)
$rsa=New-Object System.Security.Cryptography.RSACryptoServiceProvider;$rsa.ImportParameters($p)
$apiKey=$env:BYBIT_API_KEY;$recvWindow="5000"
function Call-API{param($ep,$q)$ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$body=[Text.Encoding]::UTF8.GetBytes("$ts$apiKey$recvWindow$q");$sha=[Security.Cryptography.SHA256]::Create();$sig=[Convert]::ToBase64String($rsa.SignData($body,$sha));$hd=@{"X-BAPI-API-KEY"=$apiKey;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sig;"X-BAPI-RECV-WINDOW"=$recvWindow;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"};try{$r=Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 60;return($r.Content|ConvertFrom-Json)}catch{return $null}}
function Get-K{param($i,$l)$r=Call-API -ep "/v5/market/kline" -q "category=spot&symbol=ICPUSDT&interval=$i&limit=$l";if($r-and$r.result-and$r.result.list){$k=$r.result.list;[Array]::Reverse($k);return $k};return $null}
function Calc-RSI{param($p,$per)$g=[double[]]::new($p.Count);$lo=[double[]]::new($p.Count);for($i=1;$i-lt$p.Count;$i++){$d=$p[$i]-$p[$i-1];if($d-ge0){$g[$i]=$d}else{$lo[$i]=-$d}};$ag=($g[1..$per]|Measure-Object -Sum).Sum/$per;$al=($lo[1..$per]|Measure-Object -Sum).Sum/$per;$r=[double[]]::new($p.Count);for($i=$per;$i-lt$p.Count;$i++){if($i-gt$per){$ag=(($ag*($per-1))+$g[$i])/$per;$al=(($al*($per-1))+$lo[$i])/$per};$r[$i]=if($al-eq0){100}else{100-(100/(1+($ag/$al)))}};return $r}
function Calc-EMA{param($p,$per)$e=[double[]]::new($p.Count);$e[0]=$p[0];$m=2/($per+1);for($i=1;$i-lt$p.Count;$i++){$e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m)};return $e}
function Calc-ATR{param($h,$l,$c,$per)$tr=[double[]]::new($c.Count);for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])))};$a=[double[]]::new($c.Count);if($c.Count-gt$per){$a[$per]=($tr[1..$per]|Measure-Object -Average).Average;for($i=$per+1;$i-lt$c.Count;$i++){$a[$i]=($a[$i-1]*($per-1)+$tr[$i])/$per}};return $a}
function Calc-ADX{param($h,$l,$c,$per)$tr=[double[]]::new($c.Count);$up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count);for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])));$u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}};$atr=Calc-EMA $tr $per;$du=Calc-EMA $up $per;$dd=Calc-EMA $dn $per;$dx=[double[]]::new($c.Count);for($i=$per;$i-lt$c.Count;$i++){$pdi=$du[$i]/$atr[$i]*100;$ndi=$dd[$i]/$atr[$i]*100;$dx[$i]=if(($pdi+$ndi)-eq0){0}else{[Math]::Abs($pdi-$ndi)/($pdi+$ndi)*100}};return(Calc-EMA $dx $per)}
function Calc-StochRSI{param($p,$per)$rsi=Calc-RSI $p $per;$k=[double[]]::new($p.Count);for($i=$per;$i-lt$p.Count;$i++){$mn=($rsi[($i-$per+1)..$i]|Measure-Object -Minimum).Minimum;$mx=($rsi[($i-$per+1)..$i]|Measure-Object -Maximum).Maximum;$k[$i]=if($mx-$mn-eq0){50}else{($rsi[$i]-$mn)/($mx-$mn)*100}};return $k}
function Test-Sig{param($c,$sigL,$sigS,$si)$lw=0;$ll=0;$sw=0;$sl=0;for($rel=0;$rel-lt$sigL.Length-3;$rel++){$idx=$rel+$si;if($sigL[$rel]){$fL=($c[($idx+1)..($idx+3)]|Measure-Object -Minimum).Minimum;if(($c[$idx]-$fL)/$c[$idx]*100-gt1.0){$lw++}else{$ll++}};if($sigS[$rel]){$fH=($c[($idx+1)..($idx+3)]|Measure-Object -Maximum).Maximum;if(($fH-$c[$idx])/$c[$idx]*100-gt1.0){$sw++}else{$sl++}}};$t=$lw+$ll+$sw+$sl;$wr=if($t){[Math]::Round(($lw+$sw)/$t*100,1)}else{0};return @{wr=$wr;t=$t;lw=$lw;ll=$ll;sw=$sw;sl=$sl}}

Write-Output "================================================================"
Write-Output "  ICP FULL GRID - ALL STRATEGIES X ALL TIMEFRAMES"
Write-Output "================================================================"

# Phase 0: Cache all kline data
Write-Output "`n[0] CACHING ALL KLINES..."
$tfs=@(@{n="15m";i="15"},@{n="30m";i="30"},@{n="1h";i="60"},@{n="2h";i="120"},@{n="4h";i="240"},@{n="6h";i="360"},@{n="12h";i="720"})
$kc=@{}
foreach($tf in $tfs){Write-Output "  $($tf.n)...";$k=Get-K $tf.i 800;if($k-and$k.Count-ge100){$kc[$tf.n]=@($k|?{$_})}}
Write-Output "  Cached $($kc.Count) timeframes"

# Phase 1: For each TF, compute all indicators and test all strategies
Write-Output "`n--- PHASE 1: ALL STRATEGIES TESTING ---"
$allStrategies=@();$script:strategySignals=@{}
for($ti=0;$ti-lt$tfs.Length;$ti++){$tf=$tfs[$ti];$ttf=$tf.n;$k=$kc[$ttf];if(-not$k){continue}
    $o=$k|%{[double]$_[1]};$c=$k|%{[double]$_[4]};$h=$k|%{[double]$_[2]};$l=$k|%{[double]$_[3]};$v=$k|%{[double]$_[5]};$ts=$k|%{[long]$_[0]}
    Write-Output "`n>>> $ttf ($($c.Count) candles) <<<"

    # Compute all base indicators
    $vma=Calc-EMA $v 20;$vma10=Calc-EMA $v 10
    $ma20=Calc-EMA $c 20;$ma50=Calc-EMA $c 50;$ma100=Calc-EMA $c 100;$ma200=Calc-EMA $c 200
    $atr14=Calc-ATR $h $l $c 14;$adx14=Calc-ADX $h $l $c 14;$stoch14=Calc-StochRSI $c 14
    $atrAvg=($atr14[50..($atr14.Count-1)]|Measure-Object -Average).Average
    $si=[Math]::Max(80,200) # start index to ensure all indicators are warm

    # Pre-computed common conditions (reused by many strategies)
    $bullCandle = [bool[]]::new($c.Count); $bearCandle = [bool[]]::new($c.Count)
    $volAboveAvg = @{}; foreach($m in @(1.0,1.2,1.5,2.0,2.5,3.0)){ $volAboveAvg[$m] = [bool[]]::new($c.Count) }
    $priceAboveMA = @{}; foreach($p in @(20,50,100,200)){ $priceAboveMA[$p] = [bool[]]::new($c.Count) }
    $maAboveMA = @{}; foreach($pair in @(@(20,50),@(50,100),@(20,100),@(50,200))){ $keyName="$($pair[0])_$($pair[1])"; $maAboveMA[$keyName] = [bool[]]::new($c.Count) }
    $adxAbove = @{}; foreach($thr in @(20,25,30,35,40)){ $adxAbove[$thr] = [bool[]]::new($c.Count) }
    $plusDIPos = [bool[]]::new($c.Count); $minusDIPos = [bool[]]::new($c.Count)
    $stochBelow = @{}; $stochAbove = @{}; foreach($thr in @(10,20,30,40,60,70,80,90)){ $stochBelow[$thr]=[bool[]]::new($c.Count); $stochAbove[$thr]=[bool[]]::new($c.Count) }
    $atrHigh = [bool[]]::new($c.Count); $atrLow = [bool[]]::new($c.Count)

    # DI components for ADX direction
    $up=[double[]]::new($c.Count);$dn=[double[]]::new($c.Count);$tr=[double[]]::new($c.Count)
    for($i=1;$i-lt$c.Count;$i++){$tr[$i]=[Math]::Max($h[$i]-$l[$i],[Math]::Max([Math]::Abs($h[$i]-$c[$i-1]),[Math]::Abs($l[$i]-$c[$i-1])));$u=$h[$i]-$h[$i-1];$d=$l[$i-1]-$l[$i];$up[$i]=if($u-gt$d-and$u-gt0){$u}else{0};$dn[$i]=if($d-gt$u-and$d-gt0){$d}else{0}}
    $emu=Calc-EMA $up 14;$emd=Calc-EMA $dn 14;$ematr=Calc-EMA $tr 14
    for($i=20;$i-lt$c.Count;$i++){$plusDIPos[$i]=$emu[$i]/$ematr[$i]*100 -gt $emd[$i]/$ematr[$i]*100;$minusDIPos[$i]=$emd[$i]/$ematr[$i]*100 -gt $emu[$i]/$ematr[$i]*100}

    for($i=0;$i-lt$c.Count;$i++){
        $bullCandle[$i]=$c[$i]-gt$o[$i]
        $bearCandle[$i]=$c[$i]-lt$o[$i]
        foreach($m in $volAboveAvg.Keys){$volAboveAvg[$m][$i]=$v[$i]-gt$vma[$i]*$m}
        foreach($p in $priceAboveMA.Keys){
            $ma=if($p-eq20){$ma20}elseif($p-eq50){$ma50}elseif($p-eq100){$ma100}else{$ma200}
            $priceAboveMA[$p][$i]=$c[$i]-gt$ma[$i]
        }
        if($i-gt0){
            foreach($pair in @(@(20,50),@(50,100),@(20,100),@(50,200))){
                $keyName="$($pair[0])_$($pair[1])";$ma1=if($pair[0]-eq20){$ma20}else{$ma50};$ma2=if($pair[1]-eq50){$ma50}else{if($pair[1]-eq100){$ma100}else{$ma200}}
                $maAboveMA[$keyName][$i]=$ma1[$i]-gt$ma2[$i]
            }
        }
        foreach($thr in $adxAbove.Keys){$adxAbove[$thr][$i]=$adx14[$i]-gt$thr}
        foreach($thr in $stochBelow.Keys){$stochBelow[$thr][$i]=$stoch14[$i]-lt$thr;$stochAbove[$thr][$i]=$stoch14[$i]-gt(100-$thr)}
        $atrHigh[$i]=$c[$i]-gt$o[$i]+$atr14[$i]*1.5
        $atrLow[$i]=$c[$i]-lt$o[$i]-$atr14[$i]*1.5
    }

    # RSI bruteforce to find best per/ob/os (same as before)
    $rsiBest=$null;$rsiBestWr=0;$obs=@(60,64,68,72,76,80,84);$oss=@(20,24,28,32,36,40,44)
    foreach($per in (5..50|?{$_%3-eq2-or$_-eq5})){
        $r=Calc-RSI $c $per;$pb=$null;$pbs=0
        foreach($ob in $obs){foreach($os in $oss){if($os-ge($ob-15)){continue};$lw=0;$ll=0;$sw=0;$sl=0
            for($i=$per;$i-lt$c.Count-3;$i++){if($r[$i-1]-gt$os-and$r[$i]-le$os-and$r[$i]-ne0){$fL=($c[($i+1)..($i+3)]|Measure-Object -Minimum).Minimum;if(($c[$i]-$fL)/$c[$i]*100-gt1.0){$lw++}else{$ll++}};if($r[$i-1]-lt$ob-and$r[$i]-ge$ob-and$r[$i]-ne100){$fH=($c[($i+1)..($i+3)]|Measure-Object -Maximum).Maximum;if(($fH-$c[$i])/$c[$i]*100-gt1.0){$sw++}else{$sl++}}}
            $t=$lw+$ll+$sw+$sl;if($t-ge3){$wr=[Math]::Round(($lw+$sw)/$t*100,1);$s=$wr*$t;if($s-gt$pbs){$pbs=$s;$pb=@{per=$per;ob=$ob;os=$os;wr=$wr;lw=$lw;ll=$ll;sw=$sw;sl=$sl;t=$t}}}}}
        if($pb-and$pb.wr-gt$rsiBestWr){$rsiBestWr=$pb.wr;$rsiBest=$pb}
    }
    Write-Output "  Best RSI: RSI($($rsiBest.per)) OB=$($rsiBest.ob) OS=$($rsiBest.os) WR=$($rsiBest.wr)% ($($rsiBest.t) sigs)"

    # Generate all signal arrays
    Write-Output "  Testing all strategies..."
    $rsiBase=Calc-RSI $c $rsiBest.per
    $stochCrossL=[bool[]]::new($c.Count);$stochCrossS=[bool[]]::new($c.Count);$macrossUp=[bool[]]::new($c.Count);$macrossDn=[bool[]]::new($c.Count)
    for($i=1;$i-lt$c.Count;$i++){
        $stochCrossL[$i]=$stoch14[$i-1]-lt20-and$stoch14[$i]-ge20
        $stochCrossS[$i]=$stoch14[$i-1]-gt80-and$stoch14[$i]-le80
        $macrossUp[$i]=$ma20[$i-1]-lt$ma50[$i-1]-and$ma20[$i]-ge$ma50[$i]
        $macrossDn[$i]=$ma20[$i-1]-gt$ma50[$i-1]-and$ma20[$i]-le$ma50[$i]
    }

    # Helper to register a strategy
    $regCount=0
    function Reg {
        param($n,$sigL,$sigS)
        $s=Test-Sig $c $sigL $sigS $si
        $wrVal=$s.wr; $sigCount=$s.t
        $r=[PSCustomObject]@{tf=$tf.n;name=$n;wr=$wrVal;sigs=$sigCount;lw=$s.lw;ll=$s.ll;sw=$s.sw;sl=$s.sl}
        $script:strategySignals["$($tf.n)|$n"]=@{l=@($sigL);s=@($sigS);si=$si}
        $script:allStrategies+=$r
        $regCount++
        Write-Output ("  {0,-45} WR={1,-5}% | {2} sigs (L:{3}/{4} S:{5}/{6})" -f $n,$wrVal,$sigCount,$s.lw,($s.lw+$s.ll),$s.sw,($s.sw+$s.sl))
        return $r
    }

    # ===== RSI strategies (using best per/ob/os from bruteforce) =====
    Reg "RSI alone" ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-gt$rsiBest.os-and$rsiBase[$j]-le$rsiBest.os-and$rsiBase[$j]-ne0}) ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-lt$rsiBest.ob-and$rsiBase[$j]-ge$rsiBest.ob-and$rsiBase[$j]-ne100})
    # RSI+Vol variants
    foreach($vt in @(0.7,0.8,0.9,1.0,1.2,1.5)){
        Reg "RSI+Vol($vt)" ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-gt$rsiBest.os-and$rsiBase[$j]-le$rsiBest.os-and$rsiBase[$j]-ne0-and$v[$j]-gt$vma[$j]*$vt}) ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-lt$rsiBest.ob-and$rsiBase[$j]-ge$rsiBest.ob-and$rsiBase[$j]-ne100-and$v[$j]-gt$vma[$j]*$vt})
    }
    # RSI+Vol+ADX
    foreach($at in @(20,25,30)){foreach($vt in @(0.7,0.8,1.0)){
        Reg "RSI+Vol($vt)+ADX($at)" ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-gt$rsiBest.os-and$rsiBase[$j]-le$rsiBest.os-and$rsiBase[$j]-ne0-and$v[$j]-gt$vma[$j]*$vt-and$adx14[$j]-gt$at}) ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-lt$rsiBest.ob-and$rsiBase[$j]-ge$rsiBest.ob-and$rsiBase[$j]-ne100-and$v[$j]-gt$vma[$j]*$vt-and$adx14[$j]-gt$at})
    }}
    # RSI+Vol+Stoch
    foreach($st in @(20,30,40)){Reg "RSI+Vol(0.8)+Stoch($st)" ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-gt$rsiBest.os-and$rsiBase[$j]-le$rsiBest.os-and$rsiBase[$j]-ne0-and$v[$j]-gt$vma[$j]*0.8-and$stoch14[$j]-lt$st}) ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-lt$rsiBest.ob-and$rsiBase[$j]-ge$rsiBest.ob-and$rsiBase[$j]-ne100-and$v[$j]-gt$vma[$j]*0.8-and$stoch14[$j]-gt(100-$st)})}
    # RSI+Vol+ATRreg
    Reg "RSI+Vol(0.8)+ATRreg" ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-gt$rsiBest.os-and$rsiBase[$j]-le$rsiBest.os-and$rsiBase[$j]-ne0-and$v[$j]-gt$vma[$j]*0.8-and$atr14[$j]-gt$atrAvg}) ($rsiBase[$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$rsiBase[$j-1]-lt$rsiBest.ob-and$rsiBase[$j]-ge$rsiBest.ob-and$rsiBase[$j]-ne100-and$v[$j]-gt$vma[$j]*0.8-and$atr14[$j]-gt$atrAvg})

    # ===== Volume-based strategies =====
    Reg "Vol>Avg*1.5 + Bull" ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $bullCandle[$j]}) ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $bearCandle[$j]})
    Reg "Vol>Avg*2.0 + Bull" ($volAboveAvg[2.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $bullCandle[$j]}) ($volAboveAvg[2.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $bearCandle[$j]})
    Reg "Vol>Avg*3.0 + Bull" ($volAboveAvg[3.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $bullCandle[$j]}) ($volAboveAvg[3.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $bearCandle[$j]})
    Reg "Vol>Avg*1.5 (any dir)" ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_}) ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_})
    Reg "Vol>Avg*2.0 (any dir)" ($volAboveAvg[2.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_}) ($volAboveAvg[2.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_})

    # ===== MA trend strategies =====
    Reg "Price>MA20 (uptrend)" ($priceAboveMA[20][$si..($c.Count-1)]) ($priceAboveMA[20][$si..($c.Count-1)]|%{-not$_})
    Reg "Price>MA50 (uptrend)" ($priceAboveMA[50][$si..($c.Count-1)]) ($priceAboveMA[50][$si..($c.Count-1)]|%{-not$_})
    Reg "Price>MA200 (uptrend)" ($priceAboveMA[200][$si..($c.Count-1)]) ($priceAboveMA[200][$si..($c.Count-1)]|%{-not$_})
    Reg "MA20>MA50 (uptrend)" ($maAboveMA["20_50"][$si..($c.Count-1)]) ($maAboveMA["20_50"][$si..($c.Count-1)]|%{-not$_})
    Reg "MA50>MA100 (uptrend)" ($maAboveMA["50_100"][$si..($c.Count-1)]) ($maAboveMA["50_100"][$si..($c.Count-1)]|%{-not$_})
    Reg "MA20>MA200 (uptrend)" ($maAboveMA["20_100"][$si..($c.Count-1)]) ($maAboveMA["20_100"][$si..($c.Count-1)]|%{-not$_})
    Reg "Price>MA20>MA50" ($priceAboveMA[20][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_-and$maAboveMA["20_50"][$j]}) ($priceAboveMA[20][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;-not$_-and(-not$maAboveMA["20_50"][$j])})
    Reg "Price>MA20>MA100" ($priceAboveMA[20][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_-and$maAboveMA["20_100"][$j]}) ($priceAboveMA[20][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;-not$_-and(-not$maAboveMA["20_100"][$j])})

    # ===== MA crossover (event-based) =====
    Reg "MA20x50 crossover" ($macrossUp[$si..($c.Count-1)]) ($macrossDn[$si..($c.Count-1)])

    # ===== ADX trend strength =====
    Reg "ADX>25 + DI direction" ($adxAbove[25][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $plusDIPos[$j]}) ($adxAbove[25][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $minusDIPos[$j]})
    Reg "ADX>30 + DI direction" ($adxAbove[30][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $plusDIPos[$j]}) ($adxAbove[30][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $minusDIPos[$j]})
    Reg "ADX>25 (any dir)" ($adxAbove[25][$si..($c.Count-1)]) ($adxAbove[25][$si..($c.Count-1)])

    # ===== StochRSI strategies =====
    Reg "Stoch<20 (oversold)" ($stochBelow[20][$si..($c.Count-1)]) ($stochAbove[20][$si..($c.Count-1)])
    Reg "Stoch<30 (oversold)" ($stochBelow[30][$si..($c.Count-1)]) ($stochAbove[30][$si..($c.Count-1)])
    Reg "Stoch<40 (oversold)" ($stochBelow[40][$si..($c.Count-1)]) ($stochAbove[40][$si..($c.Count-1)])
    Reg "Stoch crossover 20/80" ($stochCrossL[$si..($c.Count-1)]) ($stochCrossS[$si..($c.Count-1)])

    # ===== ATR breakout =====
    Reg "ATR>1.5x range up/dn" ($atrHigh[$si..($c.Count-1)]) ($atrLow[$si..($c.Count-1)])

    # ===== Multi-indicator combos (non-RSI) =====
    Reg "Vol(1.5)+ADX(25)+MA20dir" ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $adxAbove[25][$j] -and $priceAboveMA[20][$j]}) ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $adxAbove[25][$j] -and (-not$priceAboveMA[20][$j])})
    Reg "Vol(1.5)+MA20>MA50" ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $maAboveMA["20_50"][$j]}) ($volAboveAvg[1.5][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and (-not$maAboveMA["20_50"][$j])})
    Reg "Stoch<30+ADX(25)" ($stochBelow[30][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $adxAbove[25][$j]}) ($stochAbove[30][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $adxAbove[25][$j]})
    Reg "Vol(2.0)+ATRhigh (breakout)" ($volAboveAvg[2.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $atrHigh[$j]}) ($volAboveAvg[2.0][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $atrLow[$j]})
    Reg "MA20>MA50+ADX(25)+Vol(1.5)" ($maAboveMA["20_50"][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;$_ -and $adxAbove[25][$j] -and $volAboveAvg[1.5][$j]}) ($maAboveMA["20_50"][$si..($c.Count-1)]|%{$j=$si+$foreach.Index;(-not$_) -and $adxAbove[25][$j] -and $volAboveAvg[1.5][$j]})
}

# Phase 2: Overall ranking
Write-Output "`n`n================================================================"
Write-Output "  OVERALL RANKING"
Write-Output "================================================================"

# Rank by score (WR * sigs), min 3 sigs
$valid = $allStrategies | Where-Object { $_.sigs -ge 3 } | Sort-Object { $_.wr * $_.sigs } -Descending
Write-Output "`nTop 20 by Score (WR * sigs):"
$valid | Select-Object -First 20 | Format-Table tf, name, wr, sigs -AutoSize

# Also rank by raw WR (min 10 sigs)
$valid10 = $allStrategies | Where-Object { $_.sigs -ge 10 } | Sort-Object wr -Descending
Write-Output "`nTop 10 by WR (min 10 sigs):"
$valid10 | Select-Object -First 10 | Format-Table tf, name, wr, sigs, lw, ll, sw, sl -AutoSize

# Pick top 3 candidates for deeper analysis
$topCandidates = $valid | Select-Object -First 5
Write-Output "`nTop 5 candidates for deeper analysis:"
$topCandidates | Format-Table tf, name, wr, sigs -AutoSize
$topNames = $topCandidates | % { "$($_.tf) $($_.name)" }
Write-Output ($topNames -join "`n")

# Phase 3: TP/SL for top candidates
Write-Output "`n--- PHASE 3: TP/SL FOR TOP CANDIDATES ---"
$tps=@(0.5,1.0,1.5,2.0,2.5,3.0,4.0,5.0,6.0,8.0);$sls=@(0.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0,5.0)
$tpResults=@()

foreach($cand in $topCandidates){
    $tf=$cand.tf;$k=$kc[$tf];if(-not$k){continue}
    $c=$k|%{[double]$_[4]};$h=$k|%{[double]$_[2]};$l=$k|%{[double]$_[3]};$v=$k|%{[double]$_[5]}

    Write-Output "`n>>> $($cand.tf) $($cand.name) <<<"

    $sigData=$script:strategySignals["$($cand.tf)|$($cand.name)"]
    $le=@();$se=@()
    if($sigData){
        $si2=$sigData.si
        for($i=0;$i-lt$sigData.l.Count;$i++){
            $j=$si2+$i
            if($j-ge$c.Count-5){break}
            if($sigData.l[$i]){$le+=@{idx=$j;price=$c[$j]}}
            if($sigData.s[$i]){$se+=@{idx=$j;price=$c[$j]}}
        }
    }
    Write-Output "  $($le.Count) long, $($se.Count) short entries"

    foreach($tp in $tps){foreach($sl in $sls){
        $tw=0;$tl=0;$pPnl=0;$tT=0
        foreach($e in $le){$tpT=$e.price*(1+$tp/100);$slT=$e.price*(1-$sl/100);$hit=$null;for($j=$e.idx+1;$j-lt[Math]::Min($e.idx+48,$c.Count);$j++){if($h[$j]-ge$tpT){$hit="TP";break};if($l[$j]-le$slT){$hit="SL";break}};if($hit-eq"TP"){$tw++;$pPnl+=$tp}elseif($hit-eq"SL"){$tl++;$pPnl-=$sl};$tT++}
        foreach($e in $se){$tpT=$e.price*(1-$tp/100);$slT=$e.price*(1+$sl/100);$hit=$null;for($j=$e.idx+1;$j-lt[Math]::Min($e.idx+48,$c.Count);$j++){if($l[$j]-le$tpT){$hit="TP";break};if($h[$j]-ge$slT){$hit="SL";break}};if($hit-eq"TP"){$tw++;$pPnl+=$tp}elseif($hit-eq"SL"){$tl++;$pPnl-=$sl};$tT++}
        if($tT-ge3){$wr2=[Math]::Round($tw/$tT*100,1);$score=$wr2*$tT/100;$tpResults+=[PSCustomObject]@{TF=$cand.tf;Name=$cand.name;TP=$tp;SL=$sl;WR=$wr2;T=$tT;PnL=[Math]::Round($pPnl,2);S=[Math]::Round($score,1)}}
    }}
    Write-Output "  Best 1:1 R:R:"
    $tpResults|?{$_.TF-eq$cand.tf-and$_.Name-eq$cand.name-and$_.TP-ge$_.SL}|Sort-Object S -Descending|Select-Object -First 2|%{Write-Output "    TP=$($_.TP)% SL=$($_.SL)% | WR=$($_.WR)% | $($_.T)t | PnL=$($_.PnL)%"}
}

# Phase 4: 3-month simulation for best overall
Write-Output "`n--- PHASE 4: 3-MONTH SIMULATION (BEST OVERALL) ---"
$bestOverall = $tpResults | Where-Object { $_.TP -ge $_.SL } | Sort-Object S -Descending | Select-Object -First 1
if($bestOverall){
    Write-Output "  Best overall config: $($bestOverall.TF) $($bestOverall.Name) TP=$($bestOverall.TP)% SL=$($bestOverall.SL)%"
    $tf=$bestOverall.TF;$k=$kc[$tf];$c=$k|%{[double]$_[4]};$h=$k|%{[double]$_[2]};$l=$k|%{[double]$_[3]};$v=$k|%{[double]$_[5]};$ts=$k|%{[long]$_[0]}
    $vma=Calc-EMA $v 20

    $sigData=$script:strategySignals["$($bestOverall.TF)|$($bestOverall.Name)"]
    $startDt=[DateTimeOffset]::new(2026,3,12,0,0,0,[TimeSpan]::Zero);$startMs=$startDt.ToUnixTimeMilliseconds()
    $sIdx=0;for($i=0;$i-lt$ts.Count;$i++){if($ts[$i]-ge$startMs){$sIdx=$i;break}}
    $capital=100.0;$wins=0;$losses=0;$tT=0;$log=@()

    for($i=[Math]::Max($sIdx,200);$i-lt$c.Count-48;$i++){
        $sigIdx=$i-$sigData.si;if($sigIdx-lt0-or$sigIdx-ge$sigData.l.Count){continue}
        if(-not($sigData.l[$sigIdx]-or$sigData.s[$sigIdx])){continue}
        $dt=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i])
        $entry=$c[$i];$tpPrice=$entry*(1+$bestOverall.TP/100);$slPrice=$entry*(1-$bestOverall.SL/100);$hit=$null
        for($j=$i+1;$j-lt[Math]::Min($i+48,$c.Count);$j++){if($h[$j]-ge$tpPrice){$hit="TP";break};if($l[$j]-le$slPrice){$hit="SL";break}}
        $units=$capital/$entry;$pnl=0
        if($hit-eq"TP"){$pnl=$units*($entry*$bestOverall.TP/100)-($units*$entry*0.1/100);$wins++}else{$pnl=-$units*($entry*$bestOverall.SL/100)-($units*$entry*0.1/100);$losses++}
        $tT++;$capital+=$pnl;$log+=[PSCustomObject]@{D=$dt.ToString('MM-dd');P=[Math]::Round($entry,4);R=if($hit-eq"TP"){"TP"}else{"SL"};Pnl=[Math]::Round($pnl,4);Cap=[Math]::Round($capital,2)}
    }
    $wr3=if($tT){[Math]::Round($wins/$tT*100,1)}else{0};$ret=[Math]::Round(($capital-100)/100*100,2)
    Write-Output "  Trades: $tT ($wins W / $losses L) | WR: $wr3% | Return: $ret%"
    $log|Format-Table -AutoSize
}

# Phase 5: Live signal for best
Write-Output "`n--- LIVE SIGNAL ---"
if($bestOverall){
    $tf=$bestOverall.TF;$k=$kc[$tf];$c=$k|%{[double]$_[4]};$ts=$k|%{[long]$_[0]}
    $lp=$c[-1];$ldt=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1]);$sigData=$script:strategySignals["$tf|$($bestOverall.Name)"]
    Write-Output "  $tf @ $($ldt.ToString('MM-dd HH:mm')) UTC | $($bestOverall.Name)"
    Write-Output "  Price=$([Math]::Round($lp,4))"
    if($sigData){
        $li=$sigData.l.Count-1;if($sigData.l[$li]){Write-Output "  >>> LONG <<<"
        elseif($sigData.s[$li]){Write-Output "  >>> SHORT <<<"
        else{Write-Output "  No signal"}
    }
}

Write-Output "`n=== FULL GRID COMPLETE ==="
