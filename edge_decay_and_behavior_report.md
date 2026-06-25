# Edge Decay and Behavior Report

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Data:** 93,871 bars, 2021-02-12 to 2026-06-22
**Total trades:** 4,684
**Baseline:** Sharpe 0.426, PF 4.07, WR 71.5%

---

## 1. Is the edge improving?

**NO**

Yearly average return shows a modest decline over time:
- 2021: 1.32%
- 2022: 0.81%
- 2023: 0.70%
- 2024: 0.61%
- 2025: 0.69%
- 2026: 0.55%

Late half minus early half (yearly avg return): -0.33 percentage points. The trend is slightly negative, not improving.

---

## 2. Is the edge stable?

**YES**

| Metric | 2021 | 2022 | 2023 | 2024 | 2025 | 2026 | Range |
|--------|------|------|------|------|------|------|-------|
| PF | 4.30 | 4.10 | 4.21 | 3.31 | 4.35 | 4.19 | 3.31-4.35 |
| WR% | 72.2 | 73.1 | 70.3 | 67.8 | 73.6 | 71.4 | 67.8-73.6 |
| Sharpe | 0.456 | 0.447 | 0.457 | 0.396 | 0.499 | 0.480 | 0.396-0.499 |

All years show PF > 3.3, WR > 67%, and Sharpe > 0.39. Rolling 6-month windows show flat trend (Sharpe delta = -0.0069). No year has negative total return.

---

## 3. Is the edge degrading?

**NO** (mild decline but not degradation)

Yearly average return declined from 1.32% (2021) to 0.55% (2026). However:
- Sharpe remains consistent (0.396-0.499 in 2024-2026 vs 0.447-0.456 in 2022-2023)
- PF in 2025-2026 (4.35, 4.19) is comparable to 2021 (4.30)
- Rolling window Sharpe trend = -0.0069 (essentially flat)

The decline in average return is offset by consistent Sharpe and PF. No accelerating degradation.

---

## 4. What market behavior appears to generate the profits?

**Trend continuation during overbought conditions.**
**Mean reversion does NOT apply during oversold conditions.**

Signal breakdown:
- Stoch > 80 (overbought): 4,588 trades, avg +0.89%, WR 72.9%, PF 4.89
- Stoch < 10 (oversold): 96 trades, avg -2.20%, WR 2.1%, PF 0.008

The edge is ENTIRELY from overbought entries (97.9% of trades). When Stoch exceeds 80, buying and holding for 5 bars captures trend continuation with high reliability. The oversold condition produces near-zero WR — the Stoch < 10 state does NOT provide a reliable buying opportunity.

58.8% of signals are clustered (consecutive bars), confirming that the strategy captures multi-bar trend runs rather than isolated reversals.

Winner characteristics: immediate favorable movement (AvgMFE +2.08%, AvgMAE -1.00%).
Loser characteristics: early adverse movement (AvgMAE -2.24%, AvgMFE +0.76%).

---

## 5. What regimes contribute most profit?

| Regime | Trades | Net PnL | Expectancy | PF | PnL Share |
|--------|--------|---------|------------|-----|-----------|
| DOWN_TREND | 1,506 | +1,173.5 | +0.78 | 3.67 | 30.3% |
| UP_TREND | 1,181 | +1,000.9 | +0.85 | 4.26 | 25.9% |
| RANGING | 1,349 | +1,028.2 | +0.76 | 4.36 | 26.6% |
| HIGH_VOL | 648 | +670.9 | +1.04 | 4.18 | 17.3% |

Profit is distributed across all four regimes. No single regime dominates. HIGH_VOL produces the highest per-trade expectancy (+1.04%) but the fewest trades. DOWN_TREND produces the most trades and the most total profit.

---

## 6. How fragile is the edge?

| Removal | Avg PF After | Min PF After | Change from Baseline |
|---------|--------------|-------------|---------------------|
| 0% (baseline) | 4.07 | — | — |
| 5% randomly | 4.06 | 3.99 | -0.01 to -0.08 |
| 10% randomly | 4.05 | 3.99 | -0.02 to -0.08 |
| 15% randomly | 4.05 | 3.99 | -0.02 to -0.08 |

The edge does not collapse under random trade removal. Even with 15% of trades removed, PF stays above 3.99. The edge is distributed across all trades rather than concentrated in a few outliers.

---

## 7. Would a researcher reasonably expect the edge to survive future market conditions?

**YES**

Evidence:
1. **Temporal stability:** Consistent Sharpe (0.40-0.50) and PF (3.3-4.4) across 6 years including bull (2021, 2024-2026) and bear/correction (2022, 2023) periods.
2. **Regime independence:** Profitable in all four identified regimes (up trend, down trend, ranging, high volatility). No regime dependency.
3. **Fragility resistance:** Random removal of up to 15% of trades preserves PF > 3.99. Edge is not dependent on specific trade outcomes.
4. **Rolling consistency:** 119 six-month rolling windows show flat Sharpe trend (-0.0069), no accelerating decline.
5. **Behavioral basis:** The edge exploits trend continuation — a recurring market behavior that persists across market cycles.

Caveats:
- Average return per trade has declined from 1.32% (2021) to 0.55% (2026). If this trend continues, expectancy may approach zero within 3-5 years.
- The edge is entirely dependent on overbought (Stoch > 80) conditions. Oversold conditions produce negative expectancy. A structural market regime change that alters Stoch behavior could affect the edge.

---

## Files

| File | Content |
|------|---------|
| `edge_decay_yearly.csv` | Year-by-year metrics (6 years) |
| `edge_decay_rolling.csv` | 119 six-month rolling windows |
| `regime_profit_attribution.csv` | Profit by market regime |
| `trade_lifecycle.csv` | MAE/MFE/hold time per trade |
| `behavior_hypothesis.md` | Detailed behavior analysis |
| `fragility_test.csv` | Random trade removal results |
