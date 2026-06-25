# Forward Test Dashboard

**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) - LONG ONLY - 5-bar hold
**Historical period:** bars 0..83870 (4332 trades)
**Forward period:** bars 83871..93870 (352 trades)

## 1. How many signals were generated?
- **Forward signals:** 352
- **Forward trades (after 5-bar exit):** 352
- **Signal rate:** 3.52% of forward bars

## 2. How many trades were executed?
- **Forward trades:** 352
- **Historical trades:** 4332

## 3. How does forward performance compare to historical?

| Metric | Historical | Forward | Status |
|--------|-----------|---------|--------|
| WinRate | 66.71 | 63.92 | WITHIN_RANGE |
| ProfitFactor | 3.2358 | 2.544 | WITHIN_RANGE |
| Expectancy | 1.3441 | 0.9078 | WITHIN_RANGE |
| AvgReturnPerTrade | 0.7095 | 0.3955 | WITHIN_RANGE |
| SharpeAnnualized | 39.367 | 34.6859 | WITHIN_RANGE |
| MaxDrawdown | 317.29 | 224.79 | INFO |
| TotalTrades | 4332 | 352 | FORWARD_PERIOD |

| Fees+slippage | 0.14% round-trip | 0.14% round-trip | same |

## 4. Is the edge behaving as expected?
- **Edge status:** YES
- **Forward expectancy:** 0.9078
- **Historical expectancy:** 1.3441
- **Forward signal composition:** 340 overbought, 12 oversold
- **Forward Sharpe (annualized):** 34.6859
- **Historical Sharpe (annualized):** 39.367

## 5. Has degradation been detected?
- **Degradation:** YES
  - WR dropped 25.71 pp at trade 205
  - WR dropped 28.57 pp at trade 307

| Period | Trades | WinRate | AvgReturn |
|--------|--------|---------|-----------|
| Early half | 176 | 62.5% | 0.4236 |
| Late half | 176 | 65.34% | 0.3674 |

## Execution Assumptions
- Fee: 0.05% per side (0.10% round trip)
- Slippage: 0.02% per side (0.04% round trip)
- Total friction: 0.14% round trip
- Entry: close of signal bar + slippage + fee
- Exit: close of bar+5 - slippage - fee
- Holding period: 5 bars (150 minutes)
- Direction: Long only

## Output Files
- forward_signals.csv : All forward period signals
- forward_trade_log.csv : Every forward trade with PnL
- forward_metrics.csv : Cumulative performance tracking
- forward_vs_historical.csv : Historical vs forward comparison
- degradation_report.csv : Degradation analysis
- execution_assumptions.md : Full assumption documentation
- forward_test_dashboard.md : This file
