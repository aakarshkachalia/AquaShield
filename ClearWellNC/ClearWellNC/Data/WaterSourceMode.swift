//
//  WaterSourceMode.swift
//  ClearWellNC
//
//  Where the home's water comes from, and the one place that decides what each answer shows.
//  `AppSettings.waterSource` is the single stored value (scoped for Demo Mode); views and logic ask the
//  properties here instead of comparing cases themselves.
//

import SwiftUI

nonisolated enum WaterSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case privateWell
    case publicWater
    /// A well for some uses and city water for others (or two homes).
    case both
    case notSure

    var id: String { rawValue }

    /// Stored values from older versions (and anything unreadable) fall back to "Not sure".
    init(storedValue: String?) {
        self = storedValue.flatMap(WaterSource.init(rawValue:)) ?? .notSure
    }

    var hasWell: Bool { self == .privateWell || self == .both }
    var hasUtility: Bool { self == .publicWater || self == .both }

    /// Well content (testing calendar, shock chlorination, well flooding, well programs). "Not sure" sees it
    /// too, worded with "if you have a well", until the user picks.
    var showsWellCare: Bool { self != .publicWater }

    /// City content (utility report, lead service lines, byproducts, boil-water advisories).
    var showsCityContent: Bool { self != .privateWell }

    /// Titles say "My Well" only when the home is well-only.
    var isWell: Bool { self == .privateWell }

    /// Topics each answer sees. Shared topics are always on; Learn is always fully browsable.
    var topics: Set<WaterTopic> {
        var set = WaterTopic.shared
        if showsWellCare { set.formUnion(WaterTopic.well) }
        if showsCityContent { set.formUnion(WaterTopic.city) }
        return set
    }

    /// The tests that matter most for this source, worst-case first.
    var keyContaminants: [ContaminantID] {
        let well: [ContaminantID] = [.totalColiform, .eColi, .nitrate, .arsenic, .uranium, .radon, .manganese]
        let city: [ContaminantID] = [.lead, .copper, .pfoa, .pfos]
        switch self {
        case .privateWell: return well
        case .publicWater: return city
        case .both, .notSure:
            var combined = well
            for id in city where !combined.contains(id) { combined.append(id) }
            return combined
        }
    }
}

nonisolated enum WaterTopic: String, CaseIterable, Sendable {
    // Well
    case wellTestingCalendar, shockChlorination, wellFlooding, wellPrograms
    // City
    case utilityReport, leadServiceLine, disinfectionByproducts, boilWaterAdvisory
    // Shared
    case pfas, filters, score, household, shower, learn

    static let well: Set<WaterTopic> = [.wellTestingCalendar, .shockChlorination, .wellFlooding, .wellPrograms]
    static let city: Set<WaterTopic> = [.utilityReport, .leadServiceLine, .disinfectionByproducts, .boilWaterAdvisory]
    static let shared: Set<WaterTopic> = [.pfas, .filters, .score, .household, .shower, .learn]
}

extension WaterSource {
    /// Onboarding and Settings answer text.
    var choiceTitle: String {
        switch self {
        case .privateWell: String(localized: "Private well")
        case .publicWater: String(localized: "City or public water")
        case .both: String(localized: "Both")
        case .notSure: String(localized: "Not sure")
        }
    }

    var choiceHint: String {
        switch self {
        case .privateWell: String(localized: "There's a well head or pressure tank, and no water bill.")
        case .publicWater: String(localized: "You get a water bill from a city, county or company.")
        case .both: String(localized: "A well for some things, city water for others.")
        case .notSure: String(localized: "You can change this later in Settings.")
        }
    }
}
