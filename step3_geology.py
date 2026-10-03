"""ClearWell NC - Step 3a: bedrock geology features for every census tract.

Run from the clearwell/ project folder (after Step 1 made tracts_with_targets.gpkg):
    python step3_geology.py

Needs:
    data/processed/tracts_with_targets.gpkg   (from step1_map.py)
    data/raw/geology/  <- the unzipped USGS North Carolina geology shapefile (any file names)
Makes:
    data/processed/features_geology.csv  one row per tract:
        geo_rock_<type>  = share of the tract's area on each rock type (0-1)
        geo_unit_<unit>  = share on each of the largest individual map units (0-1)
        geo_dominant_rock = the rock type covering the most area
"""
import glob
import re
import sys

import geopandas as gpd
import pandas as pd

GEOLOGY_DIR = "data/raw/geology"
TOP_UNITS = 40          # keep the 40 largest map units as their own features
MIN_ROCK_SHARE = 0.005  # rock types covering <0.5% of NC are lumped into "other"

ROCK_COLS = ["ROCKTYPE1", "GENERALIZE", "MAJOR1", "LITH62", "ROCKTYPE", "LITHOLOGY", "LITH"]
UNIT_COLS = ["UNIT_LINK", "ORIG_LABEL", "SGMC_LABEL", "UNIT_NAME", "LABEL", "MAP_UNIT"]


def pick(columns, candidates):
    upper = {c.upper(): c for c in columns}
    return next((upper[c] for c in candidates if c in upper), None)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", str(text).lower()).strip("_")[:40] or "unknown"


def unique_names(names):
    """Make column names unique (two map units can slug to the same text)."""
    seen, out = {}, []
    for n in names:
        seen[n] = seen.get(n, 0) + 1
        out.append(n if seen[n] == 1 else f"{n}_{seen[n]}")
    return out


# 1. Find the geology polygon shapefile (USGS zips can also hold fault/line files - skip those).
shapefiles = glob.glob(f"{GEOLOGY_DIR}/**/*.shp", recursive=True)
if not shapefiles:
    sys.exit(f"No .shp files found in {GEOLOGY_DIR}/ - unzip the USGS download there first.")
polys = []
for path in shapefiles:
    g = gpd.read_file(path)
    if g.geom_type.isin(["Polygon", "MultiPolygon"]).mean() > 0.9:
        polys.append((len(g), path, g))
if not polys:
    sys.exit("Found shapefiles, but none contain polygons. Did you download the geologic map (not faults)?")
_, path, geol = max(polys, key=lambda x: x[0])
print(f"Using {path}: {len(geol)} polygons")
print(f"Columns: {list(geol.columns)}")

# 2. National file? keep North Carolina only.
state_col = pick(geol.columns, ["STATE", "ST", "STATE_ABBR"])
if state_col and geol[state_col].nunique() > 1:
    geol = geol[geol[state_col].astype(str).str.upper().isin(["NC", "NORTH CAROLINA"])]
    print(f"Filtered to North Carolina: {len(geol)} polygons")

# 3. Find the rock-type and map-unit columns. If rock type lives in a separate table, join it in.
unit_col = pick(geol.columns, UNIT_COLS)
rock_col = pick(geol.columns, ROCK_COLS)
if rock_col is None and unit_col is not None:
    for table_path in glob.glob(f"{GEOLOGY_DIR}/**/*.dbf", recursive=True) + glob.glob(f"{GEOLOGY_DIR}/**/*.csv", recursive=True):
        if table_path.replace(".dbf", ".shp") in shapefiles:
            continue  # that .dbf belongs to a shapefile, not a lookup table
        table = pd.read_csv(table_path) if table_path.endswith(".csv") else gpd.read_file(table_path)
        t_unit, t_rock = pick(table.columns, [unit_col.upper()]), pick(table.columns, ROCK_COLS)
        if t_unit and t_rock:
            lookup = table[[t_unit, t_rock]].drop_duplicates(t_unit).rename(columns={t_unit: unit_col, t_rock: "ROCK"})
            geol = geol.merge(lookup, on=unit_col, how="left")
            rock_col = "ROCK"
            print(f"Rock type joined from {table_path} ({t_rock})")
            break
if rock_col is None:
    sys.exit(f"Could not find a rock-type column. Send Claude this column list: {list(geol.columns)}")
print(f"Rock type column: {rock_col}   Map unit column: {unit_col}")

geol = geol[[c for c in [rock_col, unit_col] if c] + ["geometry"]].copy()
geol[rock_col] = geol[rock_col].fillna("unknown").astype(str).str.strip().str.lower()

# 4. Overlay tracts on geology (same coordinate system, in meters, so areas are real).
tracts = gpd.read_file("data/processed/tracts_with_targets.gpkg")[["FIPS", "geometry"]]
geol = geol.to_crs(tracts.crs)
geol["geometry"] = geol.geometry.make_valid()  # fix self-crossing polygons
geol = geol.explode(index_parts=False)           # split any mixed geometry collections
geol = geol[geol.geom_type.isin(["Polygon", "MultiPolygon"])]
print("Overlaying tracts on geology (can take 1-3 minutes)...")
pieces = gpd.overlay(tracts, geol, how="intersection", keep_geom_type=True)
pieces["area"] = pieces.geometry.area
tract_area = pieces.groupby("FIPS")["area"].transform("sum")
pieces["share"] = pieces["area"] / tract_area

# 5. Rock-type shares per tract (rare types lumped into "other").
statewide = pieces.groupby(rock_col)["area"].sum() / pieces["area"].sum()
common = set(statewide[statewide >= MIN_ROCK_SHARE].index)
pieces["rock"] = pieces[rock_col].where(pieces[rock_col].isin(common), "other")
rock = pieces.pivot_table(index="FIPS", columns="rock", values="share", aggfunc="sum", fill_value=0)
rock.columns = unique_names([f"geo_rock_{slug(c)}" for c in rock.columns])
features = rock

# 6. Shares of the largest individual map units (captures specific formations like the slate belt).
if unit_col:
    biggest = pieces.groupby(unit_col)["area"].sum().nlargest(TOP_UNITS).index
    units = pieces[pieces[unit_col].isin(biggest)].pivot_table(
        index="FIPS", columns=unit_col, values="share", aggfunc="sum", fill_value=0)
    units.columns = unique_names([f"geo_unit_{slug(c)}" for c in units.columns])
    features = features.join(units, how="left").fillna(0)

features["geo_dominant_rock"] = rock.idxmax(axis=1).str.replace("geo_rock_", "", regex=False)
features = features.reindex(tracts["FIPS"]).fillna({c: 0 for c in features.columns if c != "geo_dominant_rock"})
features.index.name = "FIPS"
features.to_csv("data/processed/features_geology.csv")
print(f"\nSaved data/processed/features_geology.csv: {len(features)} tracts x {features.shape[1]} features")
print(f"Tracts with no geology match: {features['geo_dominant_rock'].isna().sum()} (should be near 0)")

# 7. Sanity check: arsenic rate by dominant rock type. Expect metavolcanic / slate-type rocks near the top.
targets = pd.read_csv("data/processed/clearwell_targets.csv", dtype={"FIPS": str})
check = targets.merge(features[["geo_dominant_rock"]].reset_index(), on="FIPS")
summary = check.groupby("geo_dominant_rock")[["arsenic_n", "arsenic_exceed"]].sum()
summary = summary[summary["arsenic_n"] >= 200]
summary["arsenic_rate"] = summary["arsenic_exceed"] / summary["arsenic_n"]
summary = summary.sort_values("arsenic_rate", ascending=False)
summary["arsenic_rate"] = summary["arsenic_rate"].map("{:.1%}".format)
print("\nArsenic rate by dominant rock type (types with 200+ tests):")
print(summary.to_string())
