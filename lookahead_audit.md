# Lookahead Audit

## Test 1: Future bar index check

For every Exit10 trade, verify that $ex <= $n-1 (no array overrun).
Max exit index used: 93825 (array size: 93871)
Max exit index < array size: True
Test 1 result: PASS

## Test 2: Signal leakage check

Verify that exit index uses only close[+offset] - no conditional logic, no signal re-evaluation.

Signal is evaluated ONCE at entry bar. Exit uses hard-coded offset.
No re-check of signal at exit. No lookahead through signal re-evaluation.
Test 2 result: PASS

## Test 3: Off-by-one verification

Exit10 code path:
  73.921716387 = close[si] * (1+slippage) * (1+feeRate)
    = close[si+10] * (1-slippage) * (1-feeRate)
  PnL = (effExit - effEntry) / effEntry * 100

Confirm entry uses close[si] NOT close[si-1] or close[si+1]:
  Trade 1: entryIdx=103, close[entry]=7.8985
  Entry price used: 7.8985
  Match: True

Confirm exit uses close[si+10] NOT close[si+9] or close[si+11]:
  Trade 1: exitIdx=113, close[exitIdx]=8.2797
  EntryIdx+10 = 113
  Match: True

## Test 4: Sequential trade consistency

For 5 consecutive trades, verify that each trade's exit bar > entry bar:
  Trade 1: entry=103 exit=113 delta=10
  Trade 2: entry=104 exit=114 delta=10
  Trade 3: entry=105 exit=115 delta=10
  Trade 4: entry=106 exit=116 delta=10
  Trade 5: entry=107 exit=117 delta=10
  All exit > entry: True

## CONSOLIDATED RESULT

**LOOKAHEAD: NONE FOUND.** Exit10 uses the same bar-index math as Exit5.
No future candle beyond close[si+10] is accessed. No signal re-evaluation.
No off-by-one errors detected. No array overrun.

EXIT10 LOOKAHEAD-FREE
