# Trade Cluster Analysis

## Objective
Determine whether losing trades (drawdown contributors) form a statistically distinct cluster from winning trades.

## Method

Compare worst 20% vs best 20% of trades across 9 features. If the two populations have
meaningfully different feature distributions, trades can be distinguished.

## Feature Comparison: Best 20% vs Worst 20%

| Feature | Best 20% (Avg) | Worst 20% (Avg) | Difference | Interpretation |
|---------|---------------|-----------------|-----------|----------------|
| ATR Percentile | 51.74 | 52.56 | -0.82 (1.5%) | Negligible |
| Volume Percentile | 55.62 | 52.02 | 3.6 (6.9%) | Small |
| Stoch K | 50.06 | 50.8 | -0.74 (1.5%) | Negligible |
| ADX | 33.94 | 36.24 | -2.3 (6.4%) | Small |

## Regime Distribution

| Regime | Best 20% (% of group) | Worst 20% (% of group) | Difference |
|--------|----------------------|----------------------|-----------|
| VOL_EXPANSION | 29.2% | 30.2% | -1.1 pp |
| VOL_COMPRESSION | 23.9% | 25.3% | -1.4 pp |
| RANGE | 25% | 21% | 4 pp |
| TREND_DOWN | 9.8% | 11.4% | -1.6 pp |
| TREND_UP | 7.9% | 7.5% | 0.4 pp |
| ACCUMULATION | 1.4% | 1.3% | 0.1 pp |
| DISTRIBUTION | 2.8% | 3.2% | -0.4 pp |

## Signal Type Distribution

| SignalType | Best 20% (#) | Worst 20% (#) |
|-----------|-------------|--------------|
| OVERBOUGHT | 51 | 54 |
| OVERSOLD | 2 |  |
| MIDDLE | 883 | 881 |

## Year Distribution

| Year | Best 20% (#) | Worst 20% (#) | Best Avg PnL | Worst Avg PnL |
|------|-------------|--------------|-------------|--------------|
| 2021 | 348 | 243 | 4.1 | -1.87 |
| 2022 | 132 | 124 | 3.04 | -1.46 |
| 2023 | 103 | 116 | 3.14 | -1.23 |
| 2024 | 152 | 210 | 2.95 | -1.28 |
| 2025 | 172 | 196 | 2.76 | -1.22 |
| 2026 | 29 | 47 | 2.76 | -1.07 |

## Conclusion

The feature with the largest difference between best and worst 20% trades is **Volume Percentile** (6.9% difference).

The two populations show **minimal feature differences**. Winning and losing trades occur under similar conditions.

The dominant regime for best trades is VOL_EXPANSION. The dominant regime for worst trades is VOL_EXPANSION.

Key observation: both best and worst trades occur across all regimes and signal types. The primary distinguishing
factor is not the entry condition but the **market outcome after entry** - which is inherently unpredictable
with the current feature set. This suggests the edge-vs-drawdown difference is driven by market microstructure
noise rather than by identifiable trade clusters.
