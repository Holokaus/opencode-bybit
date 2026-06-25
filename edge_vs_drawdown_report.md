# Edge vs Drawdown Attribution Report

**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) - LONG ONLY - 5-bar hold
**Corrected max drawdown:** 13.4%
**Trades analyzed:** 4684
**Total winners:** 3115 (66.5%)
**Total losers:** 1569 (33.5%)
**Net PnL:** 3212.75%

---

## 1. Which trades generate most profits?

- Top 1% of trades contribute 9.45% of total profits
- Top 5% of trades contribute 30.16% of total profits
- Top 10% of trades contribute 46.34% of total profits
- Top 20% of trades contribute 67.41% of total profits

Profits are **distributed** across many trades.

## 2. Which trades generate most drawdown?

- Top 1% of trades contribute 18.03% of total drawdown
- Top 5% of trades contribute 48.03% of total drawdown
- Top 10% of trades contribute 68.6% of total drawdown
- Top 20% of trades contribute 91.08% of total drawdown

Drawdown is **highly concentrated** in the worst 20% of trades (91% of losses).

## 3. Are profits and drawdown from the same population?

- Top 20% of trades produce 67.41% of profits
- Top 20% of trades produce 91.08% of drawdown
- Profit/Loss concentration ratio (top 20%): 0.74

NO. Profits and drawdown have different concentration profiles, suggesting different sub-populations may be responsible.

## 4. Can losing trades be distinguished from winning trades?

Feature comparison (best 20% vs worst 20% trades):

| Feature | Best 20% | Worst 20% | Difference |
|---------|---------|-----------|-----------|
| ATR Percentile | 51.74 | 52.56 | -0.82 |
| Volume Percentile | 55.62 | 52.02 | 3.6 |
| Stoch K | 50.06 | 50.8 | -0.74 |
| ADX | 33.94 | 36.24 | -2.3 |
| Average PnL | 3.37 | -1.43 | 4.79 |

Dominant regime for best trades: VOL_EXPANSION
Dominant regime for worst trades: VOL_EXPANSION

NO. The feature differences between best and worst trades are small (max = Volume Percentile at 6.9%). Winning and losing trades occur under statistically similar conditions.

## 5. Is drawdown concentrated in a specific trade type?

By regime: VOL_EXPANSION contributes 33% of total losses.
By volatility: HIGH_VOL is the largest loss bucket.

PARTIALLY. The largest loss regime (VOL_EXPANSION) contributes 33% of losses, but losses are distributed across multiple regimes and volatility levels.

---

## Summary

The corrected max drawdown of 13.4% resolves the discrepancy with earlier phases.
Drawdown is highly concentrated: top 5% of trades = 48.03% of losses, top 20% = 91.08% of losses.
The best and worst trades occur under similar market conditions. Entry features alone cannot reliably
distinguish future winners from future losers.
