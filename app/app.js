/* ClearWell NC - runs entirely in the browser. Data comes from step6_export.py. */
(function () {
  "use strict";

  // NC county FIPS codes are odd numbers assigned alphabetically (Alamance = 001 ... Yancey = 199).
  const COUNTIES = ["Alamance","Alexander","Alleghany","Anson","Ashe","Avery","Beaufort","Bertie","Bladen",
    "Brunswick","Buncombe","Burke","Cabarrus","Caldwell","Camden","Carteret","Caswell","Catawba","Chatham",
    "Cherokee","Chowan","Clay","Cleveland","Columbus","Craven","Cumberland","Currituck","Dare","Davidson",
    "Davie","Duplin","Durham","Edgecombe","Forsyth","Franklin","Gaston","Gates","Graham","Granville","Greene",
    "Guilford","Halifax","Harnett","Haywood","Henderson","Hertford","Hoke","Hyde","Iredell","Jackson",
    "Johnston","Jones","Lee","Lenoir","Lincoln","Macon","Madison","Martin","McDowell","Mecklenburg","Mitchell",
    "Montgomery","Moore","Nash","New Hanover","Northampton","Onslow","Orange","Pamlico","Pasquotank","Pender",
    "Perquimans","Person","Pitt","Polk","Randolph","Richmond","Robeson","Rockingham","Rowan","Rutherford",
    "Sampson","Scotland","Stanly","Stokes","Surry","Swain","Transylvania","Tyrrell","Union","Vance","Wake",
    "Warren","Washington","Watauga","Wayne","Wilkes","Wilson","Yadkin","Yancey"];
  const countyName = (code) => COUNTIES[(parseInt(code, 10) - 1) / 2] || "your";

  const INFO = {
    arsenic: { name: "Arsenic", limit: "10 ppb (EPA limit)",
      why: "Arsenic comes from certain bedrock. It has no taste or smell, and long-term exposure raises cancer risk.",
      fix: "Reverse osmosis certified to NSF/ANSI 58 for arsenic. An under-sink unit is usually enough for drinking and cooking." },
    manganese: { name: "Manganese", limit: "50 ppb (NC standard)",
      why: "Manganese comes from rock and soil. It can stain sinks and laundry black, and high levels are a concern for infants.",
      fix: "Oxidation/filtration (greensand) or a softener rated for manganese; reverse osmosis for drinking water." },
    nitrate: { name: "Nitrate", limit: "10 mg/L (EPA limit)",
      why: "Nitrate comes from fertilizer, manure and septic systems. It is most dangerous for babies under 6 months.",
      fix: "Reverse osmosis certified to NSF/ANSI 58 for nitrate. Never boil water to remove nitrate; boiling concentrates it." },
    lead: { name: "Lead", limit: "15 ppb (EPA action level)",
      why: "Lead in well water usually comes from pipes, solder and well parts, not the rock, so it varies from house to house.",
      fix: "A point-of-use filter certified to NSF/ANSI 53 for lead; replace old brass fittings or lead solder where possible." }
  };
  const ORDER = ["arsenic", "manganese", "nitrate", "lead"];
  const LEVELS = {
    lower:    { label: "Lower than typical", cls: "lvl-lower",    color: "var(--r0)", hex: "#fde4d8", rank: 4 },
    typical:  { label: "Typical",            cls: "lvl-typical",  color: "var(--r1)", hex: "#f9ab8f", rank: 2 },
    elevated: { label: "Elevated",           cls: "lvl-elevated", color: "var(--r2)", hex: "#ec6246", rank: 1 },
    high:     { label: "High",               cls: "lvl-high",     color: "var(--r3)", hex: "#b3161f", rank: 0 },
    lead:     { label: "Test regardless",    cls: "lvl-lead",     color: "#e8e6df",   hex: "#e8e6df", rank: 3 }
  };

  let META = null, TRACTS = null, map = null, layer = null, marker = null, selected = null;
  let current = "arsenic";
  const $ = (id) => document.getElementById(id);

  // ------------------------------------------------------------ risk logic (matches step5_lookup.py)
  function levelKey(ratio) {
    if (ratio >= 3) return "high";
    if (ratio >= 1.5) return "elevated";
    if (ratio >= 0.75) return "typical";
    return "lower";
  }
  function oneIn(rate) {
    if (rate < 0.005) return "fewer than 1 in 200";
    return "about 1 in " + Math.max(2, Math.round(1 / rate));
  }
  function confidence(tests) {
    if (tests >= 30) return ["High", `Based on ${tests} tested wells in your census tract, plus the model.`];
    if (tests >= 10) return ["Medium", `Based on ${tests} tested wells in your census tract, plus the model.`];
    if (tests >= 1) return ["Low", `Only ${tests} tested well${tests > 1 ? "s" : ""} in your census tract, so this is mostly the model's estimate.`];
    return ["Low", "No wells in your census tract have been tested. This is the model's estimate from geology and nearby areas."];
  }
  function analyze(props) {
    return ORDER.map((key) => {
      const [est, tests, exceed] = props[key];
      const state = META.statewide[key];
      const ratio = est / state;
      const lvl = key === "lead" ? "lead" : levelKey(ratio);
      return { key, est, tests, exceed, state, ratio, lvl };
    }).sort((a, b) => LEVELS[a.lvl].rank - LEVELS[b.lvl].rank || b.ratio - a.ratio);
  }

  // ------------------------------------------------------------ report
  function esc(s) { return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]); }

  function renderReport(feature, matched) {
    const p = feature.properties;
    const county = countyName(p.county);
    const rows = analyze(p);
    const cards = rows.map((r) => {
      const info = INFO[r.key], L = LEVELS[r.lvl];
      const [conf, confNote] = confidence(r.tests);
      const scaleMax = Math.max(r.state * 4, r.est);
      const pct = (v) => Math.min(100, (v / scaleMax) * 100).toFixed(1);
      const observed = r.tests > 0
        ? `${r.exceed} of ${r.tests} tested wells in your census tract were above the limit.`
        : "";
      const showFix = r.lvl === "high" || r.lvl === "elevated" || r.lvl === "lead";
      return `
        <article class="card">
          <div class="card-head"><h3>${info.name}</h3><span class="badge ${L.cls}">${L.label}</span></div>
          <p class="estimate">Estimated ${oneIn(r.est)} wells in your area are above ${info.limit}.</p>
          <div class="meter" role="img" aria-label="Your area ${(r.est * 100).toFixed(1)} percent, statewide ${(r.state * 100).toFixed(1)} percent">
            <div class="you" style="width:${pct(r.est)}%;background:${L.hex === "#e8e6df" ? "#9aa0a3" : L.hex}"></div>
            <div class="state" style="left:${pct(r.state)}%"></div>
          </div>
          <div class="meter-key"><span>Your area: ${(r.est * 100).toFixed(1)}%</span><span>Statewide: ${(r.state * 100).toFixed(1)}% (black line)</span></div>
          ${observed ? `<p class="observed">${observed}</p>` : ""}
          <p class="conf"><strong>Confidence: ${conf}.</strong> ${confNote}</p>
          <details><summary>Why it matters${showFix ? " and what to do" : ""}</summary>
            <p>${info.why}</p>${showFix ? `<p><strong>If your test comes back high:</strong> ${info.fix}</p>` : ""}
          </details>
        </article>`;
    }).join("");

    const plan = ["<strong>Bacteria</strong> (total coliform / E. coli): every year and after any flooding, for every well."];
    rows.forEach((r) => {
      const n = INFO[r.key].name;
      if (r.lvl === "high" || r.lvl === "elevated") plan.push(`<strong>${n}</strong>: a priority for your area (${LEVELS[r.lvl].label.toLowerCase()} risk).`);
      else if (r.lvl === "lead") plan.push(`<strong>${n}</strong>: test at least once; it depends on your home's plumbing.`);
      else plan.push(`<strong>${n}</strong>: include in a standard metals and nitrate panel every 2 years.`);
    });
    plan.push(`<strong>How:</strong> contact ${esc(county)} County Environmental Health to order a test through the NC State Laboratory of Public Health, or use a state-certified private lab.`);

    $("report").innerHTML = `
      <div class="place"><h2>${esc(county)} County</h2><span class="tract">Census tract ${esc(p.fips)}</span></div>
      <p class="matched">${matched ? "Location: " + esc(matched) : "Selected on the map"}</p>
      ${cards}
      <div class="plan"><h3>Your test plan</h3><ol>${plan.map((x) => `<li>${x}</li>`).join("")}</ol></div>
      <p class="disclaimer">This is an estimate for your area, not your well. Only a lab test tells you what is in your water.</p>`;
    if (window.innerWidth <= 900) $("report").scrollIntoView({ behavior: "smooth", block: "start" });
    history.replaceState(null, "", "?tract=" + p.fips);
  }

  // ------------------------------------------------------------ map
  function styleFor(feature) {
    const [est, tests] = feature.properties[current];
    const lvl = levelKey(est / META.statewide[current]);
    const isSel = selected && feature.properties.fips === selected.properties.fips;
    return {
      fillColor: LEVELS[lvl].hex, fillOpacity: tests > 0 ? 0.8 : 0.55,
      color: isSel ? "#111" : "#ffffff", weight: isSel ? 3 : 0.4
    };
  }
  function renderLegend() {
    const items = ["lower", "typical", "elevated", "high"].map((k) =>
      `<span><i style="background:${LEVELS[k].hex}"></i>${LEVELS[k].label}</span>`).join("");
    const note = current === "lead"
      ? "Lead depends mostly on household plumbing, so every well should test for it regardless of the map."
      : "Compared with the North Carolina average. Paler tracts have no test data (model estimate only).";
    $("legend").innerHTML = items + `<span class="caption">${note}</span>`;
  }
  function select(feature, latlng, matched) {
    selected = feature;
    layer.setStyle(styleFor);
    if (marker) marker.remove();
    if (latlng) marker = L.marker(latlng).addTo(map);
    const b = L.geoJSON(feature).getBounds();
    map.fitBounds(b, { maxZoom: 12, padding: [20, 20] });
    renderReport(feature, matched);
  }
  function initMap() {
    map = L.map("map", { scrollWheelZoom: false }).setView([35.4, -79.4], 7);
    L.tileLayer("https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png", {
      maxZoom: 18, subdomains: "abcd",
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> &copy; <a href="https://carto.com/attributions">CARTO</a>'
    }).addTo(map);
    layer = L.geoJSON(TRACTS, {
      style: styleFor,
      onEachFeature: (f, l) => l.on("click", (e) => select(f, e.latlng, null))
    }).addTo(map);
    renderLegend();
  }

  // ------------------------------------------------------------ point in polygon
  function inRing(x, y, ring) {
    let inside = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi] = ring[i], [xj, yj] = ring[j];
      if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }
  function inPolygon(x, y, poly) {
    if (!inRing(x, y, poly[0])) return false;
    for (let h = 1; h < poly.length; h++) if (inRing(x, y, poly[h])) return false;
    return true;
  }
  function findTract(lat, lon) {
    for (const f of TRACTS.features) {
      const g = f.geometry;
      const polys = g.type === "Polygon" ? [g.coordinates] : g.coordinates;
      if (polys.some((p) => inPolygon(lon, lat, p))) return f;
    }
    return null;
  }
  function goToPoint(lat, lon, matched) {
    const f = findTract(lat, lon);
    if (!f) return setStatus("That location is outside North Carolina. ClearWell covers NC only.", true);
    setStatus("");
    select(f, [lat, lon], matched);
  }

  // ------------------------------------------------------------ search
  function setStatus(msg, isError) {
    $("status").textContent = msg;
    $("status").classList.toggle("error", !!isError);
  }
  async function geocode(q) {
    const url = "https://nominatim.openstreetmap.org/search?" + new URLSearchParams({
      q: /\bNC\b|north carolina/i.test(q) ? q : q + ", North Carolina", format: "json",
      countrycodes: "us", limit: "1"
    });
    const r = await fetch(url, { headers: { "Accept-Language": "en" } });
    if (!r.ok) throw new Error("geocoder " + r.status);
    const data = await r.json();
    return data.length ? { lat: +data[0].lat, lon: +data[0].lon, label: data[0].display_name } : null;
  }
  function byFips(fips) { return TRACTS.features.find((f) => f.properties.fips === fips); }

  function initSearch() {
    $("search-form").addEventListener("submit", async (e) => {
      e.preventDefault();
      const q = $("address").value.trim();
      if (/^37\d{9}$/.test(q)) { const f = byFips(q); return f ? select(f, null, null) : setStatus("Tract not found.", true); }
      setStatus("Finding your area...");
      try {
        const hit = await geocode(q);
        if (!hit) return setStatus("We couldn't find that address. Try adding the town and ZIP code, or click your home on the map.", true);
        goToPoint(hit.lat, hit.lon, hit.label);
      } catch (err) {
        setStatus("The address search is unavailable right now. Click your home on the map instead.", true);
      }
    });
    $("locate").addEventListener("click", () => {
      if (!navigator.geolocation) return setStatus("Your browser can't share location. Type your address instead.", true);
      setStatus("Getting your location...");
      navigator.geolocation.getCurrentPosition(
        (pos) => goToPoint(pos.coords.latitude, pos.coords.longitude, "your current location"),
        () => setStatus("Location wasn't shared. Type your address or click the map instead.", true),
        { timeout: 10000 });
    });
    document.querySelectorAll(".seg button").forEach((b) => b.addEventListener("click", () => {
      current = b.dataset.c;
      document.querySelectorAll(".seg button").forEach((x) => x.setAttribute("aria-selected", String(x === b)));
      layer.setStyle(styleFor);
      renderLegend();
    }));
  }

  function initWellQuestion() {
    const note = $("well-note");
    document.querySelectorAll("[data-well]").forEach((b) => b.addEventListener("click", () => {
      document.querySelectorAll("[data-well]").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
      const v = b.dataset.well;
      if (v === "no") {
        note.innerHTML = "City and county water systems are tested regularly and must publish a yearly water quality report (a Consumer Confidence Report). Check your utility's website for it. You can still explore the well map below.";
      } else if (v === "unsure") {
        note.innerHTML = "If you pay a water bill to a city, county or utility, you're probably not on a well. If you have a well pump or pressure tank and no water bill, you probably are.";
      } else {
        note.innerHTML = "";
      }
      note.hidden = !note.innerHTML;
      reveal();
      if (v === "yes") $("address").focus();
    }));
  }
  function reveal() {
    const first = $("search").hidden;
    $("search").hidden = false;
    $("results-layout").hidden = false;
    if (first) setTimeout(() => map.invalidateSize(), 0);
  }

  // ------------------------------------------------------------ how it works
  function renderScores() {
    if (!META.model_scores) return;
    const pct = (v) => (v * 100).toFixed(1) + "%";
    const rows = META.model_scores.map((s) => {
      const best = Math.max(s.county_average, s.neighbors_only, s.MODEL_unseen_tract);
      const td = (v) => `<td class="${v === best ? "best" : ""}">${pct(v)}</td>`;
      return `<tr><td>${INFO[s.contaminant].name}</td>${td(s.county_average)}${td(s.neighbors_only)}${td(s.MODEL_unseen_tract)}<td>${pct(s.model_unseen_county)}</td></tr>`;
    }).join("");
    $("scores").innerHTML = `<thead><tr><th>Contaminant</th><th>County average</th><th>Nearby tracts only</th><th>ClearWell model</th><th>Stress test: unseen county</th></tr></thead><tbody>${rows}</tbody>`;
  }

  // ------------------------------------------------------------ start
  async function start() {
    [META, TRACTS] = await Promise.all([
      fetch("data/meta.json").then((r) => r.json()),
      fetch("data/tracts.geojson").then((r) => r.json())
    ]);
    $("source").textContent = "Data: " + META.data_source + ". Tract estimates generated " + META.generated + ".";
    renderScores();
    initMap();
    initSearch();
    initWellQuestion();
    const t = new URLSearchParams(location.search).get("tract");
    if (t && byFips(t)) { reveal(); select(byFips(t), null, null); }
  }
  start().catch((err) => {
    document.querySelector(".hero").insertAdjacentHTML("beforeend",
      '<p class="status error">Could not load the data. Run step6_export.py, then open this page through "python -m http.server" (not by double-clicking the file).</p>');
    console.error(err);
  });
})();
