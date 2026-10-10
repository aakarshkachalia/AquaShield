//
//  TractDatabase.swift
//  ClearWellNC
//

import CoreLocation
import Foundation
import Observation

// MARK: - meta.json

nonisolated struct ModelScore: Decodable, Sendable, Identifiable {
    let contaminant: Contaminant
    let countyAverage: Double
    let neighborsOnly: Double
    let model: Double
    let modelUnseenCounty: Double
    /// Range of the unseen-county stress test across folds. Optional so older meta.json files still decode.
    let unseenCountyMin: Double?
    let unseenCountyMax: Double?

    var id: Contaminant { contaminant }

    enum CodingKeys: String, CodingKey {
        case contaminant
        case countyAverage = "county_average"
        case neighborsOnly = "neighbors_only"
        case model = "MODEL_unseen_tract"
        case modelUnseenCounty = "model_unseen_county"
        case unseenCountyMin = "unseen_county_min"
        case unseenCountyMax = "unseen_county_max"
    }

    /// 0.3619 → "36.2%"
    static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }

    /// Average with its range when available, e.g. "36.2% (32.8–41.5%)".
    var stressTestText: String {
        let average = Self.percent(modelUnseenCounty)
        guard let low = unseenCountyMin, let high = unseenCountyMax else { return average }
        let lowNumber = (low * 100).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(average) (\(lowNumber)–\(Self.percent(high)))")
    }

    /// Spoken form of `stressTestText` for VoiceOver.
    var stressTestAccessibilityText: String {
        let average = Self.percent(modelUnseenCounty)
        guard let low = unseenCountyMin, let high = unseenCountyMax else { return average }
        return String(localized: "\(average), ranging from \(Self.percent(low)) to \(Self.percent(high))")
    }
}

nonisolated struct Meta: Decodable, Sendable {
    let generated: String
    let statewide: [String: Double]
    let dataSource: String
    let modelScores: [ModelScore]

    enum CodingKeys: String, CodingKey {
        case generated, statewide
        case dataSource = "data_source"
        case modelScores = "model_scores"
    }

    func statewideRate(for contaminant: Contaminant) -> Double {
        statewide[contaminant.rawValue] ?? 0
    }
}

// MARK: - GeoJSON decoding

/// Minimal Codable mirror of tracts.geojson. Only Polygon and MultiPolygon geometries occur.
private nonisolated struct FeatureCollection: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let properties: Properties
        let geometry: Geometry
    }

    struct Properties: Decodable {
        let fips: String
        let county: String
        let arsenic: [Double]
        let manganese: [Double]
        let nitrate: [Double]
        let lead: [Double]

        func values(for c: Contaminant) -> [Double] {
            switch c {
            case .arsenic: arsenic
            case .manganese: manganese
            case .nitrate: nitrate
            case .lead: lead
            }
        }
    }

    struct Geometry: Decodable {
        /// Each polygon is a list of rings; each ring a list of [lon, lat] positions.
        let polygons: [[[[Double]]]]

        enum CodingKeys: String, CodingKey { case type, coordinates }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .type) {
            case "Polygon":
                polygons = [try c.decode([[[Double]]].self, forKey: .coordinates)]
            case "MultiPolygon":
                polygons = try c.decode([[[[Double]]]].self, forKey: .coordinates)
            case let other:
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: c, debugDescription: "Unsupported geometry type \(other)")
            }
        }
    }
}

// MARK: - Database

enum TractDataError: Error {
    case missingResource(String)
    case badContaminantArray(fips: String)
}

/// All tracts held in memory, plus meta.json. Immutable and safe to share across threads.
nonisolated struct TractDatabase: Sendable {
    let tracts: [Tract]
    let meta: Meta
    private let byFIPS: [String: Int]

    init(tracts: [Tract], meta: Meta) {
        self.tracts = tracts
        self.meta = meta
        var index: [String: Int] = [:]
        for (i, t) in tracts.enumerated() { index[t.fips] = i }
        byFIPS = index
    }

    func tract(fips: String) -> Tract? {
        byFIPS[fips].map { tracts[$0] }
    }

    /// The tract containing a coordinate, or nil if it is outside North Carolina.
    func tract(containing coordinate: CLLocationCoordinate2D) -> Tract? {
        tracts.first { $0.contains(coordinate) }
    }

    /// Loads tracts.geojson and meta.json from the bundle. Slow (parses several MB); call off the main thread.
    static func load(from bundle: Bundle = .main) throws -> TractDatabase {
        guard let geoURL = bundle.url(forResource: "tracts", withExtension: "geojson") else {
            throw TractDataError.missingResource("tracts.geojson")
        }
        guard let metaURL = bundle.url(forResource: "meta", withExtension: "json") else {
            throw TractDataError.missingResource("meta.json")
        }
        let meta = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: metaURL))
        let tracts = try parseTracts(Data(contentsOf: geoURL))
        return TractDatabase(tracts: tracts, meta: meta)
    }

    static func parseTracts(_ data: Data) throws -> [Tract] {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        return try collection.features.map { feature in
            let props = feature.properties
            var values: [Contaminant: ContaminantData] = [:]
            for c in Contaminant.allCases {
                let v = props.values(for: c)
                guard v.count == 3 else { throw TractDataError.badContaminantArray(fips: props.fips) }
                values[c] = ContaminantData(estimate: v[0], tests: Int(v[1]), aboveLimit: Int(v[2]))
            }
            let polygons = feature.geometry.polygons.map { rings in
                GeoPolygon(rings: rings.map { ring in
                    ring.compactMap { pos in pos.count >= 2 ? GeoPoint(lon: pos[0], lat: pos[1]) : nil }
                })
            }
            let box = BoundingBox(points: polygons.lazy.flatMap(\.outer))
            return Tract(fips: props.fips, countyFIPS: props.county, data: values,
                         polygons: polygons, boundingBox: box)
        }
    }
}

// MARK: - App-facing store

/// Loads the bundled data once at launch on a background task and publishes it to the UI.
@MainActor
@Observable
final class TractStore {
    enum State {
        case loading
        case loaded(TractDatabase)
        case failed(String)
    }

    private(set) var state: State = .loading

    var database: TractDatabase? {
        if case .loaded(let db) = state { return db }
        return nil
    }

    func load() async {
        guard database == nil else { return }
        do {
            let db = try await Task.detached(priority: .userInitiated) {
                try TractDatabase.load()
            }.value
            state = .loaded(db)
        } catch {
            state = .failed(String(localized: "The built-in well data could not be loaded."))
        }
    }
}
