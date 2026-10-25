"""AquaShield - Step 6a: package the model's results for the website.

Run from the project folder (after step4_model.py):
    python step6_export.py

Makes (everything the website needs - no server or Python required after this):
    app/data/tracts.geojson  simplified tract shapes + each tract's estimates and test counts
    app/data/meta.json       statewide rates, model scores, data source
    app/img/*.png            your map, calibration and importance charts for "How it works"
"""
import json
import os
import shutil
from datetime import date

import geopandas as gpd
import pandas as pd
from shapely.geometry import mapping

CONTAMINANTS = ["arsenic", "manganese", "nitrate", "lead"]
SIMPLIFY_METERS = 60  # smooth tract outlines to keep the file small; 60 m is invisible at street zoom

os.makedirs("app/data", exist_ok=True)
os.makedirs("app/img", exist_ok=True)

preds = pd.read_csv("data/processed/predictions.csv", dtype={"FIPS": str, "county_fips": str})
targets = pd.read_csv("data/processed/aquashield_targets.csv", dtype={"FIPS": str})
tracts = gpd.read_file("data/raw/tl_2010_37_tract10.shp")[["GEOID10", "geometry"]]
tracts = tracts.rename(columns={"GEOID10": "FIPS"}).merge(preds, on="FIPS").merge(
    targets[["FIPS"] + [f"{c}_exceed" for c in CONTAMINANTS]], on="FIPS")
assert len(tracts) == 2195, "Join problem - rerun steps 1-4."

# simplify in meters (NC State Plane), then back to longitude/latitude for the web map
tracts["geometry"] = tracts.to_crs(epsg=32119).geometry.simplify(SIMPLIFY_METERS, preserve_topology=True)
tracts = tracts.set_geometry("geometry").set_crs(epsg=32119, allow_override=True).to_crs(epsg=4326)


def rounded(coords):
    """Round coordinates to 5 decimals (~1 m) to shrink the file."""
    if isinstance(coords[0], (float, int)):
        return [round(coords[0], 5), round(coords[1], 5)]
    return [rounded(c) for c in coords]


features = []
for _, t in tracts.iterrows():
    geom = mapping(t.geometry)
    props = {"fips": t["FIPS"], "county": t["county_fips"]}
    for c in CONTAMINANTS:
        # [blended estimate, tests in tract, tests above the limit]
        props[c] = [round(float(t[f"{c}_estimate"]), 4), int(t[f"{c}_tests"]), int(t[f"{c}_exceed"])]
    features.append({"type": "Feature", "properties": props,
                     "geometry": {"type": geom["type"], "coordinates": rounded(geom["coordinates"])}})

with open("app/data/tracts.geojson", "w") as f:
    json.dump({"type": "FeatureCollection", "features": features}, f, separators=(",", ":"))

meta = {
    "generated": date.today().isoformat(),
    "statewide": {c: round(targets[f"{c}_exceed"].sum() / targets[f"{c}_n"].sum(), 4) for c in CONTAMINANTS},
    "data_source": "NCWELL database (Eaves et al. 2021, UNC Superfund Research Program), 1998-2019",
}
if os.path.exists("outputs/model_scores.csv"):
    meta["model_scores"] = pd.read_csv("outputs/model_scores.csv").round(4).to_dict(orient="records")
with open("app/data/meta.json", "w") as f:
    json.dump(meta, f, indent=2)

for name in ["arsenic_map.png", "calibration.png", "importance.png"]:
    if os.path.exists(f"outputs/{name}"):
        shutil.copy(f"outputs/{name}", f"app/img/{name}")

size_mb = os.path.getsize("app/data/tracts.geojson") / 1e6
print(f"Saved app/data/tracts.geojson ({size_mb:.1f} MB, {len(features)} tracts), app/data/meta.json, app/img/")
print("Next: cd app && python -m http.server 8000   then open http://localhost:8000")
