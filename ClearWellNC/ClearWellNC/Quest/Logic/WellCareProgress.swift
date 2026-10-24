//
//  WellCareProgress.swift
//  ClearWellNC
//
//  "Well Care" progression rules: badges, the yearly testing streak, the seasonal challenge, and
//  test-reminder spacing. Pure functions over dates and counts; storage lives in WellCareStore.
//  The streak and badges reward regular testing, never app opens or screen time.
//

import Foundation

nonisolated enum Badge: String, CaseIterable, Codable, Sendable, Identifiable {
    case reportReader, perfectRead, seasonalScout, steadyKeeper, learner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reportReader: String(localized: "Report Reader")
        case .perfectRead: String(localized: "Perfect Read")
        case .seasonalScout: String(localized: "Seasonal Scout")
        case .steadyKeeper: String(localized: "Steady Keeper")
        case .learner: String(localized: "Learner")
        }
    }

    var howToEarn: String {
        switch self {
        case .reportReader: String(localized: "Finish a Report Quest.")
        case .perfectRead: String(localized: "Get every stop right in a Report Quest.")
        case .seasonalScout: String(localized: "Test during your county's high season for a contaminant.")
        case .steadyKeeper: String(localized: "Log a test 12 months or more after your last one.")
        case .learner: String(localized: "Finish \(BadgeRules.learnerQuizCount) quizzes in the Learn tab.")
        }
    }

    var symbol: String {
        switch self {
        case .reportReader: "doc.text.magnifyingglass"
        case .perfectRead: "star.circle.fill"
        case .seasonalScout: "leaf.fill"
        case .steadyKeeper: "calendar.badge.checkmark"
        case .learner: "graduationcap.fill"
        }
    }
}

/// What the badge rules look at. Built from saved progress and the user's real lab results.
nonisolated struct BadgeInputs: Sendable {
    var questsCompleted = 0
    var perfectQuests = 0
    var learnQuizzesCompleted = 0
    /// Dates of real (non-sample) tests.
    var testDates: [Date] = []
    /// High-season months (1–12) for the user's county, from the forecast model.
    var highRiskMonths: Set<Int> = []
}

nonisolated enum BadgeRules {
    static let learnerQuizCount = 5
    static let steadyKeeperMonths = 12

    static func isEarned(_ badge: Badge, _ inputs: BadgeInputs, calendar: Calendar = .current) -> Bool {
        switch badge {
        case .reportReader:
            return inputs.questsCompleted >= 1
        case .perfectRead:
            return inputs.perfectQuests >= 1
        case .seasonalScout:
            return testedInHighSeason(inputs.testDates, highRiskMonths: inputs.highRiskMonths, calendar: calendar)
        case .steadyKeeper:
            return hasYearlyGap(inputs.testDates, calendar: calendar)
        case .learner:
            return inputs.learnQuizzesCompleted >= learnerQuizCount
        }
    }

    static func earned(_ inputs: BadgeInputs, calendar: Calendar = .current) -> Set<Badge> {
        Set(Badge.allCases.filter { isEarned($0, inputs, calendar: calendar) })
    }

    static func testedInHighSeason(_ dates: [Date], highRiskMonths: Set<Int>, calendar: Calendar = .current) -> Bool {
        guard !highRiskMonths.isEmpty else { return false }
        return dates.contains { highRiskMonths.contains(calendar.component(.month, from: $0)) }
    }

    /// Some test logged 12+ months after the one before it.
    static func hasYearlyGap(_ dates: [Date], calendar: Calendar = .current) -> Bool {
        let sorted = dates.sorted()
        return zip(sorted, sorted.dropFirst()).contains { previous, next in
            let months = calendar.dateComponents([.month], from: calendar.startOfDay(for: previous),
                                                 to: calendar.startOfDay(for: next)).month ?? 0
            return months >= steadyKeeperMonths
        }
    }
}

// MARK: - Streak

nonisolated enum WellCareStreak {
    /// Consecutive calendar years with at least one test. A streak stays alive through the current
    /// year until it ends, so a test last year still counts now. Many tests in one year count once;
    /// app opens don't count at all.
    static func years(testDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let years = Set(testDates.filter { $0 <= now }.map { calendar.component(.year, from: $0) })
        let thisYear = calendar.component(.year, from: now)
        var year = years.contains(thisYear) ? thisYear : thisYear - 1
        var count = 0
        while years.contains(year) {
            count += 1
            year -= 1
        }
        return count
    }
}

// MARK: - Seasonal challenge

nonisolated struct SeasonalChallenge: Sendable {
    let contaminant: ContaminantID
    /// 1–12, calendar order.
    let months: [Int]
    let county: String
    let isSampleData: Bool

    var seasonName: String {
        switch months.first ?? 1 {
        case 12, 1, 2: String(localized: "Winter")
        case 3, 4, 5: String(localized: "Spring")
        case 6, 7, 8: String(localized: "Summer")
        default: String(localized: "Fall")
        }
    }

    var monthRange: String {
        let symbols = Calendar.current.monthSymbols
        return months.map { symbols[$0 - 1] }.joined(separator: "–")
    }

    /// "Spring Nitrate Check"
    var title: String {
        String(localized: "\(seasonName) \(contaminant.info.name) Check")
    }

    // SOURCE vr-060 (needs verification, see VerificationRegister.json): "usually highest" comes from the county forecast. The bundled county_trends.csv is
    // placeholder sample data, so the card shows a "Sample data" label until real aggregates replace it.
    var detail: String {
        String(localized: "Test in \(monthRange), when \(contaminant.info.name.lowercased()) in \(county) County wells is usually highest, to earn the Seasonal Scout badge.")
    }
}

nonisolated enum SeasonalChallengeRules {
    /// High-season months for every contaminant with a strong seasonal pattern in the county.
    static func highRiskMonths(data: CountyTrendData, county: String) -> Set<Int> {
        Set(results(data: data, county: county).flatMap { SeasonalInsight.peakMonths($0.result) })
    }

    /// The challenge to show: the contaminant whose high season comes up soonest (including now).
    static func current(data: CountyTrendData, county: String, now: Date = .now,
                        calendar: Calendar = .current) -> SeasonalChallenge? {
        let month = calendar.component(.month, from: now)
        let options = results(data: data, county: county).map { entry in
            (entry.contaminant, SeasonalInsight.peakMonths(entry.result))
        }
        // Months until the season starts; 0 while it's on.
        func wait(_ months: [Int]) -> Int {
            if months.contains(month) { return 0 }
            return months.map { ($0 - month + 12) % 12 }.min() ?? 12
        }
        guard let best = options.min(by: { wait($0.1) < wait($1.1) }) else { return nil }
        return SeasonalChallenge(contaminant: best.0, months: best.1, county: county, isSampleData: data.isSample)
    }

    private static func results(data: CountyTrendData, county: String)
        -> [(contaminant: ContaminantID, result: SeasonalForecast.Result)] {
        data.contaminants(in: county).compactMap { id in
            guard let result = SeasonalForecast.fit(data.series(county: county, contaminant: id)),
                  SeasonalInsight.hasStrongPattern(result) else { return nil }
            return (id, result)
        }
    }
}

// MARK: - Test reminders

/// Opt-in Report Quest test reminder. Off by default, and never more than one a month.
nonisolated enum QuestReminderRule {
    static let minimumMonthsBetween = 1

    /// When to fire, given when the next test is due and when the last reminder went out.
    static func fireDate(due: Date, lastFired: Date?, now: Date = .now, calendar: Calendar = .current) -> Date {
        let candidate = ReminderPlanner.fireDate(due: due, now: now, calendar: calendar)
        guard let lastFired,
              let earliest = calendar.date(byAdding: .month, value: minimumMonthsBetween, to: lastFired)
        else { return candidate }
        return max(candidate, earliest)
    }

    /// The next test is due a year after the latest test, or now if there are no tests.
    static func nextTestDue(testDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Date {
        guard let latest = testDates.max() else { return now }
        return calendar.date(byAdding: .year, value: 1, to: latest) ?? now
    }
}
