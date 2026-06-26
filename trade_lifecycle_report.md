# Trade Lifecycle Report

SOL 30m | Stoch(k=5,d=5,ob=80,os=10) | LONG only | 4684 trades | Fee 0.05% | Slippage 0.02%

## Edge Evolution Summary

| Bar | WR% | PF | Expectancy | AvgRet% | Net PnL% | Compound Ret% | Max DD% | Sharpe |
|-----|-----|----|------------|---------|----------|---------------|---------|--------|
| 1 | 41.03 | 0.6669 | -0.1162 | -0.1162 | -544.12 | -99.65 | 556.37 | -0.1247 |
| 2 | 45.54 | 0.8852 | -0.0483 | -0.0483 | -226.08 | -92.95 | 277.06 | -0.0378 |
| 3 | 51.54 | 1.2415 | 0.1033 | 0.1033 | 483.88 | 7236.77 | 66.37 | 0.0684 |
| 4 | 57.51 | 1.8509 | 0.3312 | 0.3312 | 1551.55 | 263547136.67 | 65.45 | 0.192 |
| 5 | 66.5 | 3.1933 | 0.6859 | 0.6859 | 3212.75 | 3.37932199945946E+15 | 42.88 | 0.3538 |
| 6 | 76.69 | 6.5839 | 1.1861 | 1.1861 | 5555.7 | 3.47095499698191E+25 | 24.4 | 0.5557 |
| 7 | 85.33 | 12.3295 | 1.7339 | 1.7339 | 8121.56 | 2.48461335215962E+36 | 19.51 | 0.709 |
| 8 | 90.82 | 18.7856 | 2.2831 | 2.2831 | 10694.06 | 1.60381344115944E+47 | 21.72 | 0.8296 |
| 9 | 94.02 | 23.6628 | 2.8233 | 2.8233 | 13224.19 | 5.62521675745462E+57 | 29.7 | 0.9189 |
| 10 | 96.05 | 26.5018 | 3.3276 | 3.3276 | 15586.46 | 3.46762730695333E+67 | 36.19 | 0.9934 |
| 11 | 94.85 | 24.5948 | 3.3104 | 3.3104 | 15505.94 | 1.35751261092015E+67 | 32.66 | 0.9545 |
| 12 | 93.53 | 23.6457 | 3.3182 | 3.3182 | 15542.36 | 1.68231986993221E+67 | 34.11 | 0.9287 |
| 13 | 92.83 | 22.6221 | 3.3302 | 3.3302 | 15598.79 | 2.47001866808783E+67 | 36.02 | 0.9048 |
| 14 | 91.59 | 20.2755 | 3.3446 | 3.3446 | 15666.15 | 3.84613433912645E+67 | 35.03 | 0.8783 |
| 15 | 90.58 | 18.4617 | 3.3628 | 3.3628 | 15751.44 | 7.2410050821743E+67 | 37.43 | 0.8575 |
| 16 | 89.52 | 16.6487 | 3.3658 | 3.3658 | 15765.26 | 6.55318840320896E+67 | 42.43 | 0.8297 |
| 17 | 89.13 | 15.6422 | 3.3701 | 3.3701 | 15785.73 | 6.90505827471292E+67 | 39 | 0.8119 |
| 18 | 88.26 | 14.5192 | 3.3693 | 3.3693 | 15781.76 | 5.72895550842698E+67 | 42.26 | 0.7935 |
| 19 | 87.23 | 13.5743 | 3.3742 | 3.3742 | 15804.89 | 6.00087143470088E+67 | 48.81 | 0.7754 |
| 20 | 86.64 | 12.4514 | 3.38 | 3.38 | 15831.9 | 6.19481200739863E+67 | 53.23 | 0.7548 |

## 1. Is the current 5-bar exit near the optimum?

**NO.** The 5-bar exit (Compound Return = 3.37932199945946E+15%, Sharpe = 0.3538) is not at the global optimum.
- Best holding period by Compound Return: 15 bars (7.2410050821743E+67%, Sharpe 0.8575)
- Best holding period by Sharpe: 10 bars (0.9934, Compound Return 3.46762730695333E+67%)

## 2. Where does the edge appear strongest?

Examining how WR, PF, expectancy, and Sharpe evolve with holding period:
- WR at bars 1-3: 46%
- WR at bars 10-20: 90.9%
- Peak PF: bar 10 (PF=26.5018)
- Peak Expectancy: bar 20 (E=3.38)
- Peak Sharpe: bar 10 (S=0.9934)

## 3. Do winners mature early or late?

- Average PnL trajectory shows 50% of final gain achieved by bar 7.
- Average PnL trajectory shows 75% of final gain achieved by bar 9.
- Average PnL trajectory shows 90% of final gain achieved by bar 10.
- Winners mature **late**.

## 4. Do losers become unrecoverable early or late?

- Average bar of worst MAE: 5.71
- Losers that ever recover to positive: 94.3%
- Losers continue worsening **after** the current 5-bar exit.

## 5. Is exit timing the main remaining source of improvement?

- Current (5-bar): Compound Return = 3.37932199945946E+15%, PF = 3.1933, Sharpe = 0.3538
- Best alternative: 15 bars: Compound Return = 7.2410050821743E+67%, PF = 18.4617, Sharpe = 0.8575
- Potential improvement from changing exit: 2.14273901194753E+54% relative change in compound return
- **YES.** Exit timing has substantial impact. The edge continues to develop well beyond the current 5-bar exit.

## Supporting Files

- trade_lifecycle.csv: Bar-by-bar PnL for all 4684 trades
- holding_period_comparison.csv: Edge metrics at each holding period 1-20
- winner_progression.md: Winner MFE and milestone analysis
- loser_progression.md: Loser MAE and recovery analysis
- exit_efficiency.md: Exit timing efficiency assessment
- holding_period_metrics.csv: Full equity simulation by holding period

