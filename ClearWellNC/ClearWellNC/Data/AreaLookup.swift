//
//  AreaLookup.swift
//  ClearWellNC
//

import CoreLocation
import Foundation

/// A tract the user picked, by address, current location, or (later) the map.
struct AreaSelection: Identifiable, Hashable {
    let id = UUID()
    let tract: Tract
    let coordinate: CLLocationCoordinate2D
    /// What to call this place, e.g. "123 Main St, Monroe". Held in memory only until the user saves My Well.
    let placeName: String

    static func == (lhs: AreaSelection, rhs: AreaSelection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum AreaLookupError: LocalizedError {
    case emptyAddress
    case addressNotFound
    case outsideNC
    case network
    case locationDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            String(localized: "Type an address, city or ZIP code first.")
        case .addressNotFound:
            String(localized: "We couldn't find that address. Try including the town and \"NC\", for example \"123 Main St, Monroe, NC\".")
        case .outsideNC:
            String(localized: "That location is outside North Carolina. ClearWell NC only has well data for North Carolina.")
        case .network:
            String(localized: "We couldn't look up that address. Check your internet connection and try again.")
        case .locationDenied:
            String(localized: "Location access is off for ClearWell NC. You can turn it on in Settings, or type an address instead.")
        case .locationUnavailable:
            String(localized: "We couldn't find your location right now. Try again, or type an address instead.")
        }
    }
}

enum AreaLookup {
    /// Rough circle around North Carolina, used to bias geocoding toward NC results.
    private static let ncRegion = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: 35.5, longitude: -79.4), radius: 450_000, identifier: "NC")

    static func lookup(address: String, in db: TractDatabase) async throws -> AreaSelection {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AreaLookupError.emptyAddress }

        let placemarks: [CLPlacemark]
        do {
            placemarks = try await CLGeocoder().geocodeAddressString(trimmed, in: ncRegion, preferredLocale: nil)
        } catch let error as CLError where error.code == .geocodeFoundNoResult || error.code == .geocodeFoundPartialResult {
            throw AreaLookupError.addressNotFound
        } catch {
            throw AreaLookupError.network
        }
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw AreaLookupError.addressNotFound
        }
        return try selection(at: location.coordinate, placeName: name(for: placemark) ?? trimmed, in: db)
    }

    static func lookupCurrentLocation(using fetcher: LocationFetcher, in db: TractDatabase) async throws -> AreaSelection {
        let location: CLLocation
        do {
            location = try await fetcher.currentLocation()
        } catch LocationFetcher.LocationError.denied {
            throw AreaLookupError.locationDenied
        } catch {
            throw AreaLookupError.locationUnavailable
        }
        return try selection(at: location.coordinate, placeName: String(localized: "Your current location"), in: db)
    }

    static func selection(at coordinate: CLLocationCoordinate2D, placeName: String,
                          in db: TractDatabase) throws -> AreaSelection {
        guard let tract = db.tract(containing: coordinate) else { throw AreaLookupError.outsideNC }
        return AreaSelection(tract: tract, coordinate: coordinate, placeName: placeName)
    }

    private static func name(for placemark: CLPlacemark) -> String? {
        let parts = [placemark.name, placemark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
