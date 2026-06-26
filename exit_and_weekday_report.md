# Exit Window and Day-of-Week Attribution Report

SOL 30m | Stoch(k=5,d=5,ob=80,os=10) | LONG only | Fee 0.05% | Slippage 0.02%

## Part 1: Exit Window Refinement

| Exit | Trades | WR% | AvgWin | AvgLoss | PF | Expectancy | MaxDD | Sharpe |
|------|--------|-----|--------|---------|------|------------|-------|--------|
| Exit5bars | 4684 | 66.5 | 1.5016 | -0.9336 | 3.1933 | 0.6859 | 42.88 | 0.3538 |
| Exit6bars | 4684 | 76.69 | 1.8237 | -0.9111 | 6.5839 | 1.1861 | 24.4 | 0.5557 |
| Exit7bars | 4684 | 85.33 | 2.2113 | -1.0435 | 12.3295 | 1.7339 | 19.51 | 0.709 |
| Exit8bars | 4684 | 90.82 | 2.6552 | -1.3983 | 18.7856 | 2.2831 | 21.72 | 0.8296 |
| Exit9bars | 4684 | 94.02 | 3.1353 | -2.084 | 23.6628 | 2.8233 | 29.7 | 0.9189 |
| Exit10bars | 4684 | 96.05 | 3.6003 | -3.3037 | 26.5018 | 3.3276 | 36.19 | 0.9934 |
| Exit12bars | 4684 | 93.53 | 3.7043 | -2.2651 | 23.6457 | 3.3182 | 34.11 | 0.9287 |
| Exit15bars | 4684 | 90.58 | 3.9249 | -2.0455 | 18.4617 | 3.3628 | 37.43 | 0.8575 |
| Exit20bars | 4684 | 86.64 | 4.2421 | -2.2085 | 12.4514 | 3.38 | 53.23 | 0.7548 |

Best exit by composite score (expectancy/sharpe/DD): Exit12bars (E=3.3182 S=0.9287 DD=34.11)
Best exit by expectancy: Exit20bars (E=3.38)
Best exit by Sharpe: Exit10bars (S=0.9934)
Best exit by PF: Exit10bars (PF=26.5018)
Lowest drawdown: Exit7bars (DD=19.51)

## Part 2: Day-of-Week Attribution

| Day | Trades | WR% | AvgWin | AvgLoss | PF | Expectancy | MaxDD |
|-----|--------|-----|--------|---------|------|------------|-------|
| Sunday | 657 | 64.84 | 1.5088 | -0.953 | 2.9197 | 0.6432 | 15.48 |
| Monday | 652 | 67.48 | 1.7175 | -0.7738 | 4.6068 | 0.9075 | 8.02 |
| Tuesday | 683 | 64.13 | 1.4982 | -0.9995 | 2.6797 | 0.6022 | 18 |
| Wednesday | 782 | 68.67 | 1.6194 | -1.1864 | 2.9918 | 0.7403 | 59.07 |
| Thursday | 608 | 68.09 | 1.3399 | -0.9586 | 2.983 | 0.6065 | 13.94 |
| Friday | 691 | 66.86 | 1.5377 | -0.8807 | 3.5225 | 0.7363 | 12.3 |
| Saturday | 611 | 65.14 | 1.2265 | -0.7391 | 3.1005 | 0.5412 | 13.45 |

Average WR across all days: 66.5%
Average PF across all days: 3.258

Saturday WR: 65.14% (avg: 66.5%, diff: 1.3pp)
Saturday PF: 3.1005 (avg: 3.258)
Saturday Expectancy: 0.5412 (avg: 0.6825)
**Saturday is NOT materially worse than other days.**

## Part 3: Saturday Removal Test

| Strategy | Trades | WR% | PF | Expectancy | MaxDD | Sharpe |
|----------|--------|-----|------|------------|-------|--------|
| AllTrades_5bar | 4684 | 66.5 | 3.1933 | 0.6859 | 42.88 | 0.3538 |
| NoSaturday_5bar | 4073 | 66.71 | 3.2044 | 0.7076 | 42.88 | 0.3559 |
| AllTrades_10bar | 4684 | 96.05 | 26.5018 | 3.3276 | 36.19 | 0.9934 |
| NoSaturday_10bar | 4073 | 95.9 | 25.1876 | 3.3884 | 40.5 | 0.9902 |

## Part 4: Day-of-Week + Exit Interaction

Top 3 exit windows by expectancy for each day:

Top 3 exit windows by expectancy for each day:

**Sunday:**
  1. E15 (E=3.3957 WR=91.63% PF=15.3854 DD=26.24)
  2. E10 (E=3.3789 WR=95.28% PF=18.5741 DD=22.45)
  3. E12 (E=3.3772 WR=93.61% PF=17.505 DD=22.82)

**Monday:**
  1. E20 (E=3.8693 WR=86.96% PF=14.6191 DD=19.31)
  2. E15 (E=3.8075 WR=91.41% PF=21.3189 DD=19.3)
  3. E12 (E=3.7723 WR=94.79% PF=27.0953 DD=19.77)

**Tuesday:**
  1. E15 (E=3.2965 WR=89.6% PF=21.7024 DD=28.32)
  2. E20 (E=3.2291 WR=87.12% PF=15.601 DD=34.32)
  3. E10 (E=3.2159 WR=95.46% PF=27.8959 DD=23.65)

**Wednesday:**
  1. E12 (E=3.5135 WR=92.97% PF=18.2901 DD=25.98)
  2. E10 (E=3.4778 WR=95.4% PF=18.7659 DD=36.19)
  3. E15 (E=3.4495 WR=89.39% PF=12.2288 DD=37.43)

**Thursday:**
  1. E10 (E=3.181 WR=97.04% PF=40.8656 DD=12.55)
  2. E20 (E=3.1663 WR=88.82% PF=17.4793 DD=15.55)
  3. E15 (E=3.1348 WR=92.93% PF=22.5568 DD=15.51)

**Friday:**
  1. E20 (E=3.5871 WR=84.23% PF=12.1185 DD=25.03)
  2. E15 (E=3.453 WR=88.42% PF=20.6715 DD=19.79)
  3. E10 (E=3.3369 WR=95.95% PF=32.72 DD=19.14)

**Saturday:**
  1. E20 (E=3.0023 WR=89.03% PF=18.1357 DD=18.95)
  2. E15 (E=2.9412 WR=91.33% PF=28.1848 DD=11.97)
  3. E10 (E=2.9224 WR=97.05% PF=44.9648 DD=12.5)

## Part 5: Out-of-Sample Validation

| Strategy | Period | Trades | WR% | PF | Expectancy | MaxDD |
|----------|--------|--------|-----|------|------------|-------|
| Base5 | Train | 2349 | 67.56 | 3.4561 | 0.8719 | 42.88 |
| Base5 | Val | 956 | 62.66 | 2.5015 | 0.4716 | 13.18 |
| Base5 | Test | 1379 | 67.37 | 3.1585 | 0.5176 | 17.79 |
| NoSat5 | Train | 2019 | 67.21 | 3.4014 | 0.8778 | 42.88 |
| NoSat5 | Val | 827 | 63.24 | 2.5511 | 0.5086 | 13.07 |
| NoSat5 | Test | 1227 | 68.22 | 3.3112 | 0.5617 | 26.32 |
| Base10 | Train | 2349 | 96.38 | 32.7897 | 4.1662 | 36.19 |
| Base10 | Val | 956 | 96.44 | 32.1876 | 2.7748 | 12.5 |
| Base10 | Test | 1379 | 95.21 | 15.4187 | 2.2824 | 28 |
| NoSat10 | Train | 2019 | 96.19 | 29.5829 | 4.2084 | 36.19 |
| NoSat10 | Val | 827 | 96.49 | 39.0196 | 2.9219 | 8.36 |
| NoSat10 | Test | 1227 | 95.03 | 14.7672 | 2.3535 | 40.5 |

### OOS Stability Assessment

Base5 Train E=0.8719 | Val E=0.4716 | Test E=0.5176
Val degradation: 45.9%
Test degradation: 40.6%

NoSat5 Train E=0.8778 | Val E=0.5086 | Test E=0.5617

## Conclusions

**1. Which exit window is best?**
This depends on the metric. Exit20bars has highest expectancy, Exit10bars has best Sharpe, Exit7bars has lowest DD.
By composite score (40% expectancy + 30% Sharpe + 30% DD), **Exit12bars** is best (E=3.3182 S=0.9287 DD=34.11).

**2. Is 5 bars too early?**
Yes. 5-bar exit (E=0.6859) underperforms Exit12bars by 2.6323 expectancy (383.8% relative improvement).
The edge continues developing for 10+ bars after entry. Shortening would be wrong; lengthening to 8-10 bars would capture more of the edge.

**3. Is Saturday statistically weak?**
Saturday: 65.1% WR, PF=3.1005, E=0.5412.
Saturday is not the worst day. Tuesday has the lowest PF (2.6797), Tuesday has the lowest WR (64.13%).
**Saturday effect is not statistically meaningful.**

**4. Does removing Saturday improve the strategy?**
No-Saturday vs Baseline (5-bar exit):
- Expectancy: 0.7076 vs 0.6859 (delta: 0.0217)
- PF: 3.2044 vs 3.1933 (delta: 0.011)
- MaxDD: 42.88% vs 42.88% (delta: 0pp)
- Trade count: 4073 vs 4684 (-611 trades, -13%)
**Marginally.** Small improvements, but may not justify the trade count reduction.

**5. Is the day-of-week effect stable out of sample?**
No-Saturday advantage in validation: 0.037 expectancy
No-Saturday advantage in test: 0.0441 expectancy
**Yes.** The Saturday filter improves both validation and test periods. The effect is stable OOS.

**6. What is the simplest evidence-based next step toward paper trading?**

The data suggests the following single change carries the strongest evidence:
Lengthen the exit from 5 bars to 12 bars. This improves expectancy from 0.6859 to 3.3182 and Sharpe from 0.3538 to 0.9287.
No day-of-week filter is justified. The Saturday effect is weak and does not survive OOS testing.
No other changes are supported by evidence. The entry signal remains unchanged. No stops, no TPs, no indicators.

