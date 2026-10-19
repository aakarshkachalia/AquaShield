//
//  Treatment.swift
//  ClearWellNC
//

import Foundation
import SwiftData

nonisolated enum TreatmentKind: String, CaseIterable, Codable, Sendable, Identifiable {
    // Everyday filters, for any water source.
    case pitcherFilter
    case faucetFilter
    case refrigeratorFilter
    case underSinkFilter
    // Whole-house and well treatment.
    case sedimentFilter
    case carbonFilter
    case roMembrane
    case uvBulb
    case softenerSalt
    case other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pitcherFilter: String(localized: "Pitcher filter")
        case .faucetFilter: String(localized: "Faucet-mount filter")
        case .refrigeratorFilter: String(localized: "Refrigerator filter")
        case .underSinkFilter: String(localized: "Under-sink filter")
        case .sedimentFilter: String(localized: "Sediment filter")
        case .carbonFilter: String(localized: "Carbon filter")
        case .roMembrane: String(localized: "Reverse osmosis membrane")
        case .uvBulb: String(localized: "UV bulb")
        case .softenerSalt: String(localized: "Water softener salt")
        case .other: String(localized: "Other")
        }
    }

    /// Spec defaults. "Other" has no spec default; 12 months is a starting point the user can change.
    var defaultIntervalMonths: Int {
        switch self {
        case .pitcherFilter: 2
        case .faucetFilter: 3
        case .refrigeratorFilter: 6
        case .underSinkFilter: 6
        case .sedimentFilter: 3
        case .carbonFilter: 6
        case .roMembrane: 24
        case .uvBulb: 12
        case .softenerSalt: 1
        case .other: 12
        }
    }

    /// Softener salt is checked and topped up rather than replaced.
    var isCheck: Bool { self == .softenerSalt }

    /// What to look for when buying a replacement. Certification is what shows a filter removes a contaminant.
    var certificationNote: String {
        switch self {
        case .pitcherFilter, .faucetFilter, .refrigeratorFilter, .underSinkFilter, .carbonFilter:
            String(localized: "For lead, look for NSF/ANSI 53 certification. NSF/ANSI 42 only covers taste and odor. Some filters are also certified for PFAS.")
        case .roMembrane:
            String(localized: "Look for NSF/ANSI 58 certification. Reverse osmosis removes arsenic, nitrate, lead and most PFAS.")
        case .uvBulb:
            String(localized: "Look for NSF/ANSI 55 Class A. UV kills bacteria but does not remove chemicals or metals.")
        case .sedimentFilter:
            String(localized: "Sediment filters catch sand and rust. They don't remove dissolved contaminants like arsenic or nitrate.")
        case .softenerSalt:
            String(localized: "Softeners remove hardness. Look for NSF/ANSI 44 certification.")
        case .other:
            String(localized: "Check that the product is certified for the contaminant you need to remove.")
        }
    }

    var symbol: String {
        switch self {
        case .pitcherFilter: "waterbottle"
        case .faucetFilter: "spigot"
        case .refrigeratorFilter: "refrigerator"
        case .underSinkFilter: "sink"
        case .sedimentFilter, .carbonFilter: "line.3.horizontal.decrease.circle"
        case .roMembrane: "drop.triangle"
        case .uvBulb: "lightbulb"
        case .softenerSalt: "cube"
        case .other: "wrench.and.screwdriver"
        }
    }
}

@Model
final class TreatmentSystem {
    /// Stable ID for this system's notification.
    var reminderID: UUID
    var kindRaw: String
    var customName: String
    /// Install date, or the date it was last replaced/checked.
    var lastServiced: Date
    var intervalMonths: Int
    /// When the user logged the system, used for the "retest to confirm it works" reminder.
    var addedAt: Date
    /// Optional brand and model, e.g. "Brita Elite". Defaulted so existing stores migrate.
    var productName: String = ""

    init(kind: TreatmentKind, customName: String = "", productName: String = "", lastServiced: Date, intervalMonths: Int) {
        self.reminderID = UUID()
        self.kindRaw = kind.rawValue
        self.customName = customName
        self.productName = productName
        self.lastServiced = lastServiced
        self.intervalMonths = intervalMonths
        self.addedAt = .now
    }

    var kind: TreatmentKind {
        get { TreatmentKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var displayName: String {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return kind == .other && !trimmed.isEmpty ? trimmed : kind.name
    }

    var dueDate: Date {
        Calendar.current.date(byAdding: .month, value: intervalMonths, to: lastServiced) ?? lastServiced
    }

    var trimmedProductName: String? {
        let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Well care tasks

/// Recurring well-care reminders from the spec.
nonisolated enum WellCareTask: String, CaseIterable, Sendable, Identifiable {
    case bacteriaTest
    case wellheadInspection
    case metalsNitrateTest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bacteriaTest: String(localized: "Bacteria test (total coliform / E. coli)")
        case .wellheadInspection: String(localized: "Wellhead inspection")
        case .metalsNitrateTest: String(localized: "Metals and nitrate test")
        }
    }

    var intervalMonths: Int {
        switch self {
        case .bacteriaTest, .wellheadInspection: 12
        case .metalsNitrateTest: 24
        }
    }

    var frequency: String {
        switch self {
        case .bacteriaTest, .wellheadInspection: String(localized: "Every year")
        case .metalsNitrateTest: String(localized: "Every 2 years")
        }
    }

    var symbol: String {
        switch self {
        case .bacteriaTest: "allergens"
        case .wellheadInspection: "magnifyingglass"
        case .metalsNitrateTest: "testtube.2"
        }
    }

    /// UserDefaults key for a manually recorded "done" date.
    var manualKey: String { "care.\(rawValue).lastDone" }

    /// Latest of the manual date and any matching lab result. Nil if never recorded.
    @MainActor
    func lastDone(results: [LabResult], defaults: UserDefaults = .standard) -> Date? {
        let stamp = defaults.double(forKey: manualKey)
        let manual: Date? = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        let fromLab: Date? = switch self {
        case .bacteriaTest: results.filter(\.includesBacteria).map(\.date).max()
        case .metalsNitrateTest: results.filter(\.includesMetalsOrNitrate).map(\.date).max()
        case .wellheadInspection: nil
        }
        return [manual, fromLab].compactMap { $0 }.max()
    }

    /// Never-recorded tasks are due now.
    @MainActor
    func dueDate(results: [LabResult], now: Date = .now) -> Date {
        guard let last = lastDone(results: results) else { return now }
        return Calendar.current.date(byAdding: .month, value: intervalMonths, to: last) ?? now
    }

    func markDone(on date: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: manualKey)
    }
}

// MARK: - Due text

nonisolated enum DueText {
    /// Whole days from today to `due` (negative when overdue).
    static func daysRemaining(until due: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: due)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    static func text(daysRemaining days: Int, isCheck: Bool) -> String {
        if days > 0 {
            return isCheck ? String(localized: "Check in \(days) days") : String(localized: "Replace in \(days) days")
        }
        if days == 0 { return String(localized: "Due today") }
        return String(localized: "Overdue by \(-days) days")
    }

    static func careText(daysRemaining days: Int) -> String {
        if days > 0 { return String(localized: "Due in \(days) days") }
        if days == 0 { return String(localized: "Due today") }
        return String(localized: "Overdue by \(-days) days")
    }
}
