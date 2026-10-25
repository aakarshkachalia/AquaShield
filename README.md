<h1 align="center">AquaShield</h1>

<p align="center">
  <b>Know what's in your tap water, what it means for your family, and what to do about it.</b><br>
  A private, on-device iOS app for North Carolina homes on city water or private wells.
</p>

<p align="center">
  <img src="Screenshots/city/light/06-dashboard-city-light.png" width="200" alt="Dashboard">
  <img src="Screenshots/city/light/08-tap-score-kitchen-city-light.png" width="200" alt="Kitchen tap score">
  <img src="Screenshots/city/light/14-my-water-trends-city-light.png" width="200" alt="Trends">
  <img src="Screenshots/city/light/10-what-to-do-city-light.png" width="200" alt="What to do">
</p>

---

## The problem

- **Safe-looking water isn't proof of safe water.** Lead, arsenic, nitrate and PFAS have no color, smell or taste.
- **Private wells have no federal oversight.** Owners are responsible for their own testing, and many never test.
- **City water can change on the way to your tap** through service lines and home plumbing.
- **Lab reports and utility reports are hard to read**, so results often go unused.

AquaShield turns test results, utility data and filter certifications into a clear score per tap, flags real risks for the people in the home, and points to the next step.

---

## Features

### Address-first setup
- Enter your address and AquaShield estimates whether the home is on **city water or a private well**, by checking it against EPA's community water system service-area boundaries **on the device**.
- You confirm the result with one tap, and the whole app adapts. City homes never see well-only content, and vice versa.
- Welcome and setup run once, and progress is saved at every step.

<p>
  <img src="Screenshots/city/light/02-onboarding-address-city-light.png" width="180" alt="Address">
  <img src="Screenshots/city/light/03-onboarding-estimate-city-light.png" width="180" alt="Estimate">
  <img src="Screenshots/city/light/04-onboarding-confirm-city-light.png" width="180" alt="Confirm">
</p>

### Dashboard and Water Health Score
- One screen with the overall score, active alerts, filter status, next test due and the top recommended action.
- A **score for each tap** (kitchen drinking water, showers, whole house) that accounts for the filters installed at that tap.
- **The worst contaminant drives the score.** A dangerous reading is never averaged away by good ones, and missing tests lower the confidence rather than inflating the score.

### My Water
- Latest results, full history, and trend charts for every contaminant, with the limit marked.
- **Scan a paper lab report** with the camera. Text recognition runs on the device, and you review every value before it's saved.
- Manual entry for lab, county health department and home-kit results, with unit conversion and non-detect handling.
- **City mode:** enter your utility's annual water quality report (Consumer Confidence Report).
- Detail pages for each contaminant: what it is, where it comes from, health effects and how to test.

### Filters checked against certifications
- Add the drinking-water, whole-house and shower filters installed in your home.
- Reductions are based on **individual NSF/ANSI certification claims**, not marketing. A claim only counts if your water is within the level it was tested at and the filter isn't past its replacement date.
- Shower filters count for chlorine only, because that's all the shower standard (NSF/ANSI 177) covers.

### Household risk
- Optional profiles for each family member (nickname only): age group, pregnancy, infants on formula, how much tap water they drink.
- Shows **who is most exposed to which contaminant**. It screens for exposure risk; it never diagnoses.
- Critical safety alerts, e.g. high-nitrate water must never be used for infant formula, because boiling concentrates nitrate.

### What to do
- A remediation plan with **no-cost fixes first** (flushing taps, cold water for cooking, well disinfection, lead service line checks), then certified treatment options compared side by side.
- Basic care guidance for skin dryness or irritation from hard or chlorinated water, with red flags that point to a doctor.

### Stays useful over time
- Filter replacement and well-testing reminders.
- **Storm/flood mode**, infant mode and boil-water guidance, with optional National Weather Service alerts.
- Shareable **PDF report** for a doctor, landlord or well contractor.

### Get help and learn
- Find testing options and assistance programs in your county.
- Short Learn articles with quizzes, and **Report Quest**, a guided, game-style walkthrough of reading a real lab report.
- Area risk maps for well owners, built from NC census-tract well-testing data (see below).

### Accessible by default
- Dynamic Type, VoiceOver labels on every chart and score, Dark Mode and Reduce Motion support.
- Status is always shown with an icon and a label, never color alone.

---

## Privacy

- **All household and health data stays on your phone.** No accounts, no analytics, no tracking, no server.
- Your address is sent only to Apple to find its location. The water-system lookup runs entirely on the device.
- Weather alerts (National Weather Service) and nearby-help search (Apple Maps) are **opt-in** and use the coarsest location that works.
- Every outbound request is listed in **Settings → Privacy & Sources**.

---

## Data and research

| Data | Source |
|---|---|
| Drinking water limits (MCLs, action levels, health advisories) | U.S. EPA drinking water regulations |
| Water system service areas | U.S. EPA Community Water System Service Area Boundaries |
| Census-tract well water data | NCWELL tract- and county-level distributions |
| Census tract geometry | U.S. Census TIGER/Line, NC tracts |
| Filter certification standards | NSF/ANSI 42, 53, 55, 58, 62, 177, 401, 44, 244, P231 |

**Source tracking.** Every regulatory value and certification note carries its source, URL and last-verified date, recorded in `VerificationRegister.json`. Values still awaiting manual verification are listed in a debug-only Data Review screen.

**Well risk model.** The repo includes a Python pipeline that estimates, for each NC census tract, the likelihood of elevated **arsenic, lead, manganese and nitrate** in private wells. It combines NCWELL testing data with local geology features, compares against a baseline, checks calibration and feature importance, and exports the results the app uses for its area maps. These are area-level estimates, not a substitute for testing your own well.

**Sample data.** Filter products, county trend data and some county well figures bundled with the app are clearly labeled samples for demonstration. They are not presented as real measurements.

---

## Tech stack

- **Swift + SwiftUI**, no third-party packages
- **SwiftData** for user data; versioned bundled JSON for reference data
- **Swift Charts** for all visualizations
- **MapKit** for address search and service-area maps
- **VisionKit + Vision** for on-device lab report scanning
- **XCTest** unit and UI tests, including relaunch/persistence tests and automated screenshots
- **Python** (pandas/geopandas-style pipeline) for the well risk model and boundary data

---

## Repository layout

```
AquaShield/
├── AquaShield/                  # Xcode project
│   ├── AquaShield/
│   │   ├── App/                 # App state, settings, privacy & sources, demo mode
│   │   ├── Data/                # Scoring, risk, interpretation, filters, household,
│   │   │                        # remediation, location lookup, reference data
│   │   ├── DesignSystem/        # Tokens, components, step-by-step flows, gallery
│   │   ├── Drafts/              # Saved progress for every multi-step flow
│   │   ├── Help/                # Help finder, programs, storm mode
│   │   ├── Quest/               # Report Quest (guided lab-report walkthrough)
│   │   ├── RiskCheck/           # Household risk questions
│   │   ├── Scanner/             # Camera, OCR and lab report parser
│   │   ├── UI/                  # Dashboard, My Water, filters, household, learn…
│   │   └── *.json / *.geojson   # Bundled reference data with source metadata
│   ├── AquaShieldTests/         # Unit tests
│   └── AquaShieldUITests/       # UI, persistence and screenshot tests
├── DataPipeline/                # Builds the NC water-system boundary file from EPA data
├── step1_map.py … step6_export.py   # Well risk model pipeline
├── data/                        # Raw and processed inputs for the model
├── outputs/                     # Model maps, calibration and importance plots
├── app/                         # Early web prototype of the tract risk map
└── Screenshots/                 # App screenshots (city + well, light + dark)
```

---

## Getting started

**Requirements:** a Mac with the latest Xcode and an iOS simulator or device. <!-- add minimum iOS version from the project's deployment target -->

```bash
git clone https://github.com/<your-username>/AquaShield.git
cd AquaShield
open AquaShield/AquaShield.xcodeproj
```

Choose an iPhone simulator and press **⌘R**. To explore without your own data, turn on **Demo Mode** in Settings to load sample households; demo data never mixes with real data.

**Run tests:** press **⌘U** in Xcode.

**Rebuild the water-system boundaries:**
```bash
python DataPipeline/fetch_nc_water_systems.py
```

**Re-run the well risk model:** run `step1_map.py` through `step6_export.py` in order from the repo root.

---

## Screenshots

| City water | Private well |
|---|---|
| <img src="Screenshots/city/dark/06-dashboard-city-dark.png" width="220"> | <img src="Screenshots/well/dark/01-dashboard-well-dark.png" width="220"> |
| <img src="Screenshots/city/dark/16-utility-report-city-dark.png" width="220"> | <img src="Screenshots/well/dark/11-testing-and-modes-well-dark.png" width="220"> |

Full sets for both water sources in light and dark mode are in [`Screenshots/`](Screenshots/).

---

## Disclaimer

AquaShield provides **educational information, not medical advice**, and does not diagnose any condition. Results depend on the data entered and on area-level estimates. Always confirm with a state-certified laboratory and talk to a doctor about health concerns. AquaShield is not affiliated with EPA, NSF or any filter manufacturer, and receives no payment for recommendations.

---

## Author

Built by **Aakarsh Kachalia**, Cary, North Carolina.

## License

<!-- Add a LICENSE file (e.g. MIT) or state "All rights reserved." -->
