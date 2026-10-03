Build an iOS app called **ClearWell NC** in SwiftUI. It helps North Carolina families on private wells understand their area's well-water risk, decide what to test for, record their lab results, and maintain their treatment system. Read this whole spec first, then build ONLY the milestone I ask for, one at a time. Keep the project compiling after every milestone.

## Platform and constraints
- iOS 17+, SwiftUI, Swift 5.9+. iPhone first; must also work on iPad.
- Apple frameworks only, no third-party packages: MapKit, CoreLocation (CLGeocoder), SwiftData, Swift Charts, UserNotifications.
- No backend, no accounts, no analytics. All risk data ships inside the app bundle. The user's address is never stored unless they explicitly save "My Well."
- Accessibility: Dynamic Type, VoiceOver labels on every control and chart, never use color alone (every risk color also has a text label), 44pt tap targets, Dark Mode support.
- All user-facing strings go in a String Catalog (Localizable.xcstrings) so Spanish can be added later.

## Bundled data (I will drag these files into the project)
1. `tracts.geojson`: a GeoJSON FeatureCollection of 2,195 North Carolina census tracts (2010 boundaries), coordinates in [longitude, latitude], geometry is Polygon or MultiPolygon. Each feature's `properties`:
   ```json
   {"fips": "37179020502", "county": "179",
    "arsenic": [0.1880, 52, 8], "manganese": [0.3380, 52, 18],
    "nitrate": [0.0440, 9, 1], "lead": [0.0350, 52, 2]}
   ```
   Each contaminant array = [estimated share of wells above the limit (0-1), number of wells tested in this tract, number of those above the limit].
2. `meta.json`:
   ```json
   {"generated": "2026-09-29",
    "statewide": {"arsenic": 0.0227, "manganese": 0.2434, "nitrate": 0.0093, "lead": 0.0279},
    "data_source": "NCWELL database (Eaves et al. 2021, UNC Superfund Research Program), 1998-2019",
    "model_scores": [{"contaminant": "arsenic", "county_average": 0.3613, "neighbors_only": 0.6717,
                      "MODEL_unseen_tract": 0.7016, "model_unseen_county": 0.3197}, ...]}
   ```
3. Images for the "How it works" screen: `arsenic_map.png`, `calibration.png`, `importance.png`.

Parse the GeoJSON once at launch on a background task (MKGeoJSONDecoder or Codable), store tracts in memory with a precomputed bounding box for each, and use a custom ray-casting point-in-polygon (outer ring in, holes out) to find the tract containing a coordinate. Check bounding boxes first for speed.

## Risk logic (must match exactly; this mirrors my Python model)
- ratio = tract estimate / statewide rate for that contaminant.
- Level: ratio >= 3 → "High"; >= 1.5 → "Elevated"; >= 0.75 → "Typical"; otherwise "Lower than typical".
- **Lead is always "Test regardless"** (lead depends on household plumbing, not location).
- "1 in N" text: if rate < 0.005 → "fewer than 1 in 200"; else "about 1 in \(max(2, round(1/rate)))".
- Confidence from tests in tract: >= 30 High, >= 10 Medium, 1-9 Low ("mostly the model's estimate"), 0 Low ("No wells in your census tract have been tested. This is the model's estimate from geology and nearby areas.").
- Card sort order: High, Elevated, Typical, Test regardless, Lower than typical; ties broken by larger ratio first.
- County name: NC county FIPS codes are odd numbers in alphabetical order, so name = COUNTIES[(Int(fips) - 1) / 2] using this list: Alamance, Alexander, Alleghany, Anson, Ashe, Avery, Beaufort, Bertie, Bladen, Brunswick, Buncombe, Burke, Cabarrus, Caldwell, Camden, Carteret, Caswell, Catawba, Chatham, Cherokee, Chowan, Clay, Cleveland, Columbus, Craven, Cumberland, Currituck, Dare, Davidson, Davie, Duplin, Durham, Edgecombe, Forsyth, Franklin, Gaston, Gates, Graham, Granville, Greene, Guilford, Halifax, Harnett, Haywood, Henderson, Hertford, Hoke, Hyde, Iredell, Jackson, Johnston, Jones, Lee, Lenoir, Lincoln, Macon, Madison, Martin, McDowell, Mecklenburg, Mitchell, Montgomery, Moore, Nash, New Hanover, Northampton, Onslow, Orange, Pamlico, Pasquotank, Pender, Perquimans, Person, Pitt, Polk, Randolph, Richmond, Robeson, Rockingham, Rowan, Rutherford, Sampson, Scotland, Stanly, Stokes, Surry, Swain, Transylvania, Tyrrell, Union, Vance, Wake, Warren, Washington, Watauga, Wayne, Wilkes, Wilson, Yadkin, Yancey.

Contaminant content (use this text exactly):
- **Arsenic**, limit "10 ppb (EPA limit)". Why: "Arsenic comes from certain bedrock. It has no taste or smell, and long-term exposure raises cancer risk." If high: "Reverse osmosis certified to NSF/ANSI 58 for arsenic. An under-sink unit is usually enough for drinking and cooking."
- **Manganese**, limit "50 ppb (NC standard)". Why: "Manganese comes from rock and soil. It can stain sinks and laundry black, and high levels are a concern for infants." If high: "Oxidation/filtration (greensand) or a softener rated for manganese; reverse osmosis for drinking water."
- **Nitrate**, limit "10 mg/L (EPA limit)". Why: "Nitrate comes from fertilizer, manure and septic systems. It is most dangerous for babies under 6 months." If high: "Reverse osmosis certified to NSF/ANSI 58 for nitrate. Never boil water to remove nitrate; boiling concentrates it."
- **Lead**, limit "15 ppb (EPA action level)". Why: "Lead in well water usually comes from pipes, solder and well parts, not the rock, so it varies from house to house." If high: "A point-of-use filter certified to NSF/ANSI 53 for lead; replace old brass fittings or lead solder where possible."

Test plan (numbered list): 1) "Bacteria (total coliform / E. coli): every year and after any flooding, for every well." Then one line per contaminant in card order: High/Elevated → "{Name}: a priority for your area ({level} risk)."; Lead → "Lead: test at least once; it depends on your home's plumbing."; otherwise → "{Name}: include in a standard metals and nitrate panel every 2 years." Last: "How: contact {County} County Environmental Health to order a test through the NC State Laboratory of Public Health, or use a state-certified private lab."

Every report shows: "This is an estimate for your area, not your well. Only a lab test tells you what is in your water." Never recommend a product brand; only NSF/ANSI certification types.

## Screens
1. **Onboarding**: "Does your home get water from a private well?" Yes / No, city or county water / Not sure. "No" explains that public systems publish a yearly Consumer Confidence Report and lets them explore anyway. "Not sure" explains: a water bill means probably not a well; a well pump or pressure tank and no water bill means probably a well. Optional toggle: "A baby under 6 months lives here" (stored locally).
2. **Check My Area** (main tab): address field using CLGeocoder, a "Use my location" button (When In Use permission, with a clear purpose string), and a map where tapping selects a tract. Show a friendly error if the point is outside NC.
3. **Report**: county + tract header, one card per contaminant (level badge with text, "Estimated about 1 in N wells in your area are above {limit}", a horizontal bar comparing your area with the statewide rate using a marker line, "X of N tested wells in your census tract were above the limit" when tests > 0, confidence line, expandable "Why it matters and what to do"), then the test plan. If the infant toggle is on and nitrate is Typical or higher, show a prominent nitrate note about formula and well water. Button: "Save as My Well."
4. **Map**: MKMapView via UIViewRepresentable (SwiftUI Map with 2,000+ polygons is too slow). Group tracts into ONE MKMultiPolygon overlay per risk level for the selected contaminant (4 overlays), and re-group when the contaminant picker changes (Arsenic / Manganese / Nitrate / Lead). Colors, light to dark: Lower #FDE4D8, Typical #F9AB8F, Elevated #EC6246, High #B3161F, 75% opacity, thin white borders; tracts with 0 tests at lower opacity. Legend under the map with text labels. Highlight the selected tract with a dark outline.
5. **My Well** (SwiftData): saved location + tract, and a **Well Record** of lab results. Entry form: date, lab name (optional), and values for arsenic (ppb), lead (ppb), manganese (ppb), nitrate (mg/L), iron (ppb), pH, total coliform / E. coli (present / absent). Let the user pick mg/L or ppb where relevant (1 mg/L = 1000 ppb). Compare each value to its limit (arsenic 10 ppb, lead 15 ppb, manganese 50 ppb NC standard and 300 ppb health advisory, nitrate 10 mg/L, iron 300 ppb for staining only, pH 6.5-8.5, bacteria must be absent). Show pass / above-limit with text and a Swift Charts trend line per contaminant across tests. If E. coli is present, show an urgent card: do not drink the water, use bottled water, call the county health department, shock-chlorinate and retest. After a user logs a treatment system, remind them to retest to confirm it works.
6. **Treatment tracker**: add systems (sediment filter, carbon filter, reverse osmosis membrane, UV bulb, water softener salt, other) with install date and interval (defaults: sediment 3 months, carbon 6 months, RO membrane 24 months, UV bulb 12 months, softener salt check 1 month). Show days remaining, and schedule local notifications (UserNotifications) for replacements. Also yearly reminders: bacteria test and wellhead inspection; metals and nitrate every 2 years.
7. **Alerts**: for the saved well location, fetch active alerts from the free National Weather Service API `https://api.weather.gov/alerts/active?point={lat},{lon}` (set a User-Agent header like "ClearWellNC (contact email)"). If there is a flood watch or warning, hurricane, or tropical storm alert, show a before/after well checklist: before, fill clean water containers and know where the well cap is; after, if the wellhead was underwater, do not drink the water, disinfect the well, and test for bacteria before using it again. Also check on app launch.
8. **How it works**: the four explainer cards (real test results; the rock beneath you: Slate Belt metasedimentary rock has about 12% of wells over the arsenic limit, roughly 5 times the state average; a model that fills the gaps; honest confidence), a scores table from meta.json (County average / Nearby tracts only / ClearWell model / Stress test: unseen county, shown as percentages), the three images with captions, the data-audit note (silver, cadmium and chromium columns excluded because the lab's reporting limit is above the state standard; the tract file's manganese health-limit column duplicates the 50 ppb column), and the data source.

Tabs: Check My Area, My Well, Reminders, How It Works.

## Design
Clean, calm, trustworthy. Accent color #0F5C73 (deep teal), warm off-white background in light mode, system backgrounds in dark mode, SF Pro, generous spacing, rounded cards. The app icon is a simple water drop.

## Milestones (build one at a time, stop after each)
1. **Data + risk engine + unit tests**: models, GeoJSON/meta loading, point-in-polygon, all risk logic above. XCTest cases that must pass:
   - Tract 37179020502 (Union County): Arsenic High, Nitrate High, Manganese Typical, Lead Test regardless; arsenic text "about 1 in 5"; arsenic observed "8 of 52".
   - Tract 37019020201 (Brunswick County): arsenic tests = 0, so the confidence message is the "No wells in your census tract have been tested" one.
   - County FIPS "183" → Wake, "179" → Union, "001" → Alamance, "199" → Yancey.
   - A coordinate in Monroe, NC (34.9716, -80.5510) falls in a Union County tract; a coordinate in Norfolk, VA (36.85, -76.29) returns nil.
2. **Onboarding + Check My Area + Report** (no map yet).
3. **Map** with contaminant picker and tap-to-select.
4. **My Well + Well Record** with lab entry and charts.
5. **Treatment tracker + notifications.**
6. **NWS alerts.**
7. **How it works**, accessibility pass, Spanish strings.

Do not invent data, statistics, or health claims beyond this spec. If something is ambiguous, ask me before guessing.
