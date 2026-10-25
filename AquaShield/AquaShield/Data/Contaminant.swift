//
//  Contaminant.swift
//  AquaShield
//

import Foundation

/// The four contaminants the risk model covers, with the fixed explanatory text shown on report cards.
nonisolated enum Contaminant: String, CaseIterable, Codable, Sendable, Identifiable {
    case arsenic
    case manganese
    case nitrate
    case lead

    var id: String { rawValue }

    var name: String {
        switch self {
        case .arsenic: String(localized: "Arsenic")
        case .manganese: String(localized: "Manganese")
        case .nitrate: String(localized: "Nitrate")
        case .lead: String(localized: "Lead")
        }
    }

    var limit: String {
        switch self {
        case .arsenic: String(localized: "10 ppb (EPA limit)")
        case .manganese: String(localized: "50 ppb (NC standard)")
        case .nitrate: String(localized: "10 mg/L (EPA limit)")
        case .lead: String(localized: "15 ppb (EPA action level)")
        }
    }

    var whyItMatters: String {
        switch self {
        case .arsenic:
            String(localized: "Arsenic comes from certain bedrock. It has no taste or smell, and long-term exposure raises cancer risk.")
        case .manganese:
            String(localized: "Manganese comes from rock and soil. It can stain sinks and laundry black, and high levels are a concern for infants.")
        case .nitrate:
            String(localized: "Nitrate comes from fertilizer, manure and septic systems. It is most dangerous for babies under 6 months.")
        case .lead:
            String(localized: "Lead in well water usually comes from pipes, solder and well parts, not the rock, so it varies from house to house.")
        }
    }

    var ifHigh: String {
        switch self {
        case .arsenic:
            String(localized: "Reverse osmosis certified to NSF/ANSI 58 for arsenic. An under-sink unit is usually enough for drinking and cooking.")
        case .manganese:
            String(localized: "Oxidation/filtration (greensand) or a softener rated for manganese; reverse osmosis for drinking water.")
        case .nitrate:
            String(localized: "Reverse osmosis certified to NSF/ANSI 58 for nitrate. Never boil water to remove nitrate; boiling concentrates it.")
        case .lead:
            String(localized: "A point-of-use filter certified to NSF/ANSI 53 for lead; replace old brass fittings or lead solder where possible.")
        }
    }
}
