//
//  NonDetects.swift
//  ClearWellNC
//
//  "Not detected" / "< 0.005" readings. The value is saved as 0 for scoring (nothing was found above
//  the detection limit), and the detection limit is kept so every screen can say so honestly.
//

import Foundation

extension LabResult {
    /// [Analyte: detection limit, in the analyte's stored unit]. Nil limit = "ND" with no limit given.
    var nonDetects: [Analyte: Double?] {
        get {
            guard let json = nonDetectsJSON, let data = json.data(using: .utf8),
                  let raw = try? JSONDecoder().decode([String: Double?].self, from: data) else { return [:] }
            var result: [Analyte: Double?] = [:]
            for (key, limit) in raw { if let analyte = Analyte(rawValue: key) { result[analyte] = limit } }
            return result
        }
        set {
            guard !newValue.isEmpty else { nonDetectsJSON = nil; return }
            var raw: [String: Double?] = [:]
            for (analyte, limit) in newValue { raw[analyte.rawValue] = limit }
            nonDetectsJSON = (try? JSONEncoder().encode(raw)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    func isNonDetect(_ analyte: Analyte) -> Bool { nonDetects.keys.contains(analyte) }

    /// Every reading on this report, interpreted, with non-detects explained as such.
    var displayInterpretations: [Interpretation] {
        let nd = nonDetects
        return QuestReport(result: self).interpretations.map { interpretation in
            guard let analyte = Analyte.allCases.first(where: { $0.contaminant == interpretation.id }),
                  let limit = nd[analyte] else { return interpretation }
            return Interpretation.interpretNonDetect(interpretation.id, detectionLimit: limit)
        }
    }
}

nonisolated extension Interpretation {
    /// A reading reported as below the lab's detection limit.
    static func interpretNonDetect(_ id: ContaminantID, detectionLimit: Double?) -> Interpretation {
        let info = id.info
        let name = info.name.inSentence
        let reading: String
        let sentence: String
        if let detectionLimit {
            let dl = format(detectionLimit, unit: info.unit)
            reading = String(localized: "Not detected (below \(dl))")
            if let limit = info.maximumLimit {
                sentence = String(localized: "The lab didn't find any \(name) above its detection limit of \(dl), which is below the \(info.limitPhrase) of \(format(limit, unit: info.unit)).")
            } else {
                sentence = String(localized: "The lab didn't find any \(name) above its detection limit of \(dl).")
            }
        } else {
            reading = String(localized: "Not detected")
            sentence = String(localized: "The lab didn't find any \(name) in this sample.")
        }
        return Interpretation(id: id, readingText: reading, limitText: info.limitDescription, percentOfLimit: nil,
                              tier: .safe, chipLabel: String(localized: "Not detected"), sentence: sentence,
                              isHealthExceedance: false)
    }
}

// MARK: - Names labs use

nonisolated extension ContaminantID {
    /// Names and abbreviations lab reports use, lowercased. Longest/most specific first matters only for ties;
    /// the parser picks the longest alias that matches.
    var aliases: [String] {
        switch self {
        case .arsenic: ["arsenic", "arsenic (as)", "total arsenic", "as"]
        case .lead: ["lead", "lead (pb)", "total lead", "pb"]
        case .nitrate: ["nitrate as n", "nitrate-n", "nitrate nitrogen", "no3-n", "no3 as n", "nitrate (as n)",
                        "nitrate + nitrite", "nitrate/nitrite", "nitrate", "no3"]
        case .nitrite: ["nitrite as n", "nitrite-n", "no2-n", "nitrite (as n)", "nitrite", "no2"]
        case .uranium: ["uranium", "total uranium"]
        case .manganese: ["manganese", "manganese (mn)", "mn"]
        case .iron: ["iron", "iron (fe)", "total iron", "fe"]
        case .copper: ["copper", "copper (cu)", "cu"]
        case .fluoride: ["fluoride"]
        case .totalColiform: ["total coliform bacteria", "total coliforms", "total coliform", "coliform bacteria", "coliform"]
        case .eColi: ["escherichia coli", "e. coli", "e.coli", "e coli", "ecoli"]
        case .pH: ["ph"]
        case .hardness: ["total hardness", "hardness as caco3", "hardness"]
        case .radon: ["radon-222", "radon in water", "radon", "rn-222"]
        case .pfoa: ["perfluorooctanoic acid", "pfoa"]
        case .pfos: ["perfluorooctanesulfonic acid", "perfluorooctane sulfonate", "pfos"]
        case .genx: ["hfpo-da", "hfpo da", "genx", "gen x"]
        }
    }
}
