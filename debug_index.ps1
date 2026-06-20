function Read-DerLength($d,[ref]$o){if($d[$o.Value]-lt0x80){$l=$d[$o.Value];$o.Value++;return $l}$n=$d[$o.Value]-band0x7F;$o.Value++;$l=0;for($i=0;$i-lt$n;$i++){$l=($l-shl8)-bor$d[$o.Value];$o.Value++}return $l}
function Read-DerInteger($d,[ref]$o){if($d[$o.Value]-ne0x02){throw"bad"}$o.Value++;$l=Read-DerLength $d $o;$v=[byte[]]::new($l);[Array]::Copy($d,$o.Value,$v,0,$l);$s=if($v.Length-gt1-and$v[0]-eq0){1}else{0};$t=[byte[]]::new($v.Length-$s);[Array]::Copy($v,$s,$t,0,$t.Length);$o.Value+=$l;return $t}
$pem=[System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH);$b64=($pem-replace'-----[A-Z ]+-----','')-replace'\s','';$der=[System.Convert]::FromBase64String($b64);$o=0;if($der[$o]-ne0x30){throw"bad"};$o++;Read-DerLength $der([ref]$o)|Out-Null
$rs=New-Object System.Security.Cryptography.RSAParameters;Read-DerInteger $der([ref]$o)|Out-Null
$rs.Modulus=Read-DerInteger $der([ref]$o);$rs.Exponent=Read-DerInteger $der([ref]$o);$rs.D=Read-DerInteger $der([ref]$o);$rs.P=Read-DerInteger $der([ref]$o);$rs.Q=Read-DerInteger $der([ref]$o);$rs.DP=Read-DerInteger $der([ref]$o);$rs.DQ=Read-DerInteger $der([ref]$o);$rs.InverseQ=Read-DerInteger $der([ref]$o)
$r=New-Object System.Security.Cryptography.RSACryptoServiceProvider;$r.ImportParameters($rs);$ak=$env:BYBIT_API_KEY;$rw="5000"
$ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$q="category=spot&symbol=SOLUSDT&interval=240&limit=5";$ps="${ts}${ak}${rw}${q}"
$b=[Text.Encoding]::UTF8.GetBytes($ps);$h=[Security.Cryptography.SHA256]::Create();$sg=[Convert]::ToBase64String($r.SignData($b,$h))
$hd=@{"X-BAPI-API-KEY"=$ak;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
$resp=Invoke-WebRequest -Uri "https://api.bybit.com/v5/market/kline?$q" -Headers $hd -UseBasicParsing -TimeoutSec 10; $r=($resp.Content|ConvertFrom-Json).result.list
Write-Output "Bybit returns candles newest-first (index 0 = most recent)"
Write-Output ""
Write-Output "Most recent 5 candles (4h):"
$r | Select-Object -First 5 | ForEach-Object {
    $dt=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$_[0]).DateTime.ToString("MM-dd HH:mm")
    Write-Output "  $dt | O:$($_[1]) H:$($_[2]) L:$($_[3]) C:$($_[4]) V:$($_[5])"
}
Write-Output ""
Write-Output "IMPORTANT: Latest close = index 0 = $($r[0][4])"
Write-Output "Oldest of the 5 = index 4 = $($r[4][4])"
Write-Output ""
Write-Output "Current live ticker:"
$q2="category=spot&symbol=SOLUSDT";$ps2="${ts}${ak}${rw}${q2}";$b2=[Text.Encoding]::UTF8.GetBytes($ps2);$sg2=[Convert]::ToBase64String($r.SignData($b2,$h))
$hd2=@{"X-BAPI-API-KEY"=$ak;"X-BAPI-TIMESTAMP"="$ts";"X-BAPI-SIGN"=$sg2;"X-BAPI-RECV-WINDOW"=$rw;"X-BAPI-SIGN-TYPE"="2";"User-Agent"="bybit-skill/1.4.2"}
$resp2=Invoke-WebRequest -Uri "https://api.bybit.com/v5/market/tickers?$q2" -Headers $hd2 -UseBasicParsing -TimeoutSec 10; $t=($resp2.Content|ConvertFrom-Json).result.list[0]
Write-Output "  Last: $($t.lastPrice) | Bid: $($t.bid1Price) Ask: $($t.ask1Price)"
