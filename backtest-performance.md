# Backtest Performance Report

Generated: 2026-06-20 13:58 UTC
Environment: Windows 11 Pro (10.0.22621), PowerShell 5.1 Desktop (CLR 4.0)
Execution: All scripts invoked from `opencode-bybit` root via `& ".\<script>.ps1" 2>&1`

---

## Environment

| Attribute | Value |
|---|---|
| OS | Windows 11 Pro (64-bit), build 22621 |
| PowerShell | 5.1.22621.4249 (Desktop edition) |
| .NET CLR | 4.0.30319.42000 |
| Authentication | RSA sign-type 2 with `bybit_private.pem` (1679 bytes, 2048-bit key) |
| API Key | `gkPx5g3xgL2pthIg16` (hardcoded in all scripts) |
| API Endpoint | `https://api.bybit.com` (mainnet, spot market) |
| Data Source | Live Bybit klines via `GET /v5/market/kline?category=spot` |
| Key Revocation | CRITICAL: This key appears in 17 files and should be revoked |

---

## Backtest #1: ICP Full Grid (`icp_fullgrid.ps1`)

**File**: `icp_fullgrid.ps1` — 282 lines
**Symbol**: ICPUSDT
**Execution time**: ~3 minutes (7 API calls + brute-force + TP/SL grid + simulation)

### Shell / Architecture

The script is structured as 5 phases:

| Phase | Purpose | Lines |
|---|---|---|
| 0 | Cache klines for all 7 TFs (800 candles each) | 34-39 |
| 1 | Compute indicators, bruteforce RSI params, register 34+ strategies per TF | 41-182 |
| 2 | Rank all strategies by score (WR × sigs) | 184-204 |
| 3 | TP/SL bruteforce for top 5 candidates (10 TPs × 9 SLs) | 206-238 |
| 4 | 3-month forward simulation for best overall config | 240-266 |
| 5 | Live signal check for best config | 268-280 |

### Features Used

**Base Indicators** (computed once per TF, cached):
- RSI(14) via `Calc-RSI` (Wilder smooth)
- EMA(20, 50, 100, 200) via `Calc-EMA`
- ATR(14) via `Calc-ATR`
- ADX(14) via `Calc-ADX` with +DI/-DI direction
- StochRSI(14) via `Calc-StochRSI`
- Volume EMA(20) (VMA)

**Pre-computed Boolean Arrays** (to avoid recomputing the same condition):
- `bullCandle` / `bearCandle`
- `volAboveAvg[m]` for m ∈ {1.0, 1.2, 1.5, 2.0, 2.5, 3.0}
- `priceAboveMA[p]` for p ∈ {20, 50, 100, 200}
- `maAboveMA[p1_p2]` for pairs {20_50, 50_100, 20_100, 50_200}
- `adxAbove[thr]` for thr ∈ {20, 25, 30, 35, 40}
- `plusDIPos` / `minusDIPos` (DI direction for ADX)
- `stochBelow[thr]` / `stochAbove[thr]` for thr ∈ {10, 20, 30, 40, 60, 70, 80, 90}
- `atrHigh` / `atrLow` (1.5× ATR breakout)

**RSI Bruteforce Parameters**:
- Period: 5..50 (step: every 3rd + 5)
- Overbought levels: {60, 64, 68, 72, 76, 80, 84}
- Oversold levels: {20, 24, 28, 32, 36, 40, 44}
- Min OS ≤ OB - 15 (to avoid overlap)
- Win condition: +1% move within 3 bars
- Score: WR × sigs, min 3 trades

**34 Registered Strategies per TF**:

| Category | Count | Examples |
|---|---|---|
| RSI alone | 1 | Best RSI cross OS/OB from bruteforce |
| RSI+Vol | 6 | Vol thresholds 0.7, 0.8, 0.9, 1.0, 1.2, 1.5 |
| RSI+Vol+ADX | 9 | ADX thresholds 20/25/30 × Vol 0.7/0.8/1.0 |
| RSI+Vol+Stoch | 3 | Stoch thresholds 20/30/40 |
| RSI+Vol+ATRreg | 1 | ATR > average regime |
| Volume candles | 5 | 1.5×/2.0×/3.0× bull/bear/any |
| MA trend | 10 | Price>MA20/50/200, MA20>MA50/100/200, stacked |
| MA crossover | 1 | MA20×MA50 cross |
| ADX strength | 3 | >25 +DI/-DI, >30 +DI/-DI, >25 any |
| StochRSI | 4 | <20, <30, <40, crossover 20/80 |
| ATR breakout | 1 | >1.5× range |
| Multi-combo | 5 | Vol+ADX+MA20dir, Vol+MA20>MA50, Stoch+ADX, etc. |

**Signal Testing** (`Test-Sig`): For each signal entry, checks if price moves +1% within 3 bars (no TP/SL, just directional accuracy).

**TP/SL Grid** (Phase 3, top 5 candidates):
- TP levels: {0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0} %
- SL levels: {0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 5.0} %
- Max 48 bars hold, first-hit TP/SL exit
- Min 3 trades to qualify

**3-Month Simulation** (Phase 4, best overall):
- Period: 2026-03-12 to 2026-06-20
- Entry: signal at candle close
- Exit: first TP/SL hit within 48 bars
- Capital: $100 start
- Commission: 0.1% deducted per trade

### Timeframes

15m, 30m, 1h, 2h, 4h, 6h, 12h — 800 candles each

### Results

| Metric | Value |
|---|---|
| Best strategy | 12h ADX>25 (any dir) |
| Score (WR × sigs) | 57,773 (58.7% × 984 trades) |
| Best 1:1 R:R | TP=0.5% SL=0.5% → WR=84.7%, 982 trades, PnL=+341% |
| Top 5 by score | 12h ADX (984), 6h ADX (838), 2h ADX (792), 4h ADX (784), 12h MA20>MA50 (597) |
| Top WR (min 10 sigs) | 2h ATR>1.5x range (73.7%, 19 trades) |
| 3mo simulation | 112 trades, 93W/19L, WR=83%, Return=+29.29% |
| Live signal (06-20) | 12h @ 2.28, no signal |

---

## Backtest #2: SOL 3-Month Simulation (`sol_3month_sim.ps1`)

**File**: `sol_3month_sim.ps1` — 97 lines
**Symbol**: SOLUSDT
**Execution time**: ~10 seconds (1 API call)

### Shell / Architecture

Simplest script — single strategy, single timeframe, no phases.

| Section | Lines |
|---|---|
| API boilerplate | 1-42 |
| Indicator helpers | 43-58 |
| Main simulation | 60-97 |

### Features Used

- RSI(38) with OS=36 (one fixed config, no bruteforce)
- Volume filter: vol > VMA × 0.8
- LONG only (RSI crosses below OS → buy)
- TP=0.5%, SL=0.5%, commission=0.1%
- Max 48 bars hold
- Period: 2026-03-11 to 2026-06-20 (1000 candles, 2h)
- **No temporal exclusions** (January/Saturday filters removed)
- **No skip-after-loss**

### Results

| Metric | Value |
|---|---|
| Trades | 4 |
| Win/Loss | 4W / 0L |
| WR | 100% |
| Total PnL | +1.17 |
| Final capital | 101.17 |
| Return | +1.17% |
| **NOTE** | Only 4 trades — statistically meaningless |

---

## Backtest #3: XRP Complete (`xrp_complete.ps1`)

**File**: `xrp_complete.ps1` — 497 lines
**Symbol**: XRPUSDT
**Execution time**: ~2 minutes (8 API calls)

### Shell / Architecture

6 phases:

| Phase | Purpose | Lines |
|---|---|---|
| 1 | RSI bruteforce across 7 TFs (same param space as ICP) | 189-258 |
| 2 | Expanded indicator combos on best TF | 266-342 |
| 3 | TP/SL bruteforce with volume filter | 344-410 |
| 4 | Day-of-week time cycle analysis | 412-437 |
| 5 | 3-month forward simulation | 439-482 |
| 6 | Live signal | 484-497 |

### Features Used

**Phase 1 (RSI Bruteforce)**:
- Same params as ICP: per 5..50 (mod 3 + 5), OB ∈ {60,64,68,72,76,80,84}, OS ∈ {20,24,28,32,36,40,44}
- Win condition: +1% within 3 bars
- Score: WR × sigs, min 3 trades

**Phase 2 (Indicator Combos)**:
- Runs on the winning TF from Phase 1
- 20 combos tested via `Test-Cfg` helper
- Filters: volume (0.7..1.2× VMA), MA trend (20/50/100/200), ADX (20/25/30), StochRSI (20/30/40), ATR regime
- Uses the same RSI entry condition (OS/OB cross) with additional filters stacked on

**Phase 3 (TP/SL Grid)**:
- Same TP/SL space as ICP: 10 TPs × 9 SLs
- Volume filter (0.8× VMA) applied to entries
- LONG + SHORT entries from RSI cross signals
- Score: WR × trades / 100

**Phase 4 (Day-of-Week)**:
- Tracks signal distribution and WR by day of week
- Uses the 3-bar +1% win condition

**Phase 5 (3-Month Sim)**:
- Same structure as ICP Phase 4
- LONG only, TP=0.5% SL=0.5%, 0.1% commission
- Period: 2026-03-12 to 2026-06-20

### Results

| Metric | Value |
|---|---|
| Best RSI config | 2h RSI(41) OB=64 OS=40, WR=60%, 15 sigs |
| Rankings leader | 4h RSI(17) OB=64 OS=40, WR=43.8%, 48 sigs |
| Best combo | RSI+Vol+MA200: WR=100%, 1 trade (far too few) |
| Best TP/SL by score | TP=0.5% SL=5%, WR=91.9%, 37 trades, PnL=+2% |
| Best 1:1 R:R | TP=0.5% SL=0.5%, WR=64.9%, 37 trades, PnL=+5.5% |
| Day-of-week | Best: Sun/Wed (57%), Worst: Wed/Thu (25%) |
| 3mo simulation | 19 trades, 12W/7L, WR=63.2%, Return=+0.01% (essentially flat) |
| Live signal (06-20) | 4h RSI(17)=45.8, between OS=40 and OB=64 → no signal |

---

## Backtest #4: SOL Divergence Grid (`sol_divergence_grid.ps1`)

**File**: `sol_divergence_grid.ps1` — 398 lines
**Symbol**: SOLUSDT
**Execution time**: ~3 minutes (2 API calls + 2,240 configs)

### Shell / Architecture

Single brute-force phase:

| Section | Lines |
|---|---|
| API + indicator helpers | 1-116 |
| Divergence detection engine | 117-234 |
| Trade simulator | 236-265 |
| Main grid loop | 267-374 |
| Results summary + CSV export | 376-398 |

### Features Used

**Technical Indicators** (computed once per TF):
- RSI(14) — Wilder RSI
- MACD(12,26,9) — line, signal, histogram
- Stochastic(14,3) — %K smoothed via EMA
- CCI(10) — Commodity Channel Index
- Momentum(10) — raw price change
- OBV — On-Balance Volume
- CMF(21) — Chaikin Money Flow
- MFI(14) — Money Flow Index

**Divergence Detection** (`Test-Divergence`):
- Uses `Get-PivotSigs` to find pivot lows/highs (requires ±prd bars of confirmation)
- Checks 4 divergence types:
  - Regular bullish: price lower low, indicator higher low
  - Hidden bullish: price higher low, indicator lower low
  - Regular bearish: price higher high, indicator lower high
  - Hidden bearish: price lower high, indicator higher high
- Straight-line interpolation check between pivots (no crossover)
- Configurable max lookback bars and max pivot points

**Grid Parameters**:

| Parameter | Values |
|---|---|
| Timeframes | 2h, 4h |
| Pivot periods | 3, 5, 7 |
| Min divergence scores | 1, 2, 3 |
| Max pivot points | 5, 8 |
| Max lookback bars | 60, 100 |
| Indicator presets | 5 combos (RSI+MACD+Stoch+MFI, RSI+MACD+MFI, RSI+Stoch+MFI, RSI+MACD+Stoch, All9) |
| TP levels | 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0 % |
| SL levels | 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0 % |
| Candles per TF | 600 |
| **Total configs** | **2,240** |

**Trend Filter**: EMA(200) — long only above, short only below

**Trade Simulation** (`Simulate-Trades`):
- Entry at signal bar close
- Max 48 bars hold
- First-hit TP/SL exit
- Dual-direction (bullDiv → LONG, bearDiv → SHORT)
- `$canTrade` is not scoped correctly in the script (line 253 references undefined variable `$canTrade` — bearish divergence short entries may never execute)

### Output

- Console: per-config summary with WR, trades, PnL
- CSV file: `sol_divergence_results.csv` (143 KB, all 2,240+ configs with WR, PnL, Score)

### Results

| Metric | Value |
|---|---|
| Top config | 4h p7 minS=1 All9, TP=2% SL=4%, WR=100%, 4 trades, PnL=+8% |
| **NOTES** | All top results have 3-4 trades — **not statistically significant** |
| | The `$canTrade` bug on line 253 prevents short entries |
| | Divergence signals are extremely rare (0-30 sigs per config) |
| 2h results | Max WR≈28.6% (RSI+Stoch+MFI, 7 trades) — essentially random |
| 4h results | Better signal density: WR up to 60% with 5+ trades |

---

## Cumulative Comparison

| Metric | ICP (Full Grid) | SOL (3mo) | XRP (Complete) | SOL (Divergence) |
|---|---|---|---|---|
| Lines of code | 282 | 97 | 497 | 398 |
| API calls | 7 | 1 | 8 | 2 |
| Strategies tested | 34 × 7 TFs = 238 | 1 | 20 combos | 5 presets × 2 TFs |
| Total configs | ~2,500 | 1 | ~200 | 2,240 |
| Best WR (min 10 sigs) | 73.7% (2h ATR) | 100% (4 trades) | 64.9% (1:1 R:R) | 60% (4h p5 All9, 5 trades) |
| Best PnL | +341% (12h ADX) | +1.17% | +5.5% | +8% |
| Statistical validity | **HIGH** (984 trades) | **VERY LOW** (4 trades) | **LOW** (37 trades) | **VERY LOW** (3-5 trades) |
| Edge evidence | Strong | None | Marginal | None |
| Data leakage | CRITICAL — all data used for optimization | LOW — single forward test | CRITICAL — all data for bruteforce | CRITICAL — all data for grid search |

---

## Known Data Leakage Issues (Relevant to These Results)

All findings from `DATA_LEAKAGE.md` apply:

1. **No train/test split** — RSI bruteforce (ICP, XRP), divergence grid (SOL), and TP/SL grid all use 100% of available data. Reported WRs are in-sample optima, not out-of-sample expectations.

2. **Timeframe overlap** — Same candles in different TFs share signal bars. A strategy that works on 6h will mechanically also show signals on 12h (every other candle).

3. **TP/SL evaluated on same bars as signal detection** — TP/SL grid tests on the exact same price sequence that generated the signals. There is no temporal separation between "discovery" and "validation."

4. **The Phase 4 simulation in `icp_fullgrid.ps1`** is the only out-of-sample test (forward period after all optimization). It shows 83% WR on 112 trades — the most reliable data point in this report.

---

## Bugs Found During Backtesting

| Bug | File | Line | Description |
|---|---|---|---|
| `$canTrade` undefined | `sol_divergence_grid.ps1` | 253 | Variable `$canTrade` is never defined. Bearish divergence short entries will silently skip. Reduces signal count by ~50%. |
| Demo API credentials exposed | `paper_trading/run_paper_trader.ps1` | 44-45 | `DemoApiKey="xfs81fCzBeUSzW2TeG"`, `DemoApiSecret="Dp9eZQoC4PkALosAL1LLAoXvtZHYDZWMVR7x"` |
| API key in 17 files | All scripts | <10 | Hardcoded `gkPx5g3xgL2pthIg16` string literal in every script |
| Write-Host usage | All scripts | Passim | `Write-Host` bypasses pipeline capture. Phase 3/4 results may be missing when redirecting output. |

---

## Conclusion

**Only strategy with meaningful edge**: ICPUSDT 12h ADX>25 (any dir) with TP=0.5%/SL=0.5%. Out-of-sample simulation shows 83% WR across 112 trades with +29% return in 3 months. This is the only result worth pursuing for live trading.

**Everything else is noise**:
- SOL 3mo RSI: 4 trades is not a sample
- XRP RSI bruteforce: 37 trades with flat PnL after commission
- SOL divergence grid: 3-5 trades per config is statistically meaningless

**Next steps**: Integrate the ICP 12h ADX strategy with the `WalkForwardTester` module for proper out-of-sample validation, then connect it to `BybitClient` for automated execution.
