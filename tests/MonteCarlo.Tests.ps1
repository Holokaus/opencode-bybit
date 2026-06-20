# MonteCarlo.Tests.ps1

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot ".." "Modules" "MonteCarlo.psm1"
    Remove-Module MonteCarlo -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force
}

Describe "Invoke-MonteCarloSimulation" {
    It "Should return null with empty trade history" {
        $result = Invoke-MonteCarloSimulation -TradeHistory @() -Iterations 10 -OutputPath $null
        $result | Should -Be $null
    }
    It "Should produce correct iteration count" {
        $trades = @(@{PnL=1.0}, @{PnL=-0.5}, @{PnL=0.3})
        $result = Invoke-MonteCarloSimulation -TradeHistory $trades -Iterations 50 -OutputPath $null
        $result.Results.Count | Should -Be 50
    }
    It "Should produce summary statistics" {
        $trades = @(@{PnL=1.0}, @{PnL=-0.5}, @{PnL=0.3})
        $result = Invoke-MonteCarloSimulation -TradeHistory $trades -Iterations 100 -OutputPath $null
        $result.Summary.Iterations | Should -Be 100
        $result.Summary.MeanReturn | Should -Not -Be $null
        $result.Summary.MedianReturn | Should -Not -Be $null
        $result.Summary.MeanFinalCapital | Should -Not -Be $null
        $result.Summary.MeanMaxDrawdown | Should -Not -Be $null
        $result.Summary.Ci95Low | Should -Not -Be $null
        $result.Summary.Ci95High | Should -Not -Be $null
    }
    It "Should handle fee and slippage variation" {
        $trades = @(@{PnL=1.0}, @{PnL=-0.5})
        $result = Invoke-MonteCarloSimulation -TradeHistory $trades -Iterations 10 -FeeVariation 0.01 -SlippageVariation 0.001 -OutputPath $null
        $result.Results.Count | Should -Be 10
    }
}

AfterAll {
    Remove-Module MonteCarlo -ErrorAction SilentlyContinue
}
