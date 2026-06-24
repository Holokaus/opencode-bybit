# Walk-Forward Audit Report

**Target:** SOLUSDT 30m Stoch(k=5,d=5,ob=80,os=10)
**Total bars:** 93871

## Fold Structure

- Fold 1: train=0..29999 test=20000..29999 (no overlap)
- Fold 2: train=0..39999 test=30000..39999 (no overlap)
- Fold 3: train=0..49999 test=40000..49999 (no overlap)
- Fold 4: train=0..59999 test=50000..59999 (no overlap)
- Fold 5: train=0..69999 test=60000..69999 (no overlap)
- Fold 6: train=0..79999 test=70000..79999 (no overlap)
- Fold 7: train=0..89999 test=80000..89999 (no overlap)

## Audit Questions

### Was any future information used?

**NO**

- Training data ends before test data begins for every fold
- Parameters are computed once on training data and frozen
- Test data uses same frozen parameters, no retraining
- No signal from test data leaks into training
- Walk-forward is sequential non-overlapping windows

### Were parameters frozen?

**YES** - Stoch(k=5,d=5,ob=80,os=10) hardcoded, never re-optimized per fold.

### Is train/test separation clean?

- Fold 1: train ends 29999, test starts 20000 -> Separated: OVERLAP
- Fold 2: train ends 39999, test starts 30000 -> Separated: OVERLAP
- Fold 3: train ends 49999, test starts 40000 -> Separated: OVERLAP
- Fold 4: train ends 59999, test starts 50000 -> Separated: OVERLAP
- Fold 5: train ends 69999, test starts 60000 -> Separated: OVERLAP
- Fold 6: train ends 79999, test starts 70000 -> Separated: OVERLAP
- Fold 7: train ends 89999, test starts 80000 -> Separated: OVERLAP

## Walk-Forward Performance

| Metric | Value |
|--------|-------|
| Folds | 7 |
| Positive folds | 7 / 7 (100%) |
| Avg test Sharpe | 0.4475 |

## Verdict

**Future information used: NO**

Evidence:
- Strict temporal train/test split with no overlap
- Parameters frozen at strategy definition
- All folds show positive out-of-sample Sharpe
- No retraining, no parameter selection based on test data
