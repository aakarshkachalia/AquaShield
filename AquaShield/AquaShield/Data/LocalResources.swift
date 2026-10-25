//
//  LocalResources.swift
//  AquaShield
//
//  Live Apple Maps search for water help near the saved location: testing labs, filter dealers,
//  plumbers, well services and hardware stores. Nothing here is curated or endorsed.
//

import CoreLocation
import MapKit
import Observation

enum ResourceCategory: String, CaseIterable, Identifiable {
    case testingLabs
    case filterDealers
    case plumbers
    case wellServices
    case hardwareStores

    var id: String { rawValue }

    var title: String {
        switch self {
        case .testingLabs: String(localized: "Testing labs")
        case .filterDealers: String(localized: "Filters & treatment")
        case .plumbers: String(localized: "Plumbers")
        case .wellServices: String(localized: "Well services")
        case .hardwareStores: String(localized: "Hardware stores")
        }
    }

    var symbol: String {
        switch self {
        case .testingLabs: "testtube.2"
        case .filterDealers: "line.3.horizontal.decrease.circle"
        case .plumbers: "wrench.adjustable"
        case .wellServices: "hammer"
        case .hardwareStores: "cart"
        }
    }

    /// What to search Apple Maps for. Kept in English: Maps matches business categories best that way.
    var query: String {
        switch self {
        case .testingLabs: "water testing laboratory"
        case .filterDealers: "water treatment filtration"
        case .plumbers: "plumber"
        case .wellServices: "well drilling pump service"
        case .hardwareStores: "hardware store"
        }
    }

    /// Why someone would call this kind of place.
    var hint: String {
        switch self {
        case .testingLabs: String(localized: "Ask whether the lab is certified by the State of North Carolina for drinking water.")
        case .filterDealers: String(localized: "Bring your lab results so they can match a system to what's in your water.")
        case .plumbers: String(localized: "For lead pipes, old fixtures, or installing an under-sink filter.")
        case .wellServices: String(localized: "For well inspections, pump problems, cracked caps or shock chlorination.")
        case .hardwareStores: String(localized: "For pitcher, faucet and fridge filters and replacement cartridges.")
        }
    }

    static func available(for source: WaterSource) -> [ResourceCategory] {
        source.showsWellCare ? allCases : allCases.filter { $0 != .wellServices }
    }
}

struct LocalPlace: Identifiable {
    let id = UUID()
    let item: MKMapItem
    let name: String
    let address: String?
    let phone: String?
    let website: URL?
    let coordinate: CLLocationCoordinate2D
    /// Meters from the search center.
    let distance: CLLocationDistance

    var callURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    var distanceText: String {
        Measurement(value: distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

@MainActor
@Observable
final class LocalResourceSearch {
    enum State {
        case idle
        case loading
        case loaded([LocalPlace])
        case failed
    }

    private(set) var state: State = .idle
    private var cache: [String: [LocalPlace]] = [:]

    /// Search radius around the home: about 25 miles, which covers a county.
    static let radius: CLLocationDistance = 40_000

    func search(_ category: ResourceCategory, near center: CLLocationCoordinate2D) async {
        let key = "\(category.rawValue)@\(center.latitude),\(center.longitude)"
        if let cached = cache[key] {
            state = .loaded(cached)
            return
        }
        state = .loading

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: Self.radius * 2,
                                            longitudinalMeters: Self.radius * 2)
        request.regionPriority = .required

        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let places = response.mapItems.compactMap { item -> LocalPlace? in
                let location = item.location
                let distance = location.distance(from: origin)
                guard distance <= Self.radius, let name = item.name else { return nil }
                return LocalPlace(item: item, name: name, address: item.address?.shortAddress,
                                  phone: item.phoneNumber, website: item.url,
                                  coordinate: location.coordinate, distance: distance)
            }
            .sorted { $0.distance < $1.distance }
            cache[key] = places
            state = .loaded(places)
        } catch {
            // MapKit reports "no results" as an error too.
            if (error as? MKError)?.code == .placemarkNotFound {
                cache[key] = []
                state = .loaded([])
            } else {
                state = .failed
            }
        }
    }
}
