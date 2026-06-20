$rootDir = Split-Path $PSCommandPath -Parent
$stateFile = Join-Path $rootDir "state.json"
$tradesFile = Join-Path $rootDir "trades.csv"

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  MULTI-STRATEGY PAPER TRADER - Status" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

if (Test-Path $stateFile) {
    $j = Get-Content $stateFile -Raw | ConvertFrom-Json
    $ret = if ($j.PeakCapital -gt 0) { [Math]::Round(($j.TotalCapital / $j.PeakCapital - 1) * 100, 2) } else { 0 }
    $dd = if ($j.PeakCapital -gt 0) { [Math]::Round(($j.PeakCapital - $j.TotalCapital) / $j.PeakCapital * 100, 2) } else { 0 }
    $tc = if ($j.TotalCapital) { $j.TotalCapital.ToString('F2') } else { "-" }
    Write-Host ("Total: {0,8}  |  Return: {1,6:F2}%  |  Max DD: {2,5:F2}%  |  FirstRun: {3}" -f $tc, $ret, $dd, $j.FirstRun) -ForegroundColor Green

    foreach ($sym in $j.Symbols.PSObject.Properties) {
        $sn = $sym.Name; $sv = $sym.Value
        $wr = if ($sv.TotalTrades -gt 0) { [Math]::Round($sv.Wins / $sv.TotalTrades * 100, 1) } else { 0 }
        Write-Host ""
        Write-Host ("--- {0} Cap={1,7:F2} WR={2,5}% ({3}/{4}) ConsecLoss={5} ---" -f
            $sn, $sv.Capital, $wr, $sv.Wins, $sv.TotalTrades, $sv.ConsecLosses) -ForegroundColor Yellow

        if ($sv.Positions.Count -gt 0) {
            foreach ($p in $sv.Positions) {
                $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($p.EntryTime).ToString('MM-dd HH:mm')
                $oi = if ($p.OrderId) { " oid=$($p.OrderId)" } else { "" }
                Write-Host ("   LONG @ {0,7:F4} TP={1,7:F4} SL={2,7:F4} | Size={3,6:F2} | {4}{5}" -f
                    $p.EntryPrice, $p.TPPrice, $p.SLPrice, $p.SizeQuote, $dt, $oi) -ForegroundColor Magenta
            }
        } else {
            Write-Host "   No open positions" -ForegroundColor Gray
        }
        if ($sv.DemoOrderIds.Count -gt 0) {
            Write-Host ("   Demo orders: {0}" -f ($sv.DemoOrderIds -join ", ")) -ForegroundColor Cyan
        }
    }

    if (Test-Path $tradesFile) {
        $trades = Import-Csv $tradesFile
        $tCount = ($trades | Measure-Object).Count
        if ($tCount -gt 0) {
            Write-Host ""
            Write-Host "Last 5 trades:" -ForegroundColor Cyan
            $trades | Select-Object -Last 5 | Format-Table symbol, entryTime, exitTime, side, entry, exit, reason, pnl -AutoSize
        }
    }
} else {
    Write-Host "No state file found - trader has never run" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To start:   pwsh run_paper_trader.ps1" -ForegroundColor Gray
Write-Host "To reset:   pwsh run_paper_trader.ps1 -Reset" -ForegroundColor Gray
Write-Host "To config:  edit lines 12-28" -ForegroundColor Gray
Write-Host "Demo API:   set UseDemoApi=`$true in config and fix API key permissions" -ForegroundColor Gray
