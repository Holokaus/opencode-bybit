# Phase 12 Edge Stability Report

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Trades Analyzed:** 4684

---

## 1. Why does the edge exist?

The Stoch(k=5,d=5,ob=80,os=10) oscillator detects mean-reversion opportunities in SOLUSDT at the 30m timeframe.
Entry occurs when %K crosses above 80 (overbought) or below 10 (oversold).
Key driver: avg win = 1.5346% vs avg loss = -0.9494%
Win rate = 71.5% across 4684 trades since 2021

## 2. What market behavior creates it?

SOLUSDT exhibits short-term momentum persistence after stochastic extremes.
- Oversold signals precede 5-bar bounces
- Overbought signals precede 5-bar declines
- The 5-bar holding period is short enough to avoid trend reversal risk

## 3. Which environments support it?

ALL regimes are profitable. No regime destroys the edge.

- VOL_EXPANSION : Sharpe=0.6729 WR=72.4% PF=6.37 trades=29
- ACCUMULATION : Sharpe=0.5877 WR=73.9% PF=6.27 trades=222
- DISTRIBUTION : Sharpe=0.5612 WR=74.3% PF=5.29 trades=381
- RANGE : Sharpe=0.4419 WR=71% PF=4.08 trades=290
- TREND_DOWN : Sharpe=0.4335 WR=71.4% PF=4.14 trades=887
- VOL_COMPRESSION : Sharpe=0.389 WR=69.6% PF=3.78 trades=935
- TREND_UP : Sharpe=0.2952 WR=69.9% PF=2.77 trades=239

## 4. Which environments destroy it?

NONE — every regime, volatility band, and volume band is profitable.

## 5. Is the edge improving over time?

Early years avg return: 0.9428% | Recent years avg return: 0.616%
Trend: DEGRADING

## 6. Is the edge degrading over time?

YES — the edge shows mild degradation. Early years (2021-2023) outperformed recent years (2024-2026).
Early: 0.9428% avg return vs Recent: 0.616%

## 7. What is the simplest explanation for the edge?

Stoch(k=5,d=5,ob=80,os=10) on SOLUSDT 30m captures short-term directional persistence following stochastic extremes.
The edge does not depend on any single regime, volatility level, or volume condition.
It is broadly distributed across all market environments.

## Final Verdict

**EDGE CONFIRMED**

Sharpe=0.426 WR=71.5% PF=4.07 over 4684 trades

### Evidence summary:
- Edge survives ALL 6 years (2021-2026)
- Edge profitable in ALL 7 regimes
- Edge profitable in ALL 3 volatility bands
- Edge profitable in ALL 3 volume bands
- No environment filter consistently improves performance

