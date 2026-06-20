function Read-DerLength($d, [ref]$o) {
    if ($d[$o.Value] -lt 0x80) { $l = $d[$o.Value]; $o.Value++; return $l }
    $n = $d[$o.Value] -band 0x7F; $o.Value++
    $len = 0; for ($i = 0; $i -lt $n; $i++) { $len = ($len -shl 8) -bor $d[$o.Value]; $o.Value++ }
    return $len
}
function Read-DerInteger($d, [ref]$o) {
    if ($d[$o.Value] -ne 0x02) { throw "bad" }; $o.Value++
    $l = Read-DerLength $d $o
    $v = [byte[]]::new($l); [Array]::Copy($d, $o.Value, $v, 0, $l)
    $s = if ($v.Length -gt 1 -and $v[0] -eq 0) {1} else {0}
    $t = [byte[]]::new($v.Length - $s); [Array]::Copy($v, $s, $t, 0, $t.Length)
    $o.Value += $l; return $t
}

$pem = [System.IO.File]::ReadAllText("bybit_private.pem")
$b64 = ($pem -replace '-----[A-Z ]+-----', '') -replace '\s', ''
$der = [System.Convert]::FromBase64String($b64)
$o = 0
if ($der[$o] -ne 0x30) { throw "bad der" }; $o++
$seqLen = Read-DerLength $der ([ref]$o)

$rsaP = New-Object System.Security.Cryptography.RSAParameters
$v = Read-DerInteger $der ([ref]$o)
$rsaP.Modulus = Read-DerInteger $der ([ref]$o)
$rsaP.Exponent = Read-DerInteger $der ([ref]$o)
$rsaP.D = Read-DerInteger $der ([ref]$o)
$rsaP.P = Read-DerInteger $der ([ref]$o)
$rsaP.Q = Read-DerInteger $der ([ref]$o)
$rsaP.DP = Read-DerInteger $der ([ref]$o)
$rsaP.DQ = Read-DerInteger $der ([ref]$o)
$rsaP.InverseQ = Read-DerInteger $der ([ref]$o)

$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($rsaP)

$ak = "gkPx5g3xgL2pthIg16"
$rw = "5000"
$ts = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$ps = "${ts}${ak}${rw}accountType=UNIFIED"
$sb = [System.Text.Encoding]::UTF8.GetBytes($ps)
$hasher = [System.Security.Cryptography.SHA256]::Create()
$sigBytes = $rsa.SignData($sb, $hasher)
$sg = [System.Convert]::ToBase64String($sigBytes)

$h = @{
    "X-BAPI-API-KEY" = $ak
    "X-BAPI-TIMESTAMP" = "$ts"
    "X-BAPI-SIGN" = $sg
    "X-BAPI-RECV-WINDOW" = $rw
    "X-BAPI-SIGN-TYPE" = "2"
    "User-Agent" = "bybit-skill/1.4.2"
    "X-Referer" = "bybit-skill"
}

Write-Output "=== Response Headers ==="
$resp = Invoke-WebRequest -Uri "https://api.bybit.com/v5/account/wallet-balance?accountType=UNIFIED" -Headers $h -UseBasicParsing -TimeoutSec 15
foreach ($key in $resp.Headers.Keys) {
    Write-Output "$key : $($resp.Headers[$key])"
}

Write-Output "`n=== Response Body ==="
$resp.Content | ConvertFrom-Json | ConvertTo-Json -Depth 5
