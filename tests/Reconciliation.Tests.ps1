# Reconciliation.Tests.ps1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot ".." "Modules" "Reconciliation.psm1"
    Remove-Module Reconciliation -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force
}

Describe "Compare-ExchangeAndLocalPositions" {
    It "Should detect position missing locally" {
        $exchange = @(@{Symbol="SOLUSDT"; Side="Buy"; Size=10})
        $local = @()
        $result = Compare-ExchangeAndLocalPositions -ExchangePositions $exchange -LocalPositions $local
        $result.Count | Should -Be 1
        $result[0].Type | Should -Be "POSITION_MISSING_LOCAL"
    }
    It "Should detect position missing on exchange" {
        $exchange = @()
        $local = @(@{Symbol="SOLUSDT"; Side="Buy"; Size=10})
        $result = Compare-ExchangeAndLocalPositions -ExchangePositions $exchange -LocalPositions $local
        $result.Count | Should -Be 1
        $result[0].Type | Should -Be "POSITION_MISSING_EXCHANGE"
    }
    It "Should detect size mismatch" {
        $exchange = @(@{Symbol="SOLUSDT"; Side="Buy"; Size=10.0})
        $local = @(@{Symbol="SOLUSDT"; Side="Buy"; Size=9.5})
        $result = Compare-ExchangeAndLocalPositions -ExchangePositions $exchange -LocalPositions $local
        $result.Count | Should -Be 1
        $result[0].Type | Should -Be "POSITION_SIZE_MISMATCH"
    }
    It "Should return empty for consistent positions" {
        $exchange = @(@{Symbol="SOLUSDT"; Side="Buy"; Size=10.0})
        $local = @(@{Symbol="SOLUSDT"; Side="Buy"; Size=10.0})
        $result = Compare-ExchangeAndLocalPositions -ExchangePositions $exchange -LocalPositions $local
        $result.Count | Should -Be 0
    }
}

Describe "Compare-ExchangeAndLocalOrders" {
    It "Should detect order missing locally" {
        $exchange = @(@{OrderId="ORD123"; Symbol="SOLUSDT"; Status="New"})
        $local = @()
        $result = Compare-ExchangeAndLocalOrders -ExchangeOrders $exchange -LocalOrders $local
        $result.Count | Should -Be 1
        $result[0].Type | Should -Be "ORDER_MISSING_LOCAL"
    }
    It "Should detect order missing on exchange" {
        $exchange = @()
        $local = @(@{OrderId="ORD123"; Symbol="SOLUSDT"; Status="New"})
        $result = Compare-ExchangeAndLocalOrders -ExchangeOrders $exchange -LocalOrders $local
        $result.Count | Should -Be 1
        $result[0].Type | Should -Be "ORDER_MISSING_EXCHANGE"
    }
    It "Should return empty for consistent orders" {
        $exchange = @(@{OrderId="ORD123"; Symbol="SOLUSDT"; Status="Filled"})
        $local = @(@{OrderId="ORD123"; Symbol="SOLUSDT"; Status="Filled"})
        $result = Compare-ExchangeAndLocalOrders -ExchangeOrders $exchange -LocalOrders $local
        $result.Count | Should -Be 0
    }
}

Describe "New-ReconciliationReport" {
    It "Should indicate consistency when no discrepancies" {
        $report = New-ReconciliationReport -PositionDiscrepancies @() -OrderDiscrepancies @()
        $report.IsConsistent | Should -Be $true
        $report.TotalDiscrepancies | Should -Be 0
    }
    It "Should indicate inconsistency when discrepancies exist" {
        $posDiscrepancies = @([PSCustomObject]@{Type="TEST"; Detail="test"})
        $report = New-ReconciliationReport -PositionDiscrepancies $posDiscrepancies -OrderDiscrepancies @()
        $report.IsConsistent | Should -Be $false
        $report.TotalDiscrepancies | Should -Be 1
    }
}

AfterAll {
    Remove-Module Reconciliation -ErrorAction SilentlyContinue
}
