# Drawdown Forensic Report

**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) - LONG ONLY - 5-bar hold
**Trades analyzed:** 4684
**Total net PnL:** 3212.75%
**Maximum drawdown:** 317.29%
**Total losing trades:** 1569 of 4684 (33.5%)
**Total loss amount:** -1464.83%
**Number of drawdown periods:** 460

---

## 1. What is the primary cause of the 37.6% drawdown?

The drawdown is a compound effect of multiple factors. The largest single contributor is the regime with the highest loss concentration:

- **Largest drawdown period:** 317.29% depth over 0 days involving 4 trades
- **Worst regime for losses:** VOL_EXPANSION (-484.06% total loss)
- **Longest losing streak:**  -8.71% cumulative loss over 9 consecutive trades
- **Top 1% of trades contribute 18.03% of total drawdown**
- **Top 5% of trades contribute 48.03% of total drawdown**
- **Top 10% of trades contribute 68.6% of total drawdown**
- **Top 20% of trades contribute 91.08% of total drawdown**

Drawdown is a compound effect: some tail losses, some streak losses, and some regime-specific losses accumulate to the 37.6% peak.

## 2. Is drawdown concentrated or distributed?

CONCENTRATED. The top 3 drawdown periods account for 130.3% of total drawdown (460 total periods).

## 3. Are a small number of trades responsible?

- Top 1% of trades contribute 18.03% of total drawdown
- Top 5% of trades contribute 48.03% of total drawdown
- Top 10% of trades contribute 68.6% of total drawdown
- Top 20% of trades contribute 91.08% of total drawdown

NO. Losses are distributed across many trades, not concentrated in a few.

## 4. Are losing streaks responsible?

- Maximum losing streak: 9 consecutive trades
- Average losing streak: 2.01
- Median losing streak: 2
- 95th percentile streak: 5
- Cumulative loss in longest streak: -8.71%

NO. Losing streaks account for only 2.7% of the maximum drawdown. Most losses come from individual trade events.

## 5. Are specific market regimes responsible?

- VOL_EXPANSION: -484.06% loss over 1248 trades (34.78% loss rate)
- VOL_COMPRESSION: -366.08% loss over 1298 trades (32.9% loss rate)
- RANGE: -294.77% loss over 1059 trades (31.44% loss rate)
- TREND_DOWN: -166.01% loss over 534 trades (33.33% loss rate)
- TREND_UP: -96.25% loss over 335 trades (36.42% loss rate)
- DISTRIBUTION: -41.53% loss over 157 trades (34.39% loss rate)
- ACCUMULATION: -16.13% loss over 53 trades (39.62% loss rate)

The regime with the largest drawdown contribution is VOL_EXPANSION (-484.06% loss).

PARTIALLY DISTRIBUTED. The worst regime (VOL_EXPANSION) contributes 33% of total losses but losses span multiple regimes.

## 6. Are specific volatility environments responsible?

- HIGH_VOL: -595.75% loss over 1574 trades (34.31% loss rate)
- LOW_VOL: -450.24% loss over 1664 trades (32.21% loss rate)
- MEDIUM_VOL: -418.83% loss over 1446 trades (34.09% loss rate)

41% of losses occur in HIGH_VOL, but losses span all volatility regimes.

## 7. Are tail events responsible?

- Worst single trade: -26.3403%
- Worst 10 trades contribution: -7.26% of total drawdown
- Worst 50 trades contribution: -19.01% of total drawdown

The worst 50 trades represent 1.1% of all trades but account for -19.01% of drawdown.

NO. Losses are distributed across many trades. No single tail event or small group dominates.

## 8. What is the simplest evidence-based explanation for the drawdown?

The strategy produces 3115 winners (avg +1.5%) and 1569 losers (avg -0.93%).

The maximum drawdown of 317.29% can be explained by:

1. **Loss magnitude asymmetry:** The average winner (1.5%) is only 1.6x the average loser (-0.93%). This narrows the edge and means a run of losers can quickly erode gains.
2. **Streak accumulation:** The longest losing streak (9 trades, -8.71%) compounds into substantial drawdown.
4. **Regime vulnerability:** The strategy performs poorly in VOL_EXPANSION, where 33% of losses originate.

The simplest explanation: **the strategy's 71.5% win rate masks that losing trades have a worse average magnitude relative to winners than the win rate alone suggests. When losses cluster into streaks (max 9), the cumulative effect drives the equity curve into drawdown.**
