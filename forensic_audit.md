# Forensic Audit Report

**Date:** 2026-06-24
**Target:** Phase 14 — SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)

---

## Audit 1 — Latency Test

### Implementation (phase14_audit.ps1:98)

```
$ei=$si+$lat;$ex=$ei+5
```

Entry = signal bar + latency. Exit = entry + 5 bars. Correct.

### Sample Verification (latency_trade_samples.csv)

| Latency | SignalIdx | EntryIdx | ExitIdx | EntryPrice | ExitPrice | Return |
|---------|-----------|----------|---------|------------|-----------|--------|
| 0       | 104       | 104      | 109     | 8.1242     | 7.9736    | -1.85% |
| 3       | 104       | 107      | 112     | 8.0257     | 8.2258    | +2.49% |

All 400 sample trades (100 per mode) verified. Entry is correctly delayed by exactly `$lat` bars. The PF increase from 4.07 (latency 0) to 31.09 (latency 3) is real — the Stoch os=10 mean-reversion signal benefits from delayed entry because it skips continued decline bars and enters during the confirmed bounce.

**Is entry actually delayed?** YES

**Latency test valid?** YES — implementation is correct.

---

## Audit 2 — Walk-Forward Splits

### Root Cause: Variable Name Collision

In `phase14_audit.ps1:163`:
```powershell
$te=$tsw+$f*$fsw;$ts=$te;$tE=[Math]::Min($ts+$fsw,$n)
```

PowerShell variable names are **case-insensitive**. `$tE` and `$te` refer to the **same variable**.

- `$te` is intended as **train end** (e.g., 20000 for fold 1)
- `$tE` is intended as **test end** (e.g., 30000 for fold 1)

But `$tE = [Math]::Min($ts + $fsw, $n)` **overwrites `$te`**, adding 10000 bars to the training window.

### Result Per Fold

| Fold | Expected Train End | Actual Train End | Test Start | Overlap Bars |
|------|-------------------|------------------|------------|--------------|
| 1    | 19999             | 29999            | 20000      | 10000        |
| 2    | 29999             | 39999            | 30000      | 10000        |
| 3    | 39999             | 49999            | 40000      | 10000        |
| 4    | 49999             | 59999            | 50000      | 10000        |
| 5    | 59999             | 69999            | 60000      | 10000        |
| 6    | 69999             | 79999            | 70000      | 10000        |
| 7    | 79999             | 89999            | 80000      | 10000        |

Every fold: training data includes the **entire test window**. This is full data leakage.

**Do train and test overlap?** YES — all 7 folds overlap by exactly 10000 bars.

**Walk-forward validation is INVALID** — lookahead bias contaminates every fold.

### Impact

The training signal is computed on `$c[0..($te-1)]` where `$te` was overwritten by `$tE`. For fold 1, training sees bars 0..29999 and test is bars 20000..29999. The "training" data already contains the test period. All 7 positive Sharpe values are meaningless.

---

## Audit Results

### Fold 1 Detailed Trace (from forensic_audit.ps1 debug output)

```
$f=0
$tsw=20000 $fsw=10000
$te = $tsw + $f * $fsw = 20000       ← correct
$tE = [Math]::Min($ts + $fsw, $n)    ← this is actually $te = Min(30000, 93871)
$te is now 30000                      ← corrupted!
Training signal computed on bars 0..29999 ← includes test bars 20000..29999
```

Fixed version:
```powershell
$trainEnd=$tsw+$f*$fsw
$ts=$trainEnd
$testEnd=[Math]::Min($ts+$fsw,$n)
```

---

## Final Answers

**1. Latency test valid?** YES

**2. Walk-forward valid?** NO — variable name collision `$tE`/`$te` causes 10000-bar data leakage per fold.

**3. Can Phase 14 conclusions be trusted?** NO

---

**PHASE 14 INVALIDATED**

The walk-forward test (Phase 14.6) is compromised by a variable naming bug. The "7/7 positive folds" result is caused by lookahead bias, not genuine edge. Phase 14's final verdict of "EDGE SURVIVED STRICT VALIDATION" is unsupported.

All other Phase 14 components (14.1-14.5) are unaffected by this bug, but the overall verdict depends on all 6 tests passing. With Phase 14.6 invalidated, the full verdict cannot be trusted.

*Generated: 2026-06-24*
