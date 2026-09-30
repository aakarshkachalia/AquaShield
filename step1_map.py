"""ClearWell NC - Step 1: put the NCWELL tract data on a map.

Run from the clearwell/ project folder:
    python step1_map.py

Needs:
    data/raw/tl_2010_37_tract10.shp     (2010 NC census tracts, unzipped)
    data/processed/clearwell_targets.csv (from build_targets.py)
Makes:
    data/processed/tracts_with_targets.gpkg  (map + data in one file, used in later steps)
    outputs/arsenic_map.png, lead_map.png, manganese_map.png, nitrate_map.png
"""
import geopandas as gpd
import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.colors import BoundaryNorm
from matplotlib.patches import Patch

MIN_TESTS = 10  # tracts with fewer tests are drawn gray ("not enough data")

# 1. Load the tract shapes. GEOID10 is the 11-digit tract ID, e.g. "37179020403".
tracts = gpd.read_file("data/raw/tl_2010_37_tract10.shp")
tracts = tracts[["GEOID10", "COUNTYFP10", "geometry"]].rename(columns={"GEOID10": "FIPS"})

# 2. Load the targets. Read FIPS as TEXT so leading zeros and the join key match.
targets = pd.read_csv("data/processed/clearwell_targets.csv", dtype={"FIPS": str, "county_fips": str})

# 3. Join shapes to data on FIPS.
gdf = tracts.merge(targets, on="FIPS", how="left")

# 4. Sanity checks - if any of these fail, the join is wrong. Stop and fix before mapping.
print(f"Shapefile tracts: {len(tracts)}   Data tracts: {len(targets)}   Joined: {len(gdf)}")
unmatched = gdf["arsenic_n"].isna().sum()
print(f"Tracts in shapefile with no data row: {unmatched}  (should be 0)")
assert len(tracts) == 2195, "Expected 2,195 NC tracts - are you using the 2010 file, not 2020?"
assert unmatched == 0, "Join failed - check that FIPS is read as text on both sides."

# 5. Save the joined file for later steps (features, model, app).
gdf = gdf.to_crs(epsg=32119)  # NC State Plane (meters) - correct shapes and areas for NC
gdf.to_file("data/processed/tracts_with_targets.gpkg", driver="GPKG")

# 6. Draw one map per contaminant.
BINS = [0, 0.0001, 0.02, 0.05, 0.10, 0.20, 1.0001]
LABELS = ["0%", "0-2%", "2-5%", "5-10%", "10-20%", "20%+"]
COUNTY_NAMES = {"179": "Union", "167": "Stanly", "007": "Anson", "123": "Montgomery", "003": "Alexander",
                "093": "Hoke", "153": "Richmond", "051": "Cumberland", "163": "Sampson", "145": "Person",
                "195": "Wilson", "005": "Alleghany", "183": "Wake", "119": "Mecklenburg"}
CONTAMINANTS = {
    "arsenic": "Arsenic: share of tested wells above 10 ppb (EPA limit)",
    "lead": "Lead: share of tested wells above 15 ppb (EPA action level)",
    "manganese": "Manganese: share of tested wells above 50 ppb (NC standard)",
    "nitrate": "Nitrate: share of tested wells above 10 mg/L (EPA limit)",
}

cmap = plt.get_cmap("Reds", len(BINS) - 1)  # one hue, light -> dark = low -> high
norm = BoundaryNorm(BINS, cmap.N)
counties = gdf.dissolve(by="COUNTYFP10")  # county outlines drawn on top

for key, title in CONTAMINANTS.items():
    enough = gdf[f"{key}_n"] >= MIN_TESTS
    fig, ax = plt.subplots(figsize=(14, 6.5))
    gdf[~enough].plot(ax=ax, color="#d9d9d9", edgecolor="white", linewidth=0.1)
    gdf[enough].plot(ax=ax, column=f"{key}_rate", cmap=cmap, norm=norm, edgecolor="white", linewidth=0.1)
    counties.boundary.plot(ax=ax, color="#555555", linewidth=0.3)

    handles = [Patch(facecolor=cmap(i), label=LABELS[i]) for i in range(len(LABELS))]
    handles.append(Patch(facecolor="#d9d9d9", label=f"Fewer than {MIN_TESTS} tests"))
    ax.legend(handles=handles, loc="lower left", frameon=False, title="Wells above limit")
    ax.set_title(title, loc="left", fontsize=13)
    ax.text(0, -0.02, "Data: NCWELL database (Eaves et al. 2021, UNC Superfund Research Program), 1998-2019",
            transform=ax.transAxes, fontsize=8, color="#666666", va="top")
    ax.set_axis_off()
    fig.savefig(f"outputs/{key}_map.png", dpi=200, bbox_inches="tight")
    plt.close(fig)

    # Where are the hotspots? Test-weighted rate by county, top 5 with 100+ tests.
    by_county = gdf.groupby("COUNTYFP10")[[f"{key}_n", f"{key}_exceed"]].sum()
    by_county = by_county[by_county[f"{key}_n"] >= 100]
    by_county["rate"] = by_county[f"{key}_exceed"] / by_county[f"{key}_n"]
    top = by_county.sort_values("rate", ascending=False).head(5)
    print(f"\n{key.upper()} - top counties (county FIPS: rate, tests):")
    for fips, row in top.iterrows():
        print(f"  {fips} {COUNTY_NAMES.get(fips, ''):12s} {row['rate']:.1%}  ({int(row[f'{key}_n'])} tests)")

print("\nDone. Maps saved in outputs/. Arsenic should show a hotspot in Union (179) and Stanly (167).")
