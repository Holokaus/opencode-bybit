# Overlap Impact Report

Measuring the effect of concurrency limits on Exit10 performance.

## Metrics vs Concurrency

| Model | Trades | WR% | PF | E | DD% | Sharpe | CompRet% | FinalEq |
|-------|--------|-----|----|----|------|--------|----------|---------|
| MC1_R1pct | 1641 | 91.9 | 10.0913 | 2.1829 | 0.36 | 0.7502 | 43.06 | 143.06 |
| MC2_R1pct | 2738 | 93.75 | 13.885 | 2.4737 | 0.36 | 0.857 | 96.79 | 196.79 |
| MC3_R1pct | 3465 | 94.75 | 16.7702 | 2.7086 | 0.36 | 0.9113 | 155.44 | 255.44 |
| MC5_R1pct | 4265 | 95.66 | 22.496 | 3.0805 | 0.36 | 0.9846 | 271.46 | 371.46 |
| MC10_R1pct | 4684 | 96.05 | 26.5018 | 3.3276 | 0.36 | 0.9934 | 373.95 | 473.95 |
| Unconstrained_R1pct | 4684 | 96.05 | 26.5018 | 3.3276 | 0.36 | 0.9934 | 373.95 | 473.95 |

## Performance Retention

Comparing each constrained model against unconstrained baseline:

| Model | E Retention% | PF Retention% | DD vs Unconstrained |
|-------|-------------|---------------|--------------------|
| MC1_R1pct | 65.6% | 38.1% | Worse |
| MC2_R1pct | 74.3% | 52.4% | Worse |
| MC3_R1pct | 81.4% | 63.3% | Worse |
| MC5_R1pct | 92.6% | 84.9% | Worse |
| MC10_R1pct | 100% | 100% | Worse |

## Question: Does performance remain strong when capital is constrained?

**PARTIALLY.** At max 1 concurrent position, retains 65.6% expectancy and 38.1% PF. Higher concurrency improves retention.

