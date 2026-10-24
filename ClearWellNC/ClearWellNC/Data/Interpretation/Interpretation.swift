//
//  Interpretation.swift
//  ClearWellNC
//
//  Turns a raw reading into what it means: status chip, % of limit, and one plain-English sentence.
//  Pure functions over ContaminantInfo, so every screen says the same thing.
//

import Foundation

nonisolated struct Interpretation: Sendable {
    enum Tier: Sendable {
        /// Under 50% of a health limit, in range, or not detected.
        case safe
        /// 50–99% of a health limit.
        case watch
        /// At or above a health limit, or bacteria detected.
        case above
        /// Over an aesthetic guideline: a nuisance, not a health risk.
        case nuisance
        /// Classified, not limited (hardness).
        case info
    }

    let id: ContaminantID
    /// "6 mg/L", "Present", "7.2"
    let readingText: String
    /// "10 mg/L · EPA MCL (as N)"
    let limitText: String
    /// 60 for 60%. Nil when there's no single maximum (pH, hardness, bacteria).
    let percentOfLimit: Double?
    let tier: Tier
    let chipLabel: String
    let sentence: String
    /// True when a health-based limit (or health advisory) is met or exceeded.
    let isHealthExceedance: Bool

    /// The sentence follows the confirmed water source (city users never read "your well").
    init(id: ContaminantID, readingText: String, limitText: String, percentOfLimit: Double?, tier: Tier,
         chipLabel: String, sentence: String, isHealthExceedance: Bool) {
        self.id = id
        self.readingText = readingText
        self.limitText = limitText
        self.percentOfLimit = percentOfLimit
        self.tier = tier
        self.chipLabel = chipLabel
        self.sentence = Wording.adapt(sentence)
        self.isHealthExceedance = isHealthExceedance
    }

    var percentText: String? {
        guard let percentOfLimit else { return nil }
        let pct = percentOfLimit.formatted(.number.precision(.fractionLength(0)))
        let info = id.info
        return info.limitType == .health
            ? String(localized: "\(pct)% of limit")
            : String(localized: "\(pct)% of guideline")
    }

    // MARK: Thresholds

    /// Below this share of the limit is "Safe"; at or above the limit is "Above limit".
    static let watchFraction = 0.5

    // MARK: Numeric readings

    static func interpret(_ id: ContaminantID, value: Double) -> Interpretation {
        let info = id.info
        let reading = format(value, unit: info.unit)

        switch info.limit {
        case .maximum(let limit):
            return interpretMaximum(info: info, value: value, limit: limit, reading: reading)

        case .range(let low, let high):
            let inRange = (low...high).contains(value)
            let range = "\(formatNumber(low))–\(formatNumber(high))"
            let sentence: String
            if inRange {
                sentence = String(localized: "Your \(info.name) is \(reading), inside the recommended range of \(range). There is no health-based limit for \(info.name).")
            } else if value < low {
                sentence = String(localized: "Your \(info.name) is \(reading), below the recommended range of \(range). There is no health-based limit for \(info.name), but \(info.practicalImpact ?? "").")
            } else {
                sentence = String(localized: "Your \(info.name) is \(reading), above the recommended range of \(range). There is no health-based limit for \(info.name), but \(info.practicalImpactHigh ?? info.practicalImpact ?? "").")
            }
            return Interpretation(id: id, readingText: reading, limitText: info.limitDescription, percentOfLimit: nil,
                                  tier: inRange ? .safe : .nuisance,
                                  chipLabel: inRange ? String(localized: "In range") : String(localized: "Outside range"),
                                  sentence: sentence, isHealthExceedance: false)

        case .none:
            let band = info.classBands.first { band in band.upTo.map { value <= $0 } ?? true }
            let label = band?.label ?? ""
            let impact = (band?.isNoticeable ?? false)
                ? String(localized: "You may notice \(info.practicalImpact ?? "").")
                : String(localized: "You probably won't notice scale at this level.")
            let sentence = String(localized: "Your \(info.name.inSentence) is \(reading), which counts as \(label.lowercased()) water. There is no health limit for \(info.name.inSentence). \(impact)")
            return Interpretation(id: id, readingText: reading, limitText: info.limitDescription, percentOfLimit: nil,
                                  tier: .info, chipLabel: label, sentence: sentence, isHealthExceedance: false)

        case .mustBeAbsent:
            // A numeric value for a presence test: treat any count above zero as present.
            return interpret(id, present: value > 0)
        }
    }

    private static func interpretMaximum(info: ContaminantInfo, value: Double, limit: Double,
                                         reading: String) -> Interpretation {
        let fraction = value / limit
        let pct = (fraction * 100).formatted(.number.precision(.fractionLength(0)))
        let limitWithUnit = "\(formatNumber(limit)) \(info.unit.label)"

        // A health advisory (manganese) escalates an aesthetic contaminant to a health concern.
        if let advisory = info.healthAdvisory, value >= advisory.value {
            let sentence = String(localized: "Your \(info.name.inSentence) is \(reading), which is at or above the \(formatNumber(advisory.value)) \(info.unit.label) \(advisory.source.lowercased()). \(info.actionIfAbove)")
            return Interpretation(id: info.id, readingText: reading, limitText: info.limitDescription,
                                  percentOfLimit: fraction * 100, tier: .above,
                                  chipLabel: String(localized: "Above health advisory"),
                                  sentence: sentence, isHealthExceedance: true)
        }

        switch info.limitType {
        case .health:
            let lead = String(localized: "Your \(info.name.inSentence) is \(reading), which is \(pct)% of the \(info.limitPhrase) (\(limitWithUnit)).")
            let tier: Tier
            let chip: String
            let tail: String
            if fraction >= 1 {
                tier = .above
                chip = String(localized: "Above limit")
                tail = String(localized: "This is at or above the \(info.limitPhrase). \(info.actionIfAbove)")
            } else if fraction >= watchFraction {
                tier = .watch
                chip = String(localized: "Watch")
                if let groups = groupPhrase(info.sensitiveGroups) {
                    tail = String(localized: "This is OK for adults but worth retesting if \(groups) drinks this water.")
                } else {
                    tail = String(localized: "This is under the limit, but close enough that it's worth retesting.")
                }
            } else {
                tier = .safe
                chip = String(localized: "Safe")
                tail = String(localized: "This is well below the \(info.limitPhrase).")
            }
            return Interpretation(id: info.id, readingText: reading, limitText: info.limitDescription,
                                  percentOfLimit: fraction * 100, tier: tier, chipLabel: chip,
                                  sentence: "\(lead) \(tail)", isHealthExceedance: tier == .above)

        case .aesthetic:
            let lead = String(localized: "Your \(info.name.inSentence) is \(reading), which is \(pct)% of the \(limitWithUnit) \(info.limitPhrase). There is no health-based limit at this level.")
            let impact = info.practicalImpact ?? ""
            let tier: Tier
            let chip: String
            let tail: String
            if fraction >= 1 {
                tier = .nuisance
                chip = String(localized: "Above guideline")
                tail = String(localized: "At this level you may notice \(impact).")
            } else if fraction >= watchFraction {
                tier = .watch
                chip = String(localized: "Near guideline")
                tail = String(localized: "As it gets closer to the guideline you may start to notice \(impact).")
            } else {
                tier = .safe
                chip = String(localized: "Below guideline")
                tail = String(localized: "At this level it shouldn't cause problems.")
            }
            var sentence = "\(lead) \(tail)"
            if let advisory = info.healthAdvisory {
                sentence += " " + String(localized: "It is below the \(formatNumber(advisory.value)) \(info.unit.label) \(advisory.source.lowercased()).")
            }
            return Interpretation(id: info.id, readingText: reading, limitText: info.limitDescription,
                                  percentOfLimit: fraction * 100, tier: tier, chipLabel: chip,
                                  sentence: sentence, isHealthExceedance: false)
        }
    }

    // MARK: Presence readings (bacteria)

    static func interpret(_ id: ContaminantID, present: Bool) -> Interpretation {
        let info = id.info
        if !present {
            // Keep "E. coli" capitalized; lowercase other names mid-sentence.
            let name = id == .eColi ? info.name : info.name.inSentence
            return Interpretation(
                id: id, readingText: String(localized: "Absent"), limitText: info.limitDescription, percentOfLimit: nil,
                tier: .safe, chipLabel: String(localized: "Not detected"),
                sentence: String(localized: "No \(name) was found in this test. Test for bacteria every year and after flooding."),
                isHealthExceedance: false)
        }
        let sentence = id == .eColi
            ? String(localized: "E. coli was found. This means human or animal waste is getting into your well. \(info.actionIfAbove)")
            : String(localized: "Coliform bacteria were found. They are a warning sign that germs can get into your well. \(info.actionIfAbove)")
        return Interpretation(id: id, readingText: String(localized: "Present"), limitText: info.limitDescription,
                              percentOfLimit: nil, tier: .above, chipLabel: String(localized: "Detected"),
                              sentence: sentence, isHealthExceedance: true)
    }

    // MARK: Helpers

    static func format(_ value: Double, unit: MeasurementUnit) -> String {
        let number = formatNumber(value)
        return unit.label.isEmpty ? number : "\(number) \(unit.label)"
    }

    /// "an infant or someone who is pregnant"; nil when there are no sensitive groups.
    static func groupPhrase(_ groups: [SensitiveGroup]) -> String? {
        guard !groups.isEmpty else { return nil }
        return groups.map(\.phrase).formatted(.list(type: .or))
    }

    /// The action to recommend for a reading, used by the score screen.
    var nextAction: String {
        switch tier {
        case .above, .nuisance: id.info.actionIfAbove
        case .watch: id.info.actionIfWatch
        case .safe, .info: String(localized: "Keep testing on your regular schedule.")
        }
    }
}

// MARK: - Chart captions

nonisolated enum ChartCaption {
    /// "What this chart shows" for the user's own results over time.
    static func trend(for id: ContaminantID, points: [(date: Date, value: Double)]) -> String {
        let info = id.info
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else {
            return String(localized: "No \(info.name) results yet.")
        }
        guard sorted.count > 1 else {
            return String(localized: "This shows your one \(info.name.inSentence) test so far. Add results over time to see a trend.") + " "
                + Interpretation.interpret(id, value: last.value).nextActionSentence
        }

        let firstText = Interpretation.format(first.value, unit: info.unit)
        let lastText = Interpretation.format(last.value, unit: info.unit)
        let direction: String
        let base = max(abs(first.value), 1e-9)
        let change = (last.value - first.value) / base
        if abs(change) < 0.10 {
            direction = String(localized: "Your \(info.name.inSentence) stayed about the same (\(firstText) to \(lastText)) across \(sorted.count) tests.")
        } else if change > 0 {
            direction = String(localized: "Your \(info.name.inSentence) went up from \(firstText) to \(lastText) across \(sorted.count) tests.")
        } else {
            direction = String(localized: "Your \(info.name.inSentence) went down from \(firstText) to \(lastText) across \(sorted.count) tests.")
        }

        let interpretations = sorted.map { Interpretation.interpret(id, value: $0.value) }
        let overCount = interpretations.filter { $0.tier == .above || $0.tier == .nuisance }.count
        let crossing: String
        let word = info.limitType == .health ? String(localized: "limit") : String(localized: "guideline")
        switch info.limit {
        case .maximum, .range:
            if overCount > 0 {
                crossing = String(localized: "\(overCount) of \(sorted.count) tests crossed the \(word).")
            } else if interpretations.contains(where: { $0.tier == .watch }) {
                crossing = String(localized: "All tests were under the \(word), but some were close.")
            } else {
                crossing = String(localized: "All tests were well under the \(word).")
            }
        case .none, .mustBeAbsent:
            crossing = ""
        }
        let latest = Interpretation.interpret(id, value: last.value)
        return [direction, crossing, latest.nextActionSentence].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Caption for the report's area-vs-statewide bar.
    static func areaComparison(_ risk: ContaminantRisk) -> String {
        let name = risk.contaminant.name
        let comparison: String
        if risk.ratio >= 1.15 {
            let times = risk.ratio.formatted(.number.precision(.fractionLength(0...1)))
            comparison = String(localized: "The estimated share of wells near you above the \(name.inSentence) limit is about \(times) times the statewide rate.")
        } else if risk.ratio >= 0.85 {
            comparison = String(localized: "The estimated share of wells near you above the \(name.inSentence) limit is about the same as the statewide rate.")
        } else {
            comparison = String(localized: "The estimated share of wells near you above the \(name.inSentence) limit is lower than the statewide rate.")
        }
        return comparison + " " + String(localized: "This describes wells in your area, not your well. Only a test tells you about yours.")
    }
}

private nonisolated extension Interpretation {
    var nextActionSentence: String { nextAction }
}
