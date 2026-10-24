//
//  TapScore.swift
//  ClearWellNC
//
//  The per-tap score: Well Health Score rules applied to the water that actually comes out of one tap,
//  after the filters on its path. Pure and unit-tested; no UI, no SwiftData.
//
//  1. Filters apply in flow order: whole house first, then the tap's own (point-of-use) filters.
//     A filter reduces a contaminant only if it has a certification claim for it, under a standard that
//     covers it, tested at or above the measured level, and it isn't expired:
//         residual = influent × (1 − reduction)
//     Otherwise it reduces nothing, and the reading carries a flag saying why.
//  2. Scoring starts at 100. Health results take away up to 30 points each (as in WellHealthScore);
//     taste and staining issues take away 10 points at most, all together.
//  3. Caps: any health result at or above its limit → 40 or lower; bacteria at a drinking tap → 20 or lower.
//     Dangerous readings are never averaged away.
//  4. Missing recommended tests lower confidence, never the score.
//  5. Home test kits can't show lead, arsenic, PFAS, nitrate or uranium as fine: those results are
//     "Inconclusive — confirm with a certified lab" and count as missing for confidence.
//

import Foundation

// MARK: - Inputs

nonisolated enum TestMethod: String, Codable, CaseIterable, Sendable {
    case certifiedLab, homeKit, utilityReport, unknown

    var label: String {
        switch self {
        case .certifiedLab: String(localized: "Certified lab")
        case .homeKit: String(localized: "Home test kit or strip")
        case .utilityReport: String(localized: "Utility report")
        case .unknown: String(localized: "Not sure")
        }
    }
}

/// One measured value at the source (before any filter), in the target's canonical unit.
nonisolated struct Reading: Sendable, Equatable {
    let target: ClaimTarget
    /// Concentration, or nil for presence/absence tests.
    var value: Double?
    /// Bacteria and other presence tests.
    var present: Bool?
    /// "Not detected": `value` is the lab's detection limit, and the residual counts as zero.
    var isNonDetect = false
    var method: TestMethod = .certifiedLab

    static func amount(_ target: ClaimTarget, _ value: Double, unit: ReadingUnit? = nil,
                       method: TestMethod = .certifiedLab, nonDetect: Bool = false) -> Reading? {
        let canonical = ReadingUnit.canonical(for: target)
        guard let converted = ReadingUnit.convert(value, from: unit ?? canonical, to: canonical) else { return nil }
        return Reading(target: target, value: converted, isNonDetect: nonDetect, method: method)
    }

    static func presence(_ target: ClaimTarget, present: Bool, method: TestMethod = .certifiedLab) -> Reading {
        Reading(target: target, present: present, method: method)
    }
}

/// A filter the household has installed, resolved against its product (if any).
nonisolated struct InstalledFilter: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var type: FilterType
    var location: TapLocation
    var product: FilterProduct?
    var installedAt: Date
    /// The replacement interval the user set, used when the product doesn't give one.
    var intervalMonths: Int?
    /// Estimated gallons through this filter per day. Nil when unknown (gallon expiry not checked).
    var gallonsPerDay: Double?

    var lifeMonths: Int? { product?.ratedLifeMonths ?? intervalMonths }
    var capacityGallons: Double? { product?.ratedCapacityGallons }

    func dueDate(calendar: Calendar = .current) -> Date? {
        var dates: [Date] = []
        if let months = lifeMonths, let date = calendar.date(byAdding: .month, value: months, to: installedAt) {
            dates.append(date)
        }
        if let capacity = capacityGallons, let perDay = gallonsPerDay, perDay > 0 {
            dates.append(installedAt.addingTimeInterval(capacity / perDay * 86_400))
        }
        return dates.min()
    }

    func isExpired(at now: Date, calendar: Calendar = .current) -> Bool {
        dueDate(calendar: calendar).map { now >= $0 } ?? false
    }

    func daysUntilDue(from now: Date, calendar: Calendar = .current) -> Int? {
        dueDate(calendar: calendar).map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: $0)).day ?? 0
        }
    }
}

// MARK: - Filter rules

nonisolated enum FilterFlag: String, Sendable, Hashable {
    /// No certification claims at all.
    case uncertified
    /// Past its months or gallons.
    case expired
    /// The measured level is higher than the level it was certified against.
    case aboveCertifiedLevel
    /// The claim doesn't say what level it was tested at.
    case noChallengeLevel
    /// Certified, but not for this contaminant.
    case notCovered
    /// Shower filters (NSF/ANSI 177) reduce free chlorine only.
    case showerChlorineOnly
    /// UV only affects germs.
    case uvMicrobesOnly

    var label: String {
        switch self {
        case .uncertified: String(localized: "Uncertified")
        case .expired: String(localized: "Filter expired")
        case .aboveCertifiedLevel: String(localized: "Above certified test level")
        case .noChallengeLevel: String(localized: "Certified test level unknown")
        case .notCovered: String(localized: "Not certified for this")
        case .showerChlorineOnly: String(localized: "Shower filters reduce chlorine only")
        case .uvMicrobesOnly: String(localized: "UV only treats germs")
        }
    }
}

nonisolated struct FilterEffect: Sendable, Equatable {
    /// 0–100.
    let reductionPercent: Double
    let flag: FilterFlag?
    /// The claim that counted, if any.
    let claim: CertificationClaim?

    static func none(_ flag: FilterFlag) -> FilterEffect { FilterEffect(reductionPercent: 0, flag: flag, claim: nil) }
}

nonisolated enum FilterRules {
    /// What `filter` does to `target` at concentration `influent` (canonical units; nil for presence tests).
    static func effect(of filter: InstalledFilter, on target: ClaimTarget, influent: Double?, at now: Date) -> FilterEffect {
        if filter.type == .uv && !target.isMicrobial { return .none(.uvMicrobesOnly) }
        if filter.type == .shower && target != .freeChlorine { return .none(.showerChlorineOnly) }
        if filter.isExpired(at: now) { return .none(.expired) }
        guard let product = filter.product, product.isCertified else { return .none(.uncertified) }
        guard let claim = product.claims.first(where: { $0.target == target && $0.standard.allowedTargets.contains(target) })
        else { return .none(.notCovered) }
        if !target.isMicrobial {
            guard let challenge = claim.influentChallengeConcentration else { return .none(.noChallengeLevel) }
            if let influent, influent > challenge { return .none(.aboveCertifiedLevel) }
        }
        return FilterEffect(reductionPercent: min(max(claim.reductionPercent, 0), 100), flag: nil, claim: claim)
    }

    /// Filters on the path to `tap`, in flow order: whole house first, then that tap's own.
    static func path(to tap: TapLocation, filters: [InstalledFilter]) -> [InstalledFilter] {
        let ordered = filters.sorted { $0.installedAt < $1.installedAt }
        let house = ordered.filter { $0.location == .wholeHouse }
        guard tap != .wholeHouse else { return house }
        return house + ordered.filter { $0.location == tap }
    }
}

// MARK: - Limits

/// The limit each target is judged against, with its source.
nonisolated struct TargetLimit: Sendable, Equatable {
    enum Kind: Sendable { case health, aesthetic, mustBeAbsent }
    let kind: Kind
    /// Canonical units; 0 for must-be-absent.
    let value: Double
    let source: String

    static func limit(for target: ClaimTarget) -> TargetLimit? {
        switch target {
        // Not in ContaminantInfo yet: EPA values (needs verification, see SourceRef.epaDBP / epaNPDWR).
        case .tthm: return TargetLimit(kind: .health, value: 80, source: SourceRef.epaDBP.sourceName)
        case .haa5: return TargetLimit(kind: .health, value: 60, source: SourceRef.epaDBP.sourceName)
        case .freeChlorine, .chloramine:
            // EPA maximum residual disinfectant level, 4 mg/L.
            return TargetLimit(kind: .health, value: 4, source: SourceRef.epaDBP.sourceName)
        case .bacteria, .viruses, .cysts:
            return TargetLimit(kind: .mustBeAbsent, value: 0, source: String(localized: "EPA Total Coliform Rule"))
        case .vocs:
            return nil
        default:
            guard let id = target.contaminantID else { return nil }
            let info = id.info
            guard case .maximum(let max) = info.limit else { return nil }
            // Manganese is judged by its health advisory, not its staining guideline.
            if let advisory = info.healthAdvisory {
                return TargetLimit(kind: .health, value: advisory.value, source: advisory.source)
            }
            return TargetLimit(kind: info.limitType == .health ? .health : .aesthetic, value: max, source: info.limitSource)
        }
    }
}

extension ClaimTarget {
    /// The lab contaminant for this target, when there is one.
    nonisolated var contaminantID: ContaminantID? {
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
        case .radon: .radon
        case .pfoa: .pfoa
        case .pfos: .pfos
        case .genx: .genx
        case .hardness: .hardness
        case .bacteria: .totalColiform
        case .viruses, .cysts, .freeChlorine, .chloramine, .tthm, .haa5, .vocs: nil
        }
    }

    /// Home kits can't clear these (testing-quality rule).
    nonisolated var needsCertifiedLabToClear: Bool {
        [.lead, .arsenic, .pfoa, .pfos, .genx, .nitrate, .uranium].contains(self)
    }

    /// Matters for showering: breathed in as steam, or affects skin and hair.
    nonisolated var mattersInShower: Bool {
        isVolatile || [.freeChlorine, .chloramine, .hardness, .iron, .manganese].contains(self)
    }
}

// MARK: - Result

nonisolated struct TapItem: Sendable, Identifiable, Equatable {
    enum Level: Sendable, Equatable { case good, fair, poor, unsafe, inconclusive, notScored }

    let target: ClaimTarget
    let influent: Double?
    let residual: Double?
    let present: Bool?
    let limit: TargetLimit?
    let level: Level
    let flags: [FilterFlag]
    /// Filters that counted, in order.
    let appliedFilters: [String]
    let penalty: Double
    let explanation: String

    var id: ClaimTarget { target }
    var ratio: Double? {
        guard let residual, let limit, limit.value > 0 else { return nil }
        return residual / limit.value
    }
}

nonisolated struct TapScoreResult: Sendable, Equatable {
    enum Confidence: String, Sendable { case high, medium, low }

    let tap: TapLocation
    let score: Int
    let band: WellHealthScore.Band
    let confidence: Confidence
    /// Recommended tests for this water source with no usable result (missing or inconclusive).
    let missingTests: [ClaimTarget]
    /// Worst first.
    let items: [TapItem]
    let capReason: String?

    var confidenceText: String {
        let shown = Array(missingTests.prefix(2))
        let names = shown.map { $0.name.inSentence }.formatted(.list(type: .and))
        let tests = shown.count == 1 ? String(localized: "test") : String(localized: "tests")
        switch confidence {
        case .high: return String(localized: "High")
        case .medium: return String(localized: "Medium — missing \(names) \(tests)")
        case .low:
            return missingTests.isEmpty ? String(localized: "Low")
                : String(localized: "Low — missing \(names) \(tests)")
        }
    }

    var explanation: String {
        var text = String(localized: "\(score) out of 100 for \(tap.name.inSentence).")
        if let capReason { text += " " + capReason }
        return text
    }
}

// MARK: - Engine

extension WellHealthScore {
    nonisolated static let tapBacteriaCap = 20
    nonisolated static let tapAestheticMaxTotal = 10.0

    nonisolated static func tapScore(tap: TapLocation, source: WaterSource, readings: [Reading],
                         filters: [InstalledFilter], now: Date = .now) -> TapScoreResult {
        let path = FilterRules.path(to: tap, filters: filters)
        let isShower = tap.kind == .shower
        var items: [TapItem] = []

        // One reading per target: the most recent caller-supplied one wins (callers pass latest first).
        var seen: Set<ClaimTarget> = []
        for reading in readings where seen.insert(reading.target).inserted {
            items.append(item(for: reading, path: path, isShower: isShower, now: now))
        }

        // Score.
        var healthPenalty = 0.0
        var aestheticPenalty = 0.0
        for item in items {
            switch item.limit?.kind {
            case .health, .mustBeAbsent: healthPenalty += item.penalty
            case .aesthetic: aestheticPenalty += item.penalty
            case nil: break
            }
        }
        var score = Int(max(0, 100 - healthPenalty - min(aestheticPenalty, tapAestheticMaxTotal)).rounded())
        var capReason: String?
        if items.contains(where: { $0.level == .unsafe && $0.limit?.kind == .health }) {
            score = min(score, healthExceedanceCap)
            capReason = String(localized: "A result is above a health limit, so the score can't go above \(healthExceedanceCap).")
        }
        if !isShower, items.contains(where: { $0.target.isMicrobial && $0.present == true }) {
            score = min(score, tapBacteriaCap)
            capReason = String(localized: "Germs were found, so the score can't go above \(tapBacteriaCap).")
        }

        // Confidence.
        let recommended = recommendedTargets(for: source, isShower: isShower)
        let usable = Set(items.filter { $0.level != .inconclusive }.map(\.target))
        let missing = recommended.filter { !usable.contains($0) }
        let critical = Array(recommended.prefix(3))
        let confidence: TapScoreResult.Confidence =
            missing.isEmpty ? .high : (missing.contains(where: critical.contains) || missing.count >= 3 ? .low : .medium)

        items.sort { severity($0) > severity($1) }
        return TapScoreResult(tap: tap, score: score, band: Band.from(score: score), confidence: confidence,
                              missingTests: missing, items: items, capReason: capReason)
    }

    /// Recommended tests for a source, most important first.
    nonisolated static func recommendedTargets(for source: WaterSource, isShower: Bool) -> [ClaimTarget] {
        var targets: [ClaimTarget] = []
        for id in source.keyContaminants {
            if let target = ClaimTarget(contaminant: id), !targets.contains(target) { targets.append(target) }
        }
        return isShower ? targets.filter(\.mattersInShower) : targets
    }

    nonisolated private static func item(for reading: Reading, path: [InstalledFilter], isShower: Bool, now: Date) -> TapItem {
        let target = reading.target
        let limit = TargetLimit.limit(for: target)
        var flags: [FilterFlag] = []
        var applied: [String] = []

        // Presence tests (germs).
        if target.isMicrobial {
            var present = reading.present ?? false
            if present {
                for filter in path {
                    let effect = FilterRules.effect(of: filter, on: target, influent: nil, at: now)
                    if let flag = effect.flag { flags.append(flag) }
                    if effect.reductionPercent >= 99.99 {
                        present = false
                        applied.append(filter.name)
                        break
                    }
                }
            }
            let level: TapItem.Level = present ? .unsafe : .good
            let explanation = present
                ? String(localized: "Germs were found. Don't drink this water until a new test is clear.")
                : (reading.present == true
                    ? String(localized: "Germs were found at the source, but \(applied.joined()) is certified to treat them. Retest to confirm.")
                    : String(localized: "No germs were found."))
            return TapItem(target: target, influent: nil, residual: nil, present: present, limit: limit, level: level,
                           flags: flags.uniqued(), appliedFilters: applied,
                           penalty: present ? bacteriaPenalty : 0, explanation: explanation)
        }

        guard let influent = reading.value else {
            return TapItem(target: target, influent: nil, residual: nil, present: nil, limit: limit, level: .notScored,
                           flags: [], appliedFilters: [], penalty: 0, explanation: String(localized: "No number on file."))
        }

        // Filters, in order.
        var residual = reading.isNonDetect ? 0 : influent
        for filter in path where residual > 0 {
            let effect = FilterRules.effect(of: filter, on: target, influent: residual, at: now)
            if let flag = effect.flag {
                // Only worth showing when the filter could have mattered.
                if flag != .notCovered || filter.location != .wholeHouse { flags.append(flag) }
            }
            if effect.reductionPercent > 0 {
                residual *= 1 - effect.reductionPercent / 100
                applied.append(filter.name)
            }
        }

        let unit = ReadingUnit.canonical(for: target).label
        guard let limit else {
            return TapItem(target: target, influent: influent, residual: residual, present: nil, limit: nil,
                           level: .notScored, flags: flags, appliedFilters: applied, penalty: 0,
                           explanation: String(localized: "\(formatNumber(residual)) \(unit). There's no single limit for this."))
        }

        // In the shower, drinking-only contaminants don't count toward the score.
        if isShower && !target.mattersInShower {
            return TapItem(target: target, influent: influent, residual: residual, present: nil, limit: limit,
                           level: .notScored, flags: [], appliedFilters: applied, penalty: 0,
                           explanation: String(localized: "Mainly a concern for drinking and cooking, not showering."))
        }

        let ratio = limit.value > 0 ? residual / limit.value : 0
        // A utility's lead number comes from sampled homes, not this tap: it can't clear lead here.
        if reading.method == .utilityReport && target == .lead && ratio < 1 {
            return TapItem(target: target, influent: influent, residual: residual, present: nil, limit: limit,
                           level: .inconclusive, flags: flags, appliedFilters: applied, penalty: 0,
                           explanation: String(localized: "Your utility's number isn't your tap. Test your own tap for lead."))
        }
        // Testing-quality rule: a home kit can show a problem, but can't clear one of these.
        if reading.method == .homeKit && target.needsCertifiedLabToClear && ratio < 1 {
            return TapItem(target: target, influent: influent, residual: residual, present: nil, limit: limit,
                           level: .inconclusive, flags: flags, appliedFilters: applied, penalty: 0,
                           explanation: String(localized: "Inconclusive — confirm with a certified lab."))
        }

        let level: TapItem.Level
        let penalty: Double
        switch limit.kind {
        case .health, .mustBeAbsent:
            penalty = healthWeight * min(ratio, 1)
            level = ratio >= 1 ? .unsafe : (ratio >= 0.5 ? .fair : .good)
        case .aesthetic:
            penalty = aestheticWeight * min(ratio, aestheticMaxFraction)
            level = ratio >= 1 ? .poor : .good
        }

        let limitText = "\(formatNumber(limit.value)) \(unit)"
        var explanation: String
        if reading.isNonDetect {
            explanation = String(localized: "Not detected (below \(formatNumber(influent)) \(unit)).")
        } else if applied.isEmpty {
            explanation = String(localized: "\(formatNumber(residual)) \(unit) at this tap. The limit is \(limitText).")
        } else {
            explanation = String(localized: "\(formatNumber(influent)) \(unit) at the source, about \(formatNumber(residual)) \(unit) after \(applied.formatted(.list(type: .and))). The limit is \(limitText).")
        }
        if let flag = flags.first, applied.isEmpty, ratio >= 0.5 {
            explanation += " " + String(localized: "Your filter doesn't count here: \(flag.label.lowercased()).")
        }
        return TapItem(target: target, influent: influent, residual: residual, present: nil, limit: limit, level: level,
                       flags: flags.uniqued(), appliedFilters: applied,
                       penalty: penalty, explanation: explanation)
    }

    nonisolated private static func severity(_ item: TapItem) -> Double {
        switch item.level {
        case .unsafe: 1000 + (item.ratio ?? 1)
        case .poor, .fair: 100 + (item.ratio ?? 0)
        case .inconclusive: 50
        case .good: item.ratio ?? 0
        case .notScored: -1
        }
    }
}

extension Array where Element: Hashable {
    /// Keeps the first of each element, in order.
    nonisolated func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
