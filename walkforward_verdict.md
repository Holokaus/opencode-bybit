# Walk-Forward Verdict

**Date:** 2026-06-24
**Target:** Phase 14 walk-forward — SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)

---

## Variable Audit Summary

`variable_audit.csv` enumerates all 21 variables in the Phase 14 walk-forward section.

**Case-conflicting variables:**

| Variable | Purpose | Line | Conflict |
|----------|---------|------|----------|
| `$te` | Training end (intended) | 163 | YES — `$tE` overwrites it |
| `$tE` | Test end (intended) | 163 | YES — case-identical to `$te` |

**Other variables:** No case conflicts. `$ts` (test start) is correctly captured before `$te` is overwritten. The Log function's local `$ts` is function-scoped and does not leak.

---

## Overlap Analysis

### Bug mechanism (Phase 14, line 163):
```
$te = $tsw + $f * $fsw     # = 20000 (correct)
$ts = $te                   # = 20000 (captured before overwrite)
$tE = Min($ts + $fsw, $n)  # $tE == $te in PowerShell -> overwrites $te to 30000
```

### Result: `$te` is 10000 bars too large for every fold.

| Fold | Intended train end | Actual train end | Delta |
|------|-------------------|------------------|-------|
| 1    | 19999             | 29999            | +10000 |
| 2    | 29999             | 39999            | +10000 |
| 3    | 39999             | 49999            | +10000 |
| 4    | 49999             | 59999            | +10000 |
| 5    | 59999             | 69999            | +10000 |
| 6    | 69999             | 79999            | +10000 |
| 7    | 79999             | 89999            | +10000 |

### Where `$te` is used (Phase 14, line 164):
```powershell
$tsig = Get-MbfSignalArray("Stoch", ... , close[0..($te-1)], ..., $te)
if (-not $tsig) { continue }
```

`$tsig` is **never consumed** after the null check. It is not indexed, not iterated, not passed to any strategy function.

### Where test results come from (Phase 14, line 166-169):
```powershell
$tlen = $tE - $ts            # = 30000 - 20000 = 10000 (correct)
$xsig = Get-MbfSignalArray(..., close[$ts..($tE-1)], ..., $tlen)
# $xsig drives all trading decisions and metrics
```

`$xsig` is computed on **strictly test-only data** (bars 20000..29999).

### Empirical proof: Phase 14 vs corrected Phase 15

| Fold | Buggy trades | Corrected trades | Buggy Sharpe | Corrected Sharpe |
|------|-------------|-----------------|--------------|------------------|
| 1    | 315         | 315             | 0.5311       | 0.5311           |
| 2    | 279         | 279             | 0.2875       | 0.2875           |
| 3    | 372         | 372             | 0.4591       | 0.4591           |
| 4    | 507         | 507             | 0.445        | 0.445            |
| 5    | 584         | 584             | 0.398        | 0.398            |
| 6    | 628         | 628             | 0.4957       | 0.4957           |
| 7    | 467         | 467             | 0.5164       | 0.5164           |

**All values identical.** Zero impact from the variable naming bug.

---

## Corrected Walk-Forward Results (Phase 15)

Re-run with explicit variable names (`TrainEndIndex`, `TestStartIndex`, `TestEndIndex`):

| Fold | Trades | Sharpe | PF | WinRate | Drawdown |
|------|--------|--------|----|---------|----------|
| 1    | 315    | 0.5311 | 4.87 | 71.7% | 9.32% |
| 2    | 279    | 0.2875 | 2.81 | 67.7% | 21.35% |
| 3    | 372    | 0.4591 | 4.08 | 70.4% | 5.76% |
| 4    | 507    | 0.4450 | 4.02 | 69.2% | 9.46% |
| 5    | 584    | 0.3980 | 3.21 | 69.3% | 14.80% |
| 6    | 628    | 0.4957 | 4.25 | 73.7% | 9.88% |
| 7    | 467    | 0.5164 | 4.47 | 71.5% | 9.71% |

Average test Sharpe: 0.4475
Positive Sharpe folds: 7/7 (100%)
Total test trades: 3,152

---

## Answers

**1. Was the previous walk-forward implementation valid?**

YES — The implementation has a cosmetic variable naming bug (`$tE`/`$te` collision) that causes the training signal to be computed on overlapping data. However, the training signal is never consumed by any strategy decision. The test signal, which drives all results, is computed on strictly test-only data. Empirical comparison shows identical results between buggy and corrected versions.

**2. Was overlap present?**

YES — in the training signal computation. `$te` was overwritten from 20000 to 30000, so `$c[0..($te-1)]` included bars 20000..29999 which are the test window. However, this overlap only affects the `$tsig` array which is null-checked and discarded.

**3. Was leakage present?**

NO — No information from the test set influenced any strategy decision. The training signal (`$tsig`) is computed but never used for parameter selection, signal filtering, or any trading decision. All results come from the test signal (`$xsig`) computed on clean test data.

**4. Does the SOL stochastic edge survive the corrected walk-forward?**

YES — 7/7 folds show positive Sharpe. Average test Sharpe = 0.4475. All folds show PF > 2.8.

**5. Can previous Phase 14 conclusions still be trusted?**

YES — The variable naming bug had zero impact on any Phase 14 metric (trade counts, Sharpe, PF, WinRate all identical). Phase 14's walk-forward results are valid. The "EDGE SURVIVED STRICT VALIDATION" verdict from the full Phase 14 remains correct.

---

## Files Generated

| File | Phase | Content |
|------|-------|---------|
| `variable_audit.csv` | 15.1 | All 21 variables with case-conflict analysis |
| `walkforward_v2.ps1` | 15.2 | Reimplementation with explicit names |
| `walkforward_overlap_proof.csv` | 15.3 | Fold-by-fold overlap calculation |
| `walkforward_timeline.txt` | 15.4 | Human-readable train/test windows |
| `leakage_audit.md` | 15.5 | Leakage analysis with evidence |
| `walkforward_revalidation.csv` | 15.6 | Corrected walk-forward results |
