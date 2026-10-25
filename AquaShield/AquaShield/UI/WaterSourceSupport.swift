//
//  WaterSourceSupport.swift
//  AquaShield
//
//  Wording and behavior that depend on where the home's water comes from. Well owners see
//  "My Well" and well-care tasks; city/county water users see "My Water" and utility guidance.
//

import SwiftData
import SwiftUI

extension WaterSource {
    /// Report Quest streak and badges.
    var careTitle: String { isWell ? String(localized: "Well Care") : String(localized: "Water Care") }

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
