//
//  ReportQuestTests.swift
//  AquaShieldTests
//
//  Report Quest rules: safety override, answer classification, points, badges, streak, reminders.
//

import XCTest
@testable import AquaShield

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func report(_ values: [ContaminantID: Double] = [:], presence: [ContaminantID: Bool] = [:]) -> QuestReport {
    QuestReport(date: day(2026, 5, 1), values: values, presence: presence)
}

// MARK: - Safety override (highest priority)

final class QuestSafetyOverrideTests: XCTestCase {

    func testHealthExceedanceTriggersAlert() {
        let r = report([.arsenic: 10, .nitrate: 2])   // arsenic exactly at the 10 ppb limit
        XCTAssertTrue(QuestEngine.requiresSafetyAlert(r))
        XCTAssertEqual(QuestEngine.safetyFindings(for: r).map(\.id), [.arsenic])
    }

    func testEachHealthLimitTriggersAtTheLimit() {
        for id in ContaminantID.allCases {
            let info = id.info
            guard info.limitType == .health, let limit = info.maximumLimit else { continue }
            XCTAssertTrue(QuestEngine.requiresSafetyAlert(report([id: limit])), "\(id) at its limit should alert")
            XCTAssertFalse(QuestEngine.requiresSafetyAlert(report([id: limit * 0.99])), "\(id) under its limit should not alert")
        }
    }

    func testEColiTriggersAlert() {
        let r = report(presence: [.eColi: true])
        XCTAssertTrue(QuestEngine.requiresSafetyAlert(r))
        XCTAssertTrue(QuestEngine.eColiPositive(r))
        XCTAssertEqual(QuestEngine.safetyFindings(for: r).map(\.id), [.eColi])
    }

    func testTotalColiformAndManganeseAdvisoryTriggerAlert() {
        XCTAssertTrue(QuestEngine.requiresSafetyAlert(report(presence: [.totalColiform: true])))
        XCTAssertTrue(QuestEngine.requiresSafetyAlert(report([.manganese: 300])))   // health advisory
    }

    func testNoAlertForSafeWatchOrCosmeticResults() {
        XCTAssertFalse(QuestEngine.requiresSafetyAlert(report([.arsenic: 2])))
        XCTAssertFalse(QuestEngine.requiresSafetyAlert(report([.nitrate: 6])))                   // watch
        XCTAssertFalse(QuestEngine.requiresSafetyAlert(report([.iron: 400, .pH: 6.0])))           // cosmetic only
        XCTAssertFalse(QuestEngine.requiresSafetyAlert(report(presence: [.eColi: false, .totalColiform: false])))
        XCTAssertFalse(QuestEngine.requiresSafetyAlert(report()))
    }

    func testSeriousStopsNeverCelebrate() {
        let run = QuestRun(report: report([.arsenic: 20], presence: [.eColi: true]))
        XCTAssertFalse(run.stops.isEmpty)
        for stop in run.stops {
            XCTAssertTrue(stop.isSerious)
            for answer in QuestAnswer.allCases {
                XCTAssertFalse(stop.celebrates(answer), "\(stop.name) must not celebrate \(answer)")
            }
        }
    }

    func testOnlyCorrectSafeOrWatchCelebrates() {
        let run = QuestRun(report: report([.arsenic: 2, .nitrate: 6, .iron: 400]))
        let arsenic = run.stops.first { $0.contaminant == .arsenic }!
        let nitrate = run.stops.first { $0.contaminant == .nitrate }!
        let iron = run.stops.first { $0.contaminant == .iron }!
        XCTAssertTrue(arsenic.celebrates(.safe))
        XCTAssertFalse(arsenic.celebrates(.watch))     // wrong answer
        XCTAssertTrue(nitrate.celebrates(.watch))
        XCTAssertFalse(iron.celebrates(.above))         // correct, but not safe/watch
    }

    func testDemoReports() {
        XCTAssertTrue(QuestEngine.requiresSafetyAlert(DemoReport.problem.report()))
        XCTAssertTrue(QuestEngine.eColiPositive(DemoReport.problem.report()))
        XCTAssertFalse(QuestEngine.requiresSafetyAlert(DemoReport.typical.report()))
        for demo in DemoReport.allCases {
            XCTAssertTrue(demo.report().isSample)
            let count = QuestRun(report: demo.report()).stops.count + 1
            XCTAssertTrue((5...8).contains(count), "\(demo) has \(count) nodes")
        }
    }

    func testSampleQuestNeverSavesProgress() {
        var state = WellCareState()
        state.recordQuest(points: 70, perfect: true, isSample: true)
        XCTAssertEqual(state, WellCareState())
        state.recordQuest(points: 70, perfect: true, isSample: false)
        XCTAssertEqual(state.points, 70)
        XCTAssertEqual(state.questsCompleted, 1)
        XCTAssertEqual(state.perfectQuests, 1)
    }
}

// MARK: - Answers match the app's classification

final class QuestAnswerTests: XCTestCase {

    /// For every contaminant across a sweep of readings, the game's correct answer is derived from
    /// `Interpretation.interpret` and agrees with `Analyte.evaluate`.
    func testCorrectAnswerAlwaysMatchesClassification() {
        for analyte in Analyte.allCases {
            let info = analyte.info
            let readings: [Double]
            switch info.limit {
            case .maximum(let limit):
                readings = [0, 0.25, 0.49, 0.5, 0.75, 0.99, 1, 1.5, 3].map { $0 * limit }
                    + (info.healthAdvisory.map { [$0.value * 0.99, $0.value] } ?? [])
            case .range(let low, let high):
                readings = [low - 1, low - 0.01, low, (low + high) / 2, high, high + 0.01, high + 1]
            case .none:
                readings = [10, 100, 200, 400]
            case .mustBeAbsent:
                readings = [0, 1]
            }
            for value in readings {
                let interpretation = Interpretation.interpret(analyte.contaminant, value: value)
                let run = QuestRun(report: report([analyte.contaminant: value]))
                let expected = QuestAnswer.correct(for: interpretation.tier)
                XCTAssertEqual(run.stops.first?.correctAnswer, expected, "\(analyte) at \(value)")

                guard let answer = expected else { continue }   // hardness: not a stop
                switch analyte.evaluate(value).kind {
                case .above, .notice: XCTAssertEqual(answer, .above, "\(analyte) at \(value)")
                case .pass: XCTAssertNotEqual(answer, .above, "\(analyte) at \(value)")
                }
                if interpretation.tier != .nuisance {
                    XCTAssertEqual(answer.tier, interpretation.tier)
                }
            }
        }
    }

    func testBacteriaAnswers() {
        let run = QuestRun(report: report(presence: [.totalColiform: false, .eColi: true]))
        XCTAssertEqual(run.stops.map(\.correctAnswer), [.safe, .above])
    }

    func testHardnessIsNotAStop() {
        XCTAssertTrue(QuestRun(report: report([.hardness: 200])).stops.isEmpty)
    }

    func testPathKeepsSeriousResultsWhenTrimmed() {
        let values: [ContaminantID: Double] = [.arsenic: 1, .lead: 1, .nitrate: 1, .nitrite: 0.1, .uranium: 1,
                                               .manganese: 5, .iron: 10, .copper: 0.1, .fluoride: 0.2,
                                               .pH: 7, .radon: 100]
        let run = QuestRun(report: report(values, presence: [.eColi: true]))
        XCTAssertEqual(run.stops.count, QuestEngine.maxContaminantStops)
        XCTAssertTrue(run.stops.contains { $0.contaminant == .eColi })
        XCTAssertEqual(run.stops.map(\.id), Array(0..<run.stops.count))
    }
}

// MARK: - Points

final class QuestPointsTests: XCTestCase {

    func testPointValues() {
        XCTAssertEqual(QuestEngine.points(correct: true), 10)
        XCTAssertEqual(QuestEngine.points(correct: false), 3)
    }

    func testPointsNeverGoDownAndFirstAnswerSticks() {
        var run = QuestRun(report: DemoReport.typical.report())
        var last = run.points
        for stop in run.stops {
            let wrong = QuestAnswer.allCases.first { $0 != stop.correctAnswer }!
            run.answer(stop, with: wrong)
            XCTAssertGreaterThan(run.points, last)
            last = run.points
            XCTAssertEqual(run.answer(stop, with: stop.correctAnswer), 0, "Answer can't be changed")
            XCTAssertEqual(run.points, last)
        }
        XCTAssertEqual(run.points, 3 * run.stops.count)
    }

    func testPerfectRun() {
        var run = QuestRun(report: DemoReport.typical.report())
        for stop in run.stops { run.answer(stop, with: stop.correctAnswer) }
        XCTAssertFalse(run.isFinished, "Score guess still to go")
        run.guessScore(run.score.band!)
        XCTAssertTrue(run.isFinished)
        XCTAssertTrue(run.isPerfect)
        XCTAssertEqual(run.points, 10 * (run.stops.count + 1))
    }

    func testWrongScoreGuessIsNotPerfect() {
        var run = QuestRun(report: DemoReport.typical.report())
        for stop in run.stops { run.answer(stop, with: stop.correctAnswer) }
        run.guessScore(QuestEngine.scoreChoices.first { $0 != run.score.band }!)
        XCTAssertTrue(run.isFinished)
        XCTAssertFalse(run.isPerfect)
    }

    func testIncompleteReportSkipsScoreGuess() {
        var run = QuestRun(report: report([.arsenic: 2]))   // key tests missing, no cap → no score
        XCTAssertNil(run.score.score)
        XCTAssertFalse(run.hasScoreGuess)
        run.answer(run.stops[0], with: .safe)
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(run.nextAction.kind, .test)
    }

    func testNextActionPriority() {
        XCTAssertEqual(QuestRun(report: DemoReport.problem.report()).nextAction.kind, .urgent)
        XCTAssertEqual(QuestRun(report: DemoReport.typical.report()).nextAction.kind, .fix)
        let clean = report([.arsenic: 1, .lead: 1, .nitrate: 1, .manganese: 5, .pH: 7], presence: [.eColi: false])
        let score = WellHealthScore.compute(clean.scoreInput)
        XCTAssertEqual(QuestEngine.nextAction(score: score, reportDate: day(2026, 5, 1), now: day(2026, 6, 1), calendar: utc).kind, .allSet)
        XCTAssertEqual(QuestEngine.nextAction(score: score, reportDate: day(2025, 5, 1), now: day(2026, 6, 1), calendar: utc).kind, .retest)
    }

    func testExplanationsAreAtMostTwoSentences() {
        XCTAssertEqual(QuestText.firstSentences("One. Two. Three.", max: 2), "One. Two.")
        XCTAssertEqual(QuestText.firstSentences("Only one.", max: 2), "Only one.")
    }
}

// MARK: - Streak

final class WellCareStreakTests: XCTestCase {
    private let now = day(2026, 10, 18)

    func testCountsConsecutiveYears() {
        let dates = [day(2024, 3, 1), day(2025, 7, 1), day(2026, 2, 1)]
        XCTAssertEqual(WellCareStreak.years(testDates: dates, now: now, calendar: utc), 3)
    }

    func testManyTestsInOneYearCountOnce() {
        // A test every day of 2026 is still a one-year streak: it counts years, not days.
        let daily = (0..<290).map { utc.date(byAdding: .day, value: $0, to: day(2026, 1, 1))! }
        XCTAssertEqual(WellCareStreak.years(testDates: daily, now: now, calendar: utc), 1)
    }

    func testStreakSurvivesUntilThisYearEnds() {
        let dates = [day(2024, 5, 1), day(2025, 5, 1)]   // nothing yet in 2026
        XCTAssertEqual(WellCareStreak.years(testDates: dates, now: now, calendar: utc), 2)
    }

    func testGapBreaksStreak() {
        let dates = [day(2022, 5, 1), day(2023, 5, 1), day(2025, 5, 1), day(2026, 5, 1)]
        XCTAssertEqual(WellCareStreak.years(testDates: dates, now: now, calendar: utc), 2)
        XCTAssertEqual(WellCareStreak.years(testDates: [day(2023, 5, 1)], now: now, calendar: utc), 0)
        XCTAssertEqual(WellCareStreak.years(testDates: [], now: now, calendar: utc), 0)
    }

    func testFutureDatesIgnored() {
        XCTAssertEqual(WellCareStreak.years(testDates: [day(2027, 1, 1)], now: now, calendar: utc), 0)
    }
}

// MARK: - Badges

final class BadgeRuleTests: XCTestCase {

    func testReportReader() {
        XCTAssertFalse(BadgeRules.isEarned(.reportReader, BadgeInputs()))
        XCTAssertTrue(BadgeRules.isEarned(.reportReader, BadgeInputs(questsCompleted: 1)))
    }

    func testPerfectRead() {
        XCTAssertFalse(BadgeRules.isEarned(.perfectRead, BadgeInputs(questsCompleted: 3)))
        XCTAssertTrue(BadgeRules.isEarned(.perfectRead, BadgeInputs(questsCompleted: 1, perfectQuests: 1)))
    }

    func testSeasonalScout() {
        let spring: Set<Int> = [4, 5]
        XCTAssertTrue(BadgeRules.isEarned(.seasonalScout, BadgeInputs(testDates: [day(2026, 4, 20)], highRiskMonths: spring), calendar: utc))
        XCTAssertFalse(BadgeRules.isEarned(.seasonalScout, BadgeInputs(testDates: [day(2026, 9, 1)], highRiskMonths: spring), calendar: utc))
        XCTAssertFalse(BadgeRules.isEarned(.seasonalScout, BadgeInputs(testDates: [day(2026, 4, 20)], highRiskMonths: []), calendar: utc))
    }

    func testSteadyKeeper() {
        XCTAssertTrue(BadgeRules.isEarned(.steadyKeeper, BadgeInputs(testDates: [day(2025, 3, 1), day(2026, 3, 1)]), calendar: utc))
        XCTAssertTrue(BadgeRules.isEarned(.steadyKeeper, BadgeInputs(testDates: [day(2026, 3, 1), day(2024, 1, 1)]), calendar: utc), "Order doesn't matter")
        XCTAssertFalse(BadgeRules.isEarned(.steadyKeeper, BadgeInputs(testDates: [day(2025, 3, 1), day(2026, 2, 27)]), calendar: utc))
        XCTAssertFalse(BadgeRules.isEarned(.steadyKeeper, BadgeInputs(testDates: [day(2026, 3, 1)]), calendar: utc))
    }

    func testLearner() {
        XCTAssertFalse(BadgeRules.isEarned(.learner, BadgeInputs(learnQuizzesCompleted: 4)))
        XCTAssertTrue(BadgeRules.isEarned(.learner, BadgeInputs(learnQuizzesCompleted: 5)))
    }

    func testBadgesStayUnlocked() {
        var state = WellCareState()
        XCTAssertEqual(state.unlock([.reportReader], now: day(2026, 1, 1)), [.reportReader])
        XCTAssertEqual(state.unlock([.reportReader, .learner], now: day(2026, 2, 1)), [.learner])
        XCTAssertEqual(state.unlock([], now: day(2026, 3, 1)), [])
        XCTAssertTrue(state.isUnlocked(.reportReader))
        XCTAssertEqual(state.unlocked[Badge.reportReader.rawValue], day(2026, 1, 1))
    }

    func testLearnQuizzesCountDistinctQuizzes() {
        let defaults = UserDefaults(suiteName: "ReportQuestTests.learn")!
        defaults.removePersistentDomain(forName: "ReportQuestTests.learn")
        WellCareStore.recordLearnQuiz("arsenic", defaults: defaults)
        WellCareStore.recordLearnQuiz("arsenic", defaults: defaults)
        WellCareStore.recordLearnQuiz("lead", defaults: defaults)
        XCTAssertEqual(WellCareState.load(from: defaults).learnQuizIDs.count, 2)
    }
}

// MARK: - Seasonal challenge and reminders

final class SeasonalChallengeAndReminderTests: XCTestCase {

    private func springPeakData() -> CountyTrendData {
        var lines = ["county,contaminant,month,year,median,p90,n"]
        for year in 2021...2024 {
            for month in 1...12 {
                let value = (month == 4 || month == 5) ? 8.0 : 3.0
                lines.append("Wake,nitrate,\(month),\(year),\(value),\(value * 2),20")
            }
        }
        return CountyTrendData.parse(lines.joined(separator: "\n"))
    }

    func testHighRiskMonthsComeFromForecast() {
        XCTAssertEqual(SeasonalChallengeRules.highRiskMonths(data: springPeakData(), county: "Wake"), [4, 5])
        XCTAssertTrue(SeasonalChallengeRules.highRiskMonths(data: springPeakData(), county: "Nowhere").isEmpty)
    }

    func testChallengeNamesSeasonAndContaminant() {
        let challenge = SeasonalChallengeRules.current(data: springPeakData(), county: "Wake", now: day(2026, 2, 1), calendar: utc)
        XCTAssertEqual(challenge?.contaminant, .nitrate)
        XCTAssertEqual(challenge?.months, [4, 5])
        XCTAssertEqual(challenge?.seasonName, "Spring")
    }

    func testPeakMonthsMatchPeakRangeText() throws {
        let data = springPeakData()
        let result = try XCTUnwrap(SeasonalForecast.fit(data.series(county: "Wake", contaminant: .nitrate)))
        let symbols = Calendar.current.monthSymbols
        XCTAssertEqual(SeasonalInsight.peakRange(result), SeasonalInsight.peakMonths(result).map { symbols[$0 - 1] }.joined(separator: "–"))
    }

    func testReminderAtMostOncePerMonth() {
        let lastFired = day(2026, 10, 10)
        let fire = QuestReminderRule.fireDate(due: day(2026, 9, 1), lastFired: lastFired, now: day(2026, 10, 18), calendar: utc)
        XCTAssertGreaterThanOrEqual(fire, utc.date(byAdding: .month, value: 1, to: lastFired)!)
    }

    func testReminderOffByDefaultAndSpacesItself() {
        var state = WellCareState()
        XCTAssertFalse(state.testRemindersEnabled)
        XCTAssertNil(state.planReminder(testDates: [day(2025, 1, 1)], now: day(2026, 10, 18), calendar: utc))

        state.testRemindersEnabled = true
        let first = state.planReminder(testDates: [day(2025, 1, 1)], now: day(2026, 10, 18), calendar: utc)!
        // Opening the app the day after it fired must not schedule another within a month.
        let afterFiring = utc.date(byAdding: .day, value: 1, to: first)!
        let second = state.planReminder(testDates: [day(2025, 1, 1)], now: afterFiring, calendar: utc)!
        XCTAssertGreaterThanOrEqual(second, utc.date(byAdding: .month, value: 1, to: first)!)
    }
}
