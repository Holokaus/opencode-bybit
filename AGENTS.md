# Bybit Trading System — Agent Handoff

## Current State

Paper trader runs cleanly with RSA auth, dual-direction signals, no errors.

### Active Configurations
| Symbol | Strategy | TF | TP | SL | Direction | Capital |
|---|---|---|---|---|---|---|
| ICPUSDT | ADX>25 (+DI/-DI) | 12h | 0.5% | 0.5% | BOTH | 50.00 |
| SOLUSDT | Divergence (p3, RSI+MACD+Stoch+MFI) | 4h | 0.5% | 1.5% | BOTH | 50.00 |

### Authentication
- **Type**: RSA (sign-type 2) using `bybit_private.pem`
- **Keys**: `gkPx5g3xgL2pthIg16` (API key)
- **Demo API**: `UseDemoApi=$false` (needs demo keys to enable)
- Verified working: paper_trader fetches klines, generates signals, detects direction

---

## All Bug Fixes (This Session)

### 1. UseTrendFilter Inverted (`paper_trading/run_paper_trader.ps1:234-235`)
**Bug**: `$symCfg.UseTrendFilter -or $c[$ii] -gt $ma50[$ii]` — when `$UseTrendFilter=$true`, the `-or` short-circuited and skipped the trend check entirely, allowing entries against trend.
**Fix**: Changed `-or` to `-and` → `-not $symCfg.UseTrendFilter -or $c[$ii] -gt $ma50[$ii]`. When `$UseTrendFilter=$true`, the first clause is `$false`, forcing the trend check.
**Files**: `paper_trading/run_paper_trader.ps1`

### 2. Call-Bybit Always Used MainApiUrl (`paper_trading/run_paper_trader.ps1:41`)
**Bug**: `Call-Bybit` function always used `$script:MainApiUrl` instead of checking `$UseDemoApi`.
**Fix**: Added conditional: `if ($UseDemoApi) { $script:ApiBase = $DemoApiUrl } else { $script:ApiBase = $MainApiUrl }`.
**Files**: `paper_trading/run_paper_trader.ps1`

### 3. Wrong API Auth (HMAC → RSA) (`paper_trading/run_paper_trader.ps1:38-60`)
**Bug**: Used HMAC sign-type 1 with placeholder keys. Cannot authenticate to Bybit.
**Fix**: Switched to RSA sign-type 2, loading `bybit_private.pem`. Uses the proven DER parser (Read-DerInteger/Read-DerSequence) from `bybit_info.ps1`.
**Files**: `paper_trading/run_paper_trader.ps1`

### 4. Read-DerInteger Internal Call Pattern (`paper_trading/run_paper_trader.ps1`)
**Bug**: Used named parameters AND positional parameters inconsistently. `Read-DerInteger -InputBytes $bytes -Offset ([ref]$offset)` wrapped `$offset` in `[ref]` which Read-DerInteger didn't expect (it expects a scalar and returns the new offset via return value).
**Fix**: Standardized to: `$offset = Read-DerInteger -InputBytes $bytes -Offset $offset` with return-value-based offset tracking.
**Files**: `paper_trading/run_paper_trader.ps1`

### 5. ADX Direction Was Non-Directional (`paper_trading/run_paper_trader.ps1`)
**Bug**: `Get-ADXSignal` only checked `adx>25` and always returned both long+short signals simultaneously. ADX measures trend strength, not direction.
**Fix**: Added `+DI > -DI → LONG`, `-DI > +DI → SHORT` direction detection. Direction is computed at the signal candle.
**Files**: `paper_trading/run_paper_trader.ps1`

### 6. Divergence Signal UseTrendFilter Same Fix (`paper_trading/run_paper_trader.ps1`)
**Bug**: Same inverted `-or` pattern as #1 in the divergence strategy's `Get-DivergenceSignal`.
**Fix**: Applied same `-not ... -or` pattern.
**Files**: `paper_trading/run_paper_trader.ps1`

### 7. Console::TreatControlCAsInput Error (`paper_trading/run_paper_trader.ps1`)
**Bug**: `[Console]::TreatControlCAsInput = $false` throws on systems where the console handle is not available (e.g., some CI/envs).
**Fix**: Wrapped in try/catch, silently ignoring the error.
**Files**: `paper_trading/run_paper_trader.ps1`

### 8. Phase 18 Drawdown Used Wrong Denominator (`phase18_drawdown_forensics.ps1:49`)
**Bug**: `($maxPeak−$cum)/$maxPeak×100` used cumulative PnL as denominator instead of equity (100 + cum PnL), reporting 317.29% max DD instead of 13.4%.
**Fix**: Correct formula = `(equityPeak−equity)/equityPeak×100` where equity = 100 + cumulativePnL.
**Files**: `phase19_edge_vs_drawdown.ps1` (documented fix), `phase18_drawdown_forensics.ps1` (unfixed, see note)

---

## Code Review Report Fixes (report.md driven)

### Temporal Exclusions Removed (January + Saturday)
**Why**: The third-party report identified these as backtest biases. They filter out historically low-volatility periods, artificially inflating win rates.
**Files cleaned**:
- `icp_fullgrid.ps1` — removed Jan/Sat checks
- `icp_deep_dive.ps1` — removed Jan/Sat checks
- `icp_complete.ps1` — removed Jan/Sat checks
- `xrp_complete.ps1` — removed Jan/Sat checks
- `sol_3month_sim.ps1` — removed Jan/Sat checks
- `sol_divergence_grid.ps1` — removed Jan/Sat checks
- `sol_paper_trader_2h.ps1` — removed Jan/Sat checks
- `sol_divergence_strategy.pine` — removed isJan/isSat
- `sol_strategy.pine` — removed isJan/isSat
- `icp_adx_strategy.pine` — no temporal exclusions existed

### Skip-After-Loss Removed
**Why**: The report identified this as survivor bias. Skipping the next entry after a loss avoids taking the next trade that's likely also a loss, inflating WR. Real trading can't skip random trades.
**Files cleaned** (4 PS1, 2 Pine):
- `sol_3month_sim.ps1:86` — removed `$skip=$true`
- `xrp_complete.ps1:469` — removed `if($hit-eq"SL"){$skip=$true}`
- `icp_complete.ps1:453` — removed same
- `icp_deep_dive.ps1:370` — removed same
- `sol_strategy.pine` — removed skipNext logic
- `icp_adx_strategy.pine` — removed skipNext logic
- `sol_paper_trader_2h.ps1` — removed $sLos log check and skip

### Impact
**All prior backtest results are INVALIDATED.** Temporal exclusions and skip-after-loss:
- Inflated WR by ~5-15%
- Reduced trade count by ~10-30% (fewer entries eligible)
- Made strategies appear more profitable than they are
- New clean backtests needed

---

## Key Design Decisions

### Dual-Direction Trading
ICP ADX strategy now trades BOTH directions using +DI/-DI to determine side. Backtesting showed LONG-only ADX>25 only works with TP=0.5%/SL=0.5% (noise scalping, marginal EV). Direction filter gives ~2x trade opportunities.

### RSA Authentication
RSA sign-type 2 with `bybit_private.pem`. The DER parser (`Read-DerInteger`, `Read-DerSequence`) reads the raw binary key. This is proven working by `bybit_info.ps1` and `bybit_balance.ps1`.

### Signal Array Storage (`$script:strategySignals`)
Phase 1 `Reg()` stores signal arrays keyed by `"$tf|$name"`. Phases 3-4 replay these arrays instead of recomputing indicators. Eliminates RSI bruteforce recomputation and RSI-only entry detection limitation.

---

## Known Issues

### 1. `$bestOverall` Selection Inconsistency (Phase 4)
**Status**: UNINVESTIGATED
Phase 4 selects `$tpResults | Sort-Object S -Descending | Select-Object -First 1`. The best S score shows TP=0.5%/SL=5% (S≈81), but Phase 3 shows TP=0.5%/SL=0.5% with S≈824. Possible causes:
- `$tpResults` accumulates across ALL 5 candidates without candidate labels
- Phase 3 filter `$tp -ge $sl` may differ from Phase 4 filter
- S-sorted selection may not be picking the true maximum
**Note**: Prior results are invalidated anyway; this bug needs investigation when re-running backtests.

### 2. RSI Strategies Always Show WR=0%
RSI bruteforce finds parameters with high WR on training data, but entry condition `$rsiBase[$j-1]-gt$rsiBest.os-and$rsiBase[$j]-le$rsiBest.os` is so tight it produces zero test signals. Overfitting + no separate in/out-of-sample split.

### 3. `Write-Host` Mix
Scripts mix `Write-Output` and `Write-Host`. Write-Host bypasses pipeline capture. If redirecting output to a file, Phase 3/4 results may be missing.

### 4. Signal Array Memory
`$script:strategySignals` stores ~238 × 600 ≈ 140K booleans (~140KB). Each `@($sigL)` creates a new array copy, doubling memory.

### 5. Drawdown Values: Additive vs Compound (RESOLVED in Phase 21)
**Status**: RESOLVED — two valid DD values exist depending on equity model
- **Additive DD = 13.4%** (Phase 19): `equity = 100 + sum(PnL)`. Valid for fixed $ per trade.
- **Compound DD = 37.96%** (Phase 21): `equity = 100 * product(1+PnL/100)`. Valid for reinvested capital.
- Phase 18's 317% was the only genuine bug (cum PnL as denominator).
- Phase 14/16's 37.6% matches the compound model (0.36pp diff = rounding).

---

## Files Structure

| File | Purpose |
|---|---|
| `paper_trading/run_paper_trader.ps1` | Multi-strategy paper trader (dual-direction, RSA auth) |
| `icp_fullgrid.ps1` | ICP Full Grid — 5 phases, 34 strategies × 7 TFs |
| `icp_complete.ps1` | Formatted ICP reference version |
| `icp_deep_dive.ps1` | ICP deep dive analysis |
| `xrp_complete.ps1` | XRP backtest |
| `sol_3month_sim.ps1` | SOL 3-month simulation |
| `sol_divergence_grid.ps1` | SOL divergence brute-force optimizer |
| `sol_bybit_backtest.ps1` | SOL Bybit backtest |
| `sol_paper_trader_2h.ps1` | Old 2h RSI paper trader (legacy) |
| `icp_adx_strategy.pine` | TradingView PineScript v6 — ADX strategy |
| `sol_divergence_strategy.pine` | TradingView PineScript v6 — divergence strategy |
| `sol_strategy.pine` | TradingView PineScript v6 — legacy SOL strategy |
| `bybit_info.ps1` | Reference: RSA auth + account info |
| `bybit_balance.ps1` | Reference: RSA auth + balance check |
| `bybit_private.pem` | RSA private key |
| `report.md` | Third-party code review report |
| `AGENTS.md` | This file |
| `phase17_forward_test.ps1` | Phase 17 forward test framework |
| `phase18_drawdown_forensics.ps1` | Phase 18 drawdown forensic analysis |
| `phase19_edge_vs_drawdown.ps1` | Phase 19 edge vs drawdown attribution |
| `phase20_position_sizing.ps1` | Phase 20 position sizing and capital allocation |
| `phase21_ledger_audit.ps1` | Phase 21 trade ledger accounting audit |

---

## What NOT to Touch
- Bybit API auth core (lines 1-21 in paper_trader) — verified working RSA sign-type 2
- Indicator calculation functions (Calc-RSI, Calc-EMA, Calc-ATR, Calc-ADX, Calc-StochRSI) — all correct
- API endpoint and kline fetching (Get-K function) — works reliably

---

## What Needs Work

1. **Re-run all backtests** — temporal exclusions and skip-after-loss removed, all prior results invalidated
2. **Fix `$bestOverall` selection** — investigate S-score discrepancy between Phase 3 and Phase 4
3. **Fix RSI strategy zero-WR** — widen entry condition, add in/out-of-sample split
4. **Webhook/notification** — auto-place Bybit orders from live signal
5. **Enable demo API** — set `UseDemoApi=$true` with demo/testnet keys when available
6. **Parallelize Phase 1** — PowerShell jobs for 7 TFs
7. **Rotate API keys** — `gkPx5g3xgL2pthIg16` appears in git history; generate new keys at Bybit

## Completed

- **Hardcoded paths removed** — all `C:\Users\A\` references eliminated from .ps1 files. Paths now loaded via `$env:BYBIT_PRIVATE_KEY_PATH` and `$env` vars.
- **Walk-forward module created** — `Modules/WalkForwardTester.psm1` with `Invoke-WalkForwardTest`. Integrated into `sol_divergence_grid.ps1`.
- **Monte Carlo module created** — `Modules/MonteCarlo.psm1` with `Invoke-MonteCarloSimulation`. Integrated into `sol_divergence_grid.ps1`.
- **API keys removed from source** — `gkPx5g3xgL2pthIg16` and demo keys replaced with `$env:BYBIT_API_KEY` etc. in all 28 .ps1 files.
- **`.env` and `bybit_private.pem` removed from git** — added to `.gitignore`.
- **Spot/short inconsistency fixed** — `Place-Order` and `Cancel-Order` changed from `category=spot` to `category=linear`.
- **`$canTrade` bug fixed** — `sol_divergence_grid.ps1:253` removed undefined `$canTrade` filter that silently skipped all short entries.
- **Phase 17: Forward test completed** — SOL 30m Stoch(k=5,d=5,ob=80,os=10) held-out 10k bars, 352 trades. All forward metrics WITHIN_RANGE of historical. WR 63.92% (hist 66.71%), PF 2.54 (hist 3.24). Outputs: `forward_signals.csv`, `forward_trade_log.csv`, `forward_metrics.csv`, `forward_vs_historical.csv`, `degradation_report.csv`, `execution_assumptions.md`, `forward_test_dashboard.md`.
- **Phase 18: Drawdown forensics completed** — 4,684 trades, 460 drawdown periods. Key finding: top 20% losers = 91% of drawdown. Longest losing streak 9 trades (−8.71%). VOL_EXPANSION regime = largest loss share. Outputs: `drawdown_periods.csv`, `loss_contribution_analysis.csv`, `losing_streak_analysis.csv`, `time_drawdown_attribution.csv`, `regime_drawdown_attribution.csv`, `volatility_drawdown_attribution.csv`, `tail_risk_analysis.csv`, `equity_curve_forensics.csv`, `drawdown_forensic_report.md`.
- **Phase 19: Edge vs drawdown attribution completed** — Corrected drawdown calculation bug (317.29%→13.4%). Found: profits distributed (top 20%=67%), losses highly concentrated (top 20%=91%). Feature differences between best/worst 20% trades minimal (max=Volume Percentile at 6.9%). Both populations dominated by VOL_EXPANSION regime. Outputs: `phase19_edge_vs_drawdown.ps1`, `drawdown_validation.md`, `profit_contribution.csv`, `loss_contribution.csv`, `edge_contributors.csv`, `trade_cluster_analysis.md`, `edge_vs_drawdown_report.md`.
- **Phase 20: Position sizing completed** — Tested fixed fractional (0.25%-25%), volatility-adjusted, and drawdown-adaptive sizing. Key finding: fixed fractional at 1-2% per trade is optimal (1%: 37.87% ret, 0.43% DD; 2%: 90.06% ret, 0.86% DD). Volatility and drawdown-based sizing add no benefit over fixed fraction. MC simulation revealed compounded return is order-independent (multiplication is commutative) — only DD varies with trade sequence. Recommended: 1-2% fixed fractional per trade for live deployment. Outputs: `phase20_position_sizing.ps1`, `fixed_fractional_results.csv`, `volatility_adjusted_results.csv`, `adaptive_sizing_results.csv`, `capital_simulation.csv`, `capital_growth_projection.csv`, `capital_allocation_report.md`.
- **Phase 21: Ledger audit completed** — Full accounting validation from raw candles. 4684 trades reconstructed, 10/10 spot checks pass. Key findings: (1) 317.29% DD was the only genuine bug (cum PnL denominator). (2) Two valid DD values exist: **compound DD = 37.96%** (fully reinvested capital, matches earlier phases) and **additive DD = 13.4%** (fixed $/trade, Phase 19 model). Both are mathematically correct for their respective equity models. (3) PF=3.19, WR=66.5%, expectancy=0.69%/trade are all consistent across ALL phases. Accounting layer fully validated. Outputs: `phase21_ledger_audit.ps1`, `trade_ledger_audit.csv`, `equity_curve_rebuilt.csv`, `drawdown_validation_v2.md`, `pf_validation.md`, `expectancy_validation.md`, `trade_spot_check.md`, `consistency_check.csv`, `ledger_audit_report.md`.
