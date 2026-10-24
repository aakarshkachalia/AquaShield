//
//  AlertCenter.swift
//  ClearWellNC
//
//  Every nudge in one prioritized list: safety alerts, storm alerts, filters due, tests due, missing key
//  tests and active modes. Each has one action. The landing page shows the top one and a bell with a count.
//

import Foundation

nonisolated struct AppAlert: Sendable, Equatable, Identifiable {
    enum Severity: Int, Comparable, Sendable {
        /// Act now: health risk.
        case critical = 3
        /// Act soon: storm, overdue filter or test.
        case warning = 2
        /// Worth doing: coming due, missing test.
        case attention = 1
        /// Status only (a mode is on).
        case info = 0

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    enum Action: Sendable, Equatable {
        case safety, weather, filters, testing, findTesting, modes, remediation
    }

    let id: String
    let severity: Severity
    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: Action
}

nonisolated enum AlertCenter {
    /// Days ahead that count as "coming due".
    static let soonDays = 14

    struct Inputs: Sendable {
        var safety: [SafetyAlert] = []
        /// Relevant NWS alerts (event names), only when storm alerts are on.
        var weatherEvents: [String] = []
        /// Filter name and days until due.
        var filters: [(name: String, days: Int)] = []
        var tests: [TestDue] = []
        var missingTests: [ClaimTarget] = []
        var modes: Set<WaterMode> = []
        var hasReadings = false
        var now = Date.now
    }

    /// Most severe first; within a severity, the order below.
    static func alerts(_ input: Inputs) -> [AppAlert] {
        var alerts: [AppAlert] = []
        for alert in input.safety {
            alerts.append(AppAlert(id: "safety.\(alert.kind.rawValue)", severity: .critical, symbol: "xmark.octagon.fill",
                                   title: alert.title, detail: alert.message,
                                   actionTitle: String(localized: "What to do"), action: .safety))
        }
        for event in input.weatherEvents {
            alerts.append(AppAlert(id: "weather.\(event)", severity: .warning, symbol: "cloud.bolt.rain.fill",
                                   title: event, detail: String(localized: "Active near your home."),
                                   actionTitle: String(localized: "Be ready"), action: .weather))
        }
        for filter in input.filters where filter.days <= soonDays {
            let overdue = filter.days <= 0
            alerts.append(AppAlert(id: "filter.\(filter.name)", severity: overdue ? .warning : .attention,
                                   symbol: "line.3.horizontal.decrease.circle.fill",
                                   title: overdue ? String(localized: "Replace \(filter.name)")
                                                  : String(localized: "\(filter.name) due in \(filter.days) days"),
                                   detail: overdue ? String(localized: "An expired filter stops protecting you.")
                                                   : String(localized: "Order a replacement now."),
                                   actionTitle: String(localized: "Filters"), action: .filters))
        }
        for test in input.tests {
            let days = Calendar.current.dateComponents([.day], from: input.now, to: test.due).day ?? 0
            guard test.isOverdue(at: input.now) || days <= soonDays else { continue }
            alerts.append(AppAlert(id: "test.\(test.kind.rawValue)", severity: test.isOverdue(at: input.now) ? .warning : .attention,
                                   symbol: "calendar.badge.exclamationmark",
                                   title: test.isOverdue(at: input.now) ? String(localized: "\(test.title) is due") : test.title,
                                   detail: test.detail, actionTitle: String(localized: "Find testing"), action: .findTesting))
        }
        if input.hasReadings, let first = input.missingTests.first {
            let names = input.missingTests.prefix(2).map { $0.name.lowercased() }.formatted(.list(type: .and))
            alerts.append(AppAlert(id: "missing.\(first.rawValue)", severity: .attention, symbol: "circle.dashed",
                                   title: String(localized: "Test for \(names)"),
                                   detail: String(localized: "Your score is less certain without it."),
                                   actionTitle: String(localized: "Find testing"), action: .findTesting))
        }
        for mode in WaterMode.allCases where input.modes.contains(mode) {
            alerts.append(AppAlert(id: "mode.\(mode.rawValue)", severity: .info, symbol: mode.symbol,
                                   title: String(localized: "\(mode.label) mode is on"),
                                   detail: String(localized: "Tap to see guidance or turn it off."),
                                   actionTitle: String(localized: "Open"), action: .modes))
        }
        // Stable sort by severity.
        return alerts.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
    }

    /// The bell badge: anything that asks for action (not status-only).
    static func badgeCount(_ alerts: [AppAlert]) -> Int {
        alerts.filter { $0.severity > .info }.count
    }
}

extension AlertCenter.Inputs {
    @MainActor
    static func from(_ snapshot: WaterSnapshot, weatherEvents: [String], modes: Set<WaterMode>) -> AlertCenter.Inputs {
        AlertCenter.Inputs(
            safety: snapshot.alerts,
            weatherEvents: weatherEvents,
            filters: snapshot.filtersByDue.compactMap { item in item.days.map { (item.filter.name, $0) } },
            tests: snapshot.testsDue,
            missingTests: snapshot.drinking?.missingTests ?? [],
            modes: modes,
            hasReadings: snapshot.hasReadings,
            now: snapshot.now)
    }
}
