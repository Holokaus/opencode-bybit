# Code Path and Index Alignment Audit

## File: phase24_exit_and_weekday.ps1 (canonical reference)

### Signal Generation (line 20)
```
$sig = Get-MbfSignalArray Stoch k=5,d=5,ob=80,os=10 close high low volume n
```
Get-MbfSignalArray calls Calc-Stosh which returns %D line (EMA of %K).
Signal true when Stoch > 80 (overbought) OR Stoch < 10 (oversold).
Both conditions trigger LONG entries.

### Entry Index (line 33)
```
for ($si=$hedgeStart;$si-lt$sig.Length;$si++) {
    if (-not $sig[$si]) { continue }
    $ePrice=$cl[$si]
```
Entry triggers at bar $si where $sig[$si]=true.
Entry price = close of bar $si.
This matches Phase 22/23 convention.

### Exit5 Index (line 29 built-in)
```
$ex=$si+5  # phase24 line 29
```

### Exit10 Index (Calc-PnLAtBar function, line 42-48)
```
function Calc-PnLAtBar($entryIdx, $exitBar) {
    $ex = $entryIdx + $exitBar
    $ePrice = $cl[$entryIdx]
    $effEntry = $ePrice*(1+$slippage)*(1+$feeRate)
    $xPrice = $cl[$ex]
    $effExit  = $xPrice*(1-$slippage)*(1-$feeRate)
    return ($effExit-$effEntry)/$effEntry*100
}
```

### Index Math Summary

| Parameter | Exit5 | Exit10 |
|-----------|-------|--------|
| Entry bar | $si | $si |
| Exit bar | $si + 5 | $si + 10 |
| Holding bars | 5 | 10 |
| Entry price | close[$si] | close[$si] |
| Exit price | close[$si+5] | close[$si+10] |
| Fee schedule | same | same |
| Slippage | same | same |

**CONFIRMED**: Exit10 is identical to Exit5 except for the exit index offset.
No extra logic, no extra filters, no different entry conditions.

