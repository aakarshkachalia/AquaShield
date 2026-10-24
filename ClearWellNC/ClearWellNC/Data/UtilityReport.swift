//
//  UtilityReport.swift
//  ClearWellNC
//
//  City/public water: the numbers a user copies from their utility's yearly Consumer Confidence Report
//  (CCR), and what they mean. Stored on device in AppSettings (scoped for Demo Mode).
//

import Foundation

nonisolated struct UtilityReport: Codable, Equatable, Sendable {
    var utilityName = ""
    var reportYear: Int?
    /// Link the user pasted to their utility's report.
    var reportURL = ""
    /// 90th percentile lead from the utility's home sampling, ppb.
    var leadP90PPB: Double?
    /// 90th percentile copper, mg/L.
    var copperP90MgL: Double?
    /// Total trihalomethanes (a disinfection byproduct), highest running annual average, ppb.
    var tthmPPB: Double?
    /// Five haloacetic acids (a disinfection byproduct), ppb.
    var haa5PPB: Double?
    var pfoaPPT: Double?
    var pfosPPT: Double?
    var nitrateMgL: Double?
    /// "Did the report list any violations?"
    var listedViolations: Bool?

    static let storageKey = "utilityReport"

    var isEmpty: Bool { self == UtilityReport() }
}

/// One CCR value compared with its federal limit.
nonisolated struct UtilityFinding: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable, CaseIterable {
        case lead, copper, tthm, haa5, pfoa, pfos, nitrate
    }

    let kind: Kind
    let value: Double
    let limit: SourcedValue
    var id: Kind { kind }

    var isAbove: Bool { value >= limit.value }
    var ratio: Double { limit.value > 0 ? value / limit.value : 0 }

    var name: String {
        switch kind {
        case .lead: String(localized: "Lead (90th percentile)")
        case .copper: String(localized: "Copper (90th percentile)")
        case .tthm: String(localized: "Trihalomethanes (TTHM)")
        case .haa5: String(localized: "Haloacetic acids (HAA5)")
        case .pfoa: String(localized: "PFOA")
        case .pfos: String(localized: "PFOS")
        case .nitrate: String(localized: "Nitrate")
        }
    }
}

nonisolated enum UtilityReportRules {
    /// Federal limits for CCR values. All need a person to confirm against the source before release:
    /// the lead action level drops to 10 ppb under the 2024 Lead and Copper Rule Improvements (compliance
    /// around 2027), and EPA has said it may change the PFAS rule's timeline.
    static func limit(for kind: UtilityFinding.Kind) -> SourcedValue {
        switch kind {
        case .lead: SourcedValue(value: 15, unit: "ppb", source: .epaLeadCopper)
        case .copper: SourcedValue(value: 1.3, unit: "mg/L", source: .epaLeadCopper)
        case .tthm: SourcedValue(value: 80, unit: "ppb", source: .epaDBP)
        case .haa5: SourcedValue(value: 60, unit: "ppb", source: .epaDBP)
        case .pfoa, .pfos: SourcedValue(value: 4, unit: "ppt", source: .epaPFAS)
        case .nitrate: SourcedValue(value: 10, unit: "mg/L", source: .epaNPDWR)
        }
    }

    /// Every value the user entered, highest share of its limit first.
    static func findings(for report: UtilityReport) -> [UtilityFinding] {
        let values: [(UtilityFinding.Kind, Double?)] = [
            (.lead, report.leadP90PPB), (.copper, report.copperP90MgL), (.tthm, report.tthmPPB),
            (.haa5, report.haa5PPB), (.pfoa, report.pfoaPPT), (.pfos, report.pfosPPT), (.nitrate, report.nitrateMgL),
        ]
        return values
            .compactMap { kind, value in value.map { UtilityFinding(kind: kind, value: $0, limit: limit(for: kind)) } }
            .sorted { $0.ratio > $1.ratio }
    }

    /// A utility's lead number describes its sampled homes, not your tap, so lead is always worth testing
    /// at your own faucet when the home may have lead pipes or solder.
    static func shouldTestTapForLead(report: UtilityReport, homeBuiltBefore1986: Bool?) -> Bool {
        if homeBuiltBefore1986 != false { return true }
        return (report.leadP90PPB ?? 0) > 0
    }
}
