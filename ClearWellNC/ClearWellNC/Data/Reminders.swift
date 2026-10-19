//
//  Reminders.swift
//  ClearWellNC
//

import Foundation
import SwiftData
import UserNotifications

nonisolated struct PlannedReminder: Sendable, Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

nonisolated enum ReminderPlanner {
    static let hour = 9

    /// 9:00 on the due day. Overdue items fire at 9:00 tomorrow instead, so each app launch
    /// schedules at most one nudge rather than none.
    static func fireDate(due: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let onDueDay = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: due) ?? due
        if onDueDay > now { return onDueDay }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

@MainActor
enum NotificationScheduler {
    static let idPrefix = "clearwell."

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces every pending ClearWell notification with `reminders`.
    static func reschedule(_ reminders: [PlannedReminder]) async {
        let center = UNUserNotificationCenter.current()
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: idPrefix + reminder.id, content: content, trigger: trigger))
        }
    }
}

/// Recomputes all reminders from stored data and reschedules notifications.
@MainActor
enum ReminderSync {
    static func refresh(using context: ModelContext) async {
        let systems = (try? context.fetch(FetchDescriptor<TreatmentSystem>())) ?? []
        let results = (try? context.fetch(FetchDescriptor<LabResult>())) ?? []
        var reminders = plan(systems: systems, results: results, includeWellCare: WaterSource.current.showsWellCare)

        // Report Quest test reminder: opt-in, at most one a month.
        var wellCare = WellCareState.load()
        if let fire = wellCare.planReminder(testDates: results.map(\.date)) {
            reminders.append(PlannedReminder(
                id: "quest.test",
                title: String(localized: "Time to test your water"),
                body: String(localized: "It's been about a year since your last test. A new test keeps your Well Care streak going."),
                fireDate: fire))
        }
        wellCare.save()

        await NotificationScheduler.reschedule(reminders)
    }

    static func plan(systems: [TreatmentSystem], results: [LabResult], includeWellCare: Bool = true,
                     now: Date = .now) -> [PlannedReminder] {
        var reminders = systems.map { system in
            PlannedReminder(
                id: "treatment.\(system.reminderID.uuidString)",
                title: system.displayName,
                body: system.kind.isCheck
                    ? String(localized: "Time to check your water softener salt.")
                    : String(localized: "Time to replace this. Mark it replaced in ClearWell NC to reset the reminder."),
                fireDate: ReminderPlanner.fireDate(due: system.dueDate, now: now))
        }
        for task in WellCareTask.allCases where includeWellCare {
            reminders.append(PlannedReminder(
                id: "care.\(task.rawValue)",
                title: task.title,
                body: careBody(task),
                fireDate: ReminderPlanner.fireDate(due: task.dueDate(results: results, now: now), now: now)))
        }
        return reminders
    }

    private static func careBody(_ task: WellCareTask) -> String {
        switch task {
        case .bacteriaTest: String(localized: "Time for your yearly bacteria test (total coliform / E. coli).")
        case .wellheadInspection: String(localized: "Time for your yearly wellhead inspection.")
        case .metalsNitrateTest: String(localized: "Time for your metals and nitrate test (every 2 years).")
        }
    }
}
