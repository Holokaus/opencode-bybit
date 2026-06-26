# Loser Progression Report

Analysis of 1569 losing trades (NetPnL <= 0 at bar 5).

## Average PnL and MAE by Bar

| Bar | Avg PnL | Avg MAE | MAE % of Final |
|-----|---------|---------|----------------|
| 1 | -0.4774% | -0.4774% | 24.3% |
| 2 | -0.7397% | -0.892% | 45.5% |
| 3 | -0.8908% | -1.1731% | 59.8% |
| 4 | -0.9595% | -1.3857% | 70.6% |
| 5 | -0.9336% | -1.5161% | 77.3% |
| 6 | -0.3763% | -1.5649% | 79.8% |
| 7 | 0.1491% | -1.6063% | 81.9% |
| 8 | 0.6326% | -1.6416% | 83.7% |
| 9 | 1.0667% | -1.6808% | 85.7% |
| 10 | 1.5223% | -1.7315% | 88.3% |
| 11 | 1.5051% | -1.7502% | 89.2% |
| 12 | 1.4942% | -1.7613% | 89.8% |
| 13 | 1.5036% | -1.7708% | 90.3% |
| 14 | 1.533% | -1.7869% | 91.1% |
| 15 | 1.5581% | -1.8112% | 92.3% |
| 16 | 1.5265% | -1.8398% | 93.8% |
| 17 | 1.5623% | -1.8667% | 95.2% |
| 18 | 1.5328% | -1.8931% | 96.5% |
| 19 | 1.5219% | -1.924% | 98.1% |
| 20 | 1.4973% | -1.9616% | 100% |

## Recovery Analysis

- Losers that ever recover to positive: 1480 / 1569 (94.3%)
- Average bar of worst MAE: 5.71

## Key Questions

Do losers become obvious early?
- Average PnL at bar 1: -0.4774%
- Average PnL at bar 3: -0.8908%
- Losers do NOT become obvious early (avg -0.4774% at bar 1).

Do they recover? 1480 of 1569 (94.3%) ever show positive PnL.
- Many losers recover at some point during the holding period.

At what bar do they reach their worst excursion?
- Average: bar 5.71
- Losers often continue worsening **after the current 5-bar exit**.

