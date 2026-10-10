//
//  WellRecord.swift
//  ClearWellNC
//

import Foundation
import SwiftData

// MARK: - Units

nonisolated enum ConcentrationUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case ppb
    case mgL

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ppb: String(localized: "ppb")
        case .mgL: String(localized: "mg/L")
        }
    }

    /// 1 mg/L = 1000 ppb.
    static func convert(_ value: Double, from: ConcentrationUnit, to: ConcentrationUnit) -> Double {
        switch (from, to) {
        case (.ppb, .mgL): value / 1000
        case (.mgL, .ppb): value * 1000
        default: value
        }
    }
}

// MARK: - Bacteria

nonisolated enum BacteriaResult: String, CaseIterable, Codable, Sendable, Identifiable {
    case absent
    case present

    var id: String { rawValue }

    var label: String {
        switch self {
        case .absent: String(localized: "Absent")
        case .present: String(localized: "Present")
        }
    }
}

// MARK: - Results evaluation

nonisolated struct ResultStatus: Sendable, Hashable {
    enum Kind: Sendable {
        /// Within the limit or range.
        case pass
        /// Above a non-health guideline (iron staining).
        case notice
        /// Above a health limit, or bacteria present.
        case above
    }

    let kind: Kind
    let text: String

    var isPass: Bool { kind == .pass }
}

nonisolated struct ReferenceLine: Sendable, Identifiable {
    let value: Double
    let label: String
    var id: Double { value }
}

/// Values the Well Record tracks, with their limits from the spec.
nonisolated enum Analyte: String, CaseIterable, Sendable, Identifiable {
    case arsenic
    case lead
    case manganese
    case nitrate
    case iron
    case pH

    var id: String { rawValue }

    var name: String {
        switch self {
        case .arsenic: String(localized: "Arsenic")
        case .lead: String(localized: "Lead")
        case .manganese: String(localized: "Manganese")
        case .nitrate: String(localized: "Nitrate")
        case .iron: String(localized: "Iron")
        case .pH: String(localized: "pH")
        }
    }

    /// The unit values are stored in. Nil for pH.
    var storedUnit: ConcentrationUnit? {
        switch self {
        case .arsenic, .lead, .manganese, .iron: .ppb
        case .nitrate: .mgL
        case .pH: nil
        }
    }

    var limitDescription: String {
        switch self {
        case .arsenic: String(localized: "Limit: 10 ppb (EPA)")
        case .lead: String(localized: "Action level: 15 ppb (EPA)")
        case .manganese: String(localized: "50 ppb (NC standard); 300 ppb (health advisory)")
        case .nitrate: String(localized: "Limit: 10 mg/L (EPA)")
        case .iron: String(localized: "300 ppb (staining only, not a health limit)")
        case .pH: String(localized: "Range: 6.5–8.5")
        }
    }

    var referenceLines: [ReferenceLine] {
        switch self {
        case .arsenic: [ReferenceLine(value: 10, label: String(localized: "10 ppb limit"))]
        case .lead: [ReferenceLine(value: 15, label: String(localized: "15 ppb action level"))]
        case .manganese: [ReferenceLine(value: 50, label: String(localized: "50 ppb NC standard")),
                          ReferenceLine(value: 300, label: String(localized: "300 ppb health advisory"))]
        case .nitrate: [ReferenceLine(value: 10, label: String(localized: "10 mg/L limit"))]
        case .iron: [ReferenceLine(value: 300, label: String(localized: "300 ppb (staining)"))]
        case .pH: [ReferenceLine(value: 6.5, label: "6.5"), ReferenceLine(value: 8.5, label: "8.5")]
        }
    }

    /// `value` is in `storedUnit`.
    func evaluate(_ value: Double) -> ResultStatus {
        switch self {
        case .arsenic:
            value > 10 ? .init(kind: .above, text: String(localized: "Above the 10 ppb EPA limit")) : .withinLimit
        case .lead:
            value > 15 ? .init(kind: .above, text: String(localized: "Above the 15 ppb EPA action level")) : .withinLimit
        case .manganese:
            if value > 300 { .init(kind: .above, text: String(localized: "Above the 300 ppb health advisory")) }
            else if value > 50 { .init(kind: .above, text: String(localized: "Above the 50 ppb NC standard")) }
            else { .withinLimit }
        case .nitrate:
            value > 10 ? .init(kind: .above, text: String(localized: "Above the 10 mg/L EPA limit")) : .withinLimit
        case .iron:
            value > 300 ? .init(kind: .notice, text: String(localized: "Above 300 ppb: can stain, not a health limit")) : .withinLimit
        case .pH:
            (6.5...8.5).contains(value)
                ? .init(kind: .pass, text: String(localized: "In range"))
                : .init(kind: .above, text: String(localized: "Outside 6.5–8.5"))
        }
    }

    static func evaluate(bacteria: BacteriaResult) -> ResultStatus {
        switch bacteria {
        case .absent: .init(kind: .pass, text: String(localized: "Absent"))
        case .present: .init(kind: .above, text: String(localized: "Present: should be absent"))
        }
    }

    /// Formats a stored value with its unit, e.g. "12 ppb" or "7.2".
    func format(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)))
        guard let unit = storedUnit else { return number }
        return "\(number) \(unit.label)"
    }
}

private nonisolated extension ResultStatus {
    static var withinLimit: ResultStatus { .init(kind: .pass, text: String(localized: "Within limit")) }
}

// MARK: - SwiftData model

/// One lab report in the Well Record. Concentrations are stored in each analyte's `storedUnit`.
@Model
final class LabResult {
    var date: Date
    var labName: String
    var arsenicPPB: Double?
    var leadPPB: Double?
    var manganesePPB: Double?
    var nitrateMgL: Double?
    var ironPPB: Double?
    var pH: Double?
    var totalColiformRaw: String?
    var eColiRaw: String?
    var createdAt: Date

    init(date: Date = .now, labName: String = "") {
        self.date = date
        self.labName = labName
        self.createdAt = .now
    }

    func value(for analyte: Analyte) -> Double? {
        switch analyte {
        case .arsenic: arsenicPPB
        case .lead: leadPPB
        case .manganese: manganesePPB
        case .nitrate: nitrateMgL
        case .iron: ironPPB
        case .pH: pH
        }
    }

    func setValue(_ value: Double?, for analyte: Analyte) {
        switch analyte {
        case .arsenic: arsenicPPB = value
        case .lead: leadPPB = value
        case .manganese: manganesePPB = value
        case .nitrate: nitrateMgL = value
        case .iron: ironPPB = value
        case .pH: pH = value
        }
    }

    var totalColiform: BacteriaResult? {
        get { totalColiformRaw.flatMap(BacteriaResult.init(rawValue:)) }
        set { totalColiformRaw = newValue?.rawValue }
    }

    var eColi: BacteriaResult? {
        get { eColiRaw.flatMap(BacteriaResult.init(rawValue:)) }
        set { eColiRaw = newValue?.rawValue }
    }

    var includesBacteria: Bool { totalColiform != nil || eColi != nil }

    var includesMetalsOrNitrate: Bool {
        [Analyte.arsenic, .lead, .manganese, .nitrate].contains { value(for: $0) != nil }
    }
}
