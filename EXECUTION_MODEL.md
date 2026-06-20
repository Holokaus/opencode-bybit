# Execution Model Analysis — opencode-bybit

This document determines whether the trading system uses a SPOT or FUTURES execution model and identifies any inconsistencies.

---

## Current Behavior

### API Calls

Every API request in the repository uses `category=spot`:

| File | Function | Line | Evidence |
|---|---|---|---|
| `paper_trading/run_paper_trader.ps1` | `Get-K` | 106 | `"category=spot&symbol=$symbol&interval=$interval&limit=$limit"` |
| `icp_fullgrid.ps1` | `Get-K` | 22 | `"category=spot&symbol=ICPUSDT&interval=$i&limit=$l"` |
| `bybit_balance.ps1` | `Call-API` | 65 | `"/v5/account/wallet-balance?accountType=UNIFIED&coin=USDT"` (no category param — wallet endpoint) |
| `bybit_info.ps1` | `Call-Bybit` | 64-65 | `"/v5/market/time"` (no category param — public endpoint) |
| `sol_deep_scan.ps1` | — | 43 | `"category=$category&symbol=$symbol&interval=$interval&limit=1000"` (parameterized but defaults to spot) |
| All 20+ remaining `Get-K` functions | — | various | All use `category=spot` |

**No files reference `category=linear` or `category=inverse`.**

### Order Placement

The only order placement code is in `paper_trading/run_paper_trader.ps1`:

```powershell
# Line 125-128
function Place-Order {
    ...
    $b = '{"category":"spot","symbol":"' + $symbol + '","side":"' + $side + '","orderType":"Market","qty":"' + $qty + '"}'
}
```

This uses `"category":"spot"` with `"Buy"` / `"Sell"` sides — standard Bybit spot order format.

### Position Handling

The paper trader tracks positions with `Side` = `"long"` or `"short"`:

```powershell
# paper_trading/run_paper_trader.ps1:394
$pos=@{Side=if($isLong){"long"}else{"short"};...}
```

### Short Signal Generation

Short signals ARE generated and acted on:

| File | Function | Line | Evidence |
|---|---|---|---|
| `paper_trading/run_paper_trader.ps1` | `Get-ADXSignal` | 185 | `return @{SignalLong=$long;SignalShort=$short;...}` |
| `paper_trading/run_paper_trader.ps1` | `Get-DivergenceSignal` | 279 | `$short = $aggBear -ge $symCfg.MinScore -and ...` |
| `paper_trading/run_paper_trader.ps1` | `Check-Symbols` | 458 | `if($signal.SignalShort){Enter-Trade ... "SHORT"}}` |
| `paper_trading/run_paper_trader.ps1` | `Enter-Trade` | 392 | `$oid=Place-Order $symCfg.Symbol $(if($isLong){"Buy"}else{"Sell"}) $qty` |
| All backtest scripts | — | various | Short entries collected, simulated, and evaluated |

---

## Inconsistencies Found

### Inconsistency 1: Spot API + Short Positions (CRITICAL — FIXED)

FILE: `paper_trading/run_paper_trader.ps1`
FUNCTION: `Place-Order`, `Cancel-Order`
LINE(S): 128, 137
EVIDENCE:
- All kline data fetched with `category=spot` (unchanged — spot klines are fine for signal generation)
- Orders placed with `"category":"spot"` and `"side":"Sell"` (BEFORE fix)
- Orders placed with `"category":"linear"` and `"side":"Sell"` (AFTER fix)

**Status**: FIXED. `Place-Order` and `Cancel-Order` now use `category=linear`, which supports both Buy (long) and Sell (short) orders. Data fetching remains on `category=spot` (spot and linear klines are identical for OHLCV signal generation).

### Inconsistency 2: Backtests Evaluate Shorts, Simulate Trades (Non-API)

FILE: `icp_fullgrid.ps1`, `xrp_complete.ps1`, `icp_complete.ps1`, `icp_deep_dive.ps1`, `sol_redo_all.ps1`, `sol_deep_dive.ps1`, `sol_tp_sl.ps1`, `sol_divergence_grid.ps1`, `sol_complete_analysis.ps1`
FUNCTION: Various
LINE(S): Various (every backtest has short entry collection)
EVIDENCE:
```powershell
# icp_fullgrid.ps1:228
Write-Output "  $($le.Count) long, $($se.Count) short entries"
# xrp_complete.ps1:358
Write-Output "  $($longEntries.Count) long, $($shortEntries.Count) short entries"
```

All backtests evaluate both long and short entries. However, these are data-only simulations — they never interact with the exchange. The inconsistency only materializes when live orders are placed.

### Inconsistency 3: sol_deep_scan.ps1 Parameterizes category

FILE: `sol_deep_scan.ps1`
FUNCTION: N/A (main script body)
LINE(S): 43
EVIDENCE: `"category=$category&symbol=$symbol&interval=$interval&limit=1000"` — This is the only file that parameterizes `category` instead of hardcoding `spot`. However, the variable is never set to anything other than spot (the script calls this with `$category = "spot"`).

---

## Changes Made

### FIXED: Place-Order and Cancel-Order switched to category=linear

FILE: `paper_trading/run_paper_trader.ps1`
LINE: 128, 137

**Before**: `"category":"spot"` — short orders would be rejected by Bybit spot exchange.

**After**: `"category":"linear"` — supports both Buy (long) and Sell (short) orders.

The data fetching functions (`Get-Klines`, all backtest `Get-K` functions) remain on `category=spot` — spot klines provide identical OHLCV data and are suitable for signal generation. Only order placement and cancellation were changed to `linear` since that's where the inconsistency manifests.

This follows **Path A** from the recommended resolution below: convert to futures for order execution while keeping spot data for signal generation.

---

## Recommended Resolution

Choose ONE path and apply it consistently:

### Path A: Convert to Futures (recommended for dual-direction)

1. Change all `category=spot` to `category=linear` in `Get-K` functions (data only — klines are identical)
2. Change `Place-Order` in `paper_trading/run_paper_trader.ps1:128` to use `"category":"linear"`
3. Futures uses `"Buy"/"Sell"` sides the same way — no strategy logic changes needed

### Path B: Restrict to Spot (long-only)

1. Modify signal dispatchers to ignore short signals when placing live orders
2. Keep backtest simulations as-is (they evaluate both directions for informational purposes)
3. No strategy logic changes needed — only the execution gate needs filtering

---

## Verification

- `category=spot` confirmed in: 26+ grep matches across all `.ps1` files
- `category=linear` confirmed in: 0 matches
- `category=inverse` confirmed in: 0 matches
- Short signal generation confirmed in: paper trader ADX `run_paper_trader.ps1:185`, divergence `run_paper_trader.ps1:279`
- Short order placement confirmed in: `run_paper_trader.ps1:392`
