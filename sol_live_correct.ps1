function Read-DerLength($d,[ref]$o){if($d[$o.Value]-lt0x80){$l=$d[$o.Value];$o.Value++;return $l}$n=$d[$o.Value]-band0x7F;$o.Value++;$l=0;for($i=0;$i-lt$n;$i++){$l=($l-shl8)-bor$d[$o.Value];$o.Value++}return $l}
function Read-DerInteger($d,[ref]$o){if($d[$o.Value]-ne0x02){throw"bad"}$o.Value++;$l=Read-DerLength $d $o;$v=[byte[]]::new($l);[Array]::Copy($d,$o.Value,$v,0,$l);$s=if($v.Length-gt1-and$v[0]-eq0){1}else{0};$t=[byte[]]::new($v.Length-$s);[Array]::Copy($v,$s,$t,0,$t.Length);$o.Value+=$l;return $t}
$pem=[System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH);$b64=($pem-replace'-----[A-Z ]+-----','')-replace'\s','';$der=[System.Convert]::FromBase64String($b64);$o=0;if($der[$o]-ne0x30){throw"bad"};$o++;Read-DerLength $der([ref]$o)|Out-Null
$rs=New-Object System.Security.Cryptography.RSAParameters;Read-DerInteger $der([ref]$o)|Out-Null
$rs.Modulus=Read-DerInteger $der([ref]$o);$rs.Exponent=Read-DerInteger $der([ref]$o);$rs.D=Read-DerInteger $der([ref]$o);$rs.P=Read-DerInteger $der([ref]$o);$rs.Q=Read-DerInteger $der([ref]$o);$rs.DP=Read-DerInteger $der([ref]$o);$rs.DQ=Read-DerInteger $der([ref]$o);$rs.InverseQ=Read-DerInteger $der([ref]$o)
$rsa=New-Object System.Security.Cryptography.RSACryptoServiceProvider;$rsa.ImportParameters($rs);$ak=$env:BYBIT_API_KEY;$rw="5000"
function Call-API($ep,$q){$ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$ps="${ts}${ak}${rw}${q}";$b=[Text.Encoding]::UTF8.GetBytes($ps);$h=[Security.Cryptography.SHA256]::Create();$sg=[Convert]::ToBase64String($rsa.SignData($b,$h));$hd=@{"X-BAPI-API-KEY"=$ak;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"};try{return (Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 15|ConvertFrom-Json).result}catch{return $null}}
function Get-K($int,$lim){$r=Call-API -ep "/v5/market/kline" -q "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim";if($r-and$r.list){$k=$r.list;[Array]::Reverse($k);return $k}else{return $null}}
function Calc-RSI($p,$per){$g=[double[]]::new($p.Count);$l=[double[]]::new($p.Count);for($i=1;$i-lt$p.Count;$i++){$d=$p[$i]-$p[$i-1];if($d-ge0){$g[$i]=$d}else{$l[$i]=-$d}};$ag=($g[1..$per]|Measure-Object -Sum).Sum/$per;$al=($l[1..$per]|Measure-Object -Sum).Sum/$per;$r=[double[]]::new($p.Count);for($i=$per;$i-lt$p.Count;$i++){if($i-gt$per){$ag=(($ag*($per-1))+$g[$i])/$per;$al=(($al*($per-1))+$l[$i])/$per};$r[$i]=if($al-eq0){100}else{100-(100/(1+($ag/$al)))}};return $r}
function Calc-EMA($p,$per){$e=[double[]]::new($p.Count);$e[0]=$p[0];$m=2/($per+1);for($i=1;$i-lt$p.Count;$i++){$e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m)};return $e}
function Calc-ATR($h,$l,$c,$per){$tr=[double[]]::new($c.Count);for($i=1;$i-lt$c.Count;$i++){$hl=$h[$i]-$l[$i];$hc=[Math]::Abs($h[$i]-$c[$i-1]);$lc=[Math]::Abs($l[$i]-$c[$i-1]);$tr[$i]=[Math]::Max($hl,[Math]::Max($hc,$lc))};$a=[double[]]::new($c.Count);if($c.Count-gt$per){$a[$per]=($tr[1..$per]|Measure-Object -Average).Average;for($i=$per+1;$i-lt$c.Count;$i++){$a[$i]=($a[$i-1]*($per-1)+$tr[$i])/$per}};return $a}

Write-Output "=== VERIFIED: Array reversed (index -1 = newest) ==="

$klines=Get-K "240" 1000
$close=$klines|ForEach-Object{[double]$_[4]};$high=$klines|ForEach-Object{[double]$_[2]};$low=$klines|ForEach-Object{[double]$_[3]};$volume=$klines|ForEach-Object{[double]$_[5]}
$ts=$klines|ForEach-Object{[long]$_[0]}

$rsi=Calc-RSI $close 41
$atr14=Calc-ATR $high $low $close 14
$ma50=Calc-EMA $close 50

$latestDT=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1]).DateTime
Write-Output "Newest candle: $($latestDT.ToString('MM-dd HH:mm')) UTC"
Write-Output "Latest close: $($close[-1])"
Write-Output "Latest RSI(41): $([Math]::Round($rsi[-1],1)) (prev: $([Math]::Round($rsi[-2],1)))"
Write-Output "MA(50): $([Math]::Round($ma50[-1],2))"
Write-Output "ATR(14): $([Math]::Round($atr14[-1],2))"
Write-Output "Price vs MA50: $(if($close[-1]-gt$ma50[-1]){'ABOVE'}else{'BELOW'})"
Write-Output ""

$ob=68;$os=42;$latest=$rsi[-1];$prev=$rsi[-2]
if($prev-gt$os-and$latest-le$os-and$latest-ne0){Write-Output ">>> ACTIVE LONG SIGNAL <<<"}
elseif($prev-lt$ob-and$latest-ge$ob-and$latest-ne100){Write-Output ">>> ACTIVE SHORT SIGNAL <<<"}
elseif($latest-le$os){Write-Output "RSI below OS (oversold zone)"}
elseif($latest-ge$ob){Write-Output "RSI above OB (overbought zone)"}
else{Write-Output "NO SIGNAL. RSI=$([Math]::Round($latest,1)) between $os-$ob";Write-Output "Distance to OS: $([Math]::Round($latest-$os,1)) | to OB: $([Math]::Round($ob-$latest,1))"}
