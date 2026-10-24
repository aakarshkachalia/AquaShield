//
//  NetworkFeature.swift
//  ClearWellNC
//
//  The only features that send anything off the phone. Each is off until the user agrees, and Settings >
//  Privacy & Sources lists exactly what each one sends. Health and household data never leaves the device.
//

import Foundation

nonisolated enum NetworkFeature: String, Codable, CaseIterable, Sendable, Identifiable {
    case stormAlerts, helpNearYou, addressLookup

    var id: Self { self }

    var title: String {
        switch self {
        case .stormAlerts: String(localized: "Storm and flood alerts")
        case .helpNearYou: String(localized: "Help near you")
        case .addressLookup: String(localized: "Address lookup")
        }
    }

    var symbol: String {
        switch self {
        case .stormAlerts: "cloud.bolt.rain.fill"
        case .helpNearYou: "mappin.and.ellipse"
        case .addressLookup: "magnifyingglass"
        }
    }

    /// One-time explanation shown before turning it on.
    var explanation: String {
        switch self {
        case .stormAlerts:
            String(localized: "Checks the National Weather Service for flood and hurricane alerts near your home.")
        case .helpNearYou:
            String(localized: "Searches Apple Maps for labs, plumbers and filter dealers near you.")
        case .addressLookup:
            String(localized: "Uses Apple to turn an address into a spot on the map, so we can find your area's well risk.")
        }
    }

    /// Exactly what is sent, and to whom.
    var outboundRequest: (recipient: String, sends: String) {
        switch self {
        case .stormAlerts:
            (String(localized: "National Weather Service (api.weather.gov)"),
             String(localized: "Your saved location, rounded to about 1 km (2 decimal places)."))
        case .helpNearYou:
            (String(localized: "Apple Maps"),
             String(localized: "A search word (\"water testing lab\") and the map area you're looking at."))
        case .addressLookup:
            (String(localized: "Apple (geocoder)"),
             String(localized: "The address or place name you type."))
        }
    }

    var fallback: String {
        switch self {
        case .stormAlerts: String(localized: "Without it, check weather.gov or local news during storms.")
        case .helpNearYou: String(localized: "Without it, use the county health department list in Get Help.")
        case .addressLookup: String(localized: "Without it, pick your county from the list instead.")
        }
    }

    /// NWS gets coordinates at the coarsest precision that still finds the right alert zone.
    static func coarse(_ coordinate: Double) -> Double {
        (coordinate * 100).rounded() / 100
    }
}

extension AppSettings {
    /// Run once per install. People who used these features before opt-ins existed (onboarding already
    /// done) keep them, so an update never silently turns off alerts they relied on. New installs start
    /// with none. Only the real scope is migrated; demo personas start with none.
    static func migrateNetworkOptIns(_ defaults: UserDefaults) {
        let marker = "settings.networkOptInsMigrated"
        guard !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)
        let key = realScope + "networkOptIns"
        guard defaults.object(forKey: key) == nil else { return }
        let granted: Set<NetworkFeature> = defaults.bool(forKey: StorageKey.hasOnboarded) ? Set(NetworkFeature.allCases) : []
        defaults.set(try? JSONEncoder().encode(granted), forKey: key)
    }

    func isOptedIn(_ feature: NetworkFeature) -> Bool { networkOptIns.contains(feature) }
}
