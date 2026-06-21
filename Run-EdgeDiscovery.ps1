# Run-EdgeDiscovery.ps1
# Asset-Specific Edge Discovery Framework Runner
# For each asset, discovers how the asset behaves, then derives indicator settings.

param(
    [string[]]$Symbols = @("SOLUSDT", "ICPUSDT"),
    [string]$OutputDir = "edge_discovery_output",
    [switch]$SkipFetch
)

$ErrorActionPreference = "Stop"

# ===== Setup =====
$ScriptDir = Split-Path $PSCommandPath -Parent
$ModulePath = Join-Path (Join-Path $ScriptDir "Modules") "EdgeDiscovery.psm1"
$OutputDir = Join-Path $ScriptDir $OutputDir

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

Import-Module $ModulePath -Force

# ===== Internet Check =====
function Test-Internet {
    try {
        $r = Invoke-WebRequest -Uri "https://api.bybit.com" -UseBasicParsing -TimeoutSec 5 -Method Head
        return $true
    } catch { return $false }
}

if (-not (Test-Internet)) {
    Write-Warning "No internet connection detected. Bybit API is unreachable."
    Write-Warning "The framework requires internet to fetch kline data from Bybit."
    Write-Warning "Run this script again when internet is available."
    Write-Warning ""
    Write-Warning "Alternatively, use -SkipFetch to re-analyze from cached data if available."
    exit 1
}

# ===== Initialize RSA Auth =====
Write-Output "Initializing RSA authentication..."
Initialize-RsaAuth
Write-Output "RSA auth OK"

# ===== Main Loop =====
$allCharacteristics = @()
$allIndicatorSurfaces = @()
$allRegimeMaps = @()
$allFreqFiltered = @()
$allRobustRankings = @()
$allReports = @()

foreach ($sym in $Symbols) {
    Write-Output ""
    Write-Output ("=" * 70)
    Write-Output "  EDGE DISCOVERY: $sym"
    Write-Output ("=" * 70)

    # ============================================================
    # FETCH DATA
    # ============================================================
    Write-Output ""
    Write-Output "Fetching kline data..."

    # Fetch at 4h and 1h for analysis
    $klines4h = Get-Klines $sym 240 1000
    if (-not $klines4h -or $klines4h.Count -lt 200) {
        Write-Error "Failed to fetch 4h data for $sym (got $($klines4h.Count) bars)"
        continue
    }
    Write-Output "  4h: $($klines4h.Count) bars"

    $klines1h = Get-Klines $sym 60 1000
    if (-not $klines1h -or $klines1h.Count -lt 200) { $klines1h = $klines4h }
    Write-Output "  1h: $($klines1h.Count) bars"

    # ============================================================
    # STEP 1: MARKET CHARACTERIZATION
    # ============================================================
    Write-Output ""
    Write-Output "Step 1: Market Characterization..."
    $chars = Get-AssetCharacteristics $sym
    if ($chars.Count -gt 0) {
        $allCharacteristics += $chars
        $charFile = Join-Path $OutputDir "$($sym)_characteristics.csv"
        $chars | Export-Csv -Path $charFile -NoTypeInformation
        Write-Output "  Written to $charFile"
        # Print summary
        $c4 = $chars | Where-Object { $_.TF -eq "240" } | Select-Object -First 1
        if ($c4) {
            Write-Output "  4h: ADX=$($c4.AvgADX) Trend>25=$($c4.PctAbove25)% TrendLen=$($c4.AvgTrendLen)"
            Write-Output "       VolClust=$($c4.VolClustering) RetAuto=$($c4.ReturnAutocorr) BB%=$($c4.MeanRevBBPct)%"
            Write-Output "       BreakFreq=$($c4.BreakoutFreq)% Cont=$($c4.BreakoutContPct)% Fail=$($c4.BreakoutFailPct)%"
        }
    }

    # ============================================================
    # STEP 2: INDICATOR RESPONSE SURFACE
    # ============================================================
    Write-Output ""
    Write-Output "Step 2: Indicator Response Surface..."
    Write-Output "  Testing RSI, ADX, EMACross, Stoch, CCI, CMF, OBV, SMI parameter grids..."
    $surface = Get-IndicatorResponseSurface $sym $klines4h 5
    if ($surface.Count -gt 0) {
        $allIndicatorSurfaces += $surface
        $surfFile = Join-Path $OutputDir "$($sym)_indicator_response_surface.csv"
        $surface | Export-Csv -Path $surfFile -NoTypeInformation
        Write-Output "  Written to $surfFile ($($surface.Count) configs evaluated)"
        # Show top 5 by stability
        $top5 = $surface | Sort-Object Stability -Descending | Select-Object -First 5
        Write-Output "  Top 5 by signal stability:"
        $top5 | ForEach-Object { Write-Output "    $($_.Indicator) $($_.Params) | Freq=$([Math]::Round($_.SignalFreq,2))% Move=$([Math]::Round($_.AvgMove,4))% Adv=$([Math]::Round($_.AvgAdverse,4))% Stab=$([Math]::Round($_.Stability,4))" }
    }

    # ============================================================
    # STEP 3: REGIME DETECTION
    # ============================================================
    Write-Output ""
    Write-Output "Step 3: Regime Detection..."
    $regimes = Get-RegimeLabels $klines4h
    if ($regimes -and $regimes.Count -gt 0) {
        $regFile = Join-Path $OutputDir "$($sym)_regimes.csv"
        $regimes | Export-Csv -Path $regFile -NoTypeInformation
        Write-Output "  Written to $regFile ($($regimes.Count) bars classified)"

        # Regime breakdown
        $regBreakdown = $regimes | Group-Object Regime | Select-Object Name, Count
        $regBreakdown | ForEach-Object { Write-Output "    $($_.Name): $($_.Count) bars" }

        # Regime-Indicator map
        $regMap = Get-RegimeIndicatorMap $sym $klines4h $surface
        if ($regMap.Count -gt 0) {
            $allRegimeMaps += $regMap
            $regMapFile = Join-Path $OutputDir "$($sym)_regime_indicator_map.csv"
            $regMap | Export-Csv -Path $regMapFile -NoTypeInformation
            Write-Output "  Regime-Indicator map written to $regMapFile ($($regMap.Count) entries)"
        }
    }

    # ============================================================
    # STEP 4: FREQUENCY FILTERING
    # ============================================================
    Write-Output ""
    Write-Output "Step 4: Trade Frequency Filtering (target 2-5/day, reject <1.5 or >30/day)..."
    $barsPerDay = 6  # 4h bars per day
    $freqFiltered = Get-FrequencyFilteredConfigs $surface $barsPerDay
    if ($freqFiltered.Count -gt 0) {
        $allFreqFiltered += $freqFiltered
        $freqFile = Join-Path $OutputDir "$($sym)_frequency_filtered_configs.csv"
        $freqFiltered | Export-Csv -Path $freqFile -NoTypeInformation
        Write-Output "  Written to $freqFile ($($freqFiltered.Count) configs pass frequency filter)"

        # Show frequency distribution
        $freqBins = $freqFiltered | ForEach-Object {
            if ($_.DailyFreq -le 2) { "1.5-2" }
            elseif ($_.DailyFreq -le 5) { "2-5" }
            elseif ($_.DailyFreq -le 10) { "5-10" }
            elseif ($_.DailyFreq -le 20) { "10-20" }
            else { "20-30" }
        } | Group-Object | Sort-Object Name
        Write-Output "  Frequency distribution (trades/day):"
        $freqBins | ForEach-Object { Write-Output "    $($_.Name): $($_.Count) configs" }
    } else {
        Write-Output "  No configs pass frequency filter for $sym"
    }

    # ============================================================
    # STEP 5: ROBUSTNESS RANKING
    # ============================================================
    Write-Output ""
    Write-Output "Step 5: Robustness Ranking (walk-forward, Monte Carlo, drawdown, expectancy)..."
    $robust = Get-RobustConfigRankings $freqFiltered $klines4h $regimes 50
    if ($robust.Count -gt 0) {
        $allRobustRankings += $robust
        $robustFile = Join-Path $OutputDir "$($sym)_robust_config_rankings.csv"
        $robust | Export-Csv -Path $robustFile -NoTypeInformation
        Write-Output "  Written to $robustFile ($($robust.Count) configs ranked)"
        Write-Output "  Top 10 robust configs:"
        $robust | Select-Object -First 10 | ForEach-Object {
            Write-Output "    #$([array]::IndexOf($robust,$_)+1) $($_.Indicator) $($_.Params) | Freq=$($_.DailyFreq)/d Move=$($_.AvgMove)% Robust=$($_.RobustScore) WF=$($_.WFStability) MC=$($_.MCStability) DD=$($_.MaxConsecLosses)"
        }
    }

    # ============================================================
    # STEP 6: FINAL REPORT
    # ============================================================
    Write-Output ""
    Write-Output "Step 6: Final Deliverable..."
    $report = Get-EdgeDiscoveryReport $chars $robust $regimes $sym
    if ($report) {
        $allReports += $report
        Write-Output ""
        Write-Output "  ===== $sym EDGE DISCOVERY SUMMARY ====="
        Write-Output "  Market Profile:"
        Write-Output "    Avg ADX: $($report.AvgADX) | Trend Persistence: $($report.TrendPersistence)% above 25"
        Write-Output "    Avg Trend Length: $($report.AvgTrendLen) bars | Avg Strength: $($report.AvgTrendStrength)"
        Write-Output "    Volatility Clustering: $($report.VolClustering)"
        Write-Output "    Return Autocorrelation: $($report.ReturnAutocorr)"
        Write-Output "    Mean Reversion Bias: $($report.MeanRevBias)% BB touches"
        Write-Output ""
        Write-Output "  Best Trend Indicators:"
        Write-Output "    1. $($report.BestTrendIndicator1) ($($report.BestTrendParams1)) Score=$($report.BestTrendScore1)"
        Write-Output "    2. $($report.BestTrendIndicator2) ($($report.BestTrendParams2)) Score=$($report.BestTrendScore2)"
        Write-Output ""
        Write-Output "  Best Mean-Reversion Indicators:"
        Write-Output "    1. $($report.BestMeanRevIndicator1) ($($report.BestMeanRevParams1)) Score=$($report.BestMeanRevScore1)"
        Write-Output "    2. $($report.BestMeanRevIndicator2) ($($report.BestMeanRevParams2)) Score=$($report.BestMeanRevScore2)"
        Write-Output ""
        Write-Output "  Expected Trade Frequency: $($report.ExpectedTradeFreq)/day"
        Write-Output "  Expected Max Consecutive Losses: $($report.ExpectedMaxConsecLosses)"
        Write-Output "  Robust Configs Available: $($report.TopConfigsCount)"
    }
}

# ============================================================
# CONSOLIDATED OUTPUTS
# ============================================================
if ($allCharacteristics.Count -gt 0) {
    $combinedFile = Join-Path $OutputDir "asset_characteristics.csv"
    $allCharacteristics | Export-Csv -Path $combinedFile -NoTypeInformation
    Write-Output ""
    Write-Output "Combined characteristics: $combinedFile"
}

if ($allIndicatorSurfaces.Count -gt 0) {
    Write-Output ""
    $combinedFile = Join-Path $OutputDir "indicator_response_surface.csv"
    $allIndicatorSurfaces | Export-Csv -Path $combinedFile -NoTypeInformation
    Write-Output "Combined indicator surface: $combinedFile"
}

if ($allFreqFiltered.Count -gt 0) {
    Write-Output ""
    $combinedFile = Join-Path $OutputDir "frequency_filtered_configs.csv"
    $allFreqFiltered | Export-Csv -Path $combinedFile -NoTypeInformation
    Write-Output "Combined frequency filtered: $combinedFile"
}

if ($allRobustRankings.Count -gt 0) {
    Write-Output ""
    $combinedFile = Join-Path $OutputDir "robust_config_rankings.csv"
    $allRobustRankings | Export-Csv -Path $combinedFile -NoTypeInformation
    Write-Output "Combined robust rankings: $combinedFile"
}

if ($allReports.Count -gt 0) {
    Write-Output ""
    $reportFile = Join-Path $OutputDir "edge_discovery_report.csv"
    $allReports | Export-Csv -Path $reportFile -NoTypeInformation
    Write-Output "Final report: $reportFile"

    # Print the final report as a table
    Write-Output ""
    Write-Output ("=" * 70)
    Write-Output "  FINAL EDGE DISCOVERY REPORT"
    Write-Output ("=" * 70)
    $allReports | Format-Table -AutoSize -Wrap | Out-String | Write-Output
}

Write-Output ""
Write-Output "Done. All outputs in: $OutputDir"
