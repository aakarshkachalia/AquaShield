//
//  WaterSourceSupport.swift
//  ClearWellNC
//
//  Wording and behavior that depend on where the home's water comes from. Well owners see
//  "My Well" and well-care tasks; city/county water users see "My Water" and utility guidance.
//

import SwiftData
import SwiftUI

extension WaterSource {
    /// The real household's answer, saved during onboarding (or changed later). Unknown counts as "Not sure".
    /// Views use `AppSettings.waterSource`, which follows Demo Mode.
    static var current: WaterSource {
        WaterSource(rawValue: UserDefaults.standard.string(forKey: AppSettings.realWaterSourceKey) ?? "") ?? .notSure
    }

    /// Tab and screen title.
    var homeTitle: String {
        isWell ? String(localized: "My Well") : String(localized: "My Water")
    }

    var recordTitle: String {
        isWell ? String(localized: "Well Record") : String(localized: "Water Record")
    }

    var scoreTitle: String {
        isWell ? String(localized: "Well Health Score") : String(localized: "Water Health Score")
    }

    var saveLocationTitle: String {
        isWell ? String(localized: "Save as My Well") : String(localized: "Save as My Home")
    }

    var savedLocationTitle: String {
        isWell ? String(localized: "Saved as My Well") : String(localized: "Saved as My Home")
    }

    /// Name used in settings and on the dashboard.
    var settingName: String {
        switch self {
        case .privateWell: String(localized: "Private well")
        case .publicWater: String(localized: "City or public water")
        case .both: String(localized: "Both a well and city water")
        case .notSure: String(localized: "Not sure")
        }
    }

    var symbol: String {
        switch self {
        case .privateWell: "drop.circle.fill"
        case .publicWater: "building.2.fill"
        case .both: "square.split.2x1.fill"
        case .notSure: "questionmark.circle.fill"
        }
    }

    /// Tab icon.
    var tabSymbol: String { isWell ? "drop.fill" : "spigot.fill" }
}
