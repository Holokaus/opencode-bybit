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

### Inconsistency 1: Spot API + Short Positions (CRITICAL)

FILE: `paper_trading/run_paper_trader.ps1`
FUNCTION: `Place-Order`, `Enter-Trade`, `Get-ADXSignal`, `Get-DivergenceSignal`
LINE(S): 125-128, 185, 279, 392, 394, 458
EVIDENCE:
- All kline data fetched with `category=spot`
- All orders placed with `"category":"spot"` and `"side":"Sell"`
- Short signals ARE generated in signal generators (lines 185, 279)
- Short signals ARE dispatched to `Enter-Trade` (line 458)
- `Enter-Trade` calls `Place-Order` with `"Sell"` side (line 392)

**Bybit spot does not support short selling.** A `Sell` order on spot without an existing position will be rejected by the exchange. The system generates short signals and attempts to execute them via `category=spot` orders, which will fail at order placement time.

To execute dual-direction strategies, the system must either:
- **Option A**: Switch to `category=linear` (USDT perpetual futures) with `"Side":"Sell"` for shorts
- **Option B**: Restrict to long-only spot trading and ignore short signals

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

No changes were made to execution model behavior. The system remains on `category=spot` with dual-direction signal generation.

**This is a known risk**: the paper trader (`run_paper_trader.ps1`) will attempt to place short orders on spot market, which will fail at the exchange level. This risk is documented rather than fixed because fixing it would require either:
1. Modifying strategy entry conditions (violates the hard constraint against changing strategy logic)
2. Adding futures API calls (new feature, not a refactor)

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
