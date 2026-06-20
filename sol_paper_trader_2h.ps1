function Write-Log { param($m) Write-Output $m }
function Read-DerLength { param([byte[]]$d,[ref]$o) if($d[$o.Value]-lt0x80){$l=$d[$o.Value];$o.Value++;return $l} $n=$d[$o.Value]-band0x7F;$o.Value++;$len=0;for($i=0;$i-lt$n;$i++){$len=($len-shl8)-bor$d[$o.Value];$o.Value++};return $len }
function Read-DerInteger { param([byte[]]$d,[ref]$o) if($d[$o.Value]-ne0x02){throw};$o.Value++;$l=Read-DerLength -d $d -o $o;$v=[byte[]]::new($l);[Array]::Copy($d,$o.Value,$v,0,$l);$s=if($v.Length-gt1-and$v[0]-eq0){1}else{0};$t=[byte[]]::new($v.Length-$s);[Array]::Copy($v,$s,$t,0,$t.Length);$o.Value+=$l;return $t }
$pem=[System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH);$b64=($pem-replace'-----.+-----',''-replace'\s','');$der=[System.Convert]::FromBase64String($b64);$off=0;if($der[$off]-ne0x30){throw};$off++
Read-DerLength -d $der -o ([ref]$off)|Out-Null;$p=New-Object System.Security.Cryptography.RSAParameters;Read-DerInteger -d $der -o ([ref]$off)|Out-Null
$p.Modulus=Read-DerInteger -d $der -o ([ref]$off);$p.Exponent=Read-DerInteger -d $der -o ([ref]$off);$p.D=Read-DerInteger -d $der -o ([ref]$off);$p.P=Read-DerInteger -d $der -o ([ref]$off);$p.Q=Read-DerInteger -d $der -o ([ref]$off);$p.DP=Read-DerInteger -d $der -o ([ref]$off);$p.DQ=Read-DerInteger -d $der -o ([ref]$off);$p.InverseQ=Read-DerInteger -d $der -o ([ref]$off)
$rsa=New-Object System.Security.Cryptography.RSACryptoServiceProvider;$rsa.ImportParameters($p)
$ak=$env:BYBIT_API_KEY;$rw="5000"
function Call-API { param($ep,$q) $ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$b=[Text.Encoding]::UTF8.GetBytes("$ts$ak$rw$q");$h=[Security.Cryptography.SHA256]::Create();$sg=[Convert]::ToBase64String($rsa.SignData($b,$h));$hd=@{"X-BAPI-API-KEY"=$ak;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"};try{$r=Invoke-WebRequest -Uri "https://api.bybit.com$ep`?$q" -Headers $hd -UseBasicParsing -TimeoutSec 60;return($r.Content|ConvertFrom-Json)}catch{return $null} }
function Get-K { param($int,$lim) $r=Call-API -ep "/v5/market/kline" -q "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim";if($r-and$r.result-and$r.result.list){$k=$r.result.list;[Array]::Reverse($k);return $k}else{return $null} }
function Calc-RSI { param($p,$per) $g=[double[]]::new($p.Count);$l=[double[]]::new($p.Count);for($i=1;$i-lt$p.Count;$i++){$d=$p[$i]-$p[$i-1];if($d-ge0){$g[$i]=$d}else{$l[$i]=-$d}};$ag=($g[1..$per]|Measure-Object -Sum).Sum/$per;$al=($l[1..$per]|Measure-Object -Sum).Sum/$per;$r=[double[]]::new($p.Count);for($i=$per;$i-lt$p.Count;$i++){if($i-gt$per){$ag=(($ag*($per-1))+$g[$i])/$per;$al=(($al*($per-1))+$l[$i])/$per};if($al-eq0){$r[$i]=100}else{$r[$i]=100-(100/(1+($ag/$al)))}};return $r }
function Calc-EMA { param($p,$per) $e=[double[]]::new($p.Count);$e[0]=$p[0];$m=2/($per+1);for($i=1;$i-lt$p.Count;$i++){$e[$i]=$p[$i]*$m+$e[$i-1]*(1-$m)};return $e }

Write-Host "SOL PAPER TRADER - 2h RSI(38)+Volume" -ForegroundColor Cyan
$per=38;$ob=60;$os=36;$int="120";$nowDt=Get-Date
$klines=Get-K $int 500;if(-not$klines){Write-Host "FAILED" -ForegroundColor Red;exit 1}
$close=$klines|%{[double]$_[4]};$vol=$klines|%{[double]$_[5]};$ts=$klines|%{[long]$_[0]}
$rsi=Calc-RSI $close $per;$vma=Calc-EMA $vol 20
$lr=$rsi[-1];$pr=$rsi[-2];$cp=$close[-1];$lt=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1])
$lastV=[Math]::Round($vol[-1],0);$lastM=[Math]::Round($vma[-1],0)
$isL=($pr-gt$os-and$lr-le$os-and$lr-ne0);$isS=($pr-lt$ob-and$lr-ge$ob-and$lr-ne100);$vOk=($vol[-1]-gt$vma[-1]*0.8)
$candleStr=$lt.ToString("MM-dd HH:mm");$dowStr=$lt.DayOfWeek.ToString();$monStr=$lt.ToString("MMM")
Write-Output "  Time: $candleStr UTC | $dowStr $monStr"
Write-Output "  Price: $([Math]::Round($cp,4)) | RSI($per): $([Math]::Round($lr,1)) (prev $([Math]::Round($pr,1)))"
Write-Output "  OB=$ob OS=$os | Vol: $lastV vs MA20: $lastM"
$sig=$null;$dir=$null
if($isL-and$vOk){$sig="LONG";$dir="BUY"}elseif($isS-and$vOk){$sig="SHORT";$dir="SELL"}
if($sig){
    Write-Host "  [>>] $dir $sig SIGNAL" -ForegroundColor Green
    $tpP=if($dir-eq"BUY"){$cp*1.005}else{$cp*0.995};$slP=if($dir-eq"BUY"){$cp*0.995}else{$cp*1.005}
    Write-Output "  Entry: $([Math]::Round($cp,4)) TP: $([Math]::Round($tpP,4)) SL: $([Math]::Round($slP,4))"
    $tsStr=Get-Date -Format "yyyy-MM-dd HH:mm";$rStr=[Math]::Round($lr,1);$vStr=[Math]::Round($vol[-1],0)
    Add-Content -Path "paper_trading_log.txt" -Value "[$tsStr] SIGNAL $sig @ $cp RSI=$rStr TF=2h Vol=$vStr"
}else{
    Write-Output "  No signal (RSI=$([Math]::Round($lr,1)) between $os-$ob)"
    if($isL-and!$vOk){$vp=[Math]::Round($vol[-1]/$vma[-1]*100,0);Write-Output "  (OS cross, vol $vp pct of MA)"}
    if($isS-and!$vOk){Write-Output "  (OB cross, vol low)"}
}
Write-Output "  Dist to OS: $([Math]::Round($lr-$os,1)) | to OB: $([Math]::Round($ob-$lr,1))"
