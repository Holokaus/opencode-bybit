# WalkForwardTester.psm1 — Walk-forward optimization framework
# Does NOT modify existing strategy logic

function Invoke-WalkForwardTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Data,
        [Parameter(Mandatory)]
        [int]$TrainingWindow,
        [Parameter(Mandatory)]
        [int]$TestingWindow,
        [Parameter(Mandatory)]
        [int]$StepSize,
        [Parameter(Mandatory)]
        [scriptblock]$OptimizeFunction,
        [Parameter(Mandatory)]
        [scriptblock]$EvaluateFunction,
        [string]$OutputPath = "walkforward_results.csv"
    )
    $results = @()
    $dataCount = $Data.Count
    $windowStart = 0
    $windowIndex = 0
    while (($windowStart + $TrainingWindow + $TestingWindow) -le $dataCount) {
        $windowIndex++
        $trainStart = $windowStart
        $trainEnd = $windowStart + $TrainingWindow - 1
        $testStart = $trainEnd + 1
        $testEnd = $testStart + $TestingWindow - 1
        $trainData = $Data[$trainStart..$trainEnd]
        $testData = $Data[$testStart..$testEnd]
        $params = & $OptimizeFunction -Data $trainData -WindowIndex $windowIndex
        $evalResult = & $EvaluateFunction -Data $testData -Parameters $params -WindowIndex $windowIndex
        $results += [PSCustomObject]@{
            Window         = $windowIndex
            TrainStart     = $trainStart
            TrainEnd       = $trainEnd
            TestStart      = $testStart
            TestEnd        = $testEnd
            TrainSize      = $trainData.Count
            TestSize       = $testData.Count
            Parameters     = ($params | ConvertTo-Json -Compress)
            Trades         = $evalResult.Trades
            WinRate        = $evalResult.WinRate
            NetPnl         = $evalResult.NetPnl
            Sharpe         = $evalResult.Sharpe
            MaxDrawdown    = $evalResult.MaxDrawdown
        }
        $windowStart += $StepSize
    }
    if ($results.Count -gt 0 -and $OutputPath) {
        $results | Export-Csv -Path $OutputPath -NoTypeInformation
    }
    return $results
}

Export-ModuleMember -Function Invoke-WalkForwardTest
