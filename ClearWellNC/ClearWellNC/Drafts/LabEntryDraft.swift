//
//  LabEntryDraft.swift
//  ClearWellNC
//
//  Typed-in lab results before they are saved. Lives in the draft store (saved on every keystroke);
//  only "Save" turns it into a LabResult, so half-typed numbers never change the score.
//

import Foundation

nonisolated enum LabEntryStep: String, Codable, Hashable, Sendable, CaseIterable {
    case details, commonTests, otherTests, bacteria
}

nonisolated struct LabEntryDraft: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var text = ""
        var unit: ConcentrationUnit?
    }

    var date: Date
    var labName = ""
    var entries: [Analyte: Entry] = [:]
    var totalColiform: BacteriaResult?
    var eColi: BacteriaResult?
    /// Optional so drafts saved before this field still load.
    var testMethod: TestMethod?
    var flow = StepFlow(root: LabEntryStep.details)

    init(date: Date = .now) {
        self.date = date
    }

    /// One draft for a new result, and one per existing result being edited (keyed by when it was created).
    static func key(editingCreatedAt createdAt: Date?) -> DraftKey<LabEntryDraft> {
        let name = createdAt.map { "labEntry.edit.\(Int($0.timeIntervalSinceReferenceDate * 1000))" } ?? "labEntry.new"
        return DraftKey(name: name, schemaVersion: 1)
    }

    func entry(for analyte: Analyte) -> Entry {
        entries[analyte] ?? Entry(unit: analyte.storedUnit)
    }

    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = try? FloatingPointFormatStyle<Double>(locale: locale).parseStrategy.parse(trimmed),
              value >= 0, value.isFinite
        else { return nil }
        return value
    }

    func isInvalid(_ analyte: Analyte) -> Bool {
        let text = entry(for: analyte).text
        return !text.isEmpty && Self.parse(text) == nil
    }

    /// The value converted to the analyte's stored unit, or nil if blank or invalid.
    func storedValue(for analyte: Analyte) -> Double? {
        guard let entry = entries[analyte], let value = Self.parse(entry.text) else { return nil }
        guard let stored = analyte.storedUnit, let unit = entry.unit else { return value }
        return ConcentrationUnit.convert(value, from: unit, to: stored)
    }

    var hasInvalidEntry: Bool { Analyte.allCases.contains(where: isInvalid) }

    var canSave: Bool {
        guard !hasInvalidEntry else { return false }
        let anyValue = Analyte.allCases.contains { storedValue(for: $0) != nil }
        return anyValue || totalColiform != nil || eColi != nil
    }

    /// Prefilled from a saved result, for editing.
    @MainActor
    init(editing existing: LabResult) {
        self.init(date: existing.date)
        labName = existing.labName
        testMethod = existing.testMethod
        totalColiform = existing.totalColiform
        eColi = existing.eColi
        for analyte in Analyte.allCases {
            if let value = existing.value(for: analyte) {
                entries[analyte] = Entry(text: value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)),
                                         unit: analyte.storedUnit)
            }
        }
    }

    @MainActor
    func apply(to result: LabResult) {
        result.date = date
        result.labName = labName.trimmingCharacters(in: .whitespacesAndNewlines)
        result.testMethod = testMethod ?? .certifiedLab
        for analyte in Analyte.allCases {
            result.setValue(storedValue(for: analyte), for: analyte)
        }
        result.totalColiform = totalColiform
        result.eColi = eColi
    }
}
