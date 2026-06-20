# BybitClient.Tests.ps1
# Tests for Modules/BybitClient.psm1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot ".." "Modules" "BybitClient.psm1"
    Remove-Module BybitClient -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force
}

Describe "Read-DerLength" {
    It "Should parse short-form length (0x01 = 1 byte)" {
        $data = [byte[]]@(0x01, 0xAA)
        $offset = 0
        $len = Read-DerLength -data $data -offset ([ref]$offset)
        $len | Should -Be 1
        $offset | Should -Be 1
    }
    It "Should parse long-form length (0x81 0x05 = 5 bytes)" {
        $data = [byte[]]@(0x81, 0x05, 0xAA)
        $offset = 0
        $len = Read-DerLength -data $data -offset ([ref]$offset)
        $len | Should -Be 5
        $offset | Should -Be 2
    }
}

Describe "Read-DerInteger" {
    It "Should throw on non-INTEGER tag" {
        $data = [byte[]]@(0x01, 0x01, 0x00)
        $offset = 0
        { Read-DerInteger -data $data -offset ([ref]$offset) } | Should -Throw
    }
    It "Should parse INTEGER tag 0x02 0x01 0x2A" {
        $data = [byte[]]@(0x02, 0x01, 0x2A)
        $offset = 0
        $result = Read-DerInteger -data $data -offset ([ref]$offset)
        $result | Should -BeOfType [byte[]]
        $result[0] | Should -Be 0x2A
        $offset | Should -Be 3
    }
}

Describe "Initialize-BybitClient" {
    It "Should throw when private key file does not exist" {
        { Initialize-BybitClient -PrivateKeyPath "nonexistent.pem" -ApiKey "test" } | Should -Throw
    }
    It "Should initialize with HMAC auth when no private key" {
        $client = Initialize-BybitClient -ApiKey "test_key" -ApiSecret "test_secret" -BaseUrl "https://testnet.bybit.com"
        $client.UseRsa | Should -Be $false
        $client.ApiKey | Should -Be "test_key"
        $client.BaseUrl | Should -Be "https://testnet.bybit.com"
    }
}

Describe "Get-BybitClient" {
    It "Should throw when not initialized" {
        Remove-Module BybitClient -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        { Get-BybitClient } | Should -Throw
    }
}

Describe "Invoke-BybitRequest" {
    It "Should throw when client not initialized" {
        Remove-Module BybitClient -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        { Invoke-BybitRequest -Method "GET" -Endpoint "/test" } | Should -Throw
    }
}

Describe "Test-BybitClockSync" {
    It "Should return error hashtable when not initialized" {
        Remove-Module BybitClient -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force
        $result = Test-BybitClockSync
        $result.Ok | Should -Be $false
    }
}

AfterAll {
    Remove-Module BybitClient -ErrorAction SilentlyContinue
}
