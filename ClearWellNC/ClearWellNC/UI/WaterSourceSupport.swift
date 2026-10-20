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
    /// The answer saved during onboarding (or changed later). Unknown counts as "Not sure".
    static var current: WaterSource {
        WaterSource(rawValue: UserDefaults.standard.string(forKey: StorageKey.waterSource) ?? "") ?? .notSure
    }

    var isWell: Bool { self == .privateWell }

    /// Well-only tasks (wellhead inspection, shock chlorination) apply unless we know it's city water.
    var showsWellCare: Bool { self != .publicWater }

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
        case .publicWater: String(localized: "City or county water")
        case .notSure: String(localized: "Not sure")
        }
    }

    var symbol: String {
        switch self {
        case .privateWell: "drop.circle.fill"
        case .publicWater: "building.2.fill"
        case .notSure: "questionmark.circle.fill"
        }
    }

    /// Tab icon.
    var tabSymbol: String { isWell ? "drop.fill" : "spigot.fill" }
}

/// Shown to city/county water users: what their utility does, and what is still on them (lead).
struct CityWaterCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                IconTile(systemImage: "building.2.fill")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your water utility tests your water")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("City and county water systems must test regularly and publish a yearly water quality report, called a Consumer Confidence Report.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label {
                Text("Lead can still come from pipes and faucets inside your home, especially in homes built before 1986. Testing your tap for lead is the best way to know.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.statusWatch)
            }
            .font(.subheadline)
            Link(destination: WellResources.epaConsumerConfidenceReports) {
                Label("Find your water quality report", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .card()
    }
}
