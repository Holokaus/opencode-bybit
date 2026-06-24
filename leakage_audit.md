# Leakage Audit

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Walk-forward configuration:** FoldSize=10000, FirstTestStart=20000, FoldCount=7

## Variable Naming Bug (Root Cause)

Original Phase 14 code at line 163:
```
$te=$tsw+$f*$fsw;$ts=$te;$tE=[Math]::Min($ts+$fsw,$n)
```

PowerShell variable names are case-insensitive. `$tE` and `$te` are the SAME variable.
`$tE = Min($ts+$fsw, $n)` overwrites `$te` with `$te+10000`.

### Impact on `$te` (training end)

| Fold | Expected $te | Actual $te (after $tE overwrite) | Delta |
|------|-------------|----------------------------------|-------|
| 1    | 20000       | 30000                            | +10000 |
| 2    | 30000       | 40000                            | +10000 |
| 3    | 40000       | 50000                            | +10000 |
| 4    | 50000       | 60000                            | +10000 |
| 5    | 60000       | 70000                            | +10000 |
| 6    | 70000       | 80000                            | +10000 |
| 7    | 80000       | 90000                            | +10000 |

## Evidence: Does `$te` affect strategy results?

### Code path for `$te` (Phase 14, line 164)
```powershell
$tsig=Get-MbfSignalArray "Stoch" "k=5,d=5,ob=80,os=10" $c[0..($te-1)] $h[0..($te-1)] $l2[0..($te-1)] $v[0..($te-1)] $te
if(-not$tsig){continue}
```

- `$tsig` is the training signal array
- It is ONLY checked for null (`if(-not$tsig){continue}`)
- It is NEVER indexed, iterated, or passed to any strategy function
- The training signal has ZERO impact on trading decisions

### Code path for test results (Phase 14, line 166-169)
```powershell
$tlen=$tE-$ts;$xsig=Get-MbfSignalArray ... $c[$ts..($tE-1)] ... $tlen
for($si=100;$si-lt$xsig.Count;$si++){if($xsig[$si]){$gi=$ts+$si;...}}
```

- `$xsig` is the test signal array
- `$tlen = $tE - $ts = 30000 - 20000 = 10000 ` (correct for fold 1)
- `$c[$ts..($tE-1)] = $c[20000..29999]` (correct test window)
- Test signals drive all trade results

### Empirical proof: identical results

Comparison of Phase 14 (buggy) vs Phase 15 (corrected) walk-forward results:

| Fold | Phase 14 trades | Phase 15 trades | Phase 14 Sharpe | Phase 15 Sharpe |
|------|----------------|----------------|-----------------|-----------------|
| 1    | 315            | 315            | 0.5311          | 0.5311          |
| 2    | 279            | 279            | 0.2875          | 0.2875          |
| 3    | 372            | 372            | 0.4591          | 0.4591          |
| 4    | 507            | 507            | 0.445           | 0.445           |
| 5    | 584            | 584            | 0.398           | 0.398           |
| 6    | 628            | 628            | 0.4957          | 0.4957          |
| 7    | 467            | 467            | 0.5164          | 0.5164          |

All values are identical, proving the bug had zero impact on results.

## Verification Questions

### Can any test bar appear inside training data?

**YES** — but only in a throwaway computation.

- `$tsig` (training signal) is computed on `$c[0..29999]` which includes test bars 20000..29999
- However, `$tsig` is NEVER consumed — it is only null-checked
- `$xsig` (test signal) is computed on `$c[20000..29999]` — strictly test data

### Can any future information influence training?

**NO** — The Stoch(k=5,d=5,ob=80,os=10) strategy uses fixed parameters. There is no parameter optimization, no signal filtering based on training data, and no feedback loop from test to train. The training signal computation is an unused side effect.

## Conclusion

The variable naming bug (`$tE` overwrites `$te`) is real but benign.

- Phase 14 walk-forward RESULTS are valid
- Phase 14 walk-forward DISPLAY is incorrect (wrong TrainBars shown)
- No information leakage occurs because the training signal is never consumed
- All 7 folds show consistent positive out-of-sample performance

**No leakage affecting strategy results.**
