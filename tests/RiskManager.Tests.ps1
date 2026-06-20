# RiskManager.Tests.ps1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot ".." "Modules" "RiskManager.psm1"
    Remove-Module RiskManager -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force
}

Describe "New-RiskManager" {
    It "Should create manager with default values" {
        $rm = New-RiskManager
        $rm.MaxDailyLossPercent | Should -Be -2.0
        $rm.MaxDrawdownPercent | Should -Be -15.0
        $rm.MaxConsecutiveLosses | Should -Be 5
        $rm.MaxPositionSizePercent | Should -Be 10.0
        $rm.MaxExposurePercent | Should -Be 50.0
        $rm.InitialCapital | Should -Be 100.0
    }
    It "Should accept custom values" {
        $rm = New-RiskManager -MaxDailyLossPercent -5 -MaxDrawdownPercent -20 -MaxConsecutiveLosses 3 -MaxPositionSizePercent 5 -MaxExposurePercent 30 -InitialCapital 1000
        $rm.MaxDailyLossPercent | Should -Be -5
        $rm.MaxDrawdownPercent | Should -Be -20
        $rm.MaxConsecutiveLosses | Should -Be 3
        $rm.MaxPositionSizePercent | Should -Be 5
        $rm.MaxExposurePercent | Should -Be 30
        $rm.InitialCapital | Should -Be 1000
    }
}

Describe "Test-TradeAllowed" {
    It "Should allow trade under normal conditions" {
        New-RiskManager -InitialCapital 100
        $result = Test-TradeAllowed -TradeSizePercent 5 -IsNewPosition
        $result.Allowed | Should -Be $true
    }
    It "Should block trade exceeding position size" {
        New-RiskManager -InitialCapital 100 -MaxPositionSizePercent 5
        $result = Test-TradeAllowed -TradeSizePercent 10 -IsNewPosition
        $result.Allowed | Should -Be $false
        $result.Reasons | Should -Contain "PositionSizeExceeded"
    }
    It "Should block trade after max consecutive losses" {
        $rm = New-RiskManager -InitialCapital 100 -MaxConsecutiveLosses 2
        $rm.ConsecutiveLosses = 2
        $result = Test-TradeAllowed -TradeSizePercent 5 -IsNewPosition
        $result.Allowed | Should -Be $false
        $result.Reasons | Should -Contain "ConsecutiveLosses"
    }
}

Describe "Update-RiskManagerAfterTrade" {
    It "Should track consecutive losses" {
        $rm = New-RiskManager -InitialCapital 100 -MaxConsecutiveLosses 3
        Update-RiskManagerAfterTrade -PnL -5 -NewCapital 95 -IsPositionClose
        $rm.ConsecutiveLosses | Should -Be 1
    }
    It "Should reset consecutive losses on win" {
        $rm = New-RiskManager -InitialCapital 100 -MaxConsecutiveLosses 3
        $rm.ConsecutiveLosses = 2
        Update-RiskManagerAfterTrade -PnL 3 -NewCapital 98 -IsPositionClose
        $rm.ConsecutiveLosses | Should -Be 0
    }
    It "Should track position count" {
        $rm = New-RiskManager -InitialCapital 100
        Update-RiskManagerAfterTrade -PnL 0 -NewCapital 100 -IsPositionOpen
        $rm.PositionCount | Should -Be 1
        Update-RiskManagerAfterTrade -PnL 0 -NewCapital 100 -IsPositionOpen
        $rm.PositionCount | Should -Be 2
        Update-RiskManagerAfterTrade -PnL 0 -NewCapital 100 -IsPositionClose
        $rm.PositionCount | Should -Be 1
    }
}

Describe "Get-RiskManagerStatus" {
    It "Should return correct status" {
        New-RiskManager -InitialCapital 100
        $status = Get-RiskManagerStatus
        $status.CurrentCapital | Should -Be 100.0
        $status.Allowed | Should -Be $true
        $status.DrawdownPercent | Should -Be 0
    }
}

Describe "Reset-RiskManager" {
    It "Should reset to new capital" {
        New-RiskManager -InitialCapital 100 -MaxConsecutiveLosses 5
        Update-RiskManagerAfterTrade -PnL -10 -NewCapital 90 -IsPositionClose
        Reset-RiskManager -NewCapital 200
        $rm = Get-RiskManager
        $rm.CurrentCapital | Should -Be 200
        $rm.ConsecutiveLosses | Should -Be 0
    }
}

AfterAll {
    Remove-Module RiskManager -ErrorAction SilentlyContinue
}
