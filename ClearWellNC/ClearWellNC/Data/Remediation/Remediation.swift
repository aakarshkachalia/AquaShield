//
//  Remediation.swift
//  ClearWellNC
//
//  What to do: free fixes first, then only filters whose certified claims cover the contaminants driving
//  this home's risk at the levels measured here. No affiliate links, no invented products.
//

import Foundation

nonisolated struct FixStep: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable {
        case flushTaps, coldWaterOnly, shockChlorinate, checkWellCap, checkSeptic, askUtilityLeadLine, retest, bottledWater
    }
    let kind: Kind
    let title: String
    let detail: String
    let symbol: String
    var id: Kind { kind }
}

nonisolated struct ProductMatch: Sendable, Equatable, Identifiable {
    let product: FilterProduct
    /// Drivers this product is certified to reduce at the measured level.
    let covered: [ClaimTarget]
    let drivers: [ClaimTarget]
    var id: String { product.id }

    /// Share of driving contaminants covered, 0–100.
    var coveragePercent: Int { drivers.isEmpty ? 0 : Int((Double(covered.count) / Double(drivers.count) * 100).rounded()) }
    var annualCost: Double? { product.annualCostUSD }
    var capacityGallons: Double? { product.ratedCapacityGallons }
    var certifiers: [Certifier] {
        var seen: [Certifier] = []
        for claim in product.claims where covered.contains(claim.target) && !seen.contains(claim.certifier) {
            seen.append(claim.certifier)
        }
        return seen
    }
}

nonisolated struct RemediationPlan: Sendable, Equatable {
    let drivers: [ClaimTarget]
    let fixes: [FixStep]
    /// Grouped by filter type, best coverage then cheapest first within each group.
    let productsByType: [(type: FilterType, matches: [ProductMatch])]
    /// The cheapest certified option that covers something, always shown.
    let affordablePick: ProductMatch?
    let volatileNote: String?
    let skinCare: SkinCareAdvice?

    static func == (a: Self, b: Self) -> Bool {
        a.drivers == b.drivers && a.fixes == b.fixes && a.affordablePick == b.affordablePick
            && a.productsByType.map(\.type) == b.productsByType.map(\.type)
            && a.productsByType.map(\.matches) == b.productsByType.map(\.matches)
            && a.volatileNote == b.volatileNote && a.skinCare == b.skinCare
    }

    var allMatches: [ProductMatch] { productsByType.flatMap(\.matches) }
}

nonisolated struct SkinCareAdvice: Sendable, Equatable {
    let tips: [String]
    let avoid: [String]
    let redFlag: String?
}

nonisolated enum Remediation {
    static func plan(source: WaterSource, drinking: TapScoreResult?, showers: [TapScoreResult],
                     home: HomeProfile, members: [HouseholdMember], products: [FilterProduct],
                     now: Date = .now) -> RemediationPlan {
        let drinkingItems = drinking?.items ?? []
        let problem: (TapItem) -> Bool = { $0.level == .unsafe || $0.level == .fair || $0.level == .poor }
        let drivers = drinkingItems.filter(problem).map(\.target)
        let showerDrivers = showers.flatMap(\.items).filter { problem($0) && $0.target.isVolatile }.map(\.target)
        let missing = Set(drinking?.missingTests ?? [])

        // Free fixes first.
        var fixes: [FixStep] = []
        let germs = drinkingItems.contains { $0.target.isMicrobial && $0.present == true }
        let overHealthLimit = drinkingItems.contains { $0.level == .unsafe && $0.limit?.kind == .health }
        if germs || overHealthLimit || drivers.contains(.nitrate) && members.contains(where: \.infantOnFormula) {
            fixes.append(FixStep(kind: .bottledWater, title: String(localized: "Use bottled water for now"),
                                 detail: String(localized: "For drinking, cooking, formula and brushing teeth, until a new test is clear."),
                                 symbol: "waterbottle.fill"))
        }
        let leadConcern = drivers.contains(.lead) || drivers.contains(.copper)
            || (missing.contains(.lead) && home.leadPlumbingRisk)
        if leadConcern {
            fixes.append(FixStep(kind: .flushTaps, title: String(localized: "Run the tap before drinking"),
                                 detail: String(localized: "If water sat for hours, run cold water 30 seconds to 2 minutes, until it feels colder."),
                                 symbol: "drop.degreesign.fill"))
            fixes.append(FixStep(kind: .coldWaterOnly, title: String(localized: "Cook with cold water only"),
                                 detail: String(localized: "Hot water pulls more lead from pipes. Heat cold water on the stove instead."),
                                 symbol: "snowflake"))
            if source.hasUtility || source == .notSure {
                fixes.append(FixStep(kind: .askUtilityLeadLine, title: String(localized: "Ask your utility about a lead service line"),
                                     detail: String(localized: "They keep a list of which homes have one, and may replace it."),
                                     symbol: "phone.fill"))
            }
        }
        if source.showsWellCare && germs {
            fixes.append(FixStep(kind: .shockChlorinate, title: String(localized: "Shock chlorinate the well"),
                                 detail: String(localized: "A one-time dose of chlorine to kill germs in the well and pipes. Many well services do this."),
                                 symbol: "drop.triangle.fill"))
            fixes.append(FixStep(kind: .checkWellCap, title: String(localized: "Check the well cap and casing"),
                                 detail: String(localized: "Cracks or a loose cap let surface water and insects in."),
                                 symbol: "wrench.and.screwdriver.fill"))
        }
        if source.showsWellCare && (germs || drivers.contains(.nitrate)) && home.septicDistanceFeet != nil && home.septicTooClose {
            fixes.append(FixStep(kind: .checkSeptic, title: String(localized: "Septic system may be too close"),
                                 detail: String(localized: "Wells should usually be at least \(Int(HomeProfile.septicSetbackFeet)) feet from a septic system. Ask your county health department."),
                                 symbol: "ruler.fill"))
        }
        if !fixes.isEmpty || !drivers.isEmpty {
            fixes.append(FixStep(kind: .retest, title: String(localized: "Retest after fixing"),
                                 detail: String(localized: "A new test shows whether the fix worked."),
                                 symbol: "testtube.2"))
        }

        // Products: only claims that cover a driver at its measured level.
        let healthDrivers = drivers.filter { target in
            drinkingItems.first { $0.target == target }?.limit?.kind != .aesthetic
        }
        let wanted = healthDrivers.isEmpty ? drivers : healthDrivers
        var matches: [ProductMatch] = []
        for product in products where product.isCertified {
            let trial = InstalledFilter(id: product.id, name: product.displayName, type: product.type,
                                        location: product.type.defaultLocation, product: product, installedAt: now,
                                        intervalMonths: product.ratedLifeMonths, gallonsPerDay: nil)
            let covered = wanted.filter { target in
                let influent = drinkingItems.first { $0.target == target }?.residual
                return FilterRules.effect(of: trial, on: target, influent: influent, at: now).reductionPercent > 0
            }
            if !covered.isEmpty {
                matches.append(ProductMatch(product: product, covered: covered, drivers: wanted))
            }
        }
        let sorted = matches.sorted { a, b in
            if a.coveragePercent != b.coveragePercent { return a.coveragePercent > b.coveragePercent }
            return (a.annualCost ?? .infinity) < (b.annualCost ?? .infinity)
        }
        var groups: [(type: FilterType, matches: [ProductMatch])] = []
        for type in FilterType.allCases {
            let inType = sorted.filter { $0.product.type == type }
            if !inType.isEmpty { groups.append((type, inType)) }
        }
        let affordable = matches.filter { $0.annualCost != nil }.min { ($0.annualCost ?? 0) < ($1.annualCost ?? 0) }

        // Shower inhalation.
        let volatileTargets = Array(Set(drivers + showerDrivers).filter(\.isVolatile)).sorted { $0.rawValue < $1.rawValue }
        let volatileNote: String? = volatileTargets.isEmpty ? nil : String(localized: "\(volatileTargets.map(\.name).formatted(.list(type: .and))) can be breathed in as steam. Only whole-house treatment protects you in the shower; a kitchen filter doesn't.")

        return RemediationPlan(drivers: drivers, fixes: fixes, productsByType: groups, affordablePick: affordable,
                               volatileNote: volatileNote,
                               skinCare: skinCare(drinking: drinking, showers: showers, members: members, source: source))
    }

    /// Water-related dryness and irritation only. Red flags go to a doctor.
    static func skinCare(drinking: TapScoreResult?, showers: [TapScoreResult], members: [HouseholdMember],
                         source: WaterSource) -> SkinCareAdvice? {
        let items = showers.flatMap(\.items) + (drinking?.items ?? [])
        let hard = items.contains { $0.target == .hardness && ($0.ratio ?? 0) >= 1 }
            || items.contains { $0.target == .hardness && ($0.residual ?? 0) > 120 }
        let chlorine = items.contains { ($0.target == .freeChlorine || $0.target == .chloramine) && ($0.residual ?? 0) > 0 }
        let skinSymptoms = members.contains { $0.eczema || $0.symptoms.contains(.drySkin) || $0.symptoms.contains(.rash) }
        let redFlag = source.showsWellCare && members.contains { $0.symptoms.contains(where: \.isArsenicSkinRedFlag) }
        guard hard || chlorine || skinSymptoms || redFlag else { return nil }

        var tips = [
            String(localized: "Take short, lukewarm showers, not hot ones."),
            String(localized: "Within 3 minutes of drying off, put on a fragrance-free moisturizer."),
            String(localized: "Use a gentle, fragrance-free cleanser instead of harsh soap."),
            String(localized: "A colloidal oatmeal bath can calm dry, itchy skin."),
        ]
        if hard { tips.append(String(localized: "Your water is hard. A water softener can help dry skin.")) }
        return SkinCareAdvice(
            tips: tips,
            avoid: [String(localized: "Don't put lemon juice, undiluted vinegar or essential oils on your skin.")],
            redFlag: redFlag ? String(localized: "Dark patches or thick skin on palms or soles: see a doctor and test for arsenic.") : nil)
    }
}
