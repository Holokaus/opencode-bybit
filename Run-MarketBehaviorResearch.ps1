<#
.SYNOPSIS
    Institutional-Grade Market Behavior Research Framework -- 10-Phase Pipeline
.DESCRIPTION
    Discovers recurring market behaviors for each asset, then determines
    which indicators best detect those behaviors. Does NOT optimize for profit.
    
    Phases:
      1. Maximum historical data acquisition (pagination + retry)
      2. Timeframe discovery (which TF best exposes behavior?)
      3. Regime discovery (clustering on market structure)
      4. Behavior catalog (what happens next in each regime?)
      5. Indicator sensor evaluation (detection accuracy, latency, F1)
      6. Regime-specific configurations (best indicators per regime)
      7. Walk-forward validation (rolling windows, train/freeze/test)
      8. Monte Carlo validation (fee/slippage randomization)
      9. Edge discovery (rank by expectancy, robustness, drawdown)
     10. Final report generation
.PARAMETER Symbols
    Assets to analyze (default: SOLUSDT, ICPUSDT)
.PARAMETER Timeframes
    Timeframes for Phase 1-2 (default: 15m,30m,1h,4h,12h,1d)
.PARAMETER RegimeTimeframe
    Timeframe used for regime detection (default: 240 = 4h)
.PARAMETER OutputDir
    Output directory (default: current directory)
.PARAMETER SkipPhase1
    Skip data acquisition and use existing CSV files
.PARAMETER SkipPhase2
    Skip timeframe discovery
.PARAMETER SkipPhase3
    Skip regime discovery
.PARAMETER SkipPhase4
    Skip behavior catalog
.PARAMETER SkipPhase5
    Skip indicator evaluation
.PARAMETER SkipPhase6
    Skip regime playbook
.PARAMETER SkipPhase7
    Skip walk-forward validation
.PARAMETER SkipPhase8
    Skip Monte Carlo validation
.PARAMETER SkipPhase9
    Skip edge discovery
.PARAMETER SkipPhase10
    Skip final report
.PARAMETER Phase
    Run only specific phase(s). Overrides Skip* parameters.
    e.g. -Phase 1,3,5
.EXAMPLE
    # Full run (all 10 phases, sequential)
    .\Run-MarketBehaviorResearch.ps1
    
    # Skip data acquisition (if already have CSVs)
    .\Run-MarketBehaviorResearch.ps1 -SkipPhase1
    
    # Run only phases 3-6
    .\Run-MarketBehaviorResearch.ps1 -Phase 3,4,5,6
#>

param(
    [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
    [string[]]$Timeframes = @("15","30","60","240","720","D"),
    [string]$RegimeTimeframe = "240",
    [string]$OutputDir = ".",
    [switch]$SkipPhase1,
    [switch]$SkipPhase2,
    [switch]$SkipPhase3,
    [switch]$SkipPhase4,
    [switch]$SkipPhase5,
    [switch]$SkipPhase6,
    [switch]$SkipPhase7,
    [switch]$SkipPhase8,
    [switch]$SkipPhase9,
    [switch]$SkipPhase10,
    [int[]]$Phase
)

$ErrorActionPreference = "Stop"
$startTime = Get-Date

# If specific phases requested, override skip flags
if ($Phase) {
    $SkipPhase1 = $Phase -notcontains 1
    $SkipPhase2 = $Phase -notcontains 2
    $SkipPhase3 = $Phase -notcontains 3
    $SkipPhase4 = $Phase -notcontains 4
    $SkipPhase5 = $Phase -notcontains 5
    $SkipPhase6 = $Phase -notcontains 6
    $SkipPhase7 = $Phase -notcontains 7
    $SkipPhase8 = $Phase -notcontains 8
    $SkipPhase9 = $Phase -notcontains 9
    $SkipPhase10 = $Phase -notcontains 10
}

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  MARKET BEHAVIOR RESEARCH FRAMEWORK" -ForegroundColor Cyan
Write-Host "  10-Phase Pipeline"
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  Assets:      $($Symbols -join ', ')"
Write-Host "  Timeframes:  $($Timeframes -join ', ')"
Write-Host "  Regime TF:   $RegimeTimeframe"
Write-Host "  Output Dir:  $OutputDir"
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Import the module
$modulePath = Join-Path $PSScriptRoot "Modules\MarketBehaviorFramework.psm1"
if (-not (Test-Path $modulePath)) { $modulePath = Join-Path $OutputDir "Modules\MarketBehaviorFramework.psm1" }
if (-not (Test-Path $modulePath)) { throw "Module not found: $modulePath" }

Import-Module $modulePath -Force -Verbose:$false
Write-Host "Module loaded: $modulePath" -ForegroundColor Green
Write-Host ""

# Resolve output directory
$outDir = Resolve-Path $OutputDir

# ============================================================
#  PHASE 1 -- DATA ACQUISITION
# ============================================================
if (-not $SkipPhase1) {
    Write-Host "PHASE 1: MAXIMUM HISTORICAL DATA ACQUISITION" -ForegroundColor Yellow
    Write-Host "  This will paginate through ALL available history for each asset/timeframe." -ForegroundColor Gray
    Write-Host "  May take several minutes depending on API rate limits." -ForegroundColor Gray
    
    $inv = Invoke-MbfPhase1 -Symbols $Symbols -Timeframes $Timeframes -OutputDir $outDir
    if (-not $inv) { Write-Warning "Phase 1 returned no data -- check API connectivity"; exit 1 }
    
    # Show inventory summary
    Write-Host "`nData inventory:" -ForegroundColor Cyan
    $inv | Format-Table -AutoSize | Out-String | Write-Host
} else {
    Write-Host "PHASE 1: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 2 -- TIMEFRAME DISCOVERY
# ============================================================
if (-not $SkipPhase2) {
    Write-Host "`nPHASE 2: TIMEFRAME DISCOVERY" -ForegroundColor Yellow
    $tfProfile = Invoke-MbfPhase2 -Symbols $Symbols -Timeframes $Timeframes -OutputDir $outDir
    
    Write-Host "`nBest timeframe per asset:" -ForegroundColor Cyan
    $assets = $tfProfile | Group-Object Asset
    foreach ($a in $assets) {
        $best = $a.Group | Sort-Object BehaviorScore -Descending | Select-Object -First 1
        Write-Host "  $($a.Name) -> $($best.Timeframe) (score=$($best.BehaviorScore))" -ForegroundColor Green
        Write-Host "    Trend=$($best.TrendPersistencePct)% MR=$($best.MeanRevStrengthPct)% BreakoutCont=$($best.BreakoutContPct)% VolAC=$($best.VolClusteringAC)" -ForegroundColor Gray
    }
} else {
    Write-Host "PHASE 2: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 3 -- REGIME DISCOVERY
# ============================================================
if (-not $SkipPhase3) {
    Write-Host "`nPHASE 3: REGIME DISCOVERY" -ForegroundColor Yellow
    $regimes = Invoke-MbfPhase3 -Symbols $Symbols -Timeframe $RegimeTimeframe -OutputDir $outDir
    
    if ($regimes) {
        Write-Host "`nRegime distribution summary:" -ForegroundColor Cyan
        $globalDist = $regimes | Group-Object Regime | Sort-Object Count -Descending
        foreach ($rd in $globalDist) {
            $pct = $rd.Count / $regimes.Count * 100
            Write-Host "  $($rd.Name): $($rd.Count) bars ($([Math]::Round($pct,1))%)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "PHASE 3: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 4 -- BEHAVIOR CATALOG
# ============================================================
if (-not $SkipPhase4) {
    Write-Host "`nPHASE 4: BEHAVIOR CATALOG" -ForegroundColor Yellow
    $behaviors = Invoke-MbfPhase4 -Symbols $Symbols -Phase3File "market_regimes.csv" -OutputDir $outDir
    
    if ($behaviors) {
        Write-Host "`nKey behaviors per asset:" -ForegroundColor Cyan
        foreach ($sym in $Symbols) {
            $symB = $behaviors | Where-Object { $_.Asset -eq $sym }
            foreach ($b in $symB) {
                Write-Host "  $sym / $($b.Regime):" -ForegroundColor Gray
                Write-Host "    Continuation=$($b.ContinuationProbPct)% Reversal=$($b.ReversalFreqPct)% Breakout=$($b.BreakoutProbPct)% Fade=$($b.FadeProbPct)%" -ForegroundColor Gray
            }
        }
    }
} else {
    Write-Host "PHASE 4: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 5 -- INDICATOR SENSOR EVALUATION
# ============================================================
if (-not $SkipPhase5) {
    Write-Host "`nPHASE 5: INDICATOR SENSOR EVALUATION" -ForegroundColor Yellow
    Write-Host "  Testing 11 indicators with extensive parameter grids..." -ForegroundColor Gray
    $detRankings = Invoke-MbfPhase5 -Symbols $Symbols -BehaviorFile "behavior_catalog.csv" -Phase3File "market_regimes.csv" -OutputDir $outDir
    
    if ($detRankings) {
        Write-Host "`nBest detectors per asset:" -ForegroundColor Cyan
        foreach ($sym in $Symbols) {
            $symD = $detRankings | Where-Object { $_.Asset -eq $sym }
            $bestF1 = $symD | Sort-Object F1Score -Descending | Select-Object -First 5
            Write-Host "  $sym top detectors:" -ForegroundColor Gray
            foreach ($d in $bestF1) {
                Write-Host "    $($d.Indicator)($($d.Params)) -> $($d.Behavior): F1=$($d.F1Score) Acc=$($d.DetectionAccuracy)% Prec=$($d.Precision)%" -ForegroundColor Gray
            }
        }
    }
} else {
    Write-Host "PHASE 5: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 6 -- REGIME-SPECIFIC CONFIGURATIONS
# ============================================================
if (-not $SkipPhase6) {
    Write-Host "`nPHASE 6: REGIME-SPECIFIC CONFIGURATIONS" -ForegroundColor Yellow
    $playbook = Invoke-MbfPhase6 -Symbols $Symbols -Phase5File "behavior_detector_rankings.csv" -OutputDir $outDir
    
    if ($playbook) {
        Write-Host "`nRegime playbook:" -ForegroundColor Cyan
        foreach ($pb in $playbook) {
            Write-Host "  $($pb.Asset) / $($pb.Regime): 1st=$($pb.BestIndicator1)($($pb.BestParams1)) F1=$($pb.BestF1_1)" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "PHASE 6: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 7 -- WALK-FORWARD VALIDATION
# ============================================================
if (-not $SkipPhase7) {
    Write-Host "`nPHASE 7: WALK-FORWARD VALIDATION" -ForegroundColor Yellow
    $wfResults = Invoke-MbfPhase7 -Symbols $Symbols -PlaybookFile "regime_playbook.csv" -Phase3File "market_regimes.csv" -OutputDir $outDir
    
    if ($wfResults) {
        Write-Host "`nWalk-forward summary (positive expectancy only):" -ForegroundColor Cyan
        $posWf = $wfResults | Where-Object { [double]$_.Expectancy -gt 0 }
        $topWf = $posWf | Sort-Object Expectancy -Descending | Select-Object -First 10
        if ($topWf) {
            foreach ($w in $topWf) {
                Write-Host "  $($w.Asset) / $($w.Regime): $($w.Indicator)($($w.Params)) Exp=$($w.Expectancy) WR=$($w.WinRate)% Sharpe=$($w.Sharpe)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  No configs with positive expectancy across all folds" -ForegroundColor DarkYellow
        }
    }
} else {
    Write-Host "PHASE 7: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 8 -- MONTE CARLO VALIDATION
# ============================================================
if (-not $SkipPhase8) {
    Write-Host "`nPHASE 8: MONTE CARLO VALIDATION" -ForegroundColor Yellow
    $mcResults = Invoke-MbfPhase8 -Symbols $Symbols -Phase7File "walkforward_regime_results.csv" -OutputDir $outDir
    
    if ($mcResults) {
        Write-Host "`nMonte Carlo summary (1000 iterations, fee+slippage variation):" -ForegroundColor Cyan
        $topMc = $mcResults | Sort-Object MeanReturn -Descending | Select-Object -First 10
        foreach ($m in $topMc) {
            Write-Host "  $($m.Asset) / $($m.Indicator)($($m.Params)): MeanRet=$($m.MeanReturn)% CI95=[$($m.CI95Low),$($m.CI95High)] AvgDD=$($m.AvgMaxDrawdown)%" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "PHASE 8: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 9 -- EDGE DISCOVERY
# ============================================================
if (-not $SkipPhase9) {
    Write-Host "`nPHASE 9: EDGE DISCOVERY" -ForegroundColor Yellow
    $edges = Invoke-MbfPhase9 -Symbols $Symbols -Phase7File "walkforward_regime_results.csv" -Phase8File "montecarlo_regime_results.csv" -Phase5File "behavior_detector_rankings.csv" -Phase4File "behavior_catalog.csv" -OutputDir $outDir
    
    if ($edges) {
        Write-Host "`nTop institutional edge candidates:" -ForegroundColor Cyan
        $topEdges = $edges | Sort-Object { [double]$_.AvgExpectancy } -Descending | Select-Object -First 15
        $topEdges | Format-Table Asset, Regime, Indicator, Params, AvgExpectancy, AvgSharpe, PositiveFoldPct, AvgSignalCount -AutoSize | Out-String | Write-Host
    }
} else {
    Write-Host "PHASE 9: SKIPPED" -ForegroundColor DarkGray
}

# ============================================================
#  PHASE 10 -- FINAL REPORT
# ============================================================
if (-not $SkipPhase10) {
    Write-Host "`nPHASE 10: FINAL REPORT" -ForegroundColor Yellow
    $report = Invoke-MbfPhase10 -Phase2File "asset_timeframe_profile.csv" -Phase3File "market_regimes.csv" `
        -Phase4File "behavior_catalog.csv" -Phase5File "behavior_detector_rankings.csv" `
        -Phase6File "regime_playbook.csv" -Phase9File "institutional_edge_candidates.csv" `
        -OutputDir $outDir
}

# ============================================================
#  COMPLETION
# ============================================================
$elapsed = (Get-Date) - $startTime
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host "  ALL PHASES COMPLETE" -ForegroundColor Green
Write-Host "  Elapsed: $($elapsed.Hours)h $($elapsed.Minutes)m $($elapsed.Seconds)s" -ForegroundColor Green
Write-Host "  Output directory: $outDir" -ForegroundColor Green
Write-Host "========================================================================" -ForegroundColor Cyan

# List all output files
Get-ChildItem $outDir -Filter "mbf_*.csv" -Name | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Get-ChildItem $outDir -Filter "*_*.csv" -Name | Where-Object { $_ -match '^(asset_timeframe|market_regimes|behavior_catalog|behavior_detector|regime_playbook|walkforward|montecarlo|institutional_edge|historical_data_inventory)' } | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host "  market_behavior_report.txt" -ForegroundColor Gray
Write-Host "========================================================================" -ForegroundColor Cyan
