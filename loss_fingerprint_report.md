# Loss Fingerprint Report

**Strategy:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10) LONG ONLY 5-bar hold
**Trades:** 4684 total, 468 in worst 10% cohort
**Worst 10% threshold:** NetPnL <= -1.03%
**Worst  5% threshold:** NetPnL <= -1.65%
**Worst  1% threshold:** NetPnL <= -3.68%

---

## Feature Ranking (by Cohens d)

| Rank | Feature | d | Effect | Pctile Diff | Direction |
|------|---------|---|-------|------------|-----------|
| 1 | ATR vs 100-bar avg (%) | 0.2634 | small | 6.5% | higher in bad trades |
| 2 | ATR (absolute) | 0.1851 | negligible | 3.5% | higher in bad trades |
| 3 | ATR vs 20-bar avg (%) | 0.1813 | negligible | 4.8% | higher in bad trades |
| 4 | Distance from 50-bar high (%) | -0.0543 | negligible | -1.2% | lower in bad trades |
| 5 | Distance from 20-bar high (%) | -0.0401 | negligible | -1.3% | lower in bad trades |
| 6 | 50-bar slope | 0.0373 | negligible | 0.2% | higher in bad trades |
| 7 | Lower wick % | 0.0356 | negligible | 0.3% | higher in bad trades |
| 8 | Upper wick % | -0.0355 | negligible | -0.8% | lower in bad trades |
| 9 | Distance from 50-bar low (%) | 0.028 | negligible | 0.7% | higher in bad trades |
| 10 | Previous 1-bar return (%) | -0.0276 | negligible | 0.8% | lower in bad trades |
| 11 | 20-bar slope | 0.0206 | negligible | 0.8% | higher in bad trades |
| 12 | Previous 10-bar return (%) | 0.0189 | negligible | 0.9% | higher in bad trades |
| 13 | Previous 3-bar return (%) | -0.0165 | negligible | 0.2% | lower in bad trades |
| 14 | Distance from SMA50 (%) | -0.0123 | negligible | -0.7% | lower in bad trades |
| 15 | Previous 5-bar return (%) | 0.0108 | negligible | 1.2% | higher in bad trades |
| 16 | Distance from 20-bar low (%) | 0.0089 | negligible | 0.7% | higher in bad trades |
| 17 | Position in 20-bar range (%) | 0.0089 | negligible | 0.7% | higher in bad trades |
| 18 | Total wick % | 0.0024 | negligible | 0.2% | higher in bad trades |
| 19 | Body % | -0.0024 | negligible | -0.2% | lower in bad trades |
| 20 | Range expansion ratio (%) | -0.0016 | negligible | -0.5% | lower in bad trades |
| 21 | Distance from SMA20 (%) | -0.0009 | negligible | 0.3% | lower in bad trades |
| 22 | Distance from SMA200 (%) | 0 | negligible | -1.8% | lower in bad trades |

## 1. Do catastrophic losses share common characteristics?

**NO.** The top feature (ATR vs 100-bar avg (%)) shows only a small effect size (d=0.263). Worst losses occur under statistically similar conditions to normal trades.

Detailed cohort breakdown:


Top features by Cohen's d (see table above for full ranking).

- **ATR vs 100-bar avg (%)**: d=0.2634, higher in bad trades, 6.5%ile diff
- **ATR (absolute)**: d=0.1851, higher in bad trades, 3.5%ile diff
- **ATR vs 20-bar avg (%)**: d=0.1813, higher in bad trades, 4.8%ile diff
- **Distance from 50-bar high (%)**: d=-0.0543, lower in bad trades, -1.2%ile diff
- **Distance from 20-bar high (%)**: d=-0.0401, lower in bad trades, -1.3%ile diff

## 2. Which feature best separates bad trades from normal trades?

**ATR vs 100-bar avg (%)** (Cohen's d = 0.2634, effect = small).
Percentile difference: 6.5%.

Runner-up: ATR (absolute) (d = 0.1851, effect = negligible).

## 3. Are the differences economically meaningful?

Of 22 features, 0 show medium or larger effect sizes.
**NO.** All features show negligible to small effects. The differences are statistically detectable at best but not economically meaningful.

## 4. Is there evidence that a future filter could reduce drawdown?

**NO.** The feature differences are negligible. The worst losses appear to be the natural left tail of a single trade distribution, not a distinct subpopulation. No evidence supports building a filter.

---

## Feature-by-Feature Detail

| Feature | Bad Mean | Good Mean | Bad Med | Good Med | d | pctile diff |
|---------|---------|----------|--------|---------|---|------------|
| ATR vs 100-bar avg (%) | 106.1088 | 99.7979 | 101.4 | 97 | 0.2634 | 6.5% |
| ATR (absolute) | 1.3352 | 1.1462 | 1.0862 | 0.9945 | 0.1851 | 3.5% |
| ATR vs 20-bar avg (%) | 100.6654 | 99.7903 | 100.2 | 99.5 | 0.1813 | 4.8% |
| Distance from 50-bar high (%) | 64.5552 | 66.4369 | 72.11 | 71.65 | -0.0543 | -1.2% |
| Distance from 20-bar high (%) | 71.1487 | 72.7318 | 75.4 | 77.02 | -0.0401 | -1.3% |
| 50-bar slope | -0.0067 | -0.0121 | -0.0097 | -0.0085 | 0.0373 | 0.2% |
| Lower wick % | 29.5703 | 28.8036 | 24.5 | 24.8 | 0.0356 | 0.3% |
| Upper wick % | 25.8348 | 26.5414 | 21.6 | 23 | -0.0355 | -0.8% |
| Distance from 50-bar low (%) | 59.3922 | 58.4333 | 56.79 | 56.34 | 0.028 | 0.7% |
| Previous 1-bar return (%) | -0.0211 | 0.0056 | 0.0397 | 0 | -0.0276 | 0.8% |
| 20-bar slope | -0.0138 | -0.0185 | -0.0091 | -0.0104 | 0.0206 | 0.8% |
| Previous 10-bar return (%) | -0.2112 | -0.2656 | -0.15 | -0.2104 | 0.0189 | 0.9% |
| Previous 3-bar return (%) | -0.0779 | -0.0503 | -0.0331 | 0 | -0.0165 | 0.2% |
| Distance from SMA50 (%) | -0.4428 | -0.3975 | -0.6198 | -0.3756 | -0.0123 | -0.7% |
| Previous 5-bar return (%) | -0.1362 | -0.1587 | -0.0728 | -0.0883 | 0.0108 | 1.2% |
| Distance from 20-bar low (%) | 69.2001 | 68.8435 | 67.69 | 65.95 | 0.0089 | 0.7% |
| Position in 20-bar range (%) | 69.2001 | 68.8435 | 67.69 | 65.95 | 0.0089 | 0.7% |
| Total wick % | 55.4062 | 55.3455 | 56.7 | 55.6 | 0.0024 | 0.2% |
| Body % | 44.5938 | 44.6545 | 43.5 | 44.4 | -0.0024 | -0.2% |
| Range expansion ratio (%) | 105.0915 | 105.1928 | 88.3 | 89.7 | -0.0016 | -0.5% |
| Distance from SMA20 (%) | -0.2334 | -0.2313 | -0.1753 | -0.1779 | -0.0009 | 0.3% |
| Distance from SMA200 (%) | Infinity | Infinity | -0.8916 | -0.4487 | 0 | -1.8% |

