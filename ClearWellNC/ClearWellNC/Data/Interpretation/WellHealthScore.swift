//
//  WellHealthScore.swift
//  ClearWellNC
//
//  Pure, documented scoring function. No UI, no SwiftData, so it is fully unit-testable.
//

import Foundation

/// # Well Health Score (0–100)
///
/// Start at 100 and subtract a penalty for each reading on file:
///
/// | Reading                         | Penalty                                              |
/// |---------------------------------|------------------------------------------------------|
/// | Health-based, numeric           | `30 × min(value / limit, 1)`                         |
/// | Aesthetic guideline, numeric    | `10 × min(value / guideline, 1.5)` (max 15)          |
/// | Manganese                       | aesthetic penalty vs 50 ppb **plus** health penalty vs the 300 ppb advisory |
/// | pH outside 6.5–8.5              | `10 × min(pH units outside the range, 1.5)` (max 15) |
/// | Hardness                        | Hard: 3, Very hard: 5, otherwise 0                   |
/// | Bacteria detected               | 30                                                   |
///
/// Then apply hard caps, in this order:
/// 1. Any health-based limit (or health advisory) met or exceeded → score ≤ 40 (always the "Unsafe" band).
/// 2. E. coli detected → score ≤ 10, and the "Do not drink untreated" banner is shown.
///
/// Missing key tests are **never** scored as zero or as safe. If any key test is missing and no cap
/// applies, the score is `nil` and the UI shows "Incomplete — X of Y key tests on file". If a cap
/// applies, the capped score is still shown, because a known exceedance is reliable bad news.
nonisolated enum WellHealthScore {
    // MARK: Constants (documented above)

    static let healthWeight = 30.0
    static let aestheticWeight = 10.0
    static let aestheticMaxFraction = 1.5
    static let pHWeight = 10.0
    static let pHMaxUnits = 1.5
    static let hardPenalty = 3.0
    static let veryHardPenalty = 5.0
    static let bacteriaPenalty = 30.0
    static let healthExceedanceCap = 40
    static let eColiCap = 10

    // MARK: Types

    /// The latest reading for each contaminant.
    struct Input: Sendable {
        var values: [ContaminantID: Double] = [:]
        /// Bacteria: true = present.
        var presence: [ContaminantID: Bool] = [:]

        func has(_ id: ContaminantID) -> Bool { values[id] != nil || presence[id] != nil }
    }

    /// The core tests every NC well should have on file.
    // SOURCE vr-030 (needs verification, see VerificationRegister.json): chosen from NC DHHS new-well testing guidance (bacteria, nitrate/nitrite, arsenic, lead,
    // manganese, pH among others). Confirm the list matches current NC DHHS recommendations.
    enum KeyTest: String, CaseIterable, Sendable {
        case bacteria, nitrate, arsenic, lead, manganese, pH

        var name: String {
            switch self {
            case .bacteria: String(localized: "Bacteria (total coliform / E. coli)")
            case .nitrate: ContaminantID.nitrate.info.name
            case .arsenic: ContaminantID.arsenic.info.name
            case .lead: ContaminantID.lead.info.name
            case .manganese: ContaminantID.manganese.info.name
            case .pH: ContaminantID.pH.info.name
            }
        }

        func isSatisfied(by input: Input) -> Bool {
            switch self {
            case .bacteria: input.has(.totalColiform) || input.has(.eColi)
            case .nitrate: input.has(.nitrate)
            case .arsenic: input.has(.arsenic)
            case .lead: input.has(.lead)
            case .manganese: input.has(.manganese)
            case .pH: input.has(.pH)
            }
        }
    }

    enum Band: Sendable, Codable {
        case good, fair, poor, unsafe

        /// 80–100 Good, 60–79 Fair, 41–59 Poor, 0–40 Unsafe. The exceedance cap (40) always lands in Unsafe.
        static func from(score: Int) -> Band {
            switch score {
            case 80...: .good
            case 60..<80: .fair
            case 41..<60: .poor
            default: .unsafe
            }
        }

        var label: String {
            switch self {
            case .good: String(localized: "Good")
            case .fair: String(localized: "Fair")
            case .poor: String(localized: "Poor")
            case .unsafe: String(localized: "Unsafe")
            }
        }
    }

    struct Factor: Sendable, Identifiable {
        let id: ContaminantID
        let penalty: Double
        let interpretation: Interpretation
        var nextAction: String { interpretation.nextAction }
    }

    struct Result: Sendable {
        /// Nil when incomplete and no cap applies.
        let score: Int?
        let band: Band?
        /// The uncapped, unrounded score, for transparency and tests.
        let rawScore: Double
        let keyTestsOnFile: Int
        let keyTestsTotal: Int
        let missingKeyTests: [KeyTest]
        /// All contributing factors, largest penalty first.
        let factors: [Factor]
        let eColiPositive: Bool
        let healthLimitExceeded: Bool

        var isComplete: Bool { missingKeyTests.isEmpty }
        var topFactors: [Factor] { Array(factors.prefix(3)) }
    }

    // MARK: Formula

    static func compute(_ input: Input) -> Result {
        var factors: [Factor] = []

        for (id, value) in input.values {
            let interpretation = Interpretation.interpret(id, value: value)
            let penalty = penalty(for: id, value: value)
            if penalty > 0 {
                factors.append(Factor(id: id, penalty: penalty, interpretation: interpretation))
            }
        }
        for (id, present) in input.presence where present {
            factors.append(Factor(id: id, penalty: bacteriaPenalty,
                                  interpretation: Interpretation.interpret(id, present: true)))
        }

        let eColiPositive = input.presence[.eColi] == true
        let healthExceeded = factors.contains { $0.interpretation.isHealthExceedance }

        let raw = max(0, 100 - factors.reduce(0) { $0 + $1.penalty })
        var score = Int(raw.rounded())
        if healthExceeded { score = min(score, healthExceedanceCap) }
        if eColiPositive { score = min(score, eColiCap) }

        let missing = KeyTest.allCases.filter { !$0.isSatisfied(by: input) }
        let capped = healthExceeded || eColiPositive
        let shownScore: Int? = (missing.isEmpty || capped) ? score : nil

        // E. coli first, then other exceedances, then by penalty.
        factors.sort { a, b in
            if (a.id == .eColi) != (b.id == .eColi) { return a.id == .eColi }
            if a.interpretation.isHealthExceedance != b.interpretation.isHealthExceedance {
                return a.interpretation.isHealthExceedance
            }
            return a.penalty > b.penalty
        }

        return Result(score: shownScore, band: shownScore.map(Band.from(score:)), rawScore: raw,
                      keyTestsOnFile: KeyTest.allCases.count - missing.count,
                      keyTestsTotal: KeyTest.allCases.count, missingKeyTests: missing,
                      factors: factors, eColiPositive: eColiPositive, healthLimitExceeded: healthExceeded)
    }

    static func penalty(for id: ContaminantID, value: Double) -> Double {
        let info = id.info
        switch info.limit {
        case .maximum(let limit):
            var total: Double
            switch info.limitType {
            case .health: total = healthWeight * min(value / limit, 1)
            case .aesthetic: total = aestheticWeight * min(value / limit, aestheticMaxFraction)
            }
            if let advisory = info.healthAdvisory {
                total += healthWeight * min(value / advisory.value, 1)
            }
            return total
        case .range(let low, let high):
            let outside = value < low ? low - value : (value > high ? value - high : 0)
            return pHWeight * min(outside, pHMaxUnits)
        case .none:
            let band = info.classBands.firstIndex { b in b.upTo.map { value <= $0 } ?? true }
            switch band {
            case 2: return hardPenalty
            case 3: return veryHardPenalty
            default: return 0
            }
        case .mustBeAbsent:
            return value > 0 ? bacteriaPenalty : 0
        }
    }
}
