"""ClearWell NC - Step 5: turn an address into a well-water risk report.

Run from the clearwell/ project folder:
    python step5_lookup.py "3200 Old Monroe Rd, Monroe, NC"
    python step5_lookup.py --fips 37179020403          (skip geocoding - look up a tract directly)
    python step5_lookup.py --latlon 35.02 -80.55       (skip geocoding - use coordinates)

Needs:
    data/processed/predictions.csv       (from step4_model.py)
    data/processed/clearwell_targets.csv (from build_targets.py)
    data/raw/tl_2010_37_tract10.shp      (2010 tract shapes, from Step 1)
Makes:
    outputs/report_<tract>.json  - the same report as machine-readable data (the app will use this)

The address is sent to the free U.S. Census Geocoder and is never saved.
"""
import argparse
import json
import sys
import urllib.parse
import urllib.request

import pandas as pd

# NC county FIPS codes are odd numbers assigned alphabetically (Alamance = 001 ... Yancey = 199).
COUNTIES = [
    "Alamance", "Alexander", "Alleghany", "Anson", "Ashe", "Avery", "Beaufort", "Bertie", "Bladen",
    "Brunswick", "Buncombe", "Burke", "Cabarrus", "Caldwell", "Camden", "Carteret", "Caswell",
    "Catawba", "Chatham", "Cherokee", "Chowan", "Clay", "Cleveland", "Columbus", "Craven", "Cumberland",
    "Currituck", "Dare", "Davidson", "Davie", "Duplin", "Durham", "Edgecombe", "Forsyth", "Franklin",
    "Gaston", "Gates", "Graham", "Granville", "Greene", "Guilford", "Halifax", "Harnett", "Haywood",
    "Henderson", "Hertford", "Hoke", "Hyde", "Iredell", "Jackson", "Johnston", "Jones", "Lee", "Lenoir",
    "Lincoln", "Macon", "Madison", "Martin", "McDowell", "Mecklenburg", "Mitchell", "Montgomery",
    "Moore", "Nash", "New Hanover", "Northampton", "Onslow", "Orange", "Pamlico", "Pasquotank",
    "Pender", "Perquimans", "Person", "Pitt", "Polk", "Randolph", "Richmond", "Robeson", "Rockingham",
    "Rowan", "Rutherford", "Sampson", "Scotland", "Stanly", "Stokes", "Surry", "Swain", "Transylvania",
    "Tyrrell", "Union", "Vance", "Wake", "Warren", "Washington", "Watauga", "Wayne", "Wilkes", "Wilson",
    "Yadkin", "Yancey",
]
COUNTY_NAME = {f"{2 * i + 1:03d}": name for i, name in enumerate(COUNTIES)}

CONTAMINANTS = {
    "arsenic": {
        "name": "Arsenic", "limit": "10 ppb (EPA limit)",
        "why": "Arsenic comes from certain bedrock. It has no taste or smell; long-term exposure raises cancer risk.",
        "fix": "Reverse osmosis certified to NSF/ANSI 58 for arsenic (under-sink is usually enough for drinking and cooking).",
    },
    "manganese": {
        "name": "Manganese", "limit": "50 ppb (NC standard)",
        "why": "Manganese comes from rock and soil. It can stain fixtures black; high levels are a concern for infants.",
        "fix": "Oxidation/filtration (greensand) or a water softener rated for manganese; reverse osmosis for drinking water.",
    },
    "nitrate": {
        "name": "Nitrate", "limit": "10 mg/L (EPA limit)",
        "why": "Nitrate comes from fertilizer, manure and septic systems. It is most dangerous for babies under 6 months.",
        "fix": "Reverse osmosis certified to NSF/ANSI 58 for nitrate. Never boil water to remove nitrate - it concentrates it.",
    },
    "lead": {
        "name": "Lead", "limit": "15 ppb (EPA action level)",
        "why": "Lead in well water usually comes from pipes, solder and well parts, not the rock, so it varies house to house.",
        "fix": "Point-of-use filter certified to NSF/ANSI 53 for lead; replace old brass fittings or lead solder where possible.",
    },
}


# ---------------------------------------------------------------- location -> tract
def geocode(address):
    """Address -> (lat, lon, matched address) using the U.S. Census Geocoder (free, no key)."""
    url = "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?" + urllib.parse.urlencode(
        {"address": address, "benchmark": "Public_AR_Current", "format": "json"})
    with urllib.request.urlopen(url, timeout=20) as r:
        matches = json.load(r)["result"]["addressMatches"]
    if not matches:
        sys.exit("Address not found. Try the full form: '123 Main St, Town, NC 27513'.")
    m = matches[0]
    return m["coordinates"]["y"], m["coordinates"]["x"], m["matchedAddress"]


def tract_for_point(lat, lon):
    """(lat, lon) -> 11-digit 2010 tract FIPS, using the Step 1 shapefile."""
    import geopandas as gpd
    from shapely.geometry import Point
    tracts = gpd.read_file("data/raw/tl_2010_37_tract10.shp")[["GEOID10", "geometry"]]
    point = gpd.GeoDataFrame(geometry=[Point(lon, lat)], crs="EPSG:4326").to_crs(tracts.crs)
    hit = gpd.sjoin(point, tracts, predicate="within")
    if hit.empty:
        sys.exit("That location is not inside North Carolina.")
    return str(hit.iloc[0]["GEOID10"])


# ---------------------------------------------------------------- tract -> report
def one_in(rate):
    if rate < 0.005:
        return "fewer than 1 in 200"
    return f"about 1 in {max(2, round(1 / rate))}"


def confidence(tests):
    if tests >= 30:
        return "high", f"based on {tests} tested wells in your area plus the model"
    if tests >= 10:
        return "medium", f"based on {tests} tested wells in your area plus the model"
    if tests >= 1:
        return "low", f"only {tests} tested well(s) in your area - mostly the model's estimate"
    return "low", "no tested wells in your area - this is the model's estimate from geology and nearby areas"


def risk_for_tract(fips):
    preds = pd.read_csv("data/processed/predictions.csv", dtype={"FIPS": str, "county_fips": str})
    targets = pd.read_csv("data/processed/clearwell_targets.csv", dtype={"FIPS": str})
    row = preds.loc[preds["FIPS"] == fips]
    if row.empty:
        sys.exit(f"Tract {fips} not found - is it a 2010 North Carolina tract ID?")
    row = row.iloc[0]
    county = COUNTY_NAME.get(row["county_fips"], "your")

    results = []
    for key, info in CONTAMINANTS.items():
        est = float(row[f"{key}_estimate"])
        tests = int(row[f"{key}_tests"])
        state = targets[f"{key}_exceed"].sum() / targets[f"{key}_n"].sum()
        ratio = est / state
        if key == "lead":
            level = "test regardless"  # lead depends on plumbing, not location (model is weak here)
        elif ratio >= 3:
            level = "high"
        elif ratio >= 1.5:
            level = "elevated"
        elif ratio >= 0.75:
            level = "typical"
        else:
            level = "lower than typical"
        conf, conf_text = confidence(tests)
        results.append({
            "contaminant": info["name"], "key": key, "level": level, "ratio_to_state": round(ratio, 2),
            "estimate": round(est, 4), "statewide": round(state, 4), "tests_in_area": tests,
            "confidence": conf, "confidence_note": conf_text,
            "sentence": f"Estimated {one_in(est)} wells in your area are above {info['limit']} "
                        f"(statewide: {one_in(state)}).",
            "observed": (f"{int(row[f'{key}_observed'] * tests + 0.5)} of {tests} tested wells in your census tract "
                         f"were above the limit." if tests > 0 else "No wells in your census tract have been tested."),
            "why": info["why"], "fix_if_high": info["fix"],
        })

    # test plan: highest relative risk first (lead and bacteria always included)
    order = {"high": 0, "elevated": 1, "typical": 2, "test regardless": 3, "lower than typical": 4}
    results.sort(key=lambda r: (order[r["level"]], -r["ratio_to_state"]))
    plan = ["Bacteria (total coliform / E. coli) - every year and after any flooding, for every well."]
    for r in results:
        if r["level"] in ("high", "elevated"):
            plan.append(f"{r['contaminant']} - priority for your area ({r['level']} risk).")
        elif r["level"] == "test regardless":
            plan.append(f"{r['contaminant']} - test at least once; it depends on your home's plumbing.")
        else:
            plan.append(f"{r['contaminant']} - include in a standard metals/nitrate panel every 2 years.")
    plan.append(f"How: contact {county} County Environmental Health to order a test through the NC State "
                f"Laboratory of Public Health, or use a state-certified private lab.")

    return {"tract": fips, "county": county, "results": results, "test_plan": plan,
            "disclaimer": "This is an estimate for your area, not your well. Only a lab test tells you "
                          "what is in your water.",
            "data_source": "NCWELL database (Eaves et al. 2021, UNC Superfund Research Program), 1998-2019"}


def print_report(report, where=""):
    print("\n" + "=" * 72)
    print(f"ClearWell NC report{' for ' + where if where else ''}")
    print(f"{report['county']} County  |  census tract {report['tract']}")
    print("=" * 72)
    for r in report["results"]:
        print(f"\n{r['contaminant'].upper():10s} {r['level'].upper()}   (confidence: {r['confidence']})")
        print(f"  {r['sentence']}")
        print(f"  {r['observed']} Confidence note: {r['confidence_note']}.")
        print(f"  Why it matters: {r['why']}")
        if r["level"] in ("high", "elevated", "test regardless"):
            print(f"  If your test is high: {r['fix_if_high']}")
    print("\nYOUR TEST PLAN")
    for i, step in enumerate(report["test_plan"], 1):
        print(f"  {i}. {step}")
    print(f"\n{report['disclaimer']}\nData: {report['data_source']}\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="ClearWell NC well-water risk lookup")
    ap.add_argument("address", nargs="?", help='e.g. "123 Main St, Monroe, NC 28112"')
    ap.add_argument("--fips", help="11-digit 2010 census tract ID")
    ap.add_argument("--latlon", nargs=2, type=float, metavar=("LAT", "LON"))
    args = ap.parse_args()

    where = ""
    if args.fips:
        fips = args.fips
    elif args.latlon:
        fips = tract_for_point(*args.latlon)
    elif args.address:
        lat, lon, where = geocode(args.address)
        fips = tract_for_point(lat, lon)
    else:
        ap.error("give an address, --fips, or --latlon")

    report = risk_for_tract(fips)
    print_report(report, where)
    with open(f"outputs/report_{fips}.json", "w") as f:
        json.dump(report, f, indent=2)
    print(f"Saved outputs/report_{fips}.json")
