"""ClearWell NC - Step 4: the risk model.

Run from the clearwell/ project folder:
    pip install scikit-learn        (first time only)
    python step4_model.py

What it does, per contaminant (arsenic, lead, manganese, nitrate):
  1. Builds features for every tract: rock-type shares, map-unit shares, location,
     and "neighbor rates" (contamination rate in the 10 nearest tested tracts).
  2. Trains a gradient-boosted model on "k of n tests exceeded the limit" (binomial),
     so a tract with 500 tests counts more than a tract with 3.
  3. Tests it honestly, two ways (every score comes from tracts the model never trained on):
       - UNSEEN TRACT  (main score): hide 10% of tracts at a time; the model may use the tracts
         around them. This is exactly how the app is used - every NC county has test data.
       - UNSEEN COUNTY (stress test): hide whole counties; neighbors come only from other counties.
         Averaged over 5 random ways of grouping the counties, because one split can hide a whole
         hotspot (Union + Stanly + Anson) at once and swing the score a lot.
  4. Compares against the Step 2 baselines and a neighbors-only baseline.
  5. Trains a final model on everything and predicts ALL 2,195 tracts, then blends the
     prediction with each tract's own test results (more tests -> trust the data more).

Makes:
    outputs/model_scores.csv        model vs. baselines
    outputs/calibration.png         does "10% risk" really mean ~10%?
    outputs/importance.png          which feature groups matter
    data/processed/predictions.csv  the numbers the app will show
"""
import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.model_selection import KFold

CONTAMINANTS = ["arsenic", "lead", "manganese", "nitrate"]
K_NEIGHBORS = 10     # nearest tested tracts used for neighbor rates
WEIGHT_CAP = 200     # a tract counts as at most 200 tests in training, so a few huge tracts can't dominate
PRIOR_TESTS = 20     # blending: the model prediction counts like 20 extra tests
N_FOLDS = 10
COUNTY_REPEATS = 5   # stress test is averaged over this many random county groupings
SEED = 0

# ---------------------------------------------------------------- 1. load and join
targets = pd.read_csv("data/processed/clearwell_targets.csv", dtype={"FIPS": str, "county_fips": str})
geology = pd.read_csv("data/processed/features_geology.csv", dtype={"FIPS": str})
info = gpd.read_file("data/raw/tl_2010_37_tract10.shp", ignore_geometry=True)
info = pd.DataFrame({
    "FIPS": info["GEOID10"].astype(str),
    "lat": info["INTPTLAT10"].astype(float),
    "lon": info["INTPTLON10"].astype(float),
    "log_land_km2": np.log1p(info["ALAND10"].astype(float) / 1e6),
    "water_frac": info["AWATER10"].astype(float) / (info["ALAND10"].astype(float) + info["AWATER10"].astype(float)),
})
df = targets.merge(geology.drop(columns=["geo_dominant_rock"]), on="FIPS", how="left").merge(info, on="FIPS", how="left")
assert len(df) == 2195 and df["lat"].notna().all(), "Join problem - check Steps 1 and 3 outputs."
df = df.reset_index(drop=True)

GEO_ROCK = [c for c in df.columns if c.startswith("geo_rock_")]
GEO_UNIT = [c for c in df.columns if c.startswith("geo_unit_")]
LOCATION = ["lat", "lon", "log_land_km2", "water_frac"]
NEIGHBOR = [f"nbr_{c}" for c in CONTAMINANTS]
FEATURES = GEO_ROCK + GEO_UNIT + LOCATION + NEIGHBOR
df[GEO_ROCK + GEO_UNIT] = df[GEO_ROCK + GEO_UNIT].fillna(0)

county = df["county_fips"].to_numpy()
N = {c: df[f"{c}_n"].to_numpy(float) for c in CONTAMINANTS}
KX = {c: df[f"{c}_exceed"].to_numpy(float) for c in CONTAMINANTS}

# distance between every pair of tracts (km)
lat, lon = np.radians(df["lat"].to_numpy()), np.radians(df["lon"].to_numpy())
dlat, dlon = lat[:, None] - lat[None, :], lon[:, None] - lon[None, :]
a = np.sin(dlat / 2) ** 2 + np.cos(lat[:, None]) * np.cos(lat[None, :]) * np.sin(dlon / 2) ** 2
DIST = 6371 * 2 * np.arcsin(np.sqrt(a))


def neighbor_rates(query, pool, other_counties_only=False):
    """For each query tract: pooled exceedance rate of its K nearest `pool` tracts.
    A tract never counts as its own neighbor, and only `pool` (training) tracts are used,
    so hidden tracts never leak into their own features."""
    out = pd.DataFrame(index=query)
    for c in CONTAMINANTS:
        p = pool[N[c][pool] > 0]
        d = DIST[np.ix_(query, p)].copy()
        d[query[:, None] == p[None, :]] = np.inf
        if other_counties_only:
            d[county[query][:, None] == county[p][None, :]] = np.inf
        nearest = np.argpartition(d, K_NEIGHBORS, axis=1)[:, :K_NEIGHBORS]
        k_sum = KX[c][p][nearest].sum(axis=1)
        n_sum = N[c][p][nearest].sum(axis=1)
        out[f"nbr_{c}"] = k_sum / np.maximum(n_sum, 1)
    return out


def expand(X, k, n):
    """Binomial trick: each tract becomes two rows - 'exceeded' (weight k) and 'did not' (weight n-k)."""
    scale = np.minimum(n, WEIGHT_CAP) / n
    Xb = pd.concat([X, X], ignore_index=True)
    y = np.r_[np.ones(len(X)), np.zeros(len(X))]
    w = np.r_[k * scale, (n - k) * scale]
    keep = w > 0
    return Xb[keep], y[keep], w[keep]


def new_model():
    # conservative settings: small trees, strong regularization (chosen because lead/nitrate overfit otherwise)
    return HistGradientBoostingClassifier(learning_rate=0.03, max_iter=200, max_leaf_nodes=8,
                                          min_samples_leaf=40, l2_regularization=5.0, random_state=SEED)


def brier(p, k, n):
    return (k * (1 - p) ** 2 + (n - k) * p ** 2).sum() / n.sum()


# ---------------------------------------------------------------- 2. cross-validation (two tests)
def county_splits(tested, seed):
    """Randomly assign whole counties to N_FOLDS folds. Uses numpy's generator so results are the
    same on every computer and scikit-learn version."""
    counties = np.unique(county[tested])
    fold_of = dict(zip(np.random.default_rng(seed).permutation(counties), np.arange(len(counties)) % N_FOLDS))
    folds = np.array([fold_of[x] for x in county[tested]])
    for f in range(N_FOLDS):
        yield np.where(folds != f)[0], np.where(folds == f)[0]


def cross_validate(c, mode, seed=SEED):
    """Out-of-fold predictions for contaminant c. mode = 'tract' or 'county'."""
    tested = np.where(N[c] > 0)[0]
    k, n = KX[c][tested], N[c][tested]
    oof, oof_nbr = np.zeros(len(tested)), np.zeros(len(tested))
    if mode == "tract":
        splits = KFold(N_FOLDS, shuffle=True, random_state=SEED).split(tested)
    else:
        splits = county_splits(tested, seed)
    for tr, te in splits:
        tr_idx, te_idx = tested[tr], tested[te]
        X = df[GEO_ROCK + GEO_UNIT + LOCATION].copy()
        X[NEIGHBOR] = np.nan
        X.loc[tr_idx, NEIGHBOR] = neighbor_rates(tr_idx, tr_idx, mode == "county").to_numpy()
        X.loc[te_idx, NEIGHBOR] = neighbor_rates(te_idx, tr_idx, mode == "county").to_numpy()
        Xtr, ytr, wtr = expand(X.loc[tr_idx, FEATURES].reset_index(drop=True), k[tr], n[tr])
        model = new_model().fit(Xtr, ytr, sample_weight=wtr)
        oof[te] = model.predict_proba(X.loc[te_idx, FEATURES])[:, 1]
        oof_nbr[te] = X.loc[te_idx, f"nbr_{c}"].to_numpy()
    return tested, oof, oof_nbr


rows, oof_all = [], {}
print("Share of the gap closed (statewide guess = 0%, best possible = 100%):\n")
for c in CONTAMINANTS:
    tested, oof_t, nbr_t = cross_validate(c, "tract")
    county_runs = [cross_validate(c, "county", seed)[1] for seed in range(COUNTY_REPEATS)]
    oof_all[c] = pd.Series(oof_t, index=tested)
    k, n = KX[c][tested], N[c][tested]

    state = k.sum() / n.sum()
    c_k = pd.Series(k).groupby(county[tested]).transform("sum").to_numpy()
    c_n = pd.Series(n).groupby(county[tested]).transform("sum").to_numpy()
    loo = np.where(c_n - n > 0, (c_k - k) / np.maximum(c_n - n, 1), state)  # county avg without the tract
    b_state, b_ceil = brier(np.full(len(k), state), k, n), brier(k / n, k, n)
    gap = lambda p: (b_state - brier(p, k, n)) / (b_state - b_ceil)
    r = {"contaminant": c, "county_average": gap(loo), "neighbors_only": gap(nbr_t),
         "MODEL_unseen_tract": gap(oof_t),
         "model_unseen_county": float(np.mean([gap(o) for o in county_runs])),
         "unseen_county_min": min(gap(o) for o in county_runs),
         "unseen_county_max": max(gap(o) for o in county_runs)}
    rows.append(r)
    print(f"{c:10s} county avg {r['county_average']:6.1%} | neighbors only {r['neighbors_only']:6.1%} | "
          f"MODEL {r['MODEL_unseen_tract']:6.1%} | (stress test, unseen county {r['model_unseen_county']:6.1%}, "
          f"range {r['unseen_county_min']:.1%}-{r['unseen_county_max']:.1%})")

scores = pd.DataFrame(rows)
scores.to_csv("outputs/model_scores.csv", index=False, float_format="%.4f")
print("\nSaved outputs/model_scores.csv. The MODEL column is the main result; beat county avg = success.")

# ---------------------------------------------------------------- 3. calibration chart
fig, axes = plt.subplots(1, 4, figsize=(16, 4.2))
for ax, c in zip(axes, CONTAMINANTS):
    idx = oof_all[c].index.to_numpy()
    p, k, n = oof_all[c].to_numpy(), KX[c][idx], N[c][idx]
    order = np.argsort(p)
    groups = np.array_split(order, 10)  # 10 groups of tracts, low to high predicted risk
    pred = [np.average(p[g], weights=n[g]) for g in groups]
    obs = [k[g].sum() / n[g].sum() for g in groups]
    top = max(max(pred), max(obs)) * 1.1
    ax.plot([0, top], [0, top], color="#999999", linewidth=1, linestyle="--", label="perfect")
    ax.plot(pred, obs, marker="o", color="#b2182b", linewidth=2, markersize=8, label="model")
    ax.set_title(c.capitalize(), loc="left")
    ax.set_xlabel("Predicted share above limit")
    ax.set_xlim(0, top); ax.set_ylim(0, top)
    fmt = "{:.1%}" if top < 0.05 else "{:.0%}"  # one decimal for small percentages (nitrate)
    ax.xaxis.set_major_formatter(plt.FuncFormatter(lambda v, _, f=fmt: f.format(v)))
    ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _, f=fmt: f.format(v)))
    ax.spines[["top", "right"]].set_visible(False)
axes[0].set_ylabel("Actual share above limit")
axes[0].legend(frameon=False, loc="upper left")
fig.suptitle("Calibration on tracts the model never saw (points on the dashed line = honest probabilities)",
             x=0.01, ha="left", fontsize=12)
fig.tight_layout()
fig.savefig("outputs/calibration.png", dpi=200, bbox_inches="tight")
plt.close(fig)

# ---------------------------------------------------------------- 4. final models + predictions for every tract
everything = np.arange(len(df))
out = df[["FIPS", "county_fips"]].copy()
importance = {}
GROUPS = {"Rock types": GEO_ROCK, "Specific map units": GEO_UNIT, "Location": LOCATION, "Neighbor rates": NEIGHBOR}
rng = np.random.default_rng(SEED)
for c in CONTAMINANTS:
    tested = np.where(N[c] > 0)[0]
    X = df[GEO_ROCK + GEO_UNIT + LOCATION].copy()
    X[NEIGHBOR] = neighbor_rates(everything, tested).to_numpy()  # same rule as the unseen-tract test
    k, n = KX[c][tested], N[c][tested]
    Xtr, ytr, wtr = expand(X.loc[tested, FEATURES].reset_index(drop=True), k, n)
    model = new_model().fit(Xtr, ytr, sample_weight=wtr)
    p_all = model.predict_proba(X[FEATURES])[:, 1]

    kk, nn = KX[c], N[c]
    out[f"{c}_model"] = p_all.round(4)
    out[f"{c}_tests"] = nn.astype(int)
    out[f"{c}_observed"] = np.where(nn > 0, kk / np.maximum(nn, 1), np.nan).round(4)
    out[f"{c}_estimate"] = ((kk + PRIOR_TESTS * p_all) / (nn + PRIOR_TESTS)).round(4)  # what the app shows

    # grouped permutation importance: how much worse does the model get if a group is scrambled?
    base = brier(p_all[tested], k, n)
    importance[c] = {}
    for g, cols in GROUPS.items():
        Xp = X.loc[tested, FEATURES].copy()
        Xp[cols] = Xp[cols].to_numpy()[rng.permutation(len(Xp))]
        importance[c][g] = brier(model.predict_proba(Xp)[:, 1], k, n) - base

out.to_csv("data/processed/predictions.csv", index=False)
print(f"\nSaved data/processed/predictions.csv: {len(out)} tracts")

# ---------------------------------------------------------------- 5. importance chart
imp = pd.DataFrame(importance)
imp = imp.clip(lower=0)
imp = imp / imp.sum()  # share of total importance per contaminant
fig, axes = plt.subplots(1, 4, figsize=(16, 3.2), sharey=True)
for ax, c in zip(axes, CONTAMINANTS):
    vals = imp[c].reindex(list(GROUPS))[::-1]
    ax.barh(vals.index, vals.values, color="#b2182b", height=0.6)
    for y, v in enumerate(vals.values):
        ax.text(v + 0.01, y, f"{v:.0%}", va="center", fontsize=9, color="#333333")
    ax.set_title(c.capitalize(), loc="left")
    ax.set_xlim(0, 1.15)
    ax.set_xticks([])
    ax.spines[["top", "right", "bottom"]].set_visible(False)
fig.suptitle("What drives each prediction (share of importance)", x=0.01, ha="left", fontsize=12)
fig.tight_layout()
fig.savefig("outputs/importance.png", dpi=200, bbox_inches="tight")
plt.close(fig)
print("Saved outputs/calibration.png and outputs/importance.png")
print("\nImportance by group:\n" + imp.map(lambda v: f"{v:.0%}").to_string())
