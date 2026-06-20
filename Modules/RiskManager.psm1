# RiskManager.psm1 — Risk management engine
# Independent from signal generation

function New-RiskManager {
    [CmdletBinding()]
    param(
        [double]$MaxDailyLossPercent = -2.0,
        [double]$MaxDrawdownPercent = -15.0,
        [int]$MaxConsecutiveLosses = 5,
        [double]$MaxPositionSizePercent = 10.0,
        [double]$MaxExposurePercent = 50.0,
        [double]$InitialCapital = 100.0
    )
    $manager = @{
        MaxDailyLossPercent    = $MaxDailyLossPercent
        MaxDrawdownPercent     = $MaxDrawdownPercent
        MaxConsecutiveLosses   = $MaxConsecutiveLosses
        MaxPositionSizePercent = $MaxPositionSizePercent
        MaxExposurePercent     = $MaxExposurePercent
        InitialCapital         = $InitialCapital
        PeakCapital            = $InitialCapital
        CurrentCapital         = $InitialCapital
        DailyStartCapital      = $InitialCapital
        DailyPnl               = 0.0
        ConsecutiveLosses      = 0
        LastTradeDate          = (Get-Date).Date
        PositionCount          = 0
        Allowed                = $true
        DailyLossReached       = $false
        DrawdownReached        = $false
        ConsecLossReached      = $false
        ExposureReached        = $false
    }
    $script:RiskManager = $manager
    return $manager
}

function Get-RiskManager {
    if (-not $script:RiskManager) { throw "RiskManager not initialized. Call New-RiskManager first." }
    return $script:RiskManager
}

function Test-TradeAllowed {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [double]$TradeSizePercent,
        [switch]$IsNewPosition
    )
    $rm = Get-RiskManager
    $now = (Get-Date).Date
    if ($now -gt $rm.LastTradeDate) {
        $rm.DailyStartCapital = $rm.CurrentCapital
        $rm.DailyPnl = 0.0
        $rm.DailyLossReached = $false
        $rm.LastTradeDate = $now
    }
    $reasons = @()
    $allowed = $true
    $drawdownPct = ($rm.CurrentCapital - $rm.PeakCapital) / $rm.PeakCapital * 100
    if ($drawdownPct -le $rm.MaxDrawdownPercent) {
        $allowed = $false
        $rm.DrawdownReached = $true
        $reasons += "MaxDrawdown"
    }
    if ($rm.DailyPnl -le $rm.MaxDailyLossPercent / 100 * $rm.DailyStartCapital) {
        $allowed = $false
        $rm.DailyLossReached = $true
        $reasons += "MaxDailyLoss"
    }
    if ($rm.ConsecutiveLosses -ge $rm.MaxConsecutiveLosses) {
        $allowed = $false
        $rm.ConsecLossReached = $true
        $reasons += "ConsecutiveLosses"
    }
    if ($IsNewPosition -and $TradeSizePercent -gt $rm.MaxPositionSizePercent) {
        $allowed = $false
        $reasons += "PositionSizeExceeded"
    }
    $currentExposure = $rm.PositionCount * $rm.MaxPositionSizePercent
    if ($IsNewPosition -and ($currentExposure + $TradeSizePercent) -gt $rm.MaxExposurePercent) {
        $allowed = $false
        $reasons += "ExposureCapExceeded"
    }
    $rm.Allowed = $allowed
    return @{
        Allowed  = $allowed
        Reasons  = $reasons
        Drawdown = [Math]::Round($drawdownPct, 4)
        DailyPnl = [Math]::Round($rm.DailyPnl, 6)
        ConsecutiveLosses = $rm.ConsecutiveLosses
    }
}

function Update-RiskManagerAfterTrade {
    [CmdletBinding()]
    param(
        [double]$PnL,
        [double]$NewCapital,
        [switch]$IsPositionOpen,
        [switch]$IsPositionClose
    )
    $rm = Get-RiskManager
    $now = (Get-Date).Date
    if ($now -gt $rm.LastTradeDate) {
        $rm.DailyStartCapital = $rm.CurrentCapital
        $rm.DailyPnl = 0.0
        $rm.DailyLossReached = $false
        $rm.LastTradeDate = $now
    }
    $rm.CurrentCapital = $NewCapital
    $rm.DailyPnl += $PnL
    if ($NewCapital -gt $rm.PeakCapital) { $rm.PeakCapital = $NewCapital }
    if ($IsPositionOpen) { $rm.PositionCount++ }
    if ($IsPositionClose) {
        $rm.PositionCount = [Math]::Max(0, $rm.PositionCount - 1)
        if ($PnL -lt 0) { $rm.ConsecutiveLosses++ } else { $rm.ConsecutiveLosses = 0 }
    }
}

function Reset-RiskManager {
    [CmdletBinding()]
    param([double]$NewCapital)
    New-RiskManager -InitialCapital $NewCapital `
        -MaxDailyLossPercent $script:RiskManager.MaxDailyLossPercent `
        -MaxDrawdownPercent $script:RiskManager.MaxDrawdownPercent `
        -MaxConsecutiveLosses $script:RiskManager.MaxConsecutiveLosses `
        -MaxPositionSizePercent $script:RiskManager.MaxPositionSizePercent `
        -MaxExposurePercent $script:RiskManager.MaxExposurePercent
}

function Get-RiskManagerStatus {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $rm = Get-RiskManager
    $drawdownPct = if ($rm.PeakCapital -gt 0) { ($rm.CurrentCapital - $rm.PeakCapital) / $rm.PeakCapital * 100 } else { 0 }
    return @{
        Allowed              = $rm.Allowed
        CurrentCapital       = $rm.CurrentCapital
        PeakCapital          = $rm.PeakCapital
        DrawdownPercent      = [Math]::Round($drawdownPct, 4)
        DailyPnl             = [Math]::Round($rm.DailyPnl, 6)
        ConsecutiveLosses    = $rm.ConsecutiveLosses
        PositionCount        = $rm.PositionCount
        DailyLossReached     = $rm.DailyLossReached
        DrawdownReached      = $rm.DrawdownReached
        ConsecLossReached    = $rm.ConsecLossReached
        ExposureReached      = $rm.ExposureReached
        MaxDailyLossPercent  = $rm.MaxDailyLossPercent
        MaxDrawdownPercent   = $rm.MaxDrawdownPercent
        MaxConsecutiveLosses = $rm.MaxConsecutiveLosses
        MaxPositionSizePercent = $rm.MaxPositionSizePercent
        MaxExposurePercent   = $rm.MaxExposurePercent
    }
}

Export-ModuleMember -Function New-RiskManager, Get-RiskManager, Test-TradeAllowed
Export-ModuleMember -Function Update-RiskManagerAfterTrade, Reset-RiskManager, Get-RiskManagerStatus
