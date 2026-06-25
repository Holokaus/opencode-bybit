# Execution Assumptions — Phase 17 Forward Test

## Model
- **Entry execution:** Close of entry bar (market order). The entry bar index equals the signal array index `$si` (matching Phase 14/16 convention where `Get-MbfSignalArray` offset is preserved).
- **Exit execution:** Close of bar `entry_bar + 5` (market order). Fixed 5-bar holding period.
- **Direction:** Long only.

## Fees
- **Per side:** 0.05% (0.0005)
- **Round trip:** 0.10% (entry fee + exit fee)
- **Source:** Bybit linear futures VIP0 taker fee. No volume discount applied.
- **Applied as:** `effective_entry = entry_price * (1 + slippage) * (1 + fee_rate)`; `effective_exit = exit_price * (1 - slippage) * (1 - fee_rate)`

## Slippage
- **Per trade:** 0.02% (0.0002)
- **Round trip:** 0.04%
- **Source:** Estimated from typical SOLUSDT 30m bid-ask spread and volume. For the forward period (June 2026), SOL traded at ~$72 with sufficient liquidity.
- **Applied as:** Entry slippage increases entry price; exit slippage decreases exit price.

## Combined Cost (round trip)
- **Total friction:** 0.14% (0.10% fees + 0.04% slippage)
- **Breakeven:** A trade must move 0.14% in the expected direction to break even after costs.

## Data
- **Historical warmup:** 200 bars from `mbf_klines_SOLUSDT_30m.csv` ending at bar 1782054000000 (2026-06-21 ~05:00 UTC)
- **Forward data:** 154 bars fetched from Bybit `/v5/market/kline` (category=linear, interval=30) covering 2026-06-21 15:30 to 2026-06-24 20:00 UTC
- **Merge:** Warmup and forward bars concatenated sequentially. No time-alignment gap correction (the ~10-hour gap between historical end and forward start is treated as continuous bar indices).

## Signal Generation
- **Indicator:** Stoch(k=5, d=5, ob=80, os=10) via `Get-MbfSignalArray`
- **Condition:** Entry when smoothed Stoch %K (actually %D from `Calc-EMA $st $d`) > 80 OR < 10
- **Index convention:** Signal array index `$si` equals entry bar index (matching Phase 14/16). The actual Stoch condition is evaluated at bar `$si + 10` due to `Get-MbfSignalArray` offset.
- **No additional filters:** No volume filter, no trend filter, no regime filter. Frozen strategy.

## Limitations
1. **Forward period is short (3.2 days, 154 bars).** Only 1 signal generated. Results are not statistically significant.
2. The ~10-hour data gap between historical end and forward start introduces a discontinuity in the Stoch calculation (warmup bars are from ~05:00-14:30 UTC; forward bars resume at 15:30 UTC).
3. The 10-bar offset between signal detection and entry bar is a known artifact of `Get-MbfSignalArray`. Replicated exactly from Phase 14/16.
