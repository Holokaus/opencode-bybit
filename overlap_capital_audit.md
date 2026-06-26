# Overlap and Capital Logic Audit

## Can multiple trades be open at once?

**YES.** This simulation allows multiple concurrent trades.
Maximum concurrent trades at any bar: 11 (Exit10 window)
Trades overlap occurs whenever a signal fires within the holding window of a previous trade.
On a 30m chart with 10-bar hold = 5 hours, signals ~2-3 per day = ~2-3 concurrent positions.

## Is capital reused before previous trades close?

**YES.** The simulation does not enforce a capital constraint.
Each trade's PnL is computed independently from the same starting capital base.
This is equivalent to assuming infinite capital or separate accounts per trade.

## Does the simulation double count capital?

**NO.** Each trade is an independent PnL observation. The percent return is computed
against the trade's own entry cost. The metrics (WR, PF, E) are statistical
aggregates of independent trade outcomes, not a portfolio simulation.

Compound return assumes sequential reinvestment (each trade starts with the
previous trade's ending capital), which IS a simplification when trades overlap.
However, this affects both Exit5 and Exit10 equally and does not invalidate
the relative comparison.

## Is overlap handling different between Exit5 and Exit10?

**NO.** Both Exit5 and Exit10 use identical overlap/capital assumptions.
The number of concurrent positions differs (Exit10 holds twice as long),
but the simulation logic is identical. The comparison is valid.

