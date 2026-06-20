# MonteCarlo.psm1 — Monte Carlo simulation for trade sequence analysis
# Uses actual trade history inputs; no fabricated statistics

function Invoke-MonteCarloSimulation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$TradeHistory,
        [Parameter(Mandatory)]
        [int]$Iterations = 10000,
        [double]$FeeVariation = 0.0,
        [double]$SlippageVariation = 0.0,
        [double]$InitialCapital = 100.0,
        [int]$MaxConcurrentTrades = 1,
        [string]$OutputPath = "monte_carlo_results.csv"
    )
    if ($TradeHistory.Count -eq 0) {
        Write-Error "TradeHistory is empty"
        return $null
    }
    $tradePnls = $TradeHistory | ForEach-Object { [double]$_.PnL }
    $tradeCount = $tradePnls.Count
    $results = @()
    $rng = [System.Random]::new()
    for ($iter = 0; $iter -lt $Iterations; $iter++) {
        $capital = $InitialCapital
        $peakCapital = $InitialCapital
        $maxDrawdown = 0.0
        $selectedPnls = for ($i = 0; $i -lt $tradeCount; $i++) {
            $p = $tradePnls[$rng.Next(0, $tradeCount)]
            $feeNoise = $p * $FeeVariation * ($rng.NextDouble() * 2 - 1)
            $slipNoise = $InitialCapital * $SlippageVariation * ($rng.NextDouble() * 2 - 1)
            $p + $feeNoise - $slipNoise
        }
        foreach ($p in $selectedPnls) {
            $capital += $p
            if ($capital -gt $peakCapital) { $peakCapital = $capital }
            $dd = ($peakCapital - $capital) / $peakCapital * 100
            if ($dd -gt $maxDrawdown) { $maxDrawdown = $dd }
        }
        $totalReturn = ($capital - $InitialCapital) / $InitialCapital * 100
        $results += [PSCustomObject]@{
            Iteration    = $iter + 1
            FinalCapital = [Math]::Round($capital, 6)
            TotalReturn  = [Math]::Round($totalReturn, 4)
            MaxDrawdown  = [Math]::Round($maxDrawdown, 4)
        }
    }
    $finalCapitals = $results | ForEach-Object { [double]$_.FinalCapital }
    $returns = $results | ForEach-Object { [double]$_.TotalReturn }
    $drawdowns = $results | ForEach-Object { [double]$_.MaxDrawdown }
    $sortedReturns = $returns | Sort-Object
    $sortedCapitals = $finalCapitals | Sort-Object
    $sortedDD = $drawdowns | Sort-Object
    $meanReturn = ($returns | Measure-Object -Average).Average
    $medianReturn = $sortedReturns[[Math]::Floor($sortedReturns.Count / 2)]
    $meanFinal = ($finalCapitals | Measure-Object -Average).Average
    $meanDD = ($drawdowns | Measure-Object -Average).Average
    $ci95Low = $sortedCapitals[[Math]::Floor($sortedCapitals.Count * 0.025)]
    $ci95High = $sortedCapitals[[Math]::Floor($sortedCapitals.Count * 0.975)]
    $summary = [PSCustomObject]@{
        MeanReturn       = [Math]::Round($meanReturn, 4)
        MedianReturn     = [Math]::Round($medianReturn, 4)
        MeanFinalCapital = [Math]::Round($meanFinal, 6)
        MeanMaxDrawdown  = [Math]::Round($meanDD, 4)
        Ci95Low          = [Math]::Round($ci95Low, 6)
        Ci95High         = [Math]::Round($ci95High, 6)
        Iterations       = $Iterations
        TradeCount       = $tradeCount
    }
    if ($OutputPath) {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation
        $summary | Export-Csv -Path ($OutputPath -replace '\.csv$', '_summary.csv') -NoTypeInformation
    }
    return @{
        Results  = $results
        Summary  = $summary
    }
}

Export-ModuleMember -Function Invoke-MonteCarloSimulation
