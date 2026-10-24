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
    /// Legacy global keys. The values now live in AppSettings (real/demo scoped); migrated once at launch.
    static let waterSource = "waterSource"
    static let infantInHome = "infantInHome"
}

// WaterSource lives in Data/WaterSourceMode.swift.

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
    /// Opens Household on the Home tab (from the Risk Check results).
    var showingHousehold = false
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
    /// Set only when onboarding finishes; cleared only by Settings > Reset app. Not scoped: Demo Mode and
    /// UI-test flags never change the real value (UI tests use their own defaults suite).
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Self.onboardingKey) } }
    static let onboardingKey = "settings.hasCompletedOnboarding"

    var demoEnabled: Bool { didSet { defaults.set(demoEnabled, forKey: Keys.demoEnabled); reloadScoped() } }
    var demoPersona: DemoPersona { didSet { defaults.set(demoPersona.rawValue, forKey: Keys.demoPersona); reloadScoped() } }

    // Scoped (real vs. demo)
    var waterSource: WaterSource {
        didSet {
            Wording.source = waterSource
            saveScoped(waterSource.rawValue, Keys.waterSource)
        }
    }
    var county: String? { didSet { saveScoped(county, Keys.county) } }
    var pregnantInHome: Bool { didSet { saveScoped(pregnantInHome, Keys.pregnant) } }
    var infantInHome: Bool { didSet { saveScoped(infantInHome, Keys.infant) } }
    var lowIncome: Bool { didSet { saveScoped(lowIncome, Keys.lowIncome) } }
    /// Help programs the user saved.
    var savedProgramIDs: Set<String> {
        didSet {
            guard !isReloading else { return }
            setData(try? JSONEncoder().encode(savedProgramIDs), forScopedKey: "savedPrograms")
        }
    }
    /// Storm Mode checklist steps that are done.
    var stormChecked: Set<Int> {
        didSet {
            guard !isReloading else { return }
            setData(try? JSONEncoder().encode(stormChecked), forScopedKey: "stormChecklist")
        }
    }
    /// Latest Risk Check answers (used by Help Finder and the Home flood card).
    var riskAnswers: RiskCheckAnswers? {
        didSet {
            guard !isReloading else { return }
            setData(riskAnswers.flatMap { try? JSONEncoder().encode($0) }, forScopedKey: RiskCheckAnswers.storageKey)
        }
    }

    /// City/public water: values copied from the utility's yearly report.
    var utilityReport: UtilityReport {
        didSet {
            guard !isReloading else { return }
            setCodable(utilityReport.isEmpty ? nil : utilityReport, forScopedKey: UtilityReport.storageKey)
        }
    }

    /// The home's address and location (on this phone only).
    var homeLocation: HomeLocation? {
        didSet { guard !isReloading else { return }; setCodable(homeLocation, forScopedKey: HomeLocation.storageKey) }
    }
    /// The app's guess from the address. A hint only: `waterSource` is the user's confirmed answer.
    var waterSourceEstimate: WaterSourceEstimate? {
        didSet { guard !isReloading else { return }; setCodable(waterSourceEstimate, forScopedKey: WaterSourceEstimate.storageKey) }
    }
    /// Filters the user entered from a certifier listing.
    var customFilterProducts: [FilterProduct] {
        didSet { guard !isReloading else { return }; setCodable(customFilterProducts, forScopedKey: "customFilterProducts") }
    }
    /// Household members (nickname only).
    var householdMembers: [HouseholdMember] {
        didSet { guard !isReloading else { return }; setCodable(householdMembers, forScopedKey: "householdMembers") }
    }
    var homeProfile: HomeProfile {
        didSet { guard !isReloading else { return }; setCodable(homeProfile, forScopedKey: HomeProfile.storageKey) }
    }
    /// Flood, infant and boil-water modes the user turned on.
    var activeModes: Set<WaterMode> {
        didSet { guard !isReloading else { return }; setCodable(activeModes, forScopedKey: "activeModes") }
    }
    /// Features that send data off the phone, each turned on only after the user agrees.
    var networkOptIns: Set<NetworkFeature> {
        didSet { guard !isReloading else { return }; setCodable(networkOptIns, forScopedKey: "networkOptIns") }
    }

    private enum Keys {
        static let demoEnabled = "settings.demoEnabled"
        static let demoPersona = "settings.demoPersona"
        static let waterSource = "waterSource"
        static let county = "county"
        static let pregnant = "pregnantInHome"
        static let infant = "infantInHome"
        static let lowIncome = "lowIncome"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Older versions kept this in "hasOnboarded" (AppStorage). Carry it over once.
        if defaults.object(forKey: Self.onboardingKey) == nil, defaults.bool(forKey: StorageKey.hasOnboarded) {
            defaults.set(true, forKey: Self.onboardingKey)
        }
        hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
        demoEnabled = defaults.bool(forKey: Keys.demoEnabled)
        demoPersona = DemoPersona(rawValue: defaults.string(forKey: Keys.demoPersona) ?? "") ?? .neverTested
        waterSource = .notSure
        county = nil
        pregnantInHome = false
        infantInHome = false
        lowIncome = false
        riskAnswers = nil
        utilityReport = UtilityReport()
        homeLocation = nil
        waterSourceEstimate = nil
        customFilterProducts = []
        householdMembers = []
        homeProfile = HomeProfile()
        activeModes = []
        networkOptIns = []
        savedProgramIDs = []
        stormChecked = []
        Self.migrateLegacyGlobals(defaults)
        Self.migrateNetworkOptIns(defaults)
        reloadScoped()
    }

    /// The infant flag and water source used to be global values, so Demo Mode could overwrite the real
    /// answers. Move them into the real household scope once.
    static func migrateLegacyGlobals(_ defaults: UserDefaults) {
        for (legacy, key) in [(StorageKey.infantInHome, Keys.infant), (StorageKey.waterSource, Keys.waterSource)] {
            guard let value = defaults.object(forKey: legacy) else { continue }
            if defaults.object(forKey: realScope + key) == nil {
                defaults.set(value, forKey: realScope + key)
            }
            defaults.removeObject(forKey: legacy)
        }
    }

    static let realScope = "settings.real."
    /// The real household's water source, for code that runs outside Demo Mode (reminders).
    nonisolated static let realWaterSourceKey = "settings.real.waterSource"

    /// "settings.real." or "settings.demo.<persona>." prefix for household values.
    private var scope: String {
        demoEnabled ? "settings.demo.\(demoPersona.rawValue)." : Self.realScope
    }

    func scopedKey(_ key: String) -> String { scope + key }

    private var isReloading = false

    private func reloadScoped() {
        isReloading = true
        defer { isReloading = false }
        // Demo personas all have private wells.
        waterSource = WaterSource(rawValue: defaults.string(forKey: scopedKey(Keys.waterSource)) ?? "")
            ?? (demoEnabled ? .privateWell : .notSure)
        let storedCounty = defaults.string(forKey: scopedKey(Keys.county))
        county = storedCounty ?? (demoEnabled ? demoPersona.county : nil)
        pregnantInHome = defaults.bool(forKey: scopedKey(Keys.pregnant))
        infantInHome = defaults.bool(forKey: scopedKey(Keys.infant))
        lowIncome = defaults.bool(forKey: scopedKey(Keys.lowIncome))
        riskAnswers = data(forScopedKey: RiskCheckAnswers.storageKey)
            .flatMap { try? JSONDecoder().decode(RiskCheckAnswers.self, from: $0) }
        utilityReport = codable(UtilityReport.self, forScopedKey: UtilityReport.storageKey) ?? UtilityReport()
        homeLocation = codable(HomeLocation.self, forScopedKey: HomeLocation.storageKey)
        waterSourceEstimate = codable(WaterSourceEstimate.self, forScopedKey: WaterSourceEstimate.storageKey)
        customFilterProducts = codable([FilterProduct].self, forScopedKey: "customFilterProducts") ?? []
        householdMembers = codable([HouseholdMember].self, forScopedKey: "householdMembers") ?? []
        homeProfile = codable(HomeProfile.self, forScopedKey: HomeProfile.storageKey) ?? HomeProfile()
        activeModes = codable(Set<WaterMode>.self, forScopedKey: "activeModes") ?? []
        networkOptIns = codable(Set<NetworkFeature>.self, forScopedKey: "networkOptIns") ?? []
        savedProgramIDs = data(forScopedKey: "savedPrograms")
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
        stormChecked = data(forScopedKey: "stormChecklist")
            .flatMap { try? JSONDecoder().decode(Set<Int>.self, from: $0) } ?? []
        scopedRevision += 1
    }

    private func saveScoped(_ value: Any?, _ key: String) {
        guard !isReloading else { return }
        if let value { defaults.set(value, forKey: scopedKey(key)) } else { defaults.removeObject(forKey: scopedKey(key)) }
    }

    /// Bumped whenever scoped values reload (Demo Mode on/off, persona change), so dependents can refresh.
    private(set) var scopedRevision = 0

    /// The real household's confirmed water source, read without an AppSettings instance (background reminder
    /// sync). Same stored value as `waterSource`; there is no other copy.
    static func realWaterSource(_ defaults: UserDefaults = UITestSupport.defaults) -> WaterSource {
        WaterSource(storedValue: defaults.string(forKey: realWaterSourceKey))
    }

    /// Read without an AppSettings instance (background reminder sync). Real scope only.
    static func realCustomFilterProducts(_ defaults: UserDefaults = UITestSupport.defaults) -> [FilterProduct] {
        defaults.data(forKey: realScope + "customFilterProducts")
            .flatMap { try? JSONDecoder().decode([FilterProduct].self, from: $0) } ?? []
    }

    static func realRetestEvents(_ defaults: UserDefaults = UITestSupport.defaults) -> [RetestEvent] {
        defaults.data(forKey: realScope + RetestEvent.storageKey)
            .flatMap { try? JSONDecoder().decode([RetestEvent].self, from: $0) } ?? []
    }

    /// Flooding, repairs or a change in taste, color or smell: each prompts a retest.
    var retestEvents: [RetestEvent] {
        get { _ = scopedRevision; return codable([RetestEvent].self, forScopedKey: RetestEvent.storageKey) ?? [] }
        set { setCodable(newValue, forScopedKey: RetestEvent.storageKey); scopedRevision += 1 }
    }

    /// The county to use: the one chosen in settings or onboarding, else the saved home's county.
    func effectiveCounty(savedWellCounty: String?) -> String? {
        county ?? savedWellCounty
    }

    // MARK: Generic scoped storage for feature data (risk answers, checklists, saved programs)

    func data(forScopedKey key: String) -> Data? { defaults.data(forKey: scopedKey(key)) }
    func setData(_ data: Data?, forScopedKey key: String) {
        if let data { defaults.set(data, forKey: scopedKey(key)) } else { defaults.removeObject(forKey: scopedKey(key)) }
    }

    /// JSON-coded value for the current scope. Nil when missing or unreadable (never crashes on old data).
    func codable<T: Decodable>(_ type: T.Type, forScopedKey key: String) -> T? {
        data(forScopedKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func setCodable<T: Encodable>(_ value: T?, forScopedKey key: String) {
        setData(value.flatMap { try? JSONEncoder().encode($0) }, forScopedKey: key)
    }

    // MARK: Drafts

    /// In-progress flow answers for the current scope, so demo drafts never mix with real ones.
    var drafts: DraftStore { DraftStore(defaults: defaults, prefix: scopedKey("draft.")) }

    /// Unsaved scanner photos for the current scope.
    var scanPhotos: ScanPhotoStore {
        ScanPhotoStore(scope: demoEnabled ? "demo-\(demoPersona.rawValue)" : "real")
    }

    /// Removes every real (non-demo) household value and draft, and shows onboarding again. Settings > Reset app.
    func resetRealData() {
        hasCompletedOnboarding = false
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.realScope) {
            defaults.removeObject(forKey: key)
        }
        ScanPhotoStore(scope: "real").deleteAll()
        reloadScoped()
    }
}
