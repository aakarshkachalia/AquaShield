//
//  WellRecord.swift
//  AquaShield
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

/// Numeric values the Well Record tracks. Limits and wording come from `ContaminantInfo`.
nonisolated enum Analyte: String, CaseIterable, Codable, Sendable, Identifiable {
    case arsenic, lead, nitrate, nitrite, uranium, manganese, iron, copper, fluoride, pH, hardness, radon
    case pfoa, pfos, genx

    var id: String { rawValue }

    var contaminant: ContaminantID {
        switch self {
        case .arsenic: .arsenic
        case .lead: .lead
        case .nitrate: .nitrate
        case .nitrite: .nitrite
        case .uranium: .uranium
        case .manganese: .manganese
        case .iron: .iron
        case .copper: .copper
        case .fluoride: .fluoride
        case .pH: .pH
        case .hardness: .hardness
        case .radon: .radon
        case .pfoa: .pfoa
        case .pfos: .pfos
        case .genx: .genx
        }
    }

    var info: ContaminantInfo { contaminant.info }
    var name: String { info.name }

    /// The unit values are stored in, when it can be converted (ppb ⇄ mg/L). Nil for pH, hardness, radon.
    var storedUnit: ConcentrationUnit? { info.unit.concentration }

    /// Display unit label for every analyte, including fixed units ("pCi/L", "mg/L as CaCO₃").
    var unitLabel: String { info.unit.label }

    /// The common NC panel shown first in the lab form; the rest go under "Other tests".
    var isCommon: Bool {
        switch self {
        case .arsenic, .lead, .nitrate, .manganese, .iron, .pH: true
        default: false
        }
    }

    var limitDescription: String { info.limitDescription }

    var referenceLines: [ReferenceLine] {
        var lines: [ReferenceLine] = []
        switch info.limit {
        case .maximum(let value):
            let word = info.limitType == .health ? String(localized: "limit") : String(localized: "guideline")
            lines.append(ReferenceLine(value: value, label: "\(format(value)) \(word)"))
        case .range(let low, let high):
            lines.append(ReferenceLine(value: low, label: formatNumber(low)))
            lines.append(ReferenceLine(value: high, label: formatNumber(high)))
        case .none, .mustBeAbsent:
            break
        }
        if let advisory = info.healthAdvisory {
            lines.append(ReferenceLine(value: advisory.value, label: "\(format(advisory.value)) \(advisory.source.lowercased())"))
        }
        return lines
    }

    func interpret(_ value: Double) -> Interpretation {
        Interpretation.interpret(contaminant, value: value)
    }

    /// Compact status used by charts and summaries. Derived from the interpretation layer.
    func evaluate(_ value: Double) -> ResultStatus {
        let interpretation = interpret(value)
        let kind: ResultStatus.Kind = switch interpretation.tier {
        case .above: .above
        case .nuisance: .notice
        case .safe, .watch, .info: .pass
        }
        return ResultStatus(kind: kind, text: interpretation.chipLabel)
    }

    static func evaluate(bacteria: BacteriaResult) -> ResultStatus {
        switch bacteria {
        case .absent: .init(kind: .pass, text: String(localized: "Absent"))
        case .present: .init(kind: .above, text: String(localized: "Present: should be absent"))
        }
    }

    /// Formats a stored value with its unit, e.g. "12 ppb" or "7.2".
    func format(_ value: Double) -> String {
        Interpretation.format(value, unit: info.unit)
    }
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
    // Added with the interpretation layer; optional, so SwiftData migrates existing stores automatically.
    var nitriteMgL: Double?
    var uraniumPPB: Double?
    var copperMgL: Double?
    var fluorideMgL: Double?
    var hardnessMgL: Double?
    var radonPCiL: Double?
    // PFAS, in ppt (ng/L).
    var pfoaPPT: Double?
    var pfosPPT: Double?
    var genxPPT: Double?
    /// Readings reported as below the lab's detection limit: [Analyte rawValue: detection limit in stored units].
    var nonDetectsJSON: String?
    var totalColiformRaw: String?
    var eColiRaw: String?
    var createdAt: Date
    /// TestMethod.rawValue. Nil for results saved before this field existed, which came from lab reports.
    var testMethodRaw: String?

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
        case .nitrite: nitriteMgL
        case .uranium: uraniumPPB
        case .copper: copperMgL
        case .fluoride: fluorideMgL
        case .hardness: hardnessMgL
        case .radon: radonPCiL
        case .pfoa: pfoaPPT
        case .pfos: pfosPPT
        case .genx: genxPPT
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
        case .nitrite: nitriteMgL = value
        case .uranium: uraniumPPB = value
        case .copper: copperMgL = value
        case .fluoride: fluorideMgL = value
        case .hardness: hardnessMgL = value
        case .radon: radonPCiL = value
        case .pfoa: pfoaPPT = value
        case .pfos: pfosPPT = value
        case .genx: genxPPT = value
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

    var testMethod: TestMethod {
        get { testMethodRaw.flatMap(TestMethod.init(rawValue:)) ?? .certifiedLab }
        set { testMethodRaw = newValue.rawValue }
    }

    var includesMetalsOrNitrate: Bool {
        [Analyte.arsenic, .lead, .manganese, .nitrate].contains { value(for: $0) != nil }
    }
}

// MARK: - Score input

extension Array where Element == LabResult {
    /// The most recent reading of each contaminant across all results, for the Well Health Score.
    var latestScoreInput: WellHealthScore.Input {
        var input = WellHealthScore.Input()
        for result in sorted(by: { $0.date > $1.date }) {
            for analyte in Analyte.allCases where input.values[analyte.contaminant] == nil {
                if let value = result.value(for: analyte) { input.values[analyte.contaminant] = value }
            }
            if input.presence[.totalColiform] == nil, let coliform = result.totalColiform {
                input.presence[.totalColiform] = coliform == .present
            }
            if input.presence[.eColi] == nil, let eColi = result.eColi {
                input.presence[.eColi] = eColi == .present
            }
        }
        return input
    }
}
