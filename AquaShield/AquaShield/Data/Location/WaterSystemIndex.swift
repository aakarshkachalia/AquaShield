//
//  WaterSystemIndex.swift
//  AquaShield
//
//  On-device lookup of the public water system serving a point, from EPA's Community Water System Service
//  Area Boundaries (NC subset, built by DataPipeline/fetch_nc_water_systems.py). Nothing is sent anywhere.
//

import Foundation

nonisolated struct WaterSystemArea: Sendable, Identifiable {
    let pwsid: String
    let name: String
    let population: Int
    /// True for boundaries drawn by the utility or state; false for EPA-modeled boundaries.
    let sourced: Bool
    let polygons: [GeoPolygon]
    let boundingBox: BoundingBox

    var id: String { pwsid }

    func contains(_ p: GeoPoint) -> Bool {
        boundingBox.contains(p) && polygons.contains { $0.contains(p) }
    }

    /// "CARY, TOWN OF" → "Cary, Town Of": readable without changing the official name.
    var displayName: String { name.capitalized }
}

nonisolated struct WaterSystemDataInfo: Codable, Sendable {
    let sourceName: String
    let sourceURL: String
    let version: String
    let downloaded: String
    let systems: Int
}

nonisolated struct WaterSystemIndex: Sendable {
    let areas: [WaterSystemArea]

    /// The bundled index, parsed once on first use (a few hundred ms; call off the main thread).
    static let bundled: WaterSystemIndex? = try? load()
    static let info: WaterSystemDataInfo? = ReferenceData.load("nc_water_systems_meta", as: WaterSystemDataInfo.self)

    enum LoadError: Error { case missing, malformed }

    static func load(bundle: Bundle = .main, resource: String = "nc_water_systems") throws -> WaterSystemIndex {
        guard let url = bundle.url(forResource: resource, withExtension: "geojson") else { throw LoadError.missing }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> WaterSystemIndex {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { throw LoadError.malformed }
        var areas: [WaterSystemArea] = []
        areas.reserveCapacity(features.count)
        for feature in features {
            guard let props = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] as? [Any] else { continue }
            let polygons: [GeoPolygon]
            switch type {
            case "Polygon": polygons = [polygon(coordinates)].compactMap { $0 }
            case "MultiPolygon": polygons = coordinates.compactMap { ($0 as? [Any]).flatMap(polygon) }
            default: continue
            }
            guard !polygons.isEmpty else { continue }
            areas.append(WaterSystemArea(
                pwsid: props["pwsid"] as? String ?? "",
                name: props["name"] as? String ?? "",
                population: (props["population"] as? NSNumber)?.intValue ?? 0,
                sourced: props["sourced"] as? Bool ?? false,
                polygons: polygons,
                boundingBox: BoundingBox(points: polygons.flatMap(\.outer))))
        }
        return WaterSystemIndex(areas: areas)
    }

    private static func polygon(_ rings: [Any]) -> GeoPolygon? {
        let parsed: [[GeoPoint]] = rings.compactMap { ring in
            (ring as? [[Double]])?.compactMap { $0.count >= 2 ? GeoPoint(lon: $0[0], lat: $0[1]) : nil }
        }
        return parsed.first.map { _ in GeoPolygon(rings: parsed) }
    }

    /// Every system whose area contains the point: boundaries drawn by the utility first, then larger systems.
    func systems(containingLatitude lat: Double, longitude lon: Double) -> [WaterSystemArea] {
        let p = GeoPoint(lon: lon, lat: lat)
        return areas.filter { $0.contains(p) }.sorted { a, b in
            if a.sourced != b.sourced { return a.sourced }
            return a.population > b.population
        }
    }
}

/// The app's guess at the home's water source. Only ever a hint: the user's confirmed answer is what counts.
nonisolated struct WaterSourceEstimate: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Inside a boundary drawn by the utility or state.
        case likelyCity
        /// Inside an EPA-modeled boundary.
        case probablyCity
        /// Outside every public water system.
        case likelyWell
        /// No address, or the lookup couldn't run.
        case unknown
    }

    enum Confidence: String, Codable, Sendable { case high, medium, none }

    var kind: Kind
    var systemName: String?
    var pwsid: String?
    var populationServed: Int?
    /// Private wells tested in the home's census tract (NCWELL, 1998–2019): a supporting signal for wells.
    var tractWellsTested: Int?

    var confidence: Confidence {
        switch kind {
        case .likelyCity: .high
        case .probablyCity, .likelyWell: .medium
        case .unknown: .none
        }
    }

    /// The source this estimate suggests, for preselecting the confirm step.
    var suggestedSource: WaterSource? {
        switch kind {
        case .likelyCity, .probablyCity: .publicWater
        case .likelyWell: .privateWell
        case .unknown: nil
        }
    }

    var headline: String {
        let name = systemName ?? String(localized: "your local utility")
        return switch kind {
        case .likelyCity: String(localized: "Likely city water from \(name)")
        case .probablyCity: String(localized: "Probably city water from \(name)")
        case .likelyWell: String(localized: "Likely a private well")
        case .unknown: String(localized: "We can't guess without an address")
        }
    }

    static let storageKey = "waterSourceEstimate"

    static func estimate(latitude: Double?, longitude: Double?, index: WaterSystemIndex?,
                         tractWellsTested: Int? = nil) -> WaterSourceEstimate {
        guard let latitude, let longitude, let index else { return WaterSourceEstimate(kind: .unknown) }
        if let system = index.systems(containingLatitude: latitude, longitude: longitude).first {
            return WaterSourceEstimate(kind: system.sourced ? .likelyCity : .probablyCity,
                                       systemName: system.displayName, pwsid: system.pwsid,
                                       populationServed: system.population, tractWellsTested: tractWellsTested)
        }
        return WaterSourceEstimate(kind: .likelyWell, tractWellsTested: tractWellsTested)
    }
}

/// The home's address and location. On this phone only.
nonisolated struct HomeLocation: Codable, Equatable, Sendable {
    var address: String
    var latitude: Double
    var longitude: Double
    var county: String?

    static let storageKey = "homeLocation"
}
