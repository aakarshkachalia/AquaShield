//
//  WellTestingCalendar.swift
//  AquaShield
//
//  When to test next. Wells: bacteria and nitrate every year, a full panel every 3 years (NC DHHS suggests
//  every 3–5; needs verification), and a retest after flooding, well repairs, or a change in taste, color
//  or smell. Any home: a retest after one of those events.
//

import Foundation

nonisolated struct RetestEvent: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case flood, repair, tasteColorSmell

        /// City homes never see "well".
        func label(for source: WaterSource) -> String {
            self == .repair && !source.showsWellCare ? String(localized: "Plumbing repair") : label
        }

        var label: String {
            switch self {
            case .flood: String(localized: "Flooding")
            case .repair: String(localized: "Plumbing or well repair")
            case .tasteColorSmell: String(localized: "Taste, color or smell changed")
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var date: Date

    static let storageKey = "retestEvents"
}

nonisolated struct TestDue: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable { case bacteriaNitrate, fullPanel, afterEvent }
    let kind: Kind
    let due: Date
    let title: String
    let detail: String
    var id: Kind { kind }

    func isOverdue(at now: Date) -> Bool { due <= now }
}

nonisolated enum WellTestingCalendar {
    static let fullPanelYears = 3

    /// Dates of past tests by what they covered.
    struct History: Sendable {
        var bacteria: [Date] = []
        var nitrate: [Date] = []
        /// Tests that included arsenic, lead, manganese and uranium or most of the panel.
        var fullPanel: [Date] = []
        var any: [Date] = []
    }

    static func schedule(history: History, source: WaterSource, events: [RetestEvent], now: Date,
                         calendar: Calendar = .current) -> [TestDue] {
        var due: [TestDue] = []
        if source.showsWellCare {
            let lastYearly = [history.bacteria.max(), history.nitrate.max()].compactMap { $0 }.min()
            let yearly = lastYearly.flatMap { calendar.date(byAdding: .year, value: 1, to: $0) } ?? now
            due.append(TestDue(kind: .bacteriaNitrate, due: yearly,
                               title: String(localized: "Bacteria and nitrate test"),
                               detail: String(localized: "Every year, for every well.")))
            let panel = history.fullPanel.max().flatMap { calendar.date(byAdding: .year, value: fullPanelYears, to: $0) } ?? now
            due.append(TestDue(kind: .fullPanel, due: panel,
                               title: String(localized: "Full well test"),
                               detail: String(localized: "Arsenic, lead, manganese, uranium and more, every \(fullPanelYears) years.")))
        }
        // An event since the last test: retest now.
        let lastTest = history.any.max() ?? .distantPast
        if let event = events.filter({ $0.date > lastTest }).max(by: { $0.date < $1.date }) {
            due.append(TestDue(kind: .afterEvent, due: event.date,
                               title: String(localized: "Retest after \(event.kind.label(for: source).lowercased())"),
                               detail: source.showsWellCare
                                   ? String(localized: "Test for bacteria before drinking the water again.")
                                   : String(localized: "Ask your utility, and test your tap if something seems off.")))
        }
        return due.sorted { $0.due < $1.due }
    }

    @MainActor static func history(from results: [LabResult]) -> History {
        var history = History()
        for result in results {
            history.any.append(result.date)
            if result.includesBacteria { history.bacteria.append(result.date) }
            if result.nitrateMgL != nil { history.nitrate.append(result.date) }
            let panel = [Analyte.arsenic, .lead, .manganese, .uranium].filter { result.value(for: $0) != nil }.count
            if panel >= 3 { history.fullPanel.append(result.date) }
        }
        return history
    }

    /// Reminders for the full panel and event retests. Yearly bacteria comes from WellCareTask.
    @MainActor static func reminders(results: [LabResult], source: WaterSource, events: [RetestEvent], now: Date) -> [PlannedReminder] {
        schedule(history: history(from: results), source: source, events: events, now: now)
            .filter { $0.kind != .bacteriaNitrate }
            .map { PlannedReminder(id: "calendar.\($0.kind.rawValue)", title: $0.title, body: $0.detail,
                                   fireDate: ReminderPlanner.fireDate(due: $0.due, now: now)) }
    }
}
