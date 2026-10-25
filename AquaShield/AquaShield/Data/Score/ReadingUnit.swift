//
//  ReadingUnit.swift
//  AquaShield
//
//  Units labs and utilities report in, and conversion to the one unit the app stores for each target.
//

import Foundation

nonisolated enum ReadingUnit: String, Codable, CaseIterable, Sendable {
    case mgL, ppm, ugL, ppb, ngL, ppt, pCiL, gpg, mgLAsCaCO3, presence

    var label: String {
        switch self {
        case .mgL: "mg/L"
        case .ppm: "ppm"
        case .ugL: "µg/L"
        case .ppb: "ppb"
        case .ngL: "ng/L"
        case .ppt: "ppt"
        case .pCiL: "pCi/L"
        case .gpg: "gpg"
        case .mgLAsCaCO3: "mg/L as CaCO₃"
        case .presence: ""
        }
    }

    /// Unit of a daily dose per kilogram of body weight, from a concentration in this unit.
    var doseLabel: String {
        switch self {
        case .mgL, .ppm, .mgLAsCaCO3: "mg/kg/day"
        case .ugL, .ppb: "µg/kg/day"
        case .ngL, .ppt: "ng/kg/day"
        case .pCiL: "pCi/kg/day"
        case .gpg, .presence: ""
        }
    }

    /// Milligrams per liter for one unit, for mass concentrations. In water, 1 ppm = 1 mg/L,
    /// 1 ppb = 1 µg/L and 1 ppt = 1 ng/L.
    private var mgPerLiter: Double? {
        switch self {
        case .mgL, .ppm: 1
        case .ugL, .ppb: 0.001
        case .ngL, .ppt: 0.000_001
        case .pCiL, .gpg, .mgLAsCaCO3, .presence: nil
        }
    }

    /// 1 grain per gallon of hardness = 17.1 mg/L as calcium carbonate (USGS).
    static let mgLAsCaCO3PerGrain = 17.1

    /// Converts between compatible units. Nil if they measure different things (pCi/L to mg/L).
    static func convert(_ value: Double, from: ReadingUnit, to: ReadingUnit) -> Double? {
        if from == to { return value }
        if let a = from.mgPerLiter, let b = to.mgPerLiter { return value * a / b }
        switch (from, to) {
        case (.gpg, .mgLAsCaCO3): return value * mgLAsCaCO3PerGrain
        case (.mgLAsCaCO3, .gpg): return value / mgLAsCaCO3PerGrain
        // Hardness is often printed as plain mg/L or ppm, meaning "as CaCO₃".
        case (.mgL, .mgLAsCaCO3), (.ppm, .mgLAsCaCO3): return value
        case (.mgLAsCaCO3, .mgL), (.mgLAsCaCO3, .ppm): return value
        case (.gpg, .mgL), (.gpg, .ppm): return value * mgLAsCaCO3PerGrain
        default: return nil
        }
    }

    /// The unit every reading, limit and challenge concentration for `target` is stored in.
    static func canonical(for target: ClaimTarget) -> ReadingUnit {
        switch target {
        case .arsenic, .lead, .uranium, .manganese, .iron, .tthm, .haa5, .vocs: .ppb
        case .nitrate, .nitrite, .copper, .fluoride, .freeChlorine, .chloramine: .mgL
        case .pfoa, .pfos, .genx: .ppt
        case .radon: .pCiL
        case .hardness: .mgLAsCaCO3
        case .bacteria, .viruses, .cysts: .presence
        }
    }
}
