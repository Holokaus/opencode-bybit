function Read-DerLength {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -lt 0x80) {
        $len = $data[$offset.Value]; $offset.Value++; return $len
    }
    $numLen = $data[$offset.Value] -band 0x7F; $offset.Value++
    $len = 0
    for ($i = 0; $i -lt $numLen; $i++) { $len = ($len -shl 8) -bor $data[$offset.Value]; $offset.Value++ }
    return $len
}

function Read-DerInteger {
    param([byte[]]$data, [ref]$offset)
    if ($data[$offset.Value] -ne 0x02) { throw "Expected INTEGER at $($offset.Value)" }
    $offset.Value++
    $len = Read-DerLength -data $data -offset $offset
    $val = [byte[]]::new($len)
    [Array]::Copy($data, $offset.Value, $val, 0, $len)
    $start = if ($val.Length -gt 1 -and $val[0] -eq 0) { 1 } else { 0 }
    $trimmed = [byte[]]::new($val.Length - $start)
    [Array]::Copy($val, $start, $trimmed, 0, $trimmed.Length)
    $offset.Value += $len
    return $trimmed
}

$pem = Get-Content -Raw "bybit_private.pem"
$b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
$der = [System.Convert]::FromBase64String($b64)
$off = 0
if ($der[$off] -ne 0x30) { throw "Not a SEQUENCE" }; $off++
$seqLen = Read-DerLength -data $der -offset ([ref]$off)

$params = New-Object System.Security.Cryptography.RSAParameters
$version = Read-DerInteger -data $der -offset ([ref]$off)
$params.Modulus = Read-DerInteger -data $der -offset ([ref]$off)
$params.Exponent = Read-DerInteger -data $der -offset ([ref]$off)
$params.D = Read-DerInteger -data $der -offset ([ref]$off)
$params.P = Read-DerInteger -data $der -offset ([ref]$off)
$params.Q = Read-DerInteger -data $der -offset ([ref]$off)
$params.DP = Read-DerInteger -data $der -offset ([ref]$off)
$params.DQ = Read-DerInteger -data $der -offset ([ref]$off)
$params.InverseQ = Read-DerInteger -data $der -offset ([ref]$off)

$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
$rsa.ImportParameters($params)

$apiKey = "gkPx5g3xgL2pthIg16"
$recvWindow = "5000"
$baseUrl = "https://api.bybit.com"

function Call-Bybit {
    param($endpoint, $query)
    $timestamp = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $paramStr = "${timestamp}${apiKey}${recvWindow}${query}"
    $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($paramStr)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $sigBytes = $rsa.SignData($dataBytes, $hasher)
    $signature = [System.Convert]::ToBase64String($sigBytes)
    $headers = @{
        "X-BAPI-API-KEY" = $apiKey
        "X-BAPI-TIMESTAMP" = "$timestamp"
        "X-BAPI-SIGN" = $signature
        "X-BAPI-RECV-WINDOW" = $recvWindow
        "X-BAPI-SIGN-TYPE" = "2"
        "User-Agent" = "bybit-skill/1.4.2"
        "X-Referer" = "bybit-skill"
    }
    try {
        $resp = Invoke-WebRequest -Uri "$baseUrl$endpoint`?$query" -Headers $headers -UseBasicParsing -TimeoutSec 15
        return $resp.Content | ConvertFrom-Json
    } catch { return $null }
}

Write-Output "=== API Key Info ==="
$r = Call-Bybit -endpoint "/v5/account/api-key" -query ""
$r | ConvertTo-Json -Depth 5

Write-Output "`n=== Account Info ==="
$r = Call-Bybit -endpoint "/v5/account/info" -query ""
$r | ConvertTo-Json -Depth 5
