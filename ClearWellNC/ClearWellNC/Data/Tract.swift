//
//  Tract.swift
//  ClearWellNC
//

import CoreLocation
import Foundation

/// A longitude/latitude pair as stored in GeoJSON.
nonisolated struct GeoPoint: Sendable, Hashable {
    let lon: Double
    let lat: Double
}

nonisolated struct BoundingBox: Sendable, Hashable {
    var minLon: Double
    var minLat: Double
    var maxLon: Double
    var maxLat: Double

    init(points: some Sequence<GeoPoint>) {
        var box = BoundingBox(minLon: .infinity, minLat: .infinity, maxLon: -.infinity, maxLat: -.infinity)
        for p in points {
            box.minLon = min(box.minLon, p.lon)
            box.maxLon = max(box.maxLon, p.lon)
            box.minLat = min(box.minLat, p.lat)
            box.maxLat = max(box.maxLat, p.lat)
        }
        self = box
    }

    init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    func contains(_ p: GeoPoint) -> Bool {
        p.lon >= minLon && p.lon <= maxLon && p.lat >= minLat && p.lat <= maxLat
    }
}

/// One polygon: the first ring is the outer boundary, any further rings are holes.
nonisolated struct GeoPolygon: Sendable {
    let rings: [[GeoPoint]]

    var outer: [GeoPoint] { rings.first ?? [] }
    var holes: ArraySlice<[GeoPoint]> { rings.dropFirst() }

    /// Inside the outer ring and not inside any hole.
    func contains(_ p: GeoPoint) -> Bool {
        guard Self.ring(outer, contains: p) else { return false }
        return !holes.contains { Self.ring($0, contains: p) }
    }

    /// Even-odd ray casting: count crossings of a horizontal ray from `p` toward +longitude.
    static func ring(_ ring: [GeoPoint], contains p: GeoPoint) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.lat > p.lat) != (b.lat > p.lat) {
                let crossLon = (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon
                if p.lon < crossLon { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

/// Model output and observed test counts for one contaminant in one tract.
nonisolated struct ContaminantData: Sendable, Hashable {
    /// Estimated share of wells above the limit (0–1).
    let estimate: Double
    /// Number of wells tested in the tract.
    let tests: Int
    /// Number of tested wells above the limit.
    let aboveLimit: Int
}

nonisolated struct Tract: Sendable, Identifiable {
    let fips: String
    let countyFIPS: String
    let data: [Contaminant: ContaminantData]
    let polygons: [GeoPolygon]
    let boundingBox: BoundingBox

    var id: String { fips }

    var countyName: String? { CountyNames.name(forFIPS: countyFIPS) }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let p = GeoPoint(lon: coordinate.longitude, lat: coordinate.latitude)
        guard boundingBox.contains(p) else { return false }
        return polygons.contains { $0.contains(p) }
    }
}
