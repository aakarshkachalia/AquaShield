//
//  RiskEngine.swift
//  ClearWellNC
//
//  Mirrors the report logic in step5_lookup.py. Keep the two in sync.
//

import Foundation

/// Risk level for one contaminant. Raw values give the card sort order.
nonisolated enum RiskLevel: Int, Comparable, Sendable, CaseIterable {
    case high = 0
    case elevated
    case typical
    case testRegardless
    case lowerThanTypical

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .high: String(localized: "High")
        case .elevated: String(localized: "Elevated")
        case .typical: String(localized: "Typical")
        case .testRegardless: String(localized: "Test regardless")
        case .lowerThanTypical: String(localized: "Lower than typical")
        }
    }

    /// Lead depends on household plumbing, not location, so it is always "Test regardless".
    static func level(for contaminant: Contaminant, ratio: Double) -> RiskLevel {
        if contaminant == .lead { return .testRegardless }
        if ratio >= 3 { return .high }
        if ratio >= 1.5 { return .elevated }
        if ratio >= 0.75 { return .typical }
        return .lowerThanTypical
    }

    /// True for levels at or above the statewide norm (used for the infant nitrate note).
    var isTypicalOrHigher: Bool { self == .high || self == .elevated || self == .typical }
}

nonisolated struct Confidence: Sendable, Hashable {
    enum Level: Sendable {
        case high, medium, low

        var label: String {
            switch self {
            case .high: String(localized: "High")
            case .medium: String(localized: "Medium")
            case .low: String(localized: "Low")
            }
        }
    }

    let level: Level
    let note: String

    init(tests: Int) {
        switch tests {
        case 30...:
            level = .high
            note = String(localized: "Based on \(tests) tested wells in your census tract plus the model.")
        case 10...:
            level = .medium
            note = String(localized: "Based on \(tests) tested wells in your census tract plus the model.")
        case 1...:
            level = .low
            note = String(localized: "Only \(tests) tested wells in your census tract, so this is mostly the model's estimate.")
        default:
            level = .low
            note = String(localized: "No wells in your census tract have been tested. This is the model's estimate from geology and nearby areas.")
        }
    }
}

nonisolated struct ContaminantRisk: Sendable, Identifiable {
    let contaminant: Contaminant
    let estimate: Double
    let statewide: Double
    let ratio: Double
    let level: RiskLevel
    let tests: Int
    let aboveLimit: Int
    let confidence: Confidence

    var id: Contaminant { contaminant }

    init(contaminant: Contaminant, data: ContaminantData, statewide: Double) {
        self.contaminant = contaminant
        self.estimate = data.estimate
        self.statewide = statewide
        self.ratio = statewide > 0 ? data.estimate / statewide : 0
        self.level = RiskLevel.level(for: contaminant, ratio: ratio)
        self.tests = data.tests
        self.aboveLimit = data.aboveLimit
        self.confidence = Confidence(tests: data.tests)
    }

    /// e.g. "about 1 in 5"
    var oneInText: String { RiskEngine.oneIn(estimate) }
    var statewideOneInText: String { RiskEngine.oneIn(statewide) }

    /// "Estimated about 1 in 5 wells in your area are above 10 ppb (EPA limit)."
    var estimateSentence: String {
        String(localized: "Estimated \(oneInText) wells in your area are above \(contaminant.limit).")
    }

    /// "8 of 52 tested wells in your census tract were above the limit." Nil when no wells were tested.
    var observedText: String? {
        guard tests > 0 else { return nil }
        return String(localized: "\(aboveLimit) of \(tests) tested wells in your census tract were above the limit.")
    }
}

nonisolated struct RiskReport: Sendable {
    let fips: String
    let countyName: String?
    /// Sorted for display: High, Elevated, Typical, Test regardless, Lower than typical; ties by larger ratio.
    let risks: [ContaminantRisk]
    let testPlan: [String]

    static var disclaimer: String {
        String(localized: "This is an estimate for your area, not your well. Only a lab test tells you what is in your water.")
    }

    func risk(for contaminant: Contaminant) -> ContaminantRisk? {
        risks.first { $0.contaminant == contaminant }
    }
}

nonisolated enum RiskEngine {
    static func oneIn(_ rate: Double) -> String {
        if rate < 0.005 { return String(localized: "fewer than 1 in 200") }
        // Python's round() uses banker's rounding; match it.
        let n = max(2, Int((1 / rate).rounded(.toNearestOrEven)))
        return String(localized: "about 1 in \(n)")
    }

    static func report(for tract: Tract, meta: Meta) -> RiskReport {
        let risks = Contaminant.allCases.compactMap { c -> ContaminantRisk? in
            guard let data = tract.data[c] else { return nil }
            return ContaminantRisk(contaminant: c, data: data, statewide: meta.statewideRate(for: c))
        }
        .sorted { a, b in
            a.level != b.level ? a.level < b.level : a.ratio > b.ratio
        }
        return RiskReport(fips: tract.fips, countyName: tract.countyName, risks: risks,
                          testPlan: testPlan(for: risks, countyName: tract.countyName))
    }

    static func testPlan(for sortedRisks: [ContaminantRisk], countyName: String?) -> [String] {
        var plan = [String(localized: "Bacteria (total coliform / E. coli): every year and after any flooding, for every well.")]
        for r in sortedRisks {
            let name = r.contaminant.name
            switch r.level {
            case .high:
                plan.append(String(localized: "\(name): a priority for your area (high risk)."))
            case .elevated:
                plan.append(String(localized: "\(name): a priority for your area (elevated risk)."))
            case .testRegardless:
                plan.append(String(localized: "\(name): test at least once; it depends on your home's plumbing."))
            case .typical, .lowerThanTypical:
                plan.append(String(localized: "\(name): include in a standard metals and nitrate panel every 2 years."))
            }
        }
        if let countyName {
            plan.append(String(localized: "How: contact \(countyName) County Environmental Health to order a test through the NC State Laboratory of Public Health, or use a state-certified private lab."))
        } else {
            plan.append(String(localized: "How: contact your county Environmental Health office to order a test through the NC State Laboratory of Public Health, or use a state-certified private lab."))
        }
        return plan
    }
}
