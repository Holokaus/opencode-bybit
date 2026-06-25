# Forward Test Dashboard

## 1. How many signals were generated?
- **Signals generated:** 1
- **Signal period:** 2026-06-22 22:30 to 2026-06-22 22:30
- **Forward bars available:** 154

## 2. How many trades were executed?
- **Trades executed:** 1
- **First trade:** 2026-06-22 22:30
- **Last trade:** 2026-06-22 22:30

## 3. How does forward performance compare to historical?

| Metric | Historical (Expected) | Forward (Observed) | Status |
|--------|----------------------|--------------------|--------|
| WinRate | 71.5 | 0 | DIVERGED |
| ProfitFactor | 4.07 | 0 | DIVERGED |
| Expectancy | 0.7 | -0.431 | DIVERGED |
| AvgReturnPerTrade | 0.7 | -0.431 | DIVERGED |
| TotalTrades | 4684 | 1 | FORWARD_PERIOD |

## 4. Is the edge behaving as expected?
- **Edge status:** YES
- **Observation:** 
  - Cumulative forward PnL: -0.431%
  - Forward WR: N/A (insufficient trades for rolling metrics)

## 5. Has degradation been detected?
- **Degradation flag:** NO
- **Reasons:** None detected

## Execution Assumptions
- **Fee per side:** 0.05% (Bybit linear futures VIP0)
- **Slippage per trade:** 0.02%
- **Entry:** Close of signal bar (market order at close price + slippage + fee)
- **Exit:** Close of bar (entry+5) (market order at close price - slippage - fee)
- **Holding period:** 5 bars (fixed, frozen)
- **Direction:** Long only (as validated in Phase 14/16)

## Output Files
- forward_signals.csv - All forward signals
- forward_trade_log.csv - Every executed trade with fees/slippage
- forward_metrics.csv - Continuous performance tracking
- forward_vs_historical.csv - Historical comparison
- degradation_report.csv - Degradation analysis
