//
//  DemoReports.swift
//  AquaShield
//
//  Made-up sample reports so Report Quest can be shown without real test data. Every screen that
//  uses one shows a "Sample data" label, and playing one never saves points or badges.
//

import Foundation

nonisolated enum DemoReport: String, CaseIterable, Identifiable, Sendable {
    /// Mostly fine, two readings to watch. Score lands in Fair.
    case typical
    /// Arsenic over the limit and E. coli found: shows the safety alert path.
    case problem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typical: String(localized: "Sample: a typical report")
        case .problem: String(localized: "Sample: a report with a problem")
        }
    }

    var subtitle: String {
        switch self {
        case .typical: String(localized: "Mostly safe, with a couple of readings to watch.")
        case .problem: String(localized: "Shows what happens when a result is over a health limit.")
        }
    }

    func report(now: Date = .now, calendar: Calendar = .current) -> QuestReport {
        let date = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        switch self {
        case .typical:
            return QuestReport(
                date: date,
                values: [.arsenic: 2, .lead: 1, .nitrate: 6, .manganese: 40, .pH: 6.8],
                presence: [.totalColiform: false, .eColi: false],
                isSample: true)
        case .problem:
            return QuestReport(
                date: date,
                values: [.arsenic: 14, .lead: 3, .nitrate: 2, .manganese: 20, .pH: 7.1],
                presence: [.totalColiform: true, .eColi: true],
                isSample: true)
        }
    }
}
