function Read-DerLength {
    param([byte[]]$d,[ref]$o)
    if($d[$o.Value]-lt0x80){$l=$d[$o.Value];$o.Value++;return $l}
    $n=$d[$o.Value]-band0x7F;$o.Value++;$len=0
    for($i=0;$i-lt$n;$i++){$len=($len-shl8)-bor$d[$o.Value];$o.Value++}
    return $len
}
function Read-DerInteger {
    param([byte[]]$d,[ref]$o)
    if($d[$o.Value]-ne0x02){throw}
    $o.Value++;$l=Read-DerLength $d $o
    $v=[byte[]]::new($l);[Array]::Copy($d,$o.Value,$v,0,$l)
    $s=if($v.Length-gt1-and$v[0]-eq0){1}else{0}
    $t=[byte[]]::new($v.Length-$s);[Array]::Copy($v,$s,$t,0,$t.Length)
    $o.Value+=$l;return $t
}
$pem=[System.IO.File]::ReadAllText("bybit_private.pem")
$b64=($pem-replace'-----.+-----',''-replace'\s','')
$der=[System.Convert]::FromBase64String($b64);$off=0
if($der[$off]-ne0x30){throw};$off++
Read-DerLength $der ([ref]$off) | Out-Null
$p = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger $der ([ref]$off) | Out-Null
$p.Modulus = Read-DerInteger $der ([ref]$off)
$p.Exponent = Read-DerInteger $der ([ref]$off)
$p.D = Read-DerInteger $der ([ref]$off)
$p.P = Read-DerInteger $der ([ref]$off)
$p.Q = Read-DerInteger $der ([ref]$off)
$p.DP = Read-DerInteger $der ([ref]$off)
$p.DQ = Read-DerInteger $der ([ref]$off)
$p.InverseQ = Read-DerInteger $der ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($p)
$ak="gkPx5g3xgL2pthIg16";$rw="5000"
function Call-API {
    param($ep,$q)
    $ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b=[Text.Encoding]::UTF8.GetBytes("$ts$ak$rw$q")
    $h=[Security.Cryptography.SHA256]::Create()
    $sg=[Convert]::ToBase64String($rsa.SignData($b,$h))
    $hd=@{"X-BAPI-API-KEY"=$ak;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
    try{$r=Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 60;return($r.Content|ConvertFrom-Json)}catch{return $null}
}
function Get-K {
    param($int,$lim)
    $r=Call-API -ep "/v5/market/kline" -q "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if($r-and$r.result-and$r.result.list){$k=$r.result.list;[Array]::Reverse($k);return $k}else{return $null}
}
function Calc-RSI {
    param($p,$per)
    $g=[double[]]::new($p.Count);$l=[double[]]::new($p.Count)
    for($i=1;$i-lt$p.Count;$i++){$d=$p[$i]-$p[$i-1];if($d-ge0){$g[$i]=$d}else{$l[$i]=-$d}}
    $ag=($g[1..$per]|Measure-Object -Sum).Sum/$per;$al=($l[1..$per]|Measure-Object -Sum).Sum/$per
    $r=[double[]]::new($p.Count)
    for($i=$per;$i-lt$p.Count;$i++){
        if($i-gt$per){$ag=(($ag*($per-1))+$g[$i])/$per;$al=(($al*($per-1))+$l[$i])/$per}
        if($al-eq0){$r[$i]=100}else{$r[$i]=100-(100/(1+($ag/$al)))}
    }
    return $r
}
function Calc-EMA {
    param($p,$per)
    $e=[double[]]::new($p.Count);$e[0]=$p[0];$m=2/($per+1)
    for($i=1;$i-lt$p.Count;$i++){$e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m)}
    return $e
}

Write-Host "=== TRADINGVIEW BACKTEST (exact) ON BYBIT 2h DATA ===" -ForegroundColor Cyan
$per=38;$ob=60;$os=36;$int="120";$tp=0.5;$sl=0.5;$comm=0.1
$klines=Get-K $int 999;if(-not$klines){Write-Output "No data";exit 1}
$close=$klines|%{[double]$_[4]};$high=$klines|%{[double]$_[2]};$low=$klines|%{[double]$_[3]};$vol=$klines|%{[double]$_[5]};$ts=$klines|%{[long]$_[0]}
$rsi=Calc-RSI $close $per;$vma=Calc-EMA $vol 20
$entries=@()
for($i=$per+20;$i-lt$close.Count-5;$i++){
    $isL=$rsi[$i-1]-gt$os-and$rsi[$i]-le$os-and$rsi[$i]-ne0-and$vol[$i]-gt$vma[$i]*0.8
    $isS=$rsi[$i-1]-lt$ob-and$rsi[$i]-ge$ob-and$rsi[$i]-ne100-and$vol[$i]-gt$vma[$i]*0.8
    if($isL){$entries+=@{i=$i;dir="LONG";p=$close[$i];ts=$ts[$i]}}
    if($isS){$entries+=@{i=$i;dir="SHORT";p=$close[$i];ts=$ts[$i]}}
}
Write-Output "Entries: $($entries.Count)"
if($entries.Count-eq0){Write-Output "No entries found";exit 0}
$dates=$entries|%{[DateTimeOffset]::FromUnixTimeMilliseconds($_.ts)}
$first=$dates[0].ToString('yyyy-MM-dd');$last=$dates[-1].ToString('yyyy-MM-dd')
Write-Output "Period: $first to $last"

$wins=0;$losses=0;$pnl=0
foreach($e in $entries){
    $ep=$e.p
    if($e.dir-eq"LONG"){$tpP=$ep*1.005;$slP=$ep*0.995}else{$tpP=$ep*0.995;$slP=$ep*1.005}
    $hit=$null
    for($j=$e.i+1;$j-lt[Math]::Min($e.i+48,$close.Count);$j++){
        if($e.dir-eq"LONG"){if($high[$j]-ge$tpP){$hit="TP";break};if($low[$j]-le$slP){$hit="SL";break}}
        else{if($low[$j]-le$tpP){$hit="TP";break};if($high[$j]-ge$slP){$hit="SL";break}}
    }
    if($hit-eq"TP"){$wins++;$pnl+=($ep*$tp/100)-($ep*$comm/100)}
    elseif($hit-eq"SL"){$losses++;$pnl-=($ep*$sl/100)+($ep*$comm/100)}
    else{$losses++}
}
$tt=$wins+$losses;$wr=if($tt){[Math]::Round($wins/$tt*100,1)}else{0}
Write-Output "`nWin Rate: $wr% ($wins W / $losses L)"
Write-Output "Net PnL: $([Math]::Round($pnl,4)) USDT"
Write-Output "Return: $([Math]::Round($pnl/($entries|%{$_.p}|Measure-Object -Average).Average*100,2))% of avg entry"
