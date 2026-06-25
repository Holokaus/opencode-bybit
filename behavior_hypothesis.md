# Behavior Hypothesis

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Data:** 93,871 bars, 2021-02-12 to 2026-06-22

---

## Signal Composition

Analysis of Stoch values at signal bars:

| Signal Type | Trades | Avg Return | WR | PF |
|-------------|--------|------------|-----|------|
| Overbought (Stoch > 80) | 4,588 (97.9%) | +0.89% | 72.9% | 4.89 |
| Oversold (Stoch < 10) | 96 (2.1%) | -2.20% | 2.1% | 0.008 |
| Other | 0 | — | — | — |

**Key finding:** 97.9% of trades come from Stoch > 80 (overbought) signals. Oversold signals produce near-zero WR and negative expectancy.

## Signal Structure

- Isolated signals: 1,930 (41.2%)
- Consecutive/clustered signals: 2,756 (58.8%)

Majority of signals occur in clusters (consecutive bars during a Stoch excursion above 80).

## Behavior Identification

### Rejected hypotheses

**Mean reversion (selling overbought):** If the edge were mean reversion, short entries at Stoch > 80 would show negative long returns (price pulls down during hold period). Instead, overbought entries show POSITIVE long returns (+0.89% avg, 72.9% WR). The price continues UP after entry.

**Oversold bounce (buying oversold):** Stoch < 10 entries show -2.20% avg return with 2.1% WR — price continues DOWN after entry. Not a valid edge.

### Supported hypothesis

**Trend continuation following:** The edge profits from entering PRICE TRENDS during their early-to-mid stages.

- Stoch > 80 signals indicate the trend has pushed the oscillator into overbought territory
- Entry occurs during the trend continuation (not at exhaustion)
- Exit 5 bars later captures continued trend movement
- 58.8% of signals are clustered, confirming trend persistence over multiple bars

### Mechanism

1. A price trend begins (upward, for Stoch > 80 signals)
2. Stoch rises over several bars from neutral (50) toward overbought (80)
3. Once Stoch > 80, each bar triggers a signal
4. Entry at signal bar — price continues in trend direction during the 5-bar hold
5. Exit captures positive return from trend continuation

### Evidence

**Year-by-year stability:** All years show PF > 3.3 and WR > 67%. Average trade return is stable across 2021-2026 (0.55% to 1.32%). Yearly trend (late half minus early half) is -0.33 percentage points — a mild decline in average return, not a collapse.

**Rolling window trend:** 119 six-month windows show a trend of -0.0069 Sharpe — essentially flat. No meaningful degradation over time.

**MAE/MFE profiles:**
- Winners: AvgMAE = -1.00%, AvgMFE = +2.08% — trades move favorably quickly
- Losers: AvgMAE = -2.24%, AvgMFE = +0.76% — trades move against entry significantly before reversing

Winners are characterized by immediate favorable movement. Losers are characterized by early adverse movement followed by an incomplete recovery.

**Fragility:** Removing 5-15% of random trades preserves PF between 3.99 and 4.06 — the edge does not depend on any specific subset of trades.

## Conclusion

The observed profits are best explained by **trend continuation** behavior, not by mean reversion or oversold bounce. The Stoch(k=5,d=5) oscillator acts as a trend detector: when Stoch stays above 80, price is in an upward trend, and entering provides positive expectancy over 5 bars.

The strategy is not "selling overbought" but rather "buying during overbought" — a trend-following rather than contrarian behavior.
