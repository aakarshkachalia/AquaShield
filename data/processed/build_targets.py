"""ClearWell NC - build model-ready targets from NCWELL tract-level data.

Input : NCwelldata_distributions_tract_level.csv  (UNC Dataverse, Eaves et al. 2021)
Output: clearwell_targets.csv  (one row per 2010 census tract)

For each contaminant we keep COUNTS (tests, exceedances) rather than percentages,
so the model can weight tracts by how many tests back them up.
"""
import numpy as np
import pandas as pd

SRC = "NCwelldata_distributions_tract_level.csv"

# contaminant -> (column suffix to use, limit in ppb, label for the app)
TARGETS = {
    "Arsenic":   ("EPA",  10,     "EPA MCL 10 ppb"),
    "Lead":      ("EPA",  15,     "EPA action level 15 ppb"),
    "Manganese": ("NCGW", 50,     "NC groundwater std 50 ppb (tract file lacks the 300 ppb health limit)"),
    "Nitrate":   ("EPA",  10000,  "EPA MCL 10 mg/L"),
    "Iron":      ("NCGW", 300,    "NC groundwater std 300 ppb (staining/taste, not health)"),
}

df = pd.read_csv(SRC).replace(-99, np.nan)
out = pd.DataFrame({"FIPS": df["FIPS"].astype("int64").astype(str).str.zfill(11)})
out["county_fips"] = out["FIPS"].str[2:5]

for metal, (std, _, _) in TARGETS.items():
    n = df[f"{metal}.Number_non_missing"].fillna(0).astype(int)
    k = df[f"{metal}.Number_abovelimit_{std}"].fillna(0).astype(int)
    key = metal.lower()
    out[f"{key}_n"] = n
    out[f"{key}_exceed"] = k
    out[f"{key}_rate"] = np.where(n > 0, k / n.replace(0, np.nan), np.nan)
    out[f"{key}_median_ppb"] = df[f"{metal}.Med"]

# Confidence tier for the app: how many arsenic tests back this tract up
n_as = out["arsenic_n"]
out["data_confidence"] = np.select([n_as >= 30, n_as >= 10, n_as >= 1], ["high", "medium", "low"], "none")

out.to_csv("clearwell_targets.csv", index=False)

print(f"Wrote clearwell_targets.csv: {len(out)} tracts")
print(out["data_confidence"].value_counts().to_string())
for metal, (_, _, label) in TARGETS.items():
    key = metal.lower()
    print(f"{metal:10s} tests={out[key+'_n'].sum():7d}  statewide exceed rate={out[key+'_exceed'].sum()/out[key+'_n'].sum():.2%}  ({label})")
