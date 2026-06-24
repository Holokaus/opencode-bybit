# Institutional Market Behavior Research -- Phase 11 Edge Report

**Generated:** 2026-06-22 23:31:49
**Assets:** SOLUSDT, ICPUSDT
**Timeframes:** 30m (primary), 1h, 4h (regime)
**Regime Data:** 4h k-line futures data

---

## 1. Regime Distribution

### SOLUSDT

| Regime | Bars | % of History |
|--------|------|-------------|
| DISTRIBUTION | 943 | 11.5% |
| RANGE | 854 | 10.4% |
| ACCUMULATION | 555 | 6.8% |
| TREND_UP | 549 | 6.7% |
| VOL_EXPANSION | 37 | 0.5% |
| VOL_COMPRESSION | 2720 | 33.2% |
| TREND_DOWN | 2324 | 28.4% |
| WARMUP | 200 | 2.4% |

### ICPUSDT

| Regime | Bars | % of History |
|--------|------|-------------|
| TREND_DOWN | 989 | 12.1% |
| TREND_UP | 521 | 6.4% |
| VOL_EXPANSION | 433 | 5.3% |
| DISTRIBUTION | 303 | 3.7% |
| VOL_COMPRESSION | 2304 | 28.2% |
| RANGE | 2153 | 26.3% |
| WARMUP | 200 | 2.4% |
| ACCUMULATION | 1279 | 15.6% |

---

## 2. Regime Quality


### SOLUSDT

| Regime | Bars | Persistence | Avg Duration | 1B Move | 5B Move | 20B Move | Adequate |
|--------|------|------------|-------------|---------|---------|----------|----------|
| DISTRIBUTION | 943 | 45.92% | 1.8 | 0.15% | 0.53% | 1.5% | True |
| RANGE | 854 | 47.66% | 1.9 | -0.04% | -0.14% | -0.13% | True |
| ACCUMULATION | 555 | 84.86% | 6.6 | 0.12% | 0.38% | 2.95% | True |
| TREND_UP | 549 | 83.24% | 6 | 0.13% | 0.48% | 2.36% | True |
| VOL_EXPANSION | 37 | 94.59% | 18.5 | -0.66% | 0.15% | -5.2% | True |
| VOL_COMPRESSION | 2720 | 75.26% | 4 | -0.03% | 0.04% | 0.07% | True |
| TREND_DOWN | 2324 | 70.57% | 3.4 | 0.04% | 0.1% | 0.25% | True |

### ICPUSDT

| Regime | Bars | Persistence | Avg Duration | 1B Move | 5B Move | 20B Move | Adequate |
|--------|------|------------|-------------|---------|---------|----------|----------|
| TREND_DOWN | 989 | 54.7% | 2.2 | 0.13% | 0.6% | 2.53% | True |
| TREND_UP | 521 | 19.19% | 1.2 | -0.01% | -0.12% | 0.47% | True |
| VOL_EXPANSION | 433 | 87.3% | 7.9 | 0.09% | 0.31% | 0.03% | True |
| DISTRIBUTION | 303 | 92.41% | 13.2 | 0.21% | 1.06% | -0.24% | True |
| VOL_COMPRESSION | 2304 | 67.32% | 3.1 | -0.02% | -0.15% | 0.12% | True |
| RANGE | 2153 | 66.47% | 3 | -0.03% | 0.01% | -0.29% | True |
| ACCUMULATION | 1279 | 67.16% | 3 | -0.02% | -0.2% | -0.21% | True |

---

## 3. Candidate Performance by Regime


### Stoch

| Asset | TF | Regime | Params | Signals | WinRate | Sharpe | PF | AvgRet5B |
|-------|-----|--------|--------|---------|---------|--------|----|---------|
| SOLUSDT | 4h | ACCUMULATION | k=5,d=5,ob=80,os=10 | 14 | 78.6% | 0.816 | 7.92 | 3.7735% |
| SOLUSDT | 1h | DISTRIBUTION | k=5,d=5,ob=80,os=10 | 223 | 85.7% | 0.7574 | 16.1 | 2.3614% |
| SOLUSDT | 4h | TREND_UP | k=5,d=5,ob=80,os=10 | 33 | 81.8% | 0.7526 | 9.08 | 4.1787% |
| ICPUSDT | 1h | DISTRIBUTION | k=14,d=9,ob=80,os=10 | 67 | 76.1% | 0.7198 | 10.12 | 3.1457% |
| SOLUSDT | 4h | TREND_DOWN | k=5,d=5,ob=80,os=10 | 111 | 75.7% | 0.6952 | 7.27 | 2.0453% |
| SOLUSDT | 30m | VOL_EXPANSION | k=21,d=9,ob=85,os=10 | 33 | 72.7% | 0.6888 | 5.81 | 1.573% |
| SOLUSDT | 1h | ACCUMULATION | k=5,d=5,ob=80,os=10 | 99 | 76.8% | 0.6834 | 6.98 | 1.9904% |
| SOLUSDT | 30m | VOL_EXPANSION | k=5,d=5,ob=80,os=10 | 29 | 72.4% | 0.6729 | 6.37 | 1.3609% |
| SOLUSDT | 4h | DISTRIBUTION | k=5,d=5,ob=80,os=10 | 54 | 81.5% | 0.6556 | 7.63 | 2.4397% |
| SOLUSDT | 1h | TREND_DOWN | k=5,d=5,ob=80,os=10 | 335 | 72.2% | 0.6317 | 5.62 | 0.8426% |
| SOLUSDT | 30m | ACCUMULATION | k=5,d=5,ob=80,os=10 | 222 | 73.9% | 0.5877 | 6.27 | 1.3829% |
| SOLUSDT | 30m | DISTRIBUTION | k=5,d=5,ob=80,os=10 | 381 | 74.3% | 0.5612 | 5.29 | 1.0783% |
| SOLUSDT | 4h | VOL_COMPRESSION | k=5,d=5,ob=80,os=10 | 159 | 72.3% | 0.5334 | 4.46 | 1.8249% |
| SOLUSDT | 1h | VOL_COMPRESSION | k=5,d=5,ob=80,os=10 | 513 | 71.2% | 0.5287 | 4.14 | 0.7251% |
| ICPUSDT | 1h | TREND_DOWN | k=14,d=9,ob=80,os=10 | 328 | 71.3% | 0.4956 | 3.77 | 1.3328% |
| SOLUSDT | 1h | TREND_UP | k=5,d=5,ob=80,os=10 | 116 | 72.4% | 0.4836 | 3.88 | 1.1434% |
| SOLUSDT | 1h | DISTRIBUTION | k=21,d=9,ob=85,os=10 | 156 | 69.9% | 0.4824 | 3.37 | 1.2291% |
| SOLUSDT | 30m | RANGE | k=5,d=5,ob=80,os=10 | 290 | 71% | 0.4419 | 4.08 | 0.9297% |
| SOLUSDT | 30m | TREND_DOWN | k=5,d=5,ob=80,os=10 | 887 | 71.4% | 0.4335 | 4.14 | 0.8102% |
| SOLUSDT | 4h | RANGE | k=5,d=5,ob=80,os=10 | 57 | 68.4% | 0.4261 | 2.99 | 1.7393% |
| SOLUSDT | 4h | RANGE | k=21,d=9,ob=85,os=10 | 49 | 67.3% | 0.4196 | 2.85 | 1.927% |
| ICPUSDT | 4h | RANGE | k=14,d=9,ob=80,os=10 | 165 | 63.6% | 0.4056 | 3.27 | 1.5434% |
| SOLUSDT | 30m | VOL_COMPRESSION | k=5,d=5,ob=80,os=10 | 935 | 69.6% | 0.389 | 3.78 | 0.8082% |
| ICPUSDT | 30m | TREND_DOWN | k=14,d=9,ob=80,os=10 | 617 | 64.7% | 0.3675 | 2.76 | 0.7075% |
| ICPUSDT | 4h | ACCUMULATION | k=14,d=9,ob=80,os=10 | 66 | 63.6% | 0.3638 | 2.56 | 1.1874% |
| SOLUSDT | 4h | ACCUMULATION | k=21,d=9,ob=85,os=10 | 20 | 30% | -0.3567 | 0.39 | -0.6849% |
| SOLUSDT | 1h | RANGE | k=21,d=9,ob=85,os=10 | 243 | 37.9% | -0.3369 | 0.36 | -1.1562% |
| SOLUSDT | 1h | TREND_UP | k=21,d=9,ob=85,os=10 | 112 | 64.3% | 0.3233 | 2.94 | 1.0764% |
| SOLUSDT | 30m | TREND_UP | k=5,d=5,ob=80,os=10 | 239 | 69.9% | 0.2952 | 2.77 | 0.8075% |
| ICPUSDT | 4h | DISTRIBUTION | k=14,d=9,ob=80,os=10 | 9 | 44.4% | 0.29 | 3.59 | 4.1738% |
| ICPUSDT | 30m | ACCUMULATION | k=14,d=9,ob=80,os=10 | 799 | 40.4% | -0.2678 | 0.49 | -0.2783% |
| ICPUSDT | 30m | TREND_UP | k=14,d=9,ob=80,os=10 | 347 | 36% | -0.2542 | 0.37 | -1.0005% |
| ICPUSDT | 4h | TREND_DOWN | k=14,d=9,ob=80,os=10 | 71 | 52.1% | 0.2383 | 2.48 | 1.8527% |
| SOLUSDT | 1h | TREND_DOWN | k=21,d=9,ob=85,os=10 | 494 | 56.3% | 0.2142 | 1.79 | 0.258% |
| ICPUSDT | 1h | TREND_UP | k=14,d=9,ob=80,os=10 | 153 | 45.8% | -0.2132 | 0.53 | -0.86% |
| SOLUSDT | 4h | DISTRIBUTION | k=21,d=9,ob=85,os=10 | 54 | 53.7% | 0.2131 | 1.81 | 0.8183% |
| ICPUSDT | 4h | TREND_UP | k=14,d=9,ob=80,os=10 | 39 | 56.4% | 0.204 | 1.7 | 0.7614% |
| ICPUSDT | 30m | VOL_COMPRESSION | k=14,d=9,ob=80,os=10 | 1373 | 57.2% | 0.2006 | 1.72 | 0.2163% |
| ICPUSDT | 30m | DISTRIBUTION | k=14,d=9,ob=80,os=10 | 126 | 54% | 0.1872 | 1.67 | 0.7202% |
| ICPUSDT | 1h | VOL_COMPRESSION | k=14,d=9,ob=80,os=10 | 666 | 56.5% | 0.1867 | 1.66 | 0.2903% |
| SOLUSDT | 30m | TREND_DOWN | k=21,d=9,ob=85,os=10 | 914 | 59.5% | 0.1767 | 1.71 | 0.35% |
| ICPUSDT | 1h | ACCUMULATION | k=14,d=9,ob=80,os=10 | 425 | 41.6% | -0.1657 | 0.65 | -0.22% |
| SOLUSDT | 30m | DISTRIBUTION | k=21,d=9,ob=85,os=10 | 352 | 52.8% | 0.1209 | 1.46 | 0.2426% |
| SOLUSDT | 4h | TREND_DOWN | k=21,d=9,ob=85,os=10 | 104 | 41.3% | -0.1089 | 0.76 | -0.2948% |
| ICPUSDT | 1h | RANGE | k=14,d=9,ob=80,os=10 | 740 | 53.9% | 0.1003 | 1.3 | 0.1496% |
| ICPUSDT | 30m | RANGE | k=14,d=9,ob=80,os=10 | 1446 | 54.3% | 0.0923 | 1.28 | 0.0974% |
| SOLUSDT | 4h | VOL_COMPRESSION | k=21,d=9,ob=85,os=10 | 203 | 53.2% | 0.091 | 1.28 | 0.2858% |
| SOLUSDT | 1h | VOL_COMPRESSION | k=21,d=9,ob=85,os=10 | 647 | 54.3% | 0.0867 | 1.27 | 0.1126% |
| ICPUSDT | 1h | VOL_EXPANSION | k=14,d=9,ob=80,os=10 | 199 | 56.8% | 0.0841 | 1.25 | 0.3352% |
| SOLUSDT | 1h | RANGE | k=5,d=5,ob=80,os=10 | 181 | 50.8% | 0.0814 | 1.24 | 0.1837% |
| SOLUSDT | 30m | ACCUMULATION | k=21,d=9,ob=85,os=10 | 221 | 54.8% | 0.0732 | 1.24 | 0.1856% |
| SOLUSDT | 30m | VOL_COMPRESSION | k=21,d=9,ob=85,os=10 | 967 | 50.5% | 0.0623 | 1.22 | 0.1277% |
| SOLUSDT | 30m | RANGE | k=21,d=9,ob=85,os=10 | 301 | 48.8% | 0.0518 | 1.16 | 0.0974% |
| ICPUSDT | 4h | VOL_EXPANSION | k=14,d=9,ob=80,os=10 | 28 | 46.4% | 0.0384 | 1.1 | 0.2171% |
| SOLUSDT | 4h | TREND_UP | k=21,d=9,ob=85,os=10 | 36 | 44.4% | -0.0346 | 0.92 | -0.1913% |
| ICPUSDT | 30m | VOL_EXPANSION | k=14,d=9,ob=80,os=10 | 356 | 52% | 0.0268 | 1.08 | 0.0804% |
| SOLUSDT | 1h | ACCUMULATION | k=21,d=9,ob=85,os=10 | 74 | 52.7% | 0.0169 | 1.04 | 0.0502% |
| ICPUSDT | 4h | VOL_COMPRESSION | k=14,d=9,ob=80,os=10 | 159 | 44% | -0.0153 | 0.95 | -0.0778% |
| SOLUSDT | 30m | TREND_UP | k=21,d=9,ob=85,os=10 | 207 | 54.1% | 0.0053 | 1.02 | 0.0127% |

### CMF

| Asset | TF | Regime | Params | Signals | WinRate | Sharpe | PF | AvgRet5B |
|-------|-----|--------|--------|---------|---------|--------|----|---------|
| SOLUSDT | 1h | DISTRIBUTION | len=21,thresh=0 | 2318 | 68.4% | 0.4607 | 4 | 1.3907% |
| SOLUSDT | 1h | RANGE | len=21,thresh=0 | 1904 | 30.4% | -0.4544 | 0.29 | -1.269% |
| ICPUSDT | 1h | TREND_DOWN | len=21,thresh=0 | 2212 | 67.6% | 0.4415 | 3.32 | 1.2103% |
| ICPUSDT | 30m | TREND_DOWN | len=21,thresh=0 | 4490 | 66% | 0.392 | 2.89 | 0.7625% |
| ICPUSDT | 1h | TREND_UP | len=21,thresh=0 | 996 | 32.5% | -0.352 | 0.35 | -1.4142% |
| ICPUSDT | 30m | TREND_UP | len=21,thresh=0 | 2177 | 32% | -0.3102 | 0.39 | -0.9571% |
| SOLUSDT | 30m | VOL_EXPANSION | len=21,thresh=0 | 201 | 59.2% | 0.3063 | 2.2 | 0.7176% |
| ICPUSDT | 1h | ACCUMULATION | len=21,thresh=0 | 2676 | 37.1% | -0.2892 | 0.45 | -0.4459% |
| ICPUSDT | 30m | ACCUMULATION | len=21,thresh=0 | 5285 | 39.6% | -0.2655 | 0.49 | -0.2843% |
| ICPUSDT | 4h | DISTRIBUTION | len=21,thresh=0 | 89 | 47.2% | 0.2178 | 2.05 | 2.4944% |
| ICPUSDT | 1h | DISTRIBUTION | len=21,thresh=0 | 525 | 56.4% | 0.2111 | 1.84 | 1.1475% |
| SOLUSDT | 1h | VOL_EXPANSION | len=21,thresh=0 | 75 | 52% | 0.208 | 1.92 | 2.2555% |
| SOLUSDT | 4h | DISTRIBUTION | len=21,thresh=0 | 600 | 55% | 0.1833 | 1.68 | 0.8569% |
| ICPUSDT | 30m | DISTRIBUTION | len=21,thresh=0 | 1100 | 53.2% | 0.1799 | 1.7 | 0.7077% |
| SOLUSDT | 1h | TREND_DOWN | len=21,thresh=0 | 4864 | 55% | 0.1666 | 1.58 | 0.231% |
| ICPUSDT | 4h | TREND_DOWN | len=21,thresh=0 | 529 | 51.6% | 0.1414 | 1.54 | 0.8225% |
| SOLUSDT | 1h | TREND_UP | len=21,thresh=0 | 983 | 52.9% | 0.1094 | 1.36 | 0.2809% |
| ICPUSDT | 1h | VOL_COMPRESSION | len=21,thresh=0 | 4673 | 53.3% | 0.1047 | 1.33 | 0.1704% |
| ICPUSDT | 30m | VOL_COMPRESSION | len=21,thresh=0 | 9707 | 53.1% | 0.1037 | 1.32 | 0.1104% |
| SOLUSDT | 1h | ACCUMULATION | len=21,thresh=0 | 1335 | 53.3% | 0.1019 | 1.32 | 0.3062% |
| ICPUSDT | 1h | RANGE | len=21,thresh=0 | 4642 | 52.5% | 0.0953 | 1.29 | 0.1349% |
| SOLUSDT | 30m | ACCUMULATION | len=21,thresh=0 | 2411 | 50.7% | 0.0801 | 1.27 | 0.1897% |
| SOLUSDT | 4h | TREND_DOWN | len=21,thresh=0 | 1281 | 50.4% | 0.0786 | 1.24 | 0.2806% |
| SOLUSDT | 4h | ACCUMULATION | len=21,thresh=0 | 403 | 46.4% | 0.0777 | 1.27 | 0.4664% |
| ICPUSDT | 4h | ACCUMULATION | len=21,thresh=0 | 656 | 49.7% | -0.0752 | 0.81 | -0.2947% |
| SOLUSDT | 4h | RANGE | len=21,thresh=0 | 486 | 47.5% | -0.0741 | 0.81 | -0.3945% |
| ICPUSDT | 4h | VOL_EXPANSION | len=21,thresh=0 | 220 | 49.1% | 0.0707 | 1.21 | 0.4378% |
| SOLUSDT | 30m | TREND_DOWN | len=21,thresh=0 | 10479 | 50.9% | 0.0658 | 1.23 | 0.1283% |
| SOLUSDT | 4h | TREND_UP | len=21,thresh=0 | 330 | 51.8% | 0.0624 | 1.21 | 0.4217% |
| SOLUSDT | 30m | RANGE | len=21,thresh=0 | 3786 | 49.7% | 0.0603 | 1.22 | 0.1314% |
| SOLUSDT | 30m | DISTRIBUTION | len=21,thresh=0 | 4299 | 49.3% | 0.0563 | 1.19 | 0.1097% |
| SOLUSDT | 30m | VOL_COMPRESSION | len=21,thresh=0 | 11958 | 50.8% | 0.0553 | 1.18 | 0.1099% |
| SOLUSDT | 30m | TREND_UP | len=21,thresh=0 | 2688 | 49.7% | 0.0538 | 1.18 | 0.1043% |
| SOLUSDT | 4h | VOL_EXPANSION | len=21,thresh=0 | 21 | 42.9% | 0.0434 | 1.13 | 0.9369% |
| ICPUSDT | 1h | VOL_EXPANSION | len=21,thresh=0 | 857 | 51.7% | 0.0405 | 1.12 | 0.1369% |
| ICPUSDT | 30m | VOL_EXPANSION | len=21,thresh=0 | 1805 | 50.8% | 0.0375 | 1.11 | 0.0907% |
| ICPUSDT | 30m | RANGE | len=21,thresh=0 | 9035 | 50.7% | 0.0244 | 1.07 | 0.0251% |
| ICPUSDT | 4h | TREND_UP | len=21,thresh=0 | 277 | 49.1% | -0.0225 | 0.94 | -0.1063% |
| ICPUSDT | 4h | RANGE | len=21,thresh=0 | 1175 | 49% | -0.0077 | 0.98 | -0.03% |
| SOLUSDT | 4h | VOL_COMPRESSION | len=21,thresh=0 | 1510 | 49.5% | 0.0069 | 1.02 | 0.0257% |
| SOLUSDT | 1h | VOL_COMPRESSION | len=21,thresh=0 | 6159 | 49.5% | -0.0047 | 0.99 | -0.0063% |
| ICPUSDT | 4h | VOL_COMPRESSION | len=21,thresh=0 | 1216 | 47.2% | -0.0039 | 0.99 | -0.0166% |

### OBV

| Asset | TF | Regime | Params | Signals | WinRate | Sharpe | PF | AvgRet5B |
|-------|-----|--------|--------|---------|---------|--------|----|---------|
| SOLUSDT | 1h | DISTRIBUTION | ma=20 | 2266 | 70.8% | 0.5336 | 5.01 | 1.5744% |
| ICPUSDT | 1h | TREND_DOWN | ma=20 | 2052 | 70.3% | 0.5063 | 4.01 | 1.4266% |
| ICPUSDT | 30m | TREND_DOWN | ma=20 | 4091 | 69.4% | 0.4668 | 3.68 | 0.9286% |
| SOLUSDT | 30m | VOL_EXPANSION | ma=20 | 145 | 59.3% | 0.3169 | 2.17 | 0.6964% |
| ICPUSDT | 1h | DISTRIBUTION | ma=20 | 491 | 59.9% | 0.3043 | 2.5 | 1.7906% |
| SOLUSDT | 1h | RANGE | ma=20 | 1301 | 36.7% | -0.2847 | 0.46 | -0.8388% |
| ICPUSDT | 4h | DISTRIBUTION | ma=20 | 119 | 45.4% | 0.28 | 2.21 | 3.6118% |
| SOLUSDT | 4h | TREND_UP | ma=20 | 288 | 54.2% | 0.247 | 1.98 | 1.3992% |
| ICPUSDT | 4h | TREND_DOWN | ma=20 | 502 | 55.4% | 0.2122 | 1.89 | 1.2939% |
| ICPUSDT | 30m | ACCUMULATION | ma=20 | 3814 | 41.7% | -0.2076 | 0.58 | -0.2214% |
| ICPUSDT | 30m | DISTRIBUTION | ma=20 | 1080 | 55.6% | 0.2009 | 1.8 | 0.8308% |
| SOLUSDT | 1h | TREND_DOWN | ma=20 | 4687 | 56.4% | 0.1991 | 1.73 | 0.2761% |
| SOLUSDT | 4h | DISTRIBUTION | ma=20 | 532 | 55.8% | 0.188 | 1.71 | 0.9224% |
| ICPUSDT | 1h | ACCUMULATION | ma=20 | 1968 | 41.9% | -0.1853 | 0.61 | -0.2965% |
| SOLUSDT | 1h | ACCUMULATION | ma=20 | 1060 | 56.5% | 0.1839 | 1.64 | 0.547% |
| ICPUSDT | 30m | VOL_COMPRESSION | ma=20 | 8636 | 56.1% | 0.1782 | 1.62 | 0.1914% |
| ICPUSDT | 1h | TREND_UP | ma=20 | 744 | 40.9% | -0.1714 | 0.61 | -0.6663% |
| SOLUSDT | 30m | TREND_UP | ma=20 | 2137 | 54.3% | 0.1691 | 1.66 | 0.3292% |
| SOLUSDT | 30m | DISTRIBUTION | ma=20 | 3675 | 55.3% | 0.167 | 1.67 | 0.3178% |
| SOLUSDT | 1h | VOL_EXPANSION | ma=20 | 34 | 47.1% | 0.1659 | 1.63 | 2.0193% |
| ICPUSDT | 1h | VOL_COMPRESSION | ma=20 | 4122 | 55.9% | 0.1651 | 1.58 | 0.267% |
| SOLUSDT | 4h | RANGE | ma=20 | 347 | 54.5% | 0.1548 | 1.51 | 0.6538% |
| ICPUSDT | 4h | RANGE | ma=20 | 873 | 55.1% | 0.154 | 1.54 | 0.6202% |
| SOLUSDT | 4h | VOL_COMPRESSION | ma=20 | 1301 | 55.5% | 0.1533 | 1.55 | 0.5604% |
| ICPUSDT | 1h | RANGE | ma=20 | 3697 | 55% | 0.1501 | 1.5 | 0.2168% |
| SOLUSDT | 1h | TREND_UP | ma=20 | 1055 | 54.5% | 0.1414 | 1.47 | 0.3544% |
| SOLUSDT | 30m | TREND_DOWN | ma=20 | 9219 | 54.5% | 0.1403 | 1.57 | 0.2781% |
| ICPUSDT | 4h | VOL_EXPANSION | ma=20 | 181 | 53% | 0.1382 | 1.46 | 0.8297% |
| ICPUSDT | 1h | VOL_EXPANSION | ma=20 | 773 | 55.9% | 0.1376 | 1.46 | 0.4507% |
| SOLUSDT | 30m | VOL_COMPRESSION | ma=20 | 10261 | 54.8% | 0.1261 | 1.49 | 0.2659% |
| ICPUSDT | 30m | TREND_UP | ma=20 | 1310 | 41.8% | -0.1257 | 0.7 | -0.3625% |
| SOLUSDT | 30m | ACCUMULATION | ma=20 | 2119 | 53.9% | 0.1096 | 1.39 | 0.2598% |
| SOLUSDT | 30m | RANGE | ma=20 | 3447 | 52.5% | 0.1091 | 1.46 | 0.2717% |
| SOLUSDT | 4h | TREND_DOWN | ma=20 | 1118 | 50.7% | 0.1081 | 1.36 | 0.416% |
| SOLUSDT | 1h | VOL_COMPRESSION | ma=20 | 5168 | 53.7% | 0.0854 | 1.26 | 0.1138% |
| ICPUSDT | 4h | VOL_COMPRESSION | ma=20 | 1098 | 49.7% | 0.0758 | 1.24 | 0.3287% |
| SOLUSDT | 4h | ACCUMULATION | ma=20 | 300 | 44.7% | 0.0618 | 1.22 | 0.3802% |
| ICPUSDT | 30m | RANGE | ma=20 | 7438 | 51.7% | 0.0535 | 1.15 | 0.0554% |
| ICPUSDT | 30m | VOL_EXPANSION | ma=20 | 1502 | 51.4% | 0.0405 | 1.12 | 0.0984% |
| ICPUSDT | 4h | ACCUMULATION | ma=20 | 553 | 54.6% | 0.0314 | 1.09 | 0.1215% |
| ICPUSDT | 4h | TREND_UP | ma=20 | 225 | 49.8% | 0.0119 | 1.03 | 0.0531% |

### ADX

| Asset | TF | Regime | Params | Signals | WinRate | Sharpe | PF | AvgRet5B |
|-------|-----|--------|--------|---------|---------|--------|----|---------|
| SOLUSDT | 1h | RANGE | len=14,thresh=25 | 2921 | 26.3% | -0.5539 | 0.22 | -1.5829% |
| SOLUSDT | 1h | DISTRIBUTION | len=14,thresh=25 | 3041 | 70.5% | 0.4877 | 4.2 | 1.4529% |
| ICPUSDT | 1h | TREND_UP | len=14,thresh=25 | 1617 | 25.7% | -0.4669 | 0.27 | -1.7964% |
| ICPUSDT | 30m | TREND_DOWN | len=14,thresh=25 | 6299 | 69.3% | 0.4534 | 3.47 | 0.9123% |
| ICPUSDT | 1h | TREND_DOWN | len=14,thresh=25 | 3137 | 67.6% | 0.436 | 3.26 | 1.2275% |
| ICPUSDT | 30m | TREND_UP | len=14,thresh=25 | 3572 | 27.9% | -0.4077 | 0.29 | -1.2072% |
| ICPUSDT | 1h | ACCUMULATION | len=14,thresh=25 | 3956 | 34.1% | -0.3706 | 0.36 | -0.6003% |
| ICPUSDT | 30m | ACCUMULATION | len=14,thresh=25 | 7458 | 34.4% | -0.3631 | 0.38 | -0.4088% |
| SOLUSDT | 30m | VOL_EXPANSION | len=14,thresh=25 | 230 | 55.2% | 0.2622 | 1.97 | 0.5842% |
| ICPUSDT | 4h | DISTRIBUTION | len=14,thresh=25 | 182 | 43.4% | 0.2146 | 1.85 | 2.4394% |
| ICPUSDT | 4h | TREND_DOWN | len=14,thresh=25 | 795 | 55.6% | 0.2145 | 1.91 | 1.2279% |
| SOLUSDT | 4h | DISTRIBUTION | len=14,thresh=25 | 761 | 55.7% | 0.2134 | 1.82 | 0.9755% |
| ICPUSDT | 1h | DISTRIBUTION | len=14,thresh=25 | 790 | 54.6% | 0.209 | 1.82 | 1.2495% |
| ICPUSDT | 30m | DISTRIBUTION | len=14,thresh=25 | 1721 | 53.3% | 0.1923 | 1.76 | 0.8071% |
| ICPUSDT | 4h | ACCUMULATION | len=14,thresh=25 | 957 | 43.9% | -0.1856 | 0.59 | -0.7399% |
| SOLUSDT | 4h | RANGE | len=14,thresh=25 | 692 | 44.1% | -0.1438 | 0.66 | -0.7343% |
| SOLUSDT | 1h | TREND_DOWN | len=14,thresh=25 | 6750 | 54.4% | 0.1367 | 1.46 | 0.1937% |
| ICPUSDT | 4h | TREND_UP | len=14,thresh=25 | 369 | 44.2% | -0.1268 | 0.7 | -0.5862% |
| SOLUSDT | 4h | ACCUMULATION | len=14,thresh=25 | 388 | 48.2% | 0.1238 | 1.44 | 0.8176% |
| SOLUSDT | 1h | ACCUMULATION | len=14,thresh=25 | 1500 | 54.6% | 0.12 | 1.39 | 0.3598% |
| SOLUSDT | 4h | TREND_DOWN | len=14,thresh=25 | 1738 | 52.6% | 0.1066 | 1.34 | 0.4135% |
| SOLUSDT | 1h | VOL_EXPANSION | len=14,thresh=25 | 138 | 39.1% | -0.1028 | 0.73 | -1.1669% |
| ICPUSDT | 30m | VOL_COMPRESSION | len=14,thresh=25 | 12589 | 53.3% | 0.0997 | 1.31 | 0.1091% |
| ICPUSDT | 1h | VOL_COMPRESSION | len=14,thresh=25 | 6414 | 53.3% | 0.089 | 1.28 | 0.1492% |
| SOLUSDT | 1h | VOL_COMPRESSION | len=14,thresh=25 | 7962 | 46.3% | -0.0812 | 0.8 | -0.1149% |
| ICPUSDT | 1h | VOL_EXPANSION | len=14,thresh=25 | 1225 | 46.3% | -0.0666 | 0.84 | -0.2298% |
| ICPUSDT | 30m | VOL_EXPANSION | len=14,thresh=25 | 2401 | 47.6% | -0.0634 | 0.84 | -0.1578% |
| ICPUSDT | 30m | RANGE | len=14,thresh=25 | 11340 | 46.7% | -0.0601 | 0.85 | -0.0645% |
| SOLUSDT | 4h | VOL_COMPRESSION | len=14,thresh=25 | 2004 | 45.2% | -0.0573 | 0.85 | -0.2217% |
| ICPUSDT | 4h | RANGE | len=14,thresh=25 | 1519 | 45.6% | -0.057 | 0.86 | -0.2266% |
| SOLUSDT | 1h | TREND_UP | len=14,thresh=25 | 1556 | 50.6% | 0.0455 | 1.13 | 0.1255% |
| SOLUSDT | 4h | TREND_UP | len=14,thresh=25 | 396 | 44.7% | -0.0433 | 0.88 | -0.2765% |
| ICPUSDT | 4h | VOL_COMPRESSION | len=14,thresh=25 | 1587 | 49.6% | 0.0432 | 1.13 | 0.1875% |
| SOLUSDT | 30m | DISTRIBUTION | len=14,thresh=25 | 5453 | 49.8% | 0.0369 | 1.12 | 0.0732% |
| SOLUSDT | 30m | TREND_DOWN | len=14,thresh=25 | 13271 | 50.4% | 0.0343 | 1.11 | 0.0698% |
| ICPUSDT | 4h | VOL_EXPANSION | len=14,thresh=25 | 318 | 47.5% | -0.0337 | 0.92 | -0.2% |
| SOLUSDT | 4h | VOL_EXPANSION | len=14,thresh=25 | 24 | 33.3% | -0.0326 | 0.91 | -0.6613% |
| ICPUSDT | 1h | RANGE | len=14,thresh=25 | 5744 | 47.7% | -0.0256 | 0.93 | -0.0398% |
| SOLUSDT | 30m | TREND_UP | len=14,thresh=25 | 3054 | 49.5% | 0.0142 | 1.05 | 0.0346% |
| SOLUSDT | 30m | RANGE | len=14,thresh=25 | 5169 | 47.8% | 0.0081 | 1.03 | 0.0185% |
| SOLUSDT | 30m | ACCUMULATION | len=14,thresh=25 | 3126 | 49.6% | -0.008 | 0.98 | -0.0208% |
| SOLUSDT | 30m | VOL_COMPRESSION | len=14,thresh=25 | 16055 | 49.9% | 0.0055 | 1.02 | 0.0121% |

### Bollinger

| Asset | TF | Regime | Params | Signals | WinRate | Sharpe | PF | AvgRet5B |
|-------|-----|--------|--------|---------|---------|--------|----|---------|
| ICPUSDT | 4h | VOL_EXPANSION | per=50,mult=3 | 13 | 76.9% | 0.7447 | 5.28 | 3.2145% |
| ICPUSDT | 1h | TREND_UP | per=50,mult=3 | 35 | 22.9% | -0.6529 | 0.18 | -1.3018% |
| ICPUSDT | 1h | TREND_DOWN | per=50,mult=3 | 59 | 76.3% | 0.5182 | 3.67 | 1.2163% |
| ICPUSDT | 4h | DISTRIBUTION | per=50,mult=3 | 10 | 20% | -0.3433 | 0.44 | -1.4039% |
| ICPUSDT | 30m | ACCUMULATION | per=50,mult=3 | 200 | 34.5% | -0.3379 | 0.38 | -0.3434% |
| ICPUSDT | 4h | TREND_UP | per=50,mult=3 | 7 | 42.9% | -0.3324 | 0.39 | -0.5019% |
| ICPUSDT | 1h | RANGE | per=50,mult=3 | 191 | 60.7% | 0.2614 | 2.01 | 0.3348% |
| ICPUSDT | 1h | ACCUMULATION | per=50,mult=3 | 91 | 47.3% | -0.203 | 0.59 | -0.3206% |
| ICPUSDT | 30m | TREND_UP | per=50,mult=3 | 62 | 51.6% | -0.1886 | 0.6 | -0.334% |
| ICPUSDT | 1h | DISTRIBUTION | per=50,mult=3 | 7 | 57.1% | -0.1801 | 0.61 | -1.1045% |
| ICPUSDT | 30m | TREND_DOWN | per=50,mult=3 | 123 | 61% | 0.1317 | 1.42 | 0.2602% |
| ICPUSDT | 4h | RANGE | per=50,mult=3 | 53 | 47.2% | -0.1249 | 0.69 | -0.4104% |
| ICPUSDT | 4h | ACCUMULATION | per=50,mult=3 | 23 | 47.8% | -0.0865 | 0.77 | -0.2128% |
| ICPUSDT | 30m | VOL_EXPANSION | per=50,mult=3 | 58 | 51.7% | 0.0629 | 1.18 | 0.1207% |
| ICPUSDT | 4h | TREND_DOWN | per=50,mult=3 | 19 | 47.4% | -0.0572 | 0.86 | -0.1363% |
| ICPUSDT | 4h | VOL_COMPRESSION | per=50,mult=3 | 45 | 42.2% | 0.0417 | 1.11 | 0.141% |
| ICPUSDT | 30m | DISTRIBUTION | per=50,mult=3 | 50 | 44% | 0.0328 | 1.1 | 0.0848% |
| ICPUSDT | 1h | VOL_COMPRESSION | per=50,mult=3 | 177 | 47.5% | 0.0238 | 1.07 | 0.0359% |
| ICPUSDT | 30m | RANGE | per=50,mult=3 | 400 | 49% | -0.023 | 0.94 | -0.0208% |
| ICPUSDT | 1h | VOL_EXPANSION | per=50,mult=3 | 14 | 42.9% | 0.023 | 1.06 | 0.0453% |
| ICPUSDT | 30m | VOL_COMPRESSION | per=50,mult=3 | 339 | 51.3% | -0.0022 | 0.99 | -0.0023% |

---

## 4. Walk-Forward Stability

| Asset | Indicator | Params | Folds | Trades | AvgExpectancy | AvgWR | AvgSharpe | PosFolds | Stability |
|-------|-----------|--------|-------|--------|--------------|------|-----------|----------|----------|
| SOLUSDT | Stoch | k=5,d=5,ob=80,os=10 | 7 | 3189 | 0.6883 | 70.5% | 0.4464 | 100% | 0.1232 |
| SOLUSDT | OBV | ma=20 | 7 | 33350 | 0.2178 | 54.8% | 0.1336 | 100% | 0.0398 |
| ICPUSDT | OBV | ma=20 | 4 | 17339 | 0.2406 | 54.6% | 0.1316 | 100% | 0.0597 |
| ICPUSDT | Bollinger | per=50,mult=3 | 4 | 721 | -0.1776 | 45.1% | -0.1224 | 0% | 0.1181 |
| ICPUSDT | Stoch | k=14,d=9,ob=80,os=10 | 4 | 3448 | 0.1343 | 53.6% | 0.0762 | 75% | 0.1316 |
| SOLUSDT | Stoch | k=21,d=9,ob=85,os=10 | 7 | 3518 | 0.0991 | 54% | 0.0624 | 86% | 0.1222 |
| ICPUSDT | CMF | len=21,thresh=0 | 4 | 20371 | 0.0901 | 51.3% | 0.049 | 100% | 0.0435 |
| SOLUSDT | CMF | len=21,thresh=0 | 7 | 37525 | 0.0721 | 50.6% | 0.0458 | 100% | 0.0288 |
| SOLUSDT | ADX | len=14,thresh=25 | 7 | 51224 | 0.0038 | 49.9% | 0.0015 | 57% | 0.0657 |
| ICPUSDT | ADX | len=14,thresh=25 | 4 | 28625 | 0.0077 | 48.4% | 0 | 50% | 0.0627 |

---

## 5. Monte Carlo Stability

| Asset | Indicator | Params | Trades | Iterations | AvgExpectancy | AvgMaxDD | AvgPF | PFStability |
|-------|-----------|--------|--------|-----------|--------------|---------|-------|------------|
| SOLUSDT | Stoch | k=5,d=5,ob=80,os=10 | 4684 | 1000 | 0.6916 | 28.3% | 3.23 | 0.27 |
| SOLUSDT | OBV | ma=20 | 45153 | 1000 | 0.1294 | 64.3% | 1.24 | 0.1 |
| ICPUSDT | OBV | ma=20 | 28528 | 1000 | 0.0618 | 72.65% | 1.12 | 0.09 |
| SOLUSDT | Stoch | k=21,d=9,ob=85,os=10 | 5034 | 1000 | 0.0133 | 77.92% | 1.02 | 0.08 |
| SOLUSDT | CMF | len=21,thresh=0 | 51279 | 1000 | -0.0155 | 97.19% | 0.98 | 0.07 |
| ICPUSDT | Stoch | k=14,d=9,ob=80,os=10 | 5138 | 1000 | -0.0536 | 93.93% | 0.91 | 0.08 |
| ICPUSDT | CMF | len=21,thresh=0 | 34509 | 1000 | -0.0776 | 99.82% | 0.87 | 0.08 |
| SOLUSDT | ADX | len=14,thresh=25 | 68634 | 1000 | -0.1155 | 100% | 0.84 | 0.06 |
| ICPUSDT | ADX | len=14,thresh=25 | 46465 | 1000 | -0.1352 | 100% | 0.8 | 0.06 |
| ICPUSDT | Bollinger | per=50,mult=3 | 1266 | 1000 | -0.1809 | 90.05% | 0.67 | 0.07 |

---

## 6. Final Ranking

**Ranking criteria:** Statistical Confidence > Robustness > Drawdown > Expectancy > Trade Count

| Rank | Asset | Indicator | Params | Sharpe | PosFolds | AvgWR | AvgExpectancy | MaxDD | PF | Trades | Score |
|------|-------|-----------|--------|--------|----------|-------|--------------|-------|----|--------|-------|
| 1 | SOLUSDT | Stoch | k=5,d=5,ob=80,os=10 | 0.4464 | 100% | 70.5% | 0.6883 | 28.3% | 3.23 | 3189 | 0.8142 |
| 2 | SOLUSDT | OBV | ma=20 | 0.1336 | 100% | 54.8% | 0.2178 | 64.3% | 1.24 | 33350 | 0.3025 |
| 3 | ICPUSDT | OBV | ma=20 | 0.1316 | 100% | 54.6% | 0.2406 | 72.65% | 1.12 | 17339 | 0.1941 |
| 4 | SOLUSDT | CMF | len=21,thresh=0 | 0.0458 | 100% | 50.6% | 0.0721 | 97.19% | 0.98 | 37525 | 0.0869 |
| 5 | ICPUSDT | CMF | len=21,thresh=0 | 0.049 | 100% | 51.3% | 0.0901 | 99.82% | 0.87 | 20371 | 0.0608 |
| 6 | SOLUSDT | Stoch | k=21,d=9,ob=85,os=10 | 0.0624 | 86% | 54% | 0.0991 | 77.92% | 1.02 | 3518 | 0.0325 |
| 7 | ICPUSDT | Stoch | k=14,d=9,ob=80,os=10 | 0.0762 | 75% | 53.6% | 0.1343 | 93.93% | 0.91 | 3448 | 0.0305 |
| 8 | SOLUSDT | ADX | len=14,thresh=25 | 0.0015 | 57% | 49.9% | 0.0038 | 100% | 0.84 | 51224 | 0.0016 |
| 9 | ICPUSDT | ADX | len=14,thresh=25 | 0 | 50% | 48.4% | 0.0077 | 100% | 0.8 | 28625 | 0 |
| 10 | ICPUSDT | Bollinger | per=50,mult=3 | -0.1224 | 0% | 45.1% | -0.1776 | 90.05% | 0.67 | 721 | 0 |

---

## 7. Answer: Persistent Market Behaviors and Best Detectors

**Primary Finding:** SOLUSDT Stoch(k=5,d=5,ob=80,os=10) achieves Sharpe=0.4464 across 3189 trades with positive expectancy (0.6883).
**Secondary Finding:** SOLUSDT OBV(ma=20) with Sharpe=0.1336 across 33350 trades.

**Most persistent behavior:** Stochastic oscillator signals detect volatility-expansion continuation patterns most reliably.

**Regime stability:** SOLUSDT TREND_DOWN (persist=70.57%, dur=3.4 bars); SOLUSDT VOL_COMPRESSION (persist=75.26%, dur=4 bars); SOLUSDT TREND_UP (persist=83.24%, dur=6 bars); SOLUSDT VOL_EXPANSION (persist=94.59%, dur=18.5 bars); SOLUSDT ACCUMULATION (persist=84.86%, dur=6.6 bars); ICPUSDT TREND_DOWN (persist=54.7%, dur=2.2 bars); ICPUSDT VOL_COMPRESSION (persist=67.32%, dur=3.1 bars); ICPUSDT ACCUMULATION (persist=67.16%, dur=3 bars); ICPUSDT RANGE (persist=66.47%, dur=3 bars); ICPUSDT VOL_EXPANSION (persist=87.3%, dur=7.9 bars); ICPUSDT DISTRIBUTION (persist=92.41%, dur=13.2 bars)

---

*Report generated by Market Behavior Research Framework Phase 11*
*Methodology: Clustering-based regime discovery, walk-forward validation (rolling train/freeze/test), Monte Carlo simulation (1000 iterations with fee+slippage randomization)*

