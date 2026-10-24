//
//  DSIcons.swift
//  ClearWellNC
//
//  One SF Symbol per contaminant category, filter type, alert type and status level. Screens ask here
//  instead of naming symbols, so the same thing always gets the same icon.
//

import SwiftUI

extension DS {
    /// What kind of problem a contaminant is. Used for icons and grouping.
    nonisolated enum ContaminantCategory: CaseIterable, Sendable, Identifiable {
        case bacteria, metals, nitrates, pfas, radioactive, minerals, acidity

        var id: Self { self }

        init(_ id: ContaminantID) {
            switch id {
            case .totalColiform, .eColi: self = .bacteria
            case .arsenic, .lead, .copper: self = .metals
            case .nitrate, .nitrite: self = .nitrates
            case .pfoa, .pfos, .genx: self = .pfas
            case .uranium, .radon: self = .radioactive
            case .manganese, .iron, .hardness, .fluoride: self = .minerals
            case .pH: self = .acidity
            }
        }

        var label: String {
            switch self {
            case .bacteria: String(localized: "Germs")
            case .metals: String(localized: "Metals")
            case .nitrates: String(localized: "Nitrates")
            case .pfas: String(localized: "PFAS")
            case .radioactive: String(localized: "Radioactive")
            case .minerals: String(localized: "Minerals")
            case .acidity: String(localized: "pH")
            }
        }
    }

    /// Weather alert families, from the NWS event name.
    nonisolated enum AlertKind: CaseIterable, Sendable, Identifiable {
        case flood, hurricane, storm, drought, other

        var id: Self { self }

        init(event: String) {
            let e = event.lowercased()
            if e.contains("hurricane") || e.contains("tropical") {
                self = .hurricane
            } else if e.contains("flood") {
                self = .flood
            } else if e.contains("storm") || e.contains("thunder") || e.contains("tornado") {
                self = .storm
            } else if e.contains("drought") || e.contains("heat") {
                self = .drought
            } else {
                self = .other
            }
        }

        var label: String {
            switch self {
            case .flood: String(localized: "Flood")
            case .hurricane: String(localized: "Hurricane")
            case .storm: String(localized: "Storm")
            case .drought: String(localized: "Drought")
            case .other: String(localized: "Alert")
            }
        }
    }

    enum Icon {
        static func level(_ level: Level) -> String {
            switch level {
            case .excellent: "checkmark.seal.fill"
            case .good: "checkmark.circle.fill"
            case .fair: "eye.circle.fill"
            case .poor: "exclamationmark.circle.fill"
            case .unsafe: "xmark.octagon.fill"
            }
        }

        nonisolated static func category(_ category: ContaminantCategory) -> String {
            switch category {
            case .bacteria: "allergens.fill"
            case .metals: "circle.hexagongrid.fill"
            case .nitrates: "leaf.fill"
            case .pfas: "drop.triangle.fill"
            case .radioactive: "atom"
            case .minerals: "drop.halffull"
            case .acidity: "gauge.with.dots.needle.50percent"
            }
        }

        static func contaminant(_ id: ContaminantID) -> String { category(ContaminantCategory(id)) }

        /// Risk Check recommendations use the same icon as their contaminant category.
        static func recommendedTest(_ id: RecommendedTestID) -> String {
            switch id {
            case .bacteria: category(.bacteria)
            case .nitrate: category(.nitrates)
            case .arsenic, .lead: category(.metals)
            case .manganese, .iron, .hardness: category(.minerals)
            case .pH: category(.acidity)
            case .uranium, .radon: category(.radioactive)
            case .pfas: category(.pfas)
            }
        }

        static func filter(_ kind: TreatmentKind) -> String {
            switch kind {
            case .pitcherFilter: "waterbottle.fill"
            case .faucetFilter: "spigot.fill"
            case .refrigeratorFilter: "refrigerator.fill"
            case .underSinkFilter: "sink.fill"
            case .showerFilter: "shower.fill"
            case .sedimentFilter: "line.3.horizontal.decrease.circle.fill"
            case .carbonFilter: "cylinder.fill"
            case .roMembrane: "square.stack.3d.down.right.fill"
            case .uvBulb: "sun.max.fill"
            case .softenerSalt: "cube.fill"
            case .other: "wrench.and.screwdriver.fill"
            }
        }

        static func alert(_ kind: AlertKind) -> String {
            switch kind {
            case .flood: "water.waves"
            case .hurricane: "hurricane"
            case .storm: "cloud.bolt.rain.fill"
            case .drought: "sun.max.trianglebadge.exclamationmark.fill"
            case .other: "exclamationmark.bubble.fill"
            }
        }

        // App-wide actions and places.
        static let scan = "doc.viewfinder"
        static let riskCheck = "checklist"
        static let score = "gauge.with.needle.fill"
        static let help = "lifepreserver.fill"
        static let learn = "book.fill"
        static let reminder = "bell.badge.fill"
        static let test = "testtube.2"
        static let info = "info.circle.fill"
    }
}

// MARK: - Haptics

extension DS {
    /// The three haptics the app uses. UIKit already skips them when System Haptics is off.
    enum Haptics {
        /// Something finished well (report saved, quiz passed).
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        /// A choice was picked.
        static func selection() {
            UISelectionFeedbackGenerator().selectionChanged()
        }

        /// A result needs attention.
        static func warning() {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
