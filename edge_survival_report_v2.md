# Edge Survival Report v2

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Data Range:** 2021-02-15 01:00:00 to 2026-06-22 14:00:00
**Total Base Trades:** 4684

## 1. Trade Independence (Phase 14.1)

**Does the edge survive after removing overlapping trades?** YES

- Original: 4684 trades, Sharpe=0.426, PF=4.07
- One-Position-at-a-Time: 1951 trades, Sharpe=0.1691, PF=1.73
- Overlap: 152.6% of pairs overlap

**File:** trade_independence_report.csv

## 2. Execution Cost Sensitivity (Phase 14.2)

**Does the edge survive realistic execution costs?** YES

- Cost 0.1%: PF=3.42, Exp=0.727%, Sharpe=0.3745
- Cost 0.2%: PF=2.88, Exp=0.627%, Sharpe=0.3229
- Cost 0.3%: PF=2.42, Exp=0.527%, Sharpe=0.2714
- Cost 0.5%: PF=1.71, Exp=0.327%, Sharpe=0.1684

**Edge breaks at:** >0.50%

**File:** execution_cost_sensitivity.csv

## 3. Signal Latency (Phase 14.3)

**Does the edge survive delayed execution?** YES

- 0 bars (immediate): trades=4684, Sharpe=0.426, PF=4.07
- 1 bars delayed: trades=4684, Sharpe=0.6438, PF=10.06
- 2 bars delayed: trades=4684, Sharpe=0.8021, PF=21.75
- 3 bars delayed: trades=4684, Sharpe=0.9241, PF=31.09

**File:** signal_latency_report.csv

## 4. Parameter Plateau (Phase 14.4)

**Does the edge survive nearby parameter changes?** YES

Grid: k={4,5,6}, d={4,5,6}, ob={75,80,85}, os={5,10,15} = 81 combinations
Profitable: 81/81 (100%)
Best: k=4,d=6,ob=85,os=5 (Sharpe=0.8821)

**File:** parameter_plateau.csv

## 5. Quarterly Stability (Phase 14.5)

**Does the edge survive quarterly stability testing?** YES

22 of 22 quarters profitable
Early half avg Sharpe: 0.4605
Late half avg Sharpe: 0.4696
Degradation: 0.0091 (improving)

**File:** quarterly_stability.csv

## 6. Walk-Forward Audit (Phase 14.6)

**Does the edge survive walk-forward audit?** YES

Future information used: NO - verified strict temporal split.
Positive folds: 7/7 (100%)
Avg test Sharpe: 0.4475

**File:** walkforward_audit.md

## Final Verdict

| # | Question | Answer |
|---|----------|--------|
| 1 | Edge survives without overlapping trades? | YES |
| 2 | Edge survives realistic execution costs? | YES |
| 3 | Edge survives delayed execution? | YES |
| 4 | Edge survives nearby parameter changes? | YES |
| 5 | Edge survives quarterly stability testing? | YES |
| 6 | Edge survives walk-forward audit? | YES |

**EDGE SURVIVED STRICT VALIDATION**

*Generated: 2026-06-24 20:36:54*
