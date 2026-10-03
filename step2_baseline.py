"""ClearWell NC - Step 2: baseline scores the ML model has to beat.

Run from the clearwell/ project folder:
    python step2_baseline.py

For every tract we "predict" its exceedance rate two simple ways, then score them:
  A. Statewide  - every tract gets the North Carolina average.
  B. County     - every tract gets its county's average, computed WITHOUT that tract
                  (so a tract never helps predict itself).
  Ceiling       - every tract gets its OWN true rate. No area-level model can beat this,
                  because wells inside one tract still differ from each other.

Score = Brier score per test: the average of (predicted probability - actual outcome)^2
over every individual well test. Lower is better. "gap_closed" = how much of the distance
from the statewide guess to the ceiling a method covers (0% = no better than statewide,
100% = as good as an area-level prediction can possibly be).

Output: outputs/baseline_scores.csv
"""
import pandas as pd

CONTAMINANTS = ["arsenic", "lead", "manganese", "nitrate"]

df = pd.read_csv("data/processed/clearwell_targets.csv", dtype={"FIPS": str, "county_fips": str})


def brier_per_test(p, k, n):
    """Brier score over all tests. A tract with k exceedances out of n tests contributes
    k tests scored (1-p)^2 and (n-k) tests scored p^2."""
    total = (k * (1 - p) ** 2 + (n - k) * p ** 2).sum()
    return total / n.sum()


rows = []
for c in CONTAMINANTS:
    n, k = f"{c}_n", f"{c}_exceed"
    d = df[df[n] > 0].copy()  # only tracts that actually have tests

    # A. statewide rate
    state_rate = d[k].sum() / d[n].sum()
    d["pred_state"] = state_rate

    # B. county rate, leaving the tract itself out
    county_k = d.groupby("county_fips")[k].transform("sum")
    county_n = d.groupby("county_fips")[n].transform("sum")
    loo_n = county_n - d[n]
    d["pred_county"] = ((county_k - d[k]) / loo_n).where(loo_n > 0, state_rate)  # lone tract -> state rate

    bs_state = brier_per_test(d["pred_state"], d[k], d[n])
    bs_county = brier_per_test(d["pred_county"], d[k], d[n])
    bs_ceiling = brier_per_test(d[k] / d[n], d[k], d[n])
    rows.append({
        "contaminant": c,
        "tracts": len(d),
        "tests": int(d[n].sum()),
        "statewide_rate": round(state_rate, 4),
        "brier_statewide": round(bs_state, 5),
        "brier_county": round(bs_county, 5),
        "brier_ceiling": round(bs_ceiling, 5),
        "county_gap_closed": f"{(bs_state - bs_county) / (bs_state - bs_ceiling):.1%}",
    })

out = pd.DataFrame(rows)
out.to_csv("outputs/baseline_scores.csv", index=False)
print(out.to_string(index=False))
print("\nSaved outputs/baseline_scores.csv")
print("Goal for Step 4: a model whose gap_closed is higher than the county baseline's.")
