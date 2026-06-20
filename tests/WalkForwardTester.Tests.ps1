# WalkForwardTester.Tests.ps1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot ".." "Modules" "WalkForwardTester.psm1"
    Remove-Module WalkForwardTester -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force
}

Describe "Invoke-WalkForwardTest" {
    It "Should return empty results with insufficient data" {
        $data = 1..50
        $result = Invoke-WalkForwardTest -Data $data -TrainingWindow 30 -TestingWindow 10 -StepSize 20 `
            -OptimizeFunction { param($Data, $WindowIndex) return @{p=1} } `
            -EvaluateFunction { param($Data, $Parameters, $WindowIndex) return @{Trades=0;WinRate=0;NetPnl=0;Sharpe=0;MaxDrawdown=0} } `
            -OutputPath $null
        $result.Count | Should -Be 0
    }
    It "Should create at least one window with sufficient data" {
        $data = 1..200
        $result = Invoke-WalkForwardTest -Data $data -TrainingWindow 50 -TestingWindow 10 -StepSize 30 `
            -OptimizeFunction { param($Data, $WindowIndex) return @{p=1} } `
            -EvaluateFunction { param($Data, $Parameters, $WindowIndex) return @{Trades=5;WinRate=60;NetPnl=10;Sharpe=0.5;MaxDrawdown=5} } `
            -OutputPath $null
        $result.Count | Should -BeGreaterThan 0
    }
    It "Should pass WindowIndex to optimize function" {
        $data = 1..200
        $received = @()
        Invoke-WalkForwardTest -Data $data -TrainingWindow 50 -TestingWindow 10 -StepSize 30 `
            -OptimizeFunction { param($Data, $WindowIndex) $script:received += $WindowIndex; return @{p=1} } `
            -EvaluateFunction { param($Data, $Parameters, $WindowIndex) return @{Trades=0;WinRate=0;NetPnl=0;Sharpe=0;MaxDrawdown=0} } `
            -OutputPath $null
        $received.Count | Should -BeGreaterThan 0
    }
}

AfterAll {
    Remove-Module WalkForwardTester -ErrorAction SilentlyContinue
}
