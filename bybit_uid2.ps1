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

$pem = [System.IO.File]::ReadAllText($env:BYBIT_PRIVATE_KEY_PATH)
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

$ak = $env:BYBIT_API_KEY
$rw = "5000"

function Call-Bybit {
    param($ep, $q)
    $ts = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $ps = "${ts}${ak}${rw}${q}"
    $b = [System.Text.Encoding]::UTF8.GetBytes($ps)
    $h = [System.Security.Cryptography.SHA256]::Create()
    $s = $rsa.SignData($b, $h)
    $sg = [System.Convert]::ToBase64String($s)
    $hd = @{
        "X-BAPI-API-KEY" = $ak; "X-BAPI-TIMESTAMP" = "$ts"; "X-BAPI-SIGN" = $sg
        "X-BAPI-RECV-WINDOW" = $rw; "X-BAPI-SIGN-TYPE" = "2"
        "User-Agent" = "bybit-skill/1.4.2"; "X-Referer" = "bybit-skill"
    }
    try {
        $url = if ($q) { "https://api.bybit.com$ep`?$q" } else { "https://api.bybit.com$ep" }
        $resp = Invoke-WebRequest -Uri $url -Method GET -Headers $hd -UseBasicParsing -TimeoutSec 15
        return $resp.Content | ConvertFrom-Json
    } catch { Write-Output "Error: $_"; return $null }
}

Write-Output "=== 1) query-api ==="
$r = Call-Bybit -ep "/v5/user/query-api" -q ""
$r | ConvertTo-Json -Depth 5

Write-Output "`n=== 2) account/info detail ==="
$r = Call-Bybit -ep "/v5/account/info" -q ""
$r | ConvertTo-Json -Depth 5

Write-Output "`n=== 3) user/query-sub-members ==="
$r = Call-Bybit -ep "/v5/user/query-sub-members" -q ""
$r | ConvertTo-Json -Depth 5
