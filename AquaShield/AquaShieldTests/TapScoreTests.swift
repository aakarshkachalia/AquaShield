//
//  TapScoreTests.swift
//  AquaShieldTests
//
//  Per-tap score: filter claims, challenge levels, expiry, shower and UV rules, caps, confidence,
//  test-kit rule, units and non-detects. Plus household exposure alerts.
//

import XCTest
@testable import AquaShield

final class TapScoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let unverified = SourceRef("Test")

    private func claim(_ target: ClaimTarget, _ standard: CertificationStandard, reduction: Double = 99,
                       challenge: Double? = 1000) -> CertificationClaim {
        CertificationClaim(standard: standard, certifier: .nsf, target: target, reductionPercent: reduction,
                           influentChallengeConcentration: challenge, source: unverified)
    }

    private func filter(_ type: FilterType, at location: TapLocation = .kitchen, claims: [CertificationClaim],
                        installedDaysAgo: Double = 10, months: Int? = 6, capacity: Double? = nil,
                        gallonsPerDay: Double? = nil, name: String = "Filter") -> InstalledFilter {
        let product = FilterProduct(id: UUID().uuidString, brand: "Sample", model: name, type: type, claims: claims,
                                    ratedCapacityGallons: capacity, ratedLifeMonths: months, source: unverified)
        return InstalledFilter(id: UUID().uuidString, name: name, type: type, location: location, product: product,
                               installedAt: now.addingTimeInterval(-installedDaysAgo * 86_400), intervalMonths: months,
                               gallonsPerDay: gallonsPerDay)
    }

    private func score(_ readings: [Reading?], filters: [InstalledFilter] = [], tap: TapLocation = .kitchen,
                       source: WaterSource = .privateWell) -> TapScoreResult {
        WellHealthScore.tapScore(tap: tap, source: source, readings: readings.compactMap { $0 }, filters: filters, now: now)
    }

    private func item(_ result: TapScoreResult, _ target: ClaimTarget) -> TapItem {
        result.items.first { $0.target == target }!
    }

    // MARK: Filter claims

    func testLeadOnlyClaimDoesNotReducePFAS() {
        let f = filter(.pitcher, claims: [claim(.lead, .nsf53)])
        let result = score([.amount(.pfoa, 8), .amount(.lead, 10)], filters: [f])
        XCTAssertEqual(item(result, .pfoa).residual, 8)
        XCTAssertTrue(item(result, .pfoa).flags.contains(.notCovered))
        XCTAssertEqual(item(result, .lead).residual!, 0.1, accuracy: 0.0001)
    }

    func testInfluentAboveChallengeGetsNoReduction() {
        let f = filter(.underSinkCarbon, claims: [claim(.lead, .nsf53, challenge: 150)])
        let result = score([.amount(.lead, 200)], filters: [f])
        XCTAssertEqual(item(result, .lead).residual, 200)
        XCTAssertTrue(item(result, .lead).flags.contains(.aboveCertifiedLevel))
        XCTAssertEqual(item(result, .lead).level, .unsafe)
    }

    func testMissingChallengeLevelGetsNoReduction() {
        let f = filter(.faucet, claims: [claim(.lead, .nsf53, challenge: nil)])
        let result = score([.amount(.lead, 10)], filters: [f])
        XCTAssertEqual(item(result, .lead).residual, 10)
        XCTAssertTrue(item(result, .lead).flags.contains(.noChallengeLevel))
    }

    func testExpiredByMonthsGetsNoReduction() {
        let f = filter(.pitcher, claims: [claim(.lead, .nsf53)], installedDaysAgo: 200, months: 2)
        let result = score([.amount(.lead, 10)], filters: [f])
        XCTAssertEqual(item(result, .lead).residual, 10)
        XCTAssertTrue(item(result, .lead).flags.contains(.expired))
    }

    func testExpiredByGallonsGetsNoReduction() {
        let f = filter(.pitcher, claims: [claim(.lead, .nsf53)], installedDaysAgo: 30, months: 12,
                       capacity: 40, gallonsPerDay: 2)
        XCTAssertTrue(f.isExpired(at: now))
        let result = score([.amount(.lead, 10)], filters: [f])
        XCTAssertEqual(item(result, .lead).residual, 10)
    }

    func testShowerFilterDoesNotReduceLead() {
        let shower = TapLocation(kind: .shower)
        // Even a (wrong) lead claim on a shower filter doesn't count.
        let f = filter(.shower, at: shower, claims: [claim(.freeChlorine, .nsf177), claim(.lead, .nsf53)])
        let effect = FilterRules.effect(of: f, on: .lead, influent: 10, at: now)
        XCTAssertEqual(effect.reductionPercent, 0)
        XCTAssertEqual(effect.flag, .showerChlorineOnly)
        let chlorine = FilterRules.effect(of: f, on: .freeChlorine, influent: 1, at: now)
        XCTAssertEqual(chlorine.reductionPercent, 99)
    }

    func testStandard177ClaimForOtherTargetsNeverCounts() {
        let f = filter(.countertop, claims: [claim(.lead, .nsf177)])
        XCTAssertEqual(FilterRules.effect(of: f, on: .lead, influent: 10, at: now).flag, .notCovered)
    }

    func testUVOnlyTreatsGerms() {
        let uv = filter(.uv, at: .wholeHouse, claims: [claim(.bacteria, .nsf55, reduction: 99.99)])
        XCTAssertEqual(FilterRules.effect(of: uv, on: .arsenic, influent: 5, at: now).flag, .uvMicrobesOnly)
        let result = score([.presence(.bacteria, present: true)], filters: [uv])
        XCTAssertEqual(item(result, .bacteria).present, false)
    }

    func testUncertifiedProductContributesNothing() {
        let f = filter(.pitcher, claims: [])
        let result = score([.amount(.lead, 10)], filters: [f])
        XCTAssertEqual(item(result, .lead).residual, 10)
        XCTAssertTrue(item(result, .lead).flags.contains(.uncertified))
    }

    func testWholeHouseAppliesBeforePointOfUse() {
        let house = filter(.wholeHouse, at: .wholeHouse, claims: [claim(.lead, .nsf53, reduction: 50, challenge: 150)],
                           name: "House")
        // Point-of-use challenge 10: the reading only qualifies after the whole-house filter halves it.
        let tap = filter(.faucet, claims: [claim(.lead, .nsf53, reduction: 90, challenge: 10)], name: "Tap")
        let result = score([.amount(.lead, 20)], filters: [tap, house])
        XCTAssertEqual(item(result, .lead).residual!, 1, accuracy: 0.0001)
        XCTAssertEqual(item(result, .lead).appliedFilters, ["House", "Tap"])
        XCTAssertEqual(FilterRules.path(to: .kitchen, filters: [tap, house]).map(\.name), ["House", "Tap"])
    }

    // MARK: Caps and scoring

    func testBacteriaCapsDrinkingTapAt20() {
        let result = score([.presence(.bacteria, present: true), .amount(.nitrate, 1), .amount(.arsenic, 0.5),
                            .amount(.uranium, 1), .amount(.radon, 100), .amount(.manganese, 10)])
        XCTAssertLessThanOrEqual(result.score, 20)
        XCTAssertEqual(result.band, .unsafe)
    }

    func testUnsafeHealthCapsAt40AndIsNotAveragedAway() {
        // One bad reading among many good ones still caps the score.
        let result = score([.presence(.bacteria, present: false), .amount(.nitrate, 1), .amount(.arsenic, 12),
                            .amount(.uranium, 1), .amount(.radon, 100), .amount(.manganese, 10)])
        XCTAssertLessThanOrEqual(result.score, 40)
        XCTAssertEqual(result.items.first?.target, .arsenic)
    }

    func testAestheticIssuesLowerScoreByAtMost10() {
        let result = score([.presence(.bacteria, present: false), .amount(.nitrate, 0.1), .amount(.arsenic, 0.1),
                            .amount(.uranium, 0.1), .amount(.radon, 1), .amount(.manganese, 1),
                            .amount(.iron, 3000)])
        XCTAssertGreaterThanOrEqual(result.score, 89)
    }

    // MARK: Confidence

    func testMissingDataLowersConfidenceNotScore() {
        let full = score([.presence(.bacteria, present: false), .amount(.nitrate, 0.1), .amount(.arsenic, 0.1),
                          .amount(.uranium, 0.1), .amount(.radon, 1), .amount(.manganese, 1)])
        let partial = score([.presence(.bacteria, present: false), .amount(.nitrate, 0.1)])
        XCTAssertEqual(full.confidence, .high)
        XCTAssertEqual(partial.confidence, .low)
        XCTAssertTrue(partial.missingTests.contains(.arsenic))
        XCTAssertTrue(partial.confidenceText.contains("arsenic"))
        XCTAssertGreaterThanOrEqual(partial.score, full.score - 1)
    }

    func testHomeKitCannotClearLead() {
        let result = score([.amount(.lead, 2, method: .homeKit)])
        XCTAssertEqual(item(result, .lead).level, .inconclusive)
        XCTAssertTrue(item(result, .lead).explanation.contains("certified lab"))
        // …but a home kit can still show a problem.
        let high = score([.amount(.lead, 40, method: .homeKit)])
        XCTAssertEqual(item(high, .lead).level, .unsafe)
    }

    func testUtilityLeadIsInconclusiveForYourTap() {
        let result = score([.amount(.lead, 3, method: .utilityReport)], source: .publicWater)
        XCTAssertEqual(item(result, .lead).level, .inconclusive)
        XCTAssertTrue(result.missingTests.contains(.lead))
    }

    func testShowerScoreIgnoresDrinkingOnlyContaminants() {
        let result = score([.amount(.arsenic, 50)], tap: TapLocation(kind: .shower))
        XCTAssertEqual(item(result, .arsenic).level, .notScored)
        XCTAssertGreaterThan(result.score, 40)
    }

    // MARK: Units and non-detects

    func testUnitConversions() {
        XCTAssertEqual(ReadingUnit.convert(0.010, from: .mgL, to: .ppb)!, 10, accuracy: 1e-9)
        XCTAssertEqual(ReadingUnit.convert(5, from: .ppm, to: .mgL), 5)
        XCTAssertEqual(ReadingUnit.convert(7, from: .ugL, to: .ppb), 7)
        XCTAssertEqual(ReadingUnit.convert(4, from: .ngL, to: .ppt), 4)
        XCTAssertEqual(ReadingUnit.convert(0.004, from: .ppb, to: .ppt)!, 4, accuracy: 1e-9)
        XCTAssertEqual(ReadingUnit.convert(10, from: .gpg, to: .mgLAsCaCO3)!, 171, accuracy: 1e-9)
        XCTAssertNil(ReadingUnit.convert(4, from: .pCiL, to: .mgL))
        XCTAssertEqual(Reading.amount(.arsenic, 0.012, unit: .mgL)?.value ?? 0, 12, accuracy: 1e-9)
        XCTAssertEqual(Reading.amount(.radon, 300, unit: .pCiL)?.value, 300)
        XCTAssertNil(Reading.amount(.radon, 300, unit: .mgL))
    }

    func testNonDetectCountsAsTestedAndClean() {
        let result = score([.amount(.arsenic, 1, nonDetect: true)])
        XCTAssertEqual(item(result, .arsenic).residual, 0)
        XCTAssertEqual(item(result, .arsenic).level, .good)
        XCTAssertFalse(result.missingTests.contains(.arsenic))
    }

    func testFilterDueDatesUseEarlierOfMonthsAndGallons() {
        let f = filter(.pitcher, claims: [], installedDaysAgo: 0, months: 2, capacity: 40, gallonsPerDay: 1)
        XCTAssertEqual(f.daysUntilDue(from: now), 40)
    }

    // MARK: Household

    func testFormulaNitrateAlert() {
        var baby = HouseholdMember()
        baby.ageBand = .infant
        baby.infantOnFormula = true
        let high = score([.amount(.nitrate, 12)])
        let alerts = ExposureRisk.safetyAlerts(members: [baby], source: .privateWell, results: [.kitchen: high])
        XCTAssertTrue(alerts.contains { $0.kind == .formulaNitrate })
        XCTAssertTrue(alerts.first { $0.kind == .formulaNitrate }!.message.contains("Boiling does NOT remove nitrate"))

        // Untested nitrate on a well also alerts; on city water it doesn't.
        let untested = score([.amount(.lead, 1)])
        XCTAssertTrue(ExposureRisk.safetyAlerts(members: [baby], source: .privateWell, results: [.kitchen: untested])
            .contains { $0.kind == .formulaNitrate })
        XCTAssertFalse(ExposureRisk.safetyAlerts(members: [baby], source: .publicWater, results: [.kitchen: untested])
            .contains { $0.kind == .formulaNitrate })

        let low = score([.amount(.nitrate, 2)])
        XCTAssertFalse(ExposureRisk.safetyAlerts(members: [baby], source: .privateWell, results: [.kitchen: low])
            .contains { $0.kind == .formulaNitrate })
    }

    func testArsenicSkinAlertOnlyInWellHomes() {
        var adult = HouseholdMember()
        adult.symptoms = [.skinThickening]
        XCTAssertTrue(ExposureRisk.safetyAlerts(members: [adult], source: .privateWell, results: [:])
            .contains { $0.kind == .arsenicSkin })
        XCTAssertFalse(ExposureRisk.safetyAlerts(members: [adult], source: .publicWater, results: [:])
            .contains { $0.kind == .arsenicSkin })
    }

    func testBacteriaGivesBoilAlert() {
        let result = score([.presence(.bacteria, present: true)])
        XCTAssertTrue(ExposureRisk.safetyAlerts(members: [HouseholdMember()], source: .privateWell,
                                                results: [.kitchen: result]).contains { $0.kind == .bacteriaBoil })
    }

    func testSymptomsOnlyNoteWhenMatchingElevatedOrUntested() {
        var adult = HouseholdMember()
        adult.symptoms = [.skinDarkening, .cough]
        // Arsenic tested low, radon tested low → no notes.
        let clean = score([.presence(.bacteria, present: false), .amount(.nitrate, 0.1), .amount(.arsenic, 0.1),
                           .amount(.uranium, 0.1), .amount(.radon, 1), .amount(.manganese, 1)])
        XCTAssertTrue(ExposureRisk.exposure(for: adult, source: .privateWell, results: [.kitchen: clean]).notes.isEmpty)
        // Arsenic high → a doctor note for the skin symptom only.
        let high = score([.presence(.bacteria, present: false), .amount(.nitrate, 0.1), .amount(.arsenic, 20),
                          .amount(.uranium, 0.1), .amount(.radon, 1), .amount(.manganese, 1)])
        let notes = ExposureRisk.exposure(for: adult, source: .privateWell, results: [.kitchen: high]).notes
        XCTAssertEqual(notes.map(\.symptom), [.skinDarkening])
        XCTAssertTrue(notes[0].text.contains("doctor"))
    }

    func testDoseNeedsWeight() {
        XCTAssertNil(ExposureRisk.dose(residual: 10, litersPerDay: 2, weightKg: nil))
        XCTAssertEqual(ExposureRisk.dose(residual: 10, litersPerDay: 2, weightKg: 20), 1)
    }
}
