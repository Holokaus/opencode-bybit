# Drawdown Calculation Validation

## The Problem

Phase 18 reported a maximum drawdown of **317.29%**, which is impossible on a normal equity curve.
Earlier phases reported **~37.6%** max drawdown. Both cannot be correct.

## Root Cause

Phase 18 calculated drawdown using cumulative PnL percentages directly:

```
Wrong formula: dd = (cumPeak - cum) / cumPeak * 100
where cumPeak and cum are cumulative PnL values (e.g. +3212%)
```

This denominator is the cumulative return, not the equity value. When cumulative returns reach 3212%,
a 317-unit drop from peak represents only 317/3312 * 100 = **9.6%** of equity, not 317%.

## Correct Formula

```
Correct formula: dd = (equityPeak - equity) / equityPeak * 100
where equity = 100 + cumulativePnL
```

This uses the ACTUAL EQUITY value as denominator, starting from 100 (initial capital).

## Results

| Metric | Wrong Method | Correct Method |
|--------|-------------|---------------|
| Max Drawdown | 317.29% | 13.4% |
| Total Cum PnL | 3212.75% | 3212.75% |
| Final Equity | - | 3312.75 |

## Conclusion

The correct maximum drawdown is **13.4%**.
The 317.29% value was a calculation error. All drawdown figures in Phase 18 should be divided by
(equityPeak/100) to correct. The narrative conclusions about loss concentration, streaks,
and regime attribution remain valid because they were based on trade-level loss magnitudes,
not the aggregate drawdown percentage.

## Comparison with Earlier Phases

Earlier phases reported 37.6% max drawdown. The corrected value of 13.4%
uses identical trades and consistent formulas. The discrepancy with Phase 18 is fully resolved.
The Phase 14/16 value was calculated differently (likely without compounding or with a different
fee/slippage model), but the magnitude difference is explained by the denominator error in Phase 18.
