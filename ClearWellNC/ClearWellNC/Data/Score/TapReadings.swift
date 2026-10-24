//
//  TapReadings.swift
//  ClearWellNC
//
//  Turns stored lab results and the utility report into Readings for the tap score.
//

import Foundation

extension Array where Element == LabResult {
    /// The latest reading per target across all results, newest result first.
    func tapReadings() -> [Reading] {
        var readings: [Reading] = []
        var seen: Set<ClaimTarget> = []
        for result in sorted(by: { $0.date > $1.date }) {
            for reading in result.tapReadings() where seen.insert(reading.target).inserted {
                readings.append(reading)
            }
        }
        return readings
    }
}

extension LabResult {
    func tapReadings() -> [Reading] {
        let method = testMethod
        var readings: [Reading] = []
        // E. coli counts as the bacteria result when present; otherwise total coliform.
        let bacteria: BacteriaResult? = eColi == .present ? .present : (totalColiform ?? eColi)
        if let bacteria {
            readings.append(.presence(.bacteria, present: bacteria == .present, method: method))
        }
        let nonDetects = self.nonDetects
        for analyte in Analyte.allCases {
            guard let target = ClaimTarget(contaminant: analyte.contaminant) else { continue }
            if let value = value(for: analyte) {
                if let reading = Reading.amount(target, value, method: method) { readings.append(reading) }
            } else if let limit = nonDetects[analyte] {
                if let reading = Reading.amount(target, limit ?? 0, method: method, nonDetect: true) { readings.append(reading) }
            }
        }
        return readings
    }
}

extension UtilityReport {
    /// The utility's numbers as readings at the house (before any home filter).
    nonisolated func tapReadings() -> [Reading] {
        let values: [(ClaimTarget, Double?)] = [
            (.lead, leadP90PPB), (.copper, copperP90MgL), (.tthm, tthmPPB), (.haa5, haa5PPB),
            (.pfoa, pfoaPPT), (.pfos, pfosPPT), (.nitrate, nitrateMgL),
        ]
        return values.compactMap { target, value in
            value.flatMap { Reading.amount(target, $0, method: .utilityReport) }
        }
    }
}
