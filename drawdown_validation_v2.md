# Drawdown Validation v2

## Formulas
```
Equity_i = Equity_{i-1} * (1 + NetPnL_i / 100)
Peak = max(Equity_0 .. Equity_i)
Drawdown_i = (Peak_i - Equity_i) / Peak_i * 100
Equity_0 = 100.00
```

where NetPnL_i includes fees (0.05%/side) and slippage (0.02%/side).

## Results

| Metric | Value |
|--------|-------|
| Maximum Drawdown | 37.9644% |
| Average Drawdown | 2.1008% |
| Median Drawdown | 0.5401% |
| 95th Percentile DD | 8.8837% |
| Max DD Start Trade | 436 |
| Max DD End Trade | 439 |
| Equity at Peak | 12952.26 |
| Equity at Trough | 8035.02 |

**Peak trade (#436):** entered 2021-05-18 11:30:00 at 54.534, exited 2021-05-18 14:00:00 at 53.222, NetPnL=-2.5424%
**Trough trade (#439):** entered 2021-05-19 11:30:00 at 43.974, exited 2021-05-19 14:00:00 at 39.728, NetPnL=-9.7821%
