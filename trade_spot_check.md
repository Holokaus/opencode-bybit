# Trade Spot Check

10 random trades from 4684 total. Verified against raw candle CSV.

Entry price = Close[EntryIdx], Exit price = Close[EntryIdx+5].
EffectiveEntry = EntryPrice * (1 + 0.0002) * (1 + 0.0005)
EffectiveExit = ExitPrice * (1 - 0.0002) * (1 - 0.0005)

### Trade #3914

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 77997 | Raw candle row |
| ExitIdx | 78002 | EntryIdx+5 |
| Entry Date | 2025-07-26 21:30:00 | Raw CSV |
| Exit Date | 2025-07-27 00:00:00 | Raw CSV |
| Close[77997] | 186.32 | Raw CSV Close |
| Close[78002] | 185.31 | Raw CSV Close |
| GrossPnL | -0.5421% (ledger) vs -0.5421% (computed) | MATCH |
| Fee | 0.0997% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0399% | (Entry+Exit)*slippage/Entry |
| NetPnL | -0.6812% (ledger) vs -0.6812% (computed) | MATCH |

### Trade #2248

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 48438 | Raw candle row |
| ExitIdx | 48443 | EntryIdx+5 |
| Entry Date | 2023-11-19 02:00:00 | Raw CSV |
| Exit Date | 2023-11-19 04:30:00 | Raw CSV |
| Close[48438] | 57.442 | Raw CSV Close |
| Close[48443] | 58.219 | Raw CSV Close |
| GrossPnL | 1.3527% (ledger) vs 1.3527% (computed) | MATCH |
| Fee | 0.1007% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0403% | (Entry+Exit)*slippage/Entry |
| NetPnL | 1.2109% (ledger) vs 1.2109% (computed) | MATCH |

### Trade #624

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 7817 | Raw candle row |
| ExitIdx | 7822 | EntryIdx+5 |
| Entry Date | 2021-07-25 19:30:00 | Raw CSV |
| Exit Date | 2021-07-25 22:00:00 | Raw CSV |
| Close[7817] | 27.527 | Raw CSV Close |
| Close[7822] | 27.412 | Raw CSV Close |
| GrossPnL | -0.4178% (ledger) vs -0.4178% (computed) | MATCH |
| Fee | 0.0998% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0399% | (Entry+Exit)*slippage/Entry |
| NetPnL | -0.5571% (ledger) vs -0.5571% (computed) | MATCH |

### Trade #567

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 6773 | Raw candle row |
| ExitIdx | 6778 | EntryIdx+5 |
| Entry Date | 2021-07-04 01:30:00 | Raw CSV |
| Exit Date | 2021-07-04 04:00:00 | Raw CSV |
| Close[6773] | 33.664 | Raw CSV Close |
| Close[6778] | 34.01 | Raw CSV Close |
| GrossPnL | 1.0278% (ledger) vs 1.0278% (computed) | MATCH |
| Fee | 0.1005% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0402% | (Entry+Exit)*slippage/Entry |
| NetPnL | 0.8865% (ledger) vs 0.8865% (computed) | MATCH |

### Trade #304

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 2703 | Raw candle row |
| ExitIdx | 2708 | EntryIdx+5 |
| Entry Date | 2021-04-10 06:30:00 | Raw CSV |
| Exit Date | 2021-04-10 09:00:00 | Raw CSV |
| Close[2703] | 27.1252 | Raw CSV Close |
| Close[2708] | 27.3517 | Raw CSV Close |
| GrossPnL | 0.835% (ledger) vs 0.835% (computed) | MATCH |
| Fee | 0.1004% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0402% | (Entry+Exit)*slippage/Entry |
| NetPnL | 0.6939% (ledger) vs 0.6939% (computed) | MATCH |

### Trade #1303

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 19566 | Raw candle row |
| ExitIdx | 19571 | EntryIdx+5 |
| Entry Date | 2022-03-27 14:00:00 | Raw CSV |
| Exit Date | 2022-03-27 16:30:00 | Raw CSV |
| Close[19566] | 100.66 | Raw CSV Close |
| Close[19571] | 101.57 | Raw CSV Close |
| GrossPnL | 0.904% (ledger) vs 0.904% (computed) | MATCH |
| Fee | 0.1005% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0402% | (Entry+Exit)*slippage/Entry |
| NetPnL | 0.7629% (ledger) vs 0.7629% (computed) | MATCH |

### Trade #3038

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 63932 | Raw candle row |
| ExitIdx | 63937 | EntryIdx+5 |
| Entry Date | 2024-10-06 21:00:00 | Raw CSV |
| Exit Date | 2024-10-06 23:30:00 | Raw CSV |
| Close[63932] | 145.259 | Raw CSV Close |
| Close[63937] | 146.412 | Raw CSV Close |
| GrossPnL | 0.7938% (ledger) vs 0.7938% (computed) | MATCH |
| Fee | 0.1004% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0402% | (Entry+Exit)*slippage/Entry |
| NetPnL | 0.6527% (ledger) vs 0.6527% (computed) | MATCH |

### Trade #3953

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 78566 | Raw candle row |
| ExitIdx | 78571 | EntryIdx+5 |
| Entry Date | 2025-08-07 18:00:00 | Raw CSV |
| Exit Date | 2025-08-07 20:30:00 | Raw CSV |
| Close[78566] | 169.32 | Raw CSV Close |
| Close[78571] | 172.88 | Raw CSV Close |
| GrossPnL | 2.1025% (ledger) vs 2.1025% (computed) | MATCH |
| Fee | 0.1011% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0404% | (Entry+Exit)*slippage/Entry |
| NetPnL | 1.9597% (ledger) vs 1.9597% (computed) | MATCH |

### Trade #3406

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 69522 | Raw candle row |
| ExitIdx | 69527 | EntryIdx+5 |
| Entry Date | 2025-01-31 08:00:00 | Raw CSV |
| Exit Date | 2025-01-31 10:30:00 | Raw CSV |
| Close[69522] | 235.41 | Raw CSV Close |
| Close[69527] | 235.92 | Raw CSV Close |
| GrossPnL | 0.2166% (ledger) vs 0.2166% (computed) | MATCH |
| Fee | 0.1001% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.04% | (Entry+Exit)*slippage/Entry |
| NetPnL | 0.0764% (ledger) vs 0.0764% (computed) | MATCH |

### Trade #1116

| Field | Value | Source |
|-------|-------|--------|
| EntryIdx | 16010 | Raw candle row |
| ExitIdx | 16015 | EntryIdx+5 |
| Entry Date | 2022-01-12 12:00:00 | Raw CSV |
| Exit Date | 2022-01-12 14:30:00 | Raw CSV |
| Close[16010] | 142.5 | Raw CSV Close |
| Close[16015] | 147.01 | Raw CSV Close |
| GrossPnL | 3.1649% (ledger) vs 3.1649% (computed) | MATCH |
| Fee | 0.1016% | (Entry+Exit)*feeRate/Entry |
| Slippage | 0.0406% | (Entry+Exit)*slippage/Entry |
| NetPnL | 3.0206% (ledger) vs 3.0206% (computed) | MATCH |

