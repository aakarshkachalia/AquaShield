#!/usr/bin/env python3
"""
Builds ClearWellNC/ClearWellNC/nc_water_systems.geojson from EPA's Community Water System Service Area
Boundaries (https://www.epa.gov/ground-water-and-drinking-water/community-water-system-service-area-boundaries).

Source service: EPA Water_System_Boundaries FeatureServer (layer 0, "Final").
Keeps only North Carolina systems (PWSID starts with "NC") and four fields:
  pwsid, name, population, sourced (true = "System Sourced" boundary, false = "Modeled").
Polygons are simplified on the server (maxAllowableOffset, in degrees) and coordinates rounded.

Run from the repo root:
    python3 DataPipeline/fetch_nc_water_systems.py            # default ~55 m simplification
    python3 DataPipeline/fetch_nc_water_systems.py 0.001      # coarser, smaller file
Writes the GeoJSON and nc_water_systems_meta.json next to it. Uses only the Python standard library.
"""
import json, sys, time, urllib.parse, urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

SERVICE = "https://services.arcgis.com/cJ9YHowT8TU7DUyn/arcgis/rest/services/Water_System_Boundaries/FeatureServer/0"
PAGE = 100
OFFSET = float(sys.argv[1]) if len(sys.argv) > 1 else 0.0005
OUT_DIR = Path(__file__).resolve().parent.parent / "ClearWellNC" / "ClearWellNC"


def get(url, params):
    data = urllib.parse.urlencode(params).encode()
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=120) as r:
                return json.load(r)
        except Exception as e:  # retry flaky pages
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def rounded(coords, digits=5):
    if isinstance(coords[0], (int, float)):
        return [round(coords[0], digits), round(coords[1], digits)]
    return [rounded(c, digits) for c in coords]


def main():
    info = get(SERVICE, {"f": "json"})
    edited = info.get("editingInfo", {}).get("lastEditDate")
    where = "PWSID LIKE 'NC%'"
    ids = get(SERVICE + "/query", {"where": where, "returnIdsOnly": "true", "f": "json"})["objectIds"]
    ids.sort()
    features = []
    for i in range(0, len(ids), PAGE):
        page = get(SERVICE + "/query", {
            "objectIds": ",".join(map(str, ids[i:i + PAGE])),
            "outFields": "PWSID,PWS_Name,Population_Served_Count,Symbology_Field",
            "outSR": "4326", "maxAllowableOffset": str(OFFSET), "geometryPrecision": "5",
            "f": "geojson",
        })
        for f in page.get("features", []):
            p = f.get("properties", {})
            g = f.get("geometry")
            if not g or not g.get("coordinates"):
                continue
            features.append({
                "type": "Feature",
                "properties": {
                    "pwsid": p.get("PWSID"),
                    "name": (p.get("PWS_Name") or "").strip(),
                    "population": p.get("Population_Served_Count") or 0,
                    "sourced": p.get("Symbology_Field") == "System Sourced",
                },
                "geometry": {"type": g["type"], "coordinates": rounded(g["coordinates"])},
            })
        print(f"{min(i + PAGE, len(ids))}/{len(ids)}", file=sys.stderr)

    geo = {"type": "FeatureCollection", "features": features}
    out = OUT_DIR / "nc_water_systems.geojson"
    out.write_text(json.dumps(geo, separators=(",", ":")))
    meta = {
        "sourceName": "EPA Community Water System Service Area Boundaries",
        "sourceURL": "https://www.epa.gov/ground-water-and-drinking-water/community-water-system-service-area-boundaries",
        "serviceURL": SERVICE,
        "version": "service last edited %s" % (
            datetime.fromtimestamp(edited / 1000, timezone.utc).date().isoformat() if edited else "unknown"),
        "downloaded": date.today().isoformat(),
        "systems": len(features),
        "simplificationDegrees": OFFSET,
    }
    (OUT_DIR / "nc_water_systems_meta.json").write_text(json.dumps(meta, indent=2))
    print(f"{len(features)} systems, {out.stat().st_size / 1e6:.1f} MB -> {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
