//
//  WellCareStore.swift
//  AquaShield
//
//  Local-only storage for Report Quest progress: points, quests finished, Learn quizzes finished,
//  badges unlocked (kept once earned), and the opt-in test reminder. UserDefaults, no network.
//

import Foundation
import Observation

nonisolated struct WellCareState: Codable, Sendable, Equatable {
    var points = 0
    var questsCompleted = 0
    var perfectQuests = 0
    var learnQuizIDs: Set<String> = []
    /// Badge → when it was first earned. Badges stay earned even if the data behind them changes.
    var unlocked: [String: Date] = [:]
    /// Report Quest test reminders. Off by default.
    var testRemindersEnabled = false
    /// The quest reminder that's scheduled, and the last one that went out (for the 1-a-month cap).
    var reminderScheduled: Date?
    var reminderLastFired: Date?

    static let defaultsKey = "wellCare.state"

    static func load(from defaults: UserDefaults = .standard) -> WellCareState {
        guard let data = defaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(WellCareState.self, from: data) else { return WellCareState() }
        return state
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    func isUnlocked(_ badge: Badge) -> Bool { unlocked[badge.rawValue] != nil }

    /// Adds newly earned badges and returns them.
    mutating func unlock(_ earned: Set<Badge>, now: Date = .now) -> [Badge] {
        let new = Badge.allCases.filter { earned.contains($0) && unlocked[$0.rawValue] == nil }
        for badge in new { unlocked[badge.rawValue] = now }
        return new
    }

    /// Records a finished quest. Sample reports are never saved.
    mutating func recordQuest(points earned: Int, perfect: Bool, isSample: Bool) {
        guard !isSample else { return }
        points += max(0, earned)
        questsCompleted += 1
        if perfect { perfectQuests += 1 }
    }

    func badgeInputs(testDates: [Date], highRiskMonths: Set<Int>) -> BadgeInputs {
        BadgeInputs(questsCompleted: questsCompleted, perfectQuests: perfectQuests,
                    learnQuizzesCompleted: learnQuizIDs.count, testDates: testDates,
                    highRiskMonths: highRiskMonths)
    }

    /// Advances the reminder bookkeeping and returns the next fire date (nil when off or nothing due).
    mutating func planReminder(testDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard testRemindersEnabled else {
            reminderScheduled = nil
            return nil
        }
        // A scheduled reminder whose time has passed has gone out.
        if let scheduled = reminderScheduled, scheduled <= now {
            reminderLastFired = max(reminderLastFired ?? scheduled, scheduled)
        }
        let due = QuestReminderRule.nextTestDue(testDates: testDates, now: now, calendar: calendar)
        let fire = QuestReminderRule.fireDate(due: due, lastFired: reminderLastFired, now: now, calendar: calendar)
        reminderScheduled = fire
        return fire
    }
}

@MainActor
@Observable
final class WellCareStore {
    private(set) var state: WellCareState
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.state = WellCareState.load(from: defaults)
    }

    private func update(_ change: (inout WellCareState) -> Void) {
        change(&state)
        state.save(to: defaults)
    }

    func recordQuest(_ run: QuestRun) {
        update { $0.recordQuest(points: run.points, perfect: run.isPerfect, isSample: run.report.isSample) }
    }

    /// Re-checks every badge rule and returns badges unlocked just now.
    @discardableResult
    func refreshBadges(testDates: [Date], highRiskMonths: Set<Int>) -> [Badge] {
        var new: [Badge] = []
        update { state in
            new = state.unlock(BadgeRules.earned(state.badgeInputs(testDates: testDates, highRiskMonths: highRiskMonths)))
        }
        return new
    }

    func setTestReminders(_ enabled: Bool) {
        update { $0.testRemindersEnabled = enabled }
    }

    /// Called by the Learn tab when every question in a quiz has been answered.
    nonisolated static func recordLearnQuiz(_ id: String, defaults: UserDefaults = .standard) {
        var state = WellCareState.load(from: defaults)
        state.learnQuizIDs.insert(id)
        state.save(to: defaults)
    }

    /// Re-reads storage (after the Learn tab or reminders changed it directly).
    func reload() {
        state = WellCareState.load(from: defaults)
    }
}
