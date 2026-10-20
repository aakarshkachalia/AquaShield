//
//  ScanDraft.swift
//  ClearWellNC
//
//  Editable rows for the scan review screen, and how they are saved into a LabResult.
//

import Foundation

struct ReviewRow: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case number, belowDetection, notDetected, present, absent
        var id: String { rawValue }

        var label: String {
            switch self {
            case .number: String(localized: "Number")
            case .belowDetection: String(localized: "Below detection (<)")
            case .notDetected: String(localized: "Not detected")
            case .present: String(localized: "Present")
            case .absent: String(localized: "Absent")
            }
        }
    }

    let id = UUID()
    var contaminant: ContaminantID?
    /// What OCR read, shown as "Read as: …".
    var rawText: String
    var kind: Kind
    var valueText: String
    var unit: LabReportParser.ReportedUnit?
    var notes: [String]
    var confidence: Double
    /// Once the user edits a row, it no longer asks to be checked.
    var edited = false

    var needsReview: Bool { contaminant == nil || (!edited && confidence < LabReportParser.reviewThreshold) }

    var isPresenceTest: Bool { contaminant?.info.unit == .presence }

    init(parsed: LabReportParser.ParsedRow) {
        contaminant = parsed.contaminant
        rawText = parsed.rawLine
        notes = parsed.notes.map(\.text)
        confidence = parsed.confidence
        unit = parsed.unit
        switch parsed.reading {
        case .value(let v): kind = .number; valueText = formatNumber(v)
        case .belowDetection(let limit): kind = .belowDetection; valueText = formatNumber(limit)
        case .notDetected: kind = .notDetected; valueText = ""
        case .present: kind = .present; valueText = ""
        case .absent: kind = .absent; valueText = ""
        }
    }

    /// A blank row the user fills in.
    init() {
        contaminant = nil
        rawText = ""
        kind = .number
        valueText = ""
        unit = nil
        notes = []
        confidence = 1
        edited = true
    }

    /// Units that make sense for the chosen test.
    var unitChoices: [LabReportParser.ReportedUnit] {
        switch contaminant?.info.unit {
        case .ppb?, .mgL?, .ppt?: [.mgL, .ugL, .ppm, .ppb, .ppt, .ngL]
        case .pCiL?: [.pCiL]
        case .mgLAsCaCO3?: [.mgL, .ppm, .gpg]
        default: []
        }
    }

    var number: Double? {
        let text = valueText.trimmingCharacters(in: .whitespaces)
        return LabReportParser.repairedNumber(text)?.0
    }

    /// Value or detection limit converted to the app's unit.
    var normalized: Double? {
        guard let id = contaminant, let number else { return nil }
        return LabReportParser.normalize(number, from: unit, to: id.info.unit, contaminant: id).0
    }

    /// Live status preview, from the app's classification.
    var preview: Interpretation? {
        guard let id = contaminant else { return nil }
        switch kind {
        case .present: return .interpret(id, present: true)
        case .absent: return .interpret(id, present: false)
        case .notDetected: return .interpretNonDetect(id, detectionLimit: nil)
        case .belowDetection: return normalized.map { .interpretNonDetect(id, detectionLimit: $0) }
        case .number: return normalized.map { .interpret(id, value: $0) }
        }
    }

    /// Whether saving this row stores anything.
    var isSavable: Bool {
        guard let id = contaminant else { return false }
        if isPresenceTest { return kind == .present || kind == .absent }
        switch kind {
        case .number, .belowDetection: return normalized != nil && Analyte.allCases.contains { $0.contaminant == id }
        case .notDetected: return true
        case .present, .absent: return false
        }
    }

    /// Writes this row into a result.
    ///  - "<DL" with a detection limit at or above the safe limit can't confirm safety, so it is not saved as
    ///    a reading (the test stays "missing" in the score) rather than being counted as safe.
    @MainActor
    func apply(to result: LabResult) {
        guard let id = contaminant, isSavable else { return }
        if id == .totalColiform { result.totalColiform = kind == .present ? .present : .absent; return }
        if id == .eColi { result.eColi = kind == .present ? .present : .absent; return }
        guard let analyte = Analyte.allCases.first(where: { $0.contaminant == id }) else { return }
        var nonDetects = result.nonDetects
        switch kind {
        case .number:
            result.setValue(normalized, for: analyte)
            nonDetects[analyte] = nil
        case .belowDetection:
            guard let limit = normalized else { return }
            if let mcl = id.info.maximumLimit, limit >= mcl {
                result.setValue(nil, for: analyte)
                nonDetects[analyte] = nil
            } else {
                result.setValue(0, for: analyte)
                nonDetects[analyte] = .some(limit)
            }
        case .notDetected:
            result.setValue(0, for: analyte)
            nonDetects[analyte] = .some(nil)
        case .present, .absent:
            return
        }
        result.nonDetects = nonDetects
    }
}

enum ScanDraft {
    /// Builds the result to save from reviewed rows. Later rows for the same test win.
    @MainActor
    static func makeResult(rows: [ReviewRow], date: Date, labName: String) -> LabResult {
        let result = LabResult(date: date, labName: labName.trimmingCharacters(in: .whitespacesAndNewlines))
        for row in rows { row.apply(to: result) }
        return result
    }
}
