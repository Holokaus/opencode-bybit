# BybitClient.psm1 — Unified Bybit API client
# Consolidated from 17 duplicated implementations
# Supports RSA (sign-type 2) and HMAC (sign-type 1)

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
    if ($data[$offset.Value] -ne 0x02) { throw "Expected INTEGER tag at offset $($offset.Value)" }
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

function Initialize-BybitClient {
    [CmdletBinding()]
    param(
        [string]$PrivateKeyPath,
        [string]$ApiKey,
        [string]$ApiSecret,
        [string]$BaseUrl = "https://api.bybit.com",
        [string]$RecvWindow = "5000",
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3
    )
    $client = @{
        ApiKey      = $ApiKey
        ApiSecret   = $ApiSecret
        BaseUrl     = $BaseUrl
        RecvWindow  = $RecvWindow
        TimeoutSec  = $TimeoutSec
        MaxRetries  = $MaxRetries
        UseRsa      = (-not [string]::IsNullOrEmpty($PrivateKeyPath))
    }
    if ($client.UseRsa) {
        $pem = Get-Content -Raw $PrivateKeyPath
        $b64 = ($pem -replace '-----.+-----', '' -replace '\s', '')
        $der = [System.Convert]::FromBase64String($b64)
        $off = 0
        if ($der[$off] -ne 0x30) { throw "Not a DER SEQUENCE at offset 0" }
        $off++
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
        $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
        $rsa.ImportParameters($params)
        $client.RsaProvider = $rsa
    }
    $script:BybitClient = $client
    return $client
}

function Get-BybitClient {
    if (-not $script:BybitClient) { throw "BybitClient not initialized. Call Initialize-BybitClient first." }
    return $script:BybitClient
}

function Invoke-BybitRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        [Parameter(Mandatory)]
        [string]$Endpoint,
        [string]$Query = "",
        [string]$Body = "",
        [int]$RetryCount = -1
    )
    $client = Get-BybitClient
    $maxRetries = if ($RetryCount -ge 0) { $RetryCount } else { $client.MaxRetries }
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $recvWindow = $client.RecvWindow
    $apiKey = $client.ApiKey
    $tsStr = "$timestamp$apiKey$recvWindow"
    $payload = if ($Method -eq "GET") { "$tsStr$Query" } else { "$tsStr$Body" }
    if ($client.UseRsa) {
        $dataBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $sigBytes = $client.RsaProvider.SignData($dataBytes, $hasher)
        $signature = [System.Convert]::ToBase64String($sigBytes)
        $signType = "2"
    } elseif ($client.ApiSecret) {
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($client.ApiSecret)
        $sigBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
        $signature = [BitConverter]::ToString($sigBytes).Replace("-", "").ToLower()
        $signType = "1"
    } else {
        throw "No authentication method configured (RSA key or HMAC secret required)"
    }
    $headers = @{
        "X-BAPI-API-KEY"    = $apiKey
        "X-BAPI-TIMESTAMP"  = "$timestamp"
        "X-BAPI-SIGN"       = $signature
        "X-BAPI-RECV-WINDOW" = $recvWindow
        "X-BAPI-SIGN-TYPE"  = $signType
        "User-Agent"        = "bybit-skill/1.4.2"
    }
    $url = "$($client.BaseUrl)$Endpoint"
    if ($Query) { $url = "$url`?$Query" }
    $params = @{
        Uri         = $url
        Headers     = $headers
        UseBasicParsing = $true
        TimeoutSec  = $client.TimeoutSec
    }
    if ($Method -eq "POST") {
        $params.Method = "POST"
        if ($Body) { $params.Body = $Body; $params.ContentType = "application/json" }
    }
    $lastError = $null
    for ($r = 0; $r -le $maxRetries; $r++) {
        try {
            $response = Invoke-WebRequest @params
            return ($response.Content | ConvertFrom-Json)
        } catch {
            $lastError = $_
            if ($r -lt $maxRetries) {
                $sleepMs = [Math]::Pow(2, $r) * 1000
                Write-Warning ("Bybit API retry {0}/{1} for {2}: {3}" -f ($r+1), $maxRetries, $Endpoint, $_.Exception.Message)
                Start-Sleep -Milliseconds $sleepMs
            }
        }
    }
    Write-Error ("Bybit API request failed after {0} retries: {1}" -f $maxRetries, $lastError.Exception.Message)
    return $null
}

function Get-BybitKlines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Symbol,
        [Parameter(Mandatory)]
        [string]$Interval,
        [int]$Limit = 200,
        [string]$Category = "spot"
    )
    $query = "category=$Category&symbol=$Symbol&interval=$Interval&limit=$Limit"
    $data = Invoke-BybitRequest -Method "GET" -Endpoint "/v5/market/kline" -Query $query
    if ($data -and $data.retCode -eq 0 -and $data.result -and $data.result.list) {
        $klines = $data.result.list
        [Array]::Reverse($klines)
        return $klines
    }
    return $null
}

function Get-BybitBalance {
    [CmdletBinding()]
    param(
        [string]$AccountType = "UNIFIED",
        [string]$Coin = "USDT"
    )
    $query = "accountType=$AccountType&coin=$Coin"
    $data = Invoke-BybitRequest -Method "GET" -Endpoint "/v5/account/wallet-balance" -Query $query
    if ($data -and $data.retCode -eq 0 -and $data.result) {
        return $data.result.list[0].coin
    }
    return $null
}

function New-BybitOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Symbol,
        [Parameter(Mandatory)]
        [ValidateSet("Buy", "Sell")]
        [string]$Side,
        [Parameter(Mandatory)]
        [string]$Quantity,
        [string]$OrderType = "Market",
        [string]$Category = "spot"
    )
    $body = '{"category":"' + $Category + '","symbol":"' + $Symbol + '","side":"' + $Side + '","orderType":"' + $OrderType + '","qty":"' + $Quantity + '"}'
    $data = Invoke-BybitRequest -Method "POST" -Endpoint "/v5/order/create" -Body $body
    if ($data -and $data.retCode -eq 0) { return $data.result.orderId }
    Write-Warning ("Order failed: {0} {1}" -f $data.retCode, $data.retMsg)
    return "FAIL"
}

function Stop-BybitOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Symbol,
        [Parameter(Mandatory)]
        [string]$OrderId,
        [string]$Category = "spot"
    )
    $body = '{"category":"' + $Category + '","symbol":"' + $Symbol + '","orderId":"' + $OrderId + '"}'
    $data = Invoke-BybitRequest -Method "POST" -Endpoint "/v5/order/cancel" -Body $body
    return ($data -and $data.retCode -eq 0)
}

function Get-BybitServerTime {
    $data = Invoke-BybitRequest -Method "GET" -Endpoint "/v5/market/time" -RetryCount 1
    if ($data -and $data.retCode -eq 0 -and $data.result) {
        return [long]$data.result.timeNano
    }
    return $null
}

function Test-BybitClockSync {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([int]$MaxDriftMs = 5000)
    $serverNano = Get-BybitServerTime
    if (-not $serverNano) { return @{Ok=$false; DriftMs=999999; Error="Could not fetch server time"} }
    $serverMs = [long][Math]::Round($serverNano / 1000000.0)
    $localMs = [System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $diff = [Math]::Abs($serverMs - $localMs)
    return @{Ok=($diff -le $MaxDriftMs); DriftMs=$diff; ServerMs=$serverMs; LocalMs=$localMs}
}

Export-ModuleMember -Function Initialize-BybitClient, Get-BybitClient, Invoke-BybitRequest
Export-ModuleMember -Function Get-BybitKlines, Get-BybitBalance, New-BybitOrder, Stop-BybitOrder
Export-ModuleMember -Function Get-BybitServerTime, Test-BybitClockSync
