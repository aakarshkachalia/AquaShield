//
//  AppState.swift
//  ClearWellNC
//
//  App-wide navigation (AppRouter) and on-device settings (AppSettings).
//

import Foundation
import Observation
import SwiftUI

/// UserDefaults keys for small on-device preferences.
enum StorageKey {
    static let hasOnboarded = "hasOnboarded"
    static let waterSource = "waterSource"
    static let infantInHome = "infantInHome"
}

enum WaterSource: String, CaseIterable, Identifiable {
    case privateWell
    case publicWater
    case notSure

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .privateWell: "Yes"
        case .publicWater: "No, city or county water"
        case .notSure: "Not sure"
        }
    }
}

// MARK: - Navigation

/// Exactly four tabs, in priority order.
enum AppTab: Hashable {
    case home, myWater, help, learn
}

/// What Help Finder should show first when opened from elsewhere.
enum HelpFilter: Hashable, Sendable {
    case all
    case testing
    case payToFix
    case emergency
    /// Programs relevant to one contaminant over its limit (from the safety override).
    case contaminant(ContaminantID)
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var showingScanner = false
    var showingRiskCheck = false
    /// Set before switching to the Get Help tab; Help Finder applies it once.
    var pendingHelpFilter: HelpFilter?

    func openHelp(_ filter: HelpFilter = .all) {
        pendingHelpFilter = filter
        selectedTab = .help
    }
}

// MARK: - Settings

/// Small on-device settings. Values that describe "your household" are kept separately while Demo
/// Mode is on, so demo personas never overwrite real answers.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    // Global
    var demoEnabled: Bool { didSet { defaults.set(demoEnabled, forKey: Keys.demoEnabled); reloadScoped() } }
    var demoPersona: DemoPersona { didSet { defaults.set(demoPersona.rawValue, forKey: Keys.demoPersona); reloadScoped() } }

    // Scoped (real vs. demo)
    var county: String? { didSet { saveScoped(county, Keys.county) } }
    var pregnantInHome: Bool { didSet { saveScoped(pregnantInHome, Keys.pregnant) } }
    var lowIncome: Bool { didSet { saveScoped(lowIncome, Keys.lowIncome) } }

    private enum Keys {
        static let demoEnabled = "settings.demoEnabled"
        static let demoPersona = "settings.demoPersona"
        static let county = "county"
        static let pregnant = "pregnantInHome"
        static let lowIncome = "lowIncome"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        demoEnabled = defaults.bool(forKey: Keys.demoEnabled)
        demoPersona = DemoPersona(rawValue: defaults.string(forKey: Keys.demoPersona) ?? "") ?? .neverTested
        county = nil
        pregnantInHome = false
        lowIncome = false
        reloadScoped()
    }

    /// "settings.real." or "settings.demo.<persona>." prefix for household values.
    private var scope: String {
        demoEnabled ? "settings.demo.\(demoPersona.rawValue)." : "settings.real."
    }

    func scopedKey(_ key: String) -> String { scope + key }

    private var isReloading = false

    private func reloadScoped() {
        isReloading = true
        defer { isReloading = false }
        let storedCounty = defaults.string(forKey: scopedKey(Keys.county))
        county = storedCounty ?? (demoEnabled ? demoPersona.county : nil)
        pregnantInHome = defaults.bool(forKey: scopedKey(Keys.pregnant))
        lowIncome = defaults.bool(forKey: scopedKey(Keys.lowIncome))
        scopedRevision += 1
    }

    private func saveScoped(_ value: Any?, _ key: String) {
        guard !isReloading else { return }
        if let value { defaults.set(value, forKey: scopedKey(key)) } else { defaults.removeObject(forKey: scopedKey(key)) }
    }

    /// Bumped whenever scoped values reload (Demo Mode on/off, persona change), so dependents can refresh.
    private(set) var scopedRevision = 0

    /// The county to use: the one chosen in settings or onboarding, else the saved home's county.
    func effectiveCounty(savedWellCounty: String?) -> String? {
        county ?? savedWellCounty
    }

    // MARK: Generic scoped storage for feature data (risk answers, checklists, saved programs)

    func data(forScopedKey key: String) -> Data? { defaults.data(forKey: scopedKey(key)) }
    func setData(_ data: Data?, forScopedKey key: String) {
        if let data { defaults.set(data, forKey: scopedKey(key)) } else { defaults.removeObject(forKey: scopedKey(key)) }
    }

    /// Removes every real (non-demo) household value. Used by "Reset all data".
    func resetRealData() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("settings.real.") {
            defaults.removeObject(forKey: key)
        }
        reloadScoped()
    }
}
