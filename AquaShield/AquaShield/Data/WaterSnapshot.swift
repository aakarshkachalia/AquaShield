//
//  WaterSnapshot.swift
//  AquaShield
//
//  Everything the dashboard and its detail screens show, computed in one place from stored data:
//  per-tap scores, filters, alerts, household exposure and the remediation plan.
//

import Foundation

@MainActor
struct WaterSnapshot {
    let source: WaterSource
    let readings: [Reading]
    let filters: [InstalledFilter]
    let taps: [TapLocation: TapScoreResult]
    let alerts: [SafetyAlert]
    let exposures: [UUID: MemberExposure]
    let plan: RemediationPlan
    let testsDue: [TestDue]
    let latest: LabResult?
    let members: [HouseholdMember]
    let now: Date

    var drinking: TapScoreResult? { taps[.kitchen] }
    var showers: [TapScoreResult] {
        taps.values.filter { $0.tap.kind == .shower }.sorted { $0.tap.index < $1.tap.index }
    }
    var hasReadings: Bool { !readings.isEmpty }
    var nextTest: TestDue? { testsDue.first }

    /// Filters by days until replacement, soonest first.
    var filtersByDue: [(filter: InstalledFilter, days: Int?)] {
        filters.map { ($0, $0.daysUntilDue(from: now)) }
            .sorted { ($0.days ?? .max) < ($1.days ?? .max) }
    }

    /// The single most useful thing to do next.
    var topNextStep: String {
        if let alert = alerts.first { return alert.title }
        if !hasReadings {
            return source.showsWellCare ? String(localized: "Get your well tested")
                                        : String(localized: "Add your utility's water report")
        }
        if let fix = plan.fixes.first { return fix.title }
        if let due = nextTest, due.isOverdue(at: now) { return due.title }
        if let filter = filtersByDue.first, let days = filter.days, days <= 14 {
            return String(localized: "Replace \(filter.filter.name)")
        }
        if let missing = drinking?.missingTests.first {
            return String(localized: "Test for \(missing.name.inSentence)")
        }
        return String(localized: "Keep testing every year")
    }

    static func make(results: [LabResult], systems: [TreatmentSystem], settings: AppSettings,
                     reference: ReferenceDataStore = .shared, now: Date = .now) -> WaterSnapshot {
        let source = settings.waterSource
        var readings = results.tapReadings()
        if source.showsCityContent {
            let have = Set(readings.map(\.target))
            readings += settings.utilityReport.tapReadings().filter { !have.contains($0.target) }
        }
        let filters = systems.map { $0.installed(product: reference.product(id: $0.productID, custom: settings.customFilterProducts)) }

        var tapList = settings.homeProfile.taps
        for filter in filters where filter.location != .wholeHouse && !tapList.contains(filter.location) {
            tapList.append(filter.location)
        }
        var taps: [TapLocation: TapScoreResult] = [:]
        for tap in tapList {
            taps[tap] = WellHealthScore.tapScore(tap: tap, source: source, readings: readings, filters: filters, now: now)
        }

        let members = settings.householdMembers
        var exposures: [UUID: MemberExposure] = [:]
        for member in members {
            exposures[member.id] = ExposureRisk.exposure(for: member, source: source, results: taps)
        }
        let showers = taps.values.filter { $0.tap.kind == .shower }
        let plan = Remediation.plan(source: source, drinking: taps[.kitchen], showers: Array(showers),
                                    home: settings.homeProfile, members: members,
                                    products: reference.filterProducts(custom: settings.customFilterProducts), now: now)
        let due = WellTestingCalendar.schedule(history: WellTestingCalendar.history(from: results), source: source,
                                               events: settings.retestEvents, now: now)
        return WaterSnapshot(source: source, readings: readings, filters: filters, taps: taps,
                             alerts: ExposureRisk.safetyAlerts(members: members, source: source, results: taps),
                             exposures: exposures, plan: plan, testsDue: due,
                             latest: results.max { $0.date < $1.date }, members: members, now: now)
    }
}
