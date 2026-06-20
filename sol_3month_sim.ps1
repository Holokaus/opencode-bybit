function Read-DerLength { param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) { $len = $data[$offset.Value]; $offset.Value++; return $len }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0; for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }; return $len
}
function Read-DerInteger { param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw "bad" }; $offset.Value++
    $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len); [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start); [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len; return $trimmed
}
$pem = [System.IO.File]::ReadAllText("bybit_private.pem")
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0; if ($der[$off] -ne 0x30) { throw "bad" }; $off++
Read-DerLength -data $der -offset ([ref]$off) | Out-Null
$params = New-Object System.Security.Cryptography.RSAParameters
Read-DerInteger -data $der -offset ([ref]$off) | Out-Null
$params.Modulus = Read-DerInteger -data $der -offset ([ref]$off)
$params.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
$params.D = Read-DerInteger -data $der -offset ([ref]$off)
$params.P = Read-DerInteger -data $der -offset ([ref]$off)
$params.Q = Read-DerInteger -data $der -offset ([ref]$off)
$params.DP = Read-DerInteger -data $der -offset ([ref]$off)
$params.DQ = Read-DerInteger -data $der -offset ([ref]$off)
$params.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider; $rsa.ImportParameters($params)
$apiKey = "gkPx5g3xgL2pthIg16"; $recvWindow = "5000"
function Call-API { param($endpoint, $query)
    $t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $b = [Text.Encoding]::UTF8.GetBytes("${t}${apiKey}${recvWindow}${query}")
    $h = [Security.Cryptography.SHA256]::Create()
    $s = [Convert]::ToBase64String($rsa.SignData($b, $h))
    $hd = @{ "X-BAPI-API-KEY" = $apiKey; "X-BAPI-TIMESTAMP" = "$t"; "X-BAPI-SIGN" = $s; "X-BAPI-RECV-WINDOW" = $recvWindow; "X-BAPI-SIGN-TYPE" = "2"; "User-Agent" = "bybit-skill/1.4.2" }
    try { $r = Invoke-WebRequest -Uri "https://api.bybit.com$endpoint`?$query" -Headers $hd -UseBasicParsing -TimeoutSec 60; return ($r.Content | ConvertFrom-Json) } catch { return $null }
}
function Get-K { param($int, $lim)
    $r = Call-API -endpoint "/v5/market/kline" -query "category=spot&symbol=SOLUSDT&interval=$int&limit=$lim"
    if ($r -and $r.result -and $r.result.list) { $k = $r.result.list; [Array]::Reverse($k); return $k } else { return $null }
}
function Calc-RSI { param($p, $per)
    $g=[double[]]::new($p.Count); $l=[double[]]::new($p.Count)
    for ($i=1; $i -lt $p.Count; $i++) { $d=$p[$i]-$p[$i-1]; if ($d -ge 0) { $g[$i]=$d } else { $l[$i]=-$d } }
    $ag=($g[1..$per] | Measure-Object -Sum).Sum / $per; $al=($l[1..$per] | Measure-Object -Sum).Sum / $per
    $r=[double[]]::new($p.Count)
    for ($i=$per; $i -lt $p.Count; $i++) {
        if ($i -gt $per) { $ag=(($ag*($per-1))+$g[$i])/$per; $al=(($al*($per-1))+$l[$i])/$per }
        $r[$i]=if ($al -eq 0) { 100 } else { 100 - (100 / (1 + ($ag/$al))) }
    }
    return $r
}
function Calc-EMA { param($p, $per)
    $e=[double[]]::new($p.Count); $e[0]=$p[0]; $m=2/($per+1)
    for ($i=1; $i -lt $p.Count; $i++) { $e[$i]=$p[$i]*$m + $e[$i-1]*(1-$m) }
    return $e
}

Write-Host "=== 3-MONTH SIMULATION: LONG ONLY ===" -ForegroundColor Cyan
Write-Host "Start: 100 USD | 2h RSI(38) OS=36 | TP=0.5% SL=0.5% | No Sat/Jan/Loss-skip" -ForegroundColor Cyan

$per=38;$ob=60;$os=36;$int="120";$tp=0.5;$sl=0.5;$comm=0.1
$klines=Get-K $int 1000
if (-not $klines) { Write-Output "No data"; exit 1 }
$close=$klines|%{[double]$_[4]};$high=$klines|%{[double]$_[2]};$low=$klines|%{[double]$_[3]};$vol=$klines|%{[double]$_[5]};$ts=$klines|%{[long]$_[0]}

$rsi=Calc-RSI $close $per;$vma=Calc-EMA $vol 20

# Find 3 months back
$startDt=[DateTimeOffset]::new(2026,3,11,0,0,0,[TimeSpan]::Zero)
$startMs=$startDt.ToUnixTimeMilliseconds()
$si=0;for($i=0;$i-lt$ts.Count;$i++){if($ts[$i]-ge$startMs){$si=$i;break}}
Write-Output "Range: $($startDt.ToString('yyyy-MM-dd')) to $([DateTimeOffset]::FromUnixTimeMilliseconds($ts[-1]).ToString('yyyy-MM-dd'))"
Write-Output "Candles: $($close.Count), Start index: $si"

$cap=100.0;$w=0;$l=0;$tt=0;$log=@()
for ($i=[Math]::Max($si,$per+20); $i -lt $close.Count-5; $i++) {
    $isL=$rsi[$i-1]-gt$os-and$rsi[$i]-le$os-and$rsi[$i]-ne0-and$vol[$i]-gt$vma[$i]*0.8
    if (-not $isL) { continue }
    $dt=[DateTimeOffset]::FromUnixTimeMilliseconds($ts[$i])
    $ep=$close[$i];$tpP=$ep*1.005;$slP=$ep*0.995;$hit=$null
    for ($j=$i+1; $j -lt [Math]::Min($i+48, $close.Count); $j++) { if ($high[$j] -ge $tpP) { $hit="TP"; break }; if ($low[$j] -le $slP) { $hit="SL"; break } }
    $pnl=0
    if ($hit -eq "TP") { $pnl=($ep*$tp/100)-($ep*$comm/100); $w++ }
    elseif ($hit -eq "SL") { $pnl=-($ep*$sl/100)-($ep*$comm/100); $l++ }
    else { $pnl=-($ep*$sl/100)-($ep*$comm/100); $l++ }
    $tt++;$cap+=$pnl
    if ($tt -le 3 -or $tt % 2 -eq 0 -or $i -ge $close.Count-6) {
        $log+=[PSCustomObject]@{D=$dt.ToString('MM-dd');P=[Math]::Round($ep,2);R=$hit;Pnl=[Math]::Round($pnl,4);Cap=[Math]::Round($cap,2)}
    }
}
$wr=if($tt){[Math]::Round($w/$tt*100,1)}else{0}
Write-Output "`nTrades: $tt ($w W / $l L) | WR: $wr%"
Write-Output "Total PnL: $([Math]::Round($cap-100,2)) | Final: $([Math]::Round($cap,2)) | Return: $([Math]::Round(($cap-100)/100*100,2))%"
Write-Output "`nLog:"
$log|Format-Table -AutoSize
