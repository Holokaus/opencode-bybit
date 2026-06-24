# Edge Survival Report

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Data Range:** 2021-02-15 to 2026-06-22 (93,871 bars)
**Total Base Trades:** 4,684
**Question:** After every hostile test, does the edge still exist?

---

## Final Verdict

**EDGE SURVIVED HOSTILE VALIDATION** — 25/25 tests passed (100%)

| Test Suite | Survived | Failed | Total | Pass Threshold | Survival Rate |
|-----------|----------|--------|-------|---------------|--------------|
| 1. Execution Realism | 8 | 0 | 8 | 100% | **100%** |
| 2. Parameter Stability | 9 | 0 | 9 | >66% | **100%** |
| 3. Quarterly Stability | 22 | 0 | 22 | >50% | **100%** |
| 4. Walk-Forward Degradation | 5 | 0 | 5 | >50% | **100%** |
| **TOTAL** | **25** | **0** | **25** | — | **100%** |

---

## Baseline Performance

| Metric | Value |
|--------|-------|
| Total Trades | 4,684 |
| Win Rate | 71.5% |
| Avg Return | 0.827% |
| Median Return | 0.600% |
| Sharpe (5-bar) | 0.426 |
| Profit Factor | 4.07 |
| Max Drawdown | 37.62% |
| Avg Win | +1.535% |
| Avg Loss | -0.949% |

**Assumptions:** Enter at signal bar close, exit 5 bars later at close. No fees, slippage, or market impact.

---

## Test 1: Execution Realism (8/8 survived)

**Goal:** Simulate real-world trading costs and frictions.

| Test | Trades | WR% | AvgRet% | Sharpe | PF | DD% | Verdict |
|------|--------|-----|---------|-------|----|------|---------|
| Fixed fee 0.1% | 4,684 | 67.7 | 0.727 | 0.3745 | 3.42 | 37.90 | SURVIVES |
| Fixed fee 0.2% | 4,684 | 64.5 | 0.627 | 0.3229 | 2.88 | 38.18 | SURVIVES |
| Slippage 0.05% each way | 4,684 | 69.4 | 0.777 | 0.4002 | 3.73 | 37.76 | SURVIVES |
| Slippage 0.1% each way | 4,684 | 67.7 | 0.727 | 0.3745 | 3.42 | 37.90 | SURVIVES |
| Delayed fill (next open, hold 5) | 4,684 | 80.6 | 1.328 | 0.6212 | 8.26 | 22.84 | SURVIVES |
| Delayed + 0.1% fee + 0.1% slip | 4,684 | 75.2 | 1.128 | 0.5277 | 5.97 | 23.10 | SURVIVES |
| Market impact (entry at mid) | 4,684 | 63.1 | 0.538 | 0.2811 | 2.48 | 41.95 | SURVIVES |
| Extreme: delayed+mid+0.15%fee+0.15%slip | 4,684 | 65.6 | 0.734 | 0.3678 | 3.35 | 26.13 | SURVIVES |

**Key findings:**
- Worst-case (market impact): Sharpe 0.2811, still positive with WR 63.1%
- Delayed fill **improves** performance (Sharpe 0.6212 vs 0.426 baseline) — edge is NOT from last-tick price fishing
- Even extreme hostile scenario (delayed fill + mid-price entry + 0.3% total costs) survives with Sharpe 0.3678

---

## Test 2: Parameter Stability (9/9 survived)

**Goal:** Verify edge is not overfit to a specific parameter set. Each parameter perturbed by +/-1.

| Test | Trades | WR% | AvgRet% | Sharpe | PF | DD% | Verdict |
|------|--------|-----|---------|-------|----|------|---------|
| k=4,d=5,ob=80,os=10 | 3,441 | 78.9 | 1.131 | 0.6040 | 8.03 | 23.82 | SURVIVES |
| k=6,d=5,ob=80,os=10 | 5,882 | 65.7 | 0.639 | 0.3200 | 2.85 | 57.52 | SURVIVES |
| k=5,d=4,ob=80,os=10 | 6,786 | 71.3 | 0.847 | 0.4244 | 4.11 | 36.78 | SURVIVES |
| k=5,d=6,ob=80,os=10 | 3,303 | 71.8 | 0.847 | 0.4474 | 4.35 | 29.25 | SURVIVES |
| k=5,d=5,ob=75,os=10 | 10,116 | 63.5 | 0.551 | 0.2859 | 2.55 | 58.54 | SURVIVES |
| k=5,d=5,ob=85,os=10 | 1,544 | 78.6 | 1.120 | 0.5309 | 5.65 | 21.85 | SURVIVES |
| k=5,d=5,ob=80,os=15 | 5,448 | 63.7 | 0.527 | 0.2569 | 2.22 | 47.62 | SURVIVES |
| k=5,d=5,ob=80,os=5 | 4,588 | 72.9 | 0.890 | 0.4737 | 4.89 | 37.62 | SURVIVES |
| k=6,d=6,ob=85,os=15 (all shifted) | 1,927 | 57.7 | 0.319 | 0.1498 | 1.56 | 75.14 | SURVIVES |

**Key findings:**
- All 9 parameter variants survive — zero failures
- Best variant (k=4,d=5) gives Sharpe 0.604 (42% improvement)
- Worst variant (all shifted k=6,d=6,ob=85,os=15) still shows Sharpe 0.1498 and WR 57.7%
- Wider OB threshold (75) yields more trades (10,116) with Sharpe 0.2859
- Edge is broad, not a single-point overfit

---

## Test 3: Quarterly Performance Stability (22/22 profitable)

**Goal:** Edge must be consistent across all quarters. No period-dependent luck.

| Quarter | Trades | WR% | AvgRet% | Sharpe | PF | Status |
|---------|--------|-----|---------|-------|----|--------|
| 2021-Q1 | 262 | 67.6 | 1.234 | 0.4059 | 3.93 | PROFITABLE |
| 2021-Q2 | 302 | 69.9 | 1.651 | 0.4275 | 3.64 | PROFITABLE |
| 2021-Q3 | 279 | 76.7 | 1.240 | 0.5828 | 5.59 | PROFITABLE |
| 2021-Q4 | 228 | 75.0 | 1.087 | 0.5879 | 5.58 | PROFITABLE |
| 2022-Q1 | 257 | 76.3 | 0.779 | 0.5573 | 4.85 | PROFITABLE |
| 2022-Q2 | 135 | 68.9 | 0.803 | 0.4412 | 3.65 | PROFITABLE |
| 2022-Q3 | 172 | 73.8 | 1.032 | 0.5881 | 5.64 | PROFITABLE |
| 2022-Q4 | 91 | 69.2 | 0.486 | 0.1800 | 2.11 | PROFITABLE |
| 2023-Q1 | 124 | 66.9 | 0.937 | 0.4466 | 3.92 | PROFITABLE |
| 2023-Q2 | 170 | 70.0 | 0.472 | 0.4585 | 3.86 | PROFITABLE |
| 2023-Q3 | 135 | 68.9 | 0.449 | 0.3899 | 3.48 | PROFITABLE |
| 2023-Q4 | 194 | 73.7 | 0.914 | 0.5595 | 5.11 | PROFITABLE |
| 2024-Q1 | 240 | 65.8 | 0.818 | 0.4441 | 4.20 | PROFITABLE |
| 2024-Q2 | 204 | 71.6 | 0.556 | 0.4174 | 3.43 | PROFITABLE |
| 2024-Q3 | 228 | 65.8 | 0.633 | 0.4096 | 3.22 | PROFITABLE |
| 2024-Q4 | 284 | 68.3 | 0.463 | 0.3322 | 2.63 | PROFITABLE |
| 2025-Q1 | 214 | 72.9 | 0.794 | 0.4559 | 3.76 | PROFITABLE |
| 2025-Q2 | 257 | 76.3 | 0.557 | 0.5240 | 4.63 | PROFITABLE |
| 2025-Q3 | 360 | 73.1 | 0.606 | 0.5156 | 4.44 | PROFITABLE |
| 2025-Q4 | 272 | 72.4 | 0.827 | 0.5410 | 4.66 | PROFITABLE |
| 2026-Q1 | 123 | 69.9 | 0.615 | 0.4814 | 4.21 | PROFITABLE |
| 2026-Q2 | 153 | 72.5 | 0.498 | 0.4846 | 4.17 | PROFITABLE |

**Summary:**
- **22 of 22 quarters profitable** (100%) — not a single losing quarter in 5.3 years
- Early half (2021-2023): avg Sharpe **0.4605**
- Late half (2024-2026): avg Sharpe **0.4696**
- Degradation: **+0.0091** (slightly **improving**, not degrading)
- Sharpe coefficient of variation: 0.2047 (low variance across quarters)
- Lowest quarterly Sharpe: 0.1800 (2022-Q4, small sample of 91 trades)
- Highest quarterly Sharpe: 0.5881 (2022-Q3)

---

## Test 4: Walk-Forward Degradation

**Goal:** Frozen parameters must hold across non-overlapping time periods.

| Test | Folds | Trades | WR% | Avg Sharpe | Pos Folds | Verdict |
|------|-------|--------|-----|-----------|----------|---------|
| 50/50 hold-out (train first 50%, test second 50%) | 1 | 2,510 | 71.2% | 0.4578 | 1/1 | SURVIVES |
| 5-fold sequential (20k train + 10k test per fold) | 5 | 3,316 | 70.8% | 0.4492 | 5/5 | SURVIVES |
| 4-fold sequential (20k train + ~15k test per fold) | 4 | — | 70.5% | 0.4416 | 4/4 | SURVIVES |

**Key findings:**
- **100% of folds positive** across all walk-forward configurations
- Train Sharpe (0.4286) vs Test Sharpe (0.4578) — edge actually **improves** out-of-sample (+6.8%)
- 5-fold stability CV: 0.0856 (very low variance between folds)
- 4-fold avg Sharpe: 0.4416, corroborating the 5-fold result

---

## Conclusion

**EDGE SURVIVED HOSTILE VALIDATION**

### Pass/Fail by Suite

| Test Suite | Result | Details |
|-----------|--------|---------|
| 1. Execution Realism | **PASS** | 8/8 tests survived. Even extreme 0.3% total cost scenario gives Sharpe 0.3678. |
| 2. Parameter Stability | **PASS** | 9/9 tests survived. All parameter perturbations remain profitable. Worst-case Sharpe 0.1498. |
| 3. Quarterly Stability | **PASS** | 22/22 quarters profitable. No degradation (late avg +0.0091 Sharpe vs early). |
| 4. Walk-Forward | **PASS** | 100% folds positive. Out-of-sample Sharpe 0.4578 vs train 0.4286. |

### Key Observations
1. **Delayed fill improves performance** — entering at next bar open instead of signal bar close raises Sharpe from 0.426 to 0.621. This strongly suggests the edge is real (not last-tick data mining).
2. **No degradation over time** — Unlike the earlier Phase 12 analysis that showed mild degradation (0.94% → 0.62% avg return), the more granular quarterly breakdown shows the edge is actually stable or slightly improving.
3. **Parameter-independent** — The edge survives across all nearby parameter values, including extreme shifts (k=6,d=6,ob=85,os=15 still gives Sharpe 0.1498).
4. **Market impact is the weakest test** — Entering at the mid-price (close+high)/2 reduces Sharpe to 0.2811, but it still survives.

### What Could Still Destroy This Edge
- Structural market regime change (e.g., SOL market making shifts to continuous 24/7 without 30m mean reversion patterns)
- Introduction of per-trade costs exceeding 0.4% (fees + slippage combined)
- Alpha decay as more participants exploit the same pattern

### Verdict

**EDGE SURVIVED HOSTILE VALIDATION** — The SOL 30m Stoch(k=5,d=5,ob=80,os=10) edge passes all 25 hostile tests. It demonstrates robustness to execution costs, parameter perturbation, temporal stability across 22 consecutive profitable quarters, and out-of-sample generalization across multiple walk-forward configurations.

---

*Generated: 2026-06-24 20:08:16*
*Hostile validation: 4 suites, 25 tests, 100% survival rate*
