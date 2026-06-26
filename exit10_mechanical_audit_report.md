# Exit10 Mechanical Audit Report

SOL 30m | Stoch(k=5,d=5,ob=80,os=10) | LONG only | 4684 trades

## 1. Is Exit10 mechanically correct?

**YES.** Exit10 is mechanically correct.
- Code path audited: same functions, same parameters, different exit index only
- Index alignment verified: exit = entry + 10
- Spot check: 10 random trades verified directly against raw candle data
- All manual recalculations match computed values within rounding tolerance

## 2. Is Exit10 using the same signals as Exit5?

**YES.** Both exit windows use the identical signal array ($sig) and the same entry loop.
The entry condition is evaluated once. Both exit5 and exit10 are computed from the same $si range.
Signal count: 4684 entries valid for 5-bar, 4684 for 10-bar, 4684 overlap.

## 3. Is Exit10 free of lookahead?

**YES.** Exit10 is lookahead-free:
- Entry uses close[si] (no future data)
- Exit uses close[si+10] (the intended exit candle)
- No array overrun: max exit index 93825 < array size 93871
- No signal re-evaluation at exit
- No conditional exit logic
- Off-by-one confirmed correct: entry+10 = exit

## 4. Is the Exit5 vs Exit10 comparison valid?

**YES.** The comparison is valid because:
1. Same entry signal array
2. Same fee/slippage model
3. Same data window
4. Same capital/overlap assumptions
5. Only the exit index changes (5 vs 10)

Exit10 Summary: WR=96.05% PF=26.5018 E=3.3276% DD=36.19%
Exit5  Summary: WR=66.5% PF=3.1933 E=0.6859% DD=42.88%

## 5. If valid, is the Exit10 improvement real?

**YES, the improvement is real.** The key evidence:

Average Win: Exit5=1.5016% Exit10=3.6003%
Average Loss: Exit5=-0.9336% Exit10=-3.3037%

The WR jump from 66.5% to 96.1% is explained by:
1. Most losing trades at bar 5 become winners by bar 10 (Phase 23.4: 94.3% of losers recover)
2. Winners continue to develop beyond bar 5 (Phase 23.3: only 29% of final MFE by bar 5)
3. Monotonicity check: only 891 of 4684 trades (19%) show excessive reversals

The high PF (26.5) reflects 96% win rate with average loss still meaningful:
- Most losers are eliminated (they become winners with more time)
- The few remaining losers are the ones that never recover

## 6. If invalid, what exactly is broken?

**NOTHING BROKEN.** All tests pass. The Exit10 result is mechanically valid.

FINAL VERDICT:

**EXIT10 MECHANICALLY VALID**

