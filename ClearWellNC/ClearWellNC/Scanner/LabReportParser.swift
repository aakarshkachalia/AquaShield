//
//  LabReportParser.swift
//  ClearWellNC
//
//  Turns OCR text from a lab report into structured readings. Pure Swift: no Vision, no UI, so every
//  rule is unit-tested with text fixtures.
//
//  Per line:
//   1. Split into tokens; find the first "value" token (a number, "<0.005", ND, Present/Absent…).
//      Method numbers ("EPA 200.8") and dates are skipped so they aren't read as results.
//   2. Everything before the value is the name. Match it to ContaminantID aliases after undoing common
//      OCR swaps (1→i, 0→o, 5→s) and allowing a small edit distance ("Arsen1c", "Manganse").
//   3. Repair the value (O→0, l→1, S→5), read the unit next to it, and convert to the app's unit.
//   4. Score confidence: every guess or repair lowers it, with a plain-language note why.
//

import Foundation

nonisolated enum LabReportParser {
    // MARK: Types

    enum Reading: Sendable, Equatable {
        case value(Double)
        /// "<0.005": below the lab's detection limit (the limit, in the reported unit).
        case belowDetection(limit: Double)
        /// "ND", "Not Detected", "BDL" with no limit given.
        case notDetected
        case present
        case absent
    }

    enum ReportedUnit: String, CaseIterable, Codable, Sendable, Identifiable {
        case mgL, ugL, ppm, ppb, ppt, ngL, pCiL, gpg, su

        var id: String { rawValue }

        var label: String {
            switch self {
            case .mgL: "mg/L"
            case .ugL: "µg/L"
            case .ppm: "ppm"
            case .ppb: "ppb"
            case .ppt: "ppt"
            case .ngL: "ng/L"
            case .pCiL: "pCi/L"
            case .gpg: "gpg"
            case .su: "s.u."
            }
        }

        /// How many of the app's base unit one reported unit is worth, for mass concentrations (in µg/L).
        fileprivate var microgramsPerLiter: Double? {
            switch self {
            case .mgL, .ppm: 1000
            case .ugL, .ppb: 1
            case .ppt, .ngL: 0.001
            case .pCiL, .gpg, .su: nil
            }
        }
    }

    struct Note: Sendable, Equatable, Hashable {
        let text: String
        /// How much this note lowered confidence.
        let penalty: Double
    }

    struct ParsedRow: Sendable, Identifiable, Equatable {
        var id = UUID()
        /// The OCR line it came from.
        var rawLine: String
        /// The name as printed.
        var rawName: String
        /// Nil = "unrecognized": kept for the user to review, never silently dropped.
        var contaminant: ContaminantID?
        var reading: Reading
        var unit: ReportedUnit?
        /// Value in ContaminantInfo's unit (numeric readings only).
        var normalizedValue: Double?
        /// Detection limit in ContaminantInfo's unit (below-detection readings only).
        var normalizedDetectionLimit: Double?
        var notes: [Note] = []

        /// 0…1. Starts at 1 and drops with each repair or guess.
        var confidence: Double {
            guard contaminant != nil else { return 0 }
            return max(0, min(1, 1 - notes.reduce(0) { $0 + $1.penalty }))
        }

        var needsReview: Bool { contaminant == nil || confidence < LabReportParser.reviewThreshold }
    }

    struct Result: Sendable {
        var rows: [ParsedRow]
        var collectionDate: Date?
        var labName: String?

        var recognized: [ParsedRow] { rows.filter { $0.contaminant != nil } }
        var unrecognized: [ParsedRow] { rows.filter { $0.contaminant == nil } }
    }

    /// Rows under this confidence are highlighted "Please check this".
    static let reviewThreshold = 0.7

    // MARK: Entry points

    static func parse(text: String) -> Result {
        parse(lines: text.components(separatedBy: .newlines))
    }

    static func parse(lines: [String]) -> Result {
        var rows: [ParsedRow] = []
        var date: Date?
        var lab: String?
        for raw in lines {
            let line = clean(raw)
            guard !line.isEmpty else { continue }
            if date == nil, let found = collectionDate(in: line) { date = found; continue }
            if lab == nil, let found = labName(in: line) { lab = found; continue }
            if isMetadata(line) { continue }
            if let row = parseRow(line) { rows.append(row) }
        }
        return Result(rows: dedupe(rows), collectionDate: date, labName: lab)
    }

    // MARK: One row

    static func parseRow(_ line: String) -> ParsedRow? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let valueIndex = firstValueIndex(tokens) else { return nil }
        let nameTokens = Array(tokens[..<valueIndex])
        let rawName = nameTokens.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.-|,;").union(.whitespaces))
        guard rawName.filter(\.isLetter).count >= 2 else { return nil }

        var notes: [Note] = []
        let match = matchContaminant(rawName)
        if let penalty = match?.penalty, penalty > 0 {
            notes.append(Note(text: String(localized: "The name was hard to read; we matched it to the closest test."), penalty: penalty))
        }

        let rest = Array(tokens[valueIndex...])
        guard var (reading, consumed, repaired) = readValue(rest) else { return nil }
        if repaired {
            notes.append(Note(text: String(localized: "Some characters in the number looked like letters, so we corrected them."), penalty: 0.15))
        }
        let unit = readUnit(Array(rest.dropFirst(consumed).prefix(4)))

        var row = ParsedRow(rawLine: line, rawName: rawName, contaminant: match?.id, reading: reading, unit: unit)
        guard let id = match?.id else { return row }   // unrecognized: keep as-is

        let info = id.info
        if info.unit == .presence {
            // Bacteria: a number counts as present if above zero ("<1" means none found).
            switch reading {
            case .value(let v): reading = v > 0 ? .present : .absent
            case .belowDetection, .notDetected: reading = .absent
            case .present, .absent: break
            }
            row.reading = reading
            row.notes = notes
            return row
        }
        if reading == .present || reading == .absent {
            notes.append(Note(text: String(localized: "This test usually has a number, but the report shows a word."), penalty: 0.4))
        }

        switch reading {
        case .value(let v):
            let (value, unitNotes) = normalize(v, from: unit, to: info.unit, contaminant: id)
            row.normalizedValue = value
            notes += unitNotes
            if let value { notes += plausibility(value, info: info) }
        case .belowDetection(let limit):
            let (value, unitNotes) = normalize(limit, from: unit, to: info.unit, contaminant: id)
            row.normalizedDetectionLimit = value
            notes += unitNotes
            if let value, let mcl = info.maximumLimit, value >= mcl {
                notes.append(Note(text: String(localized: "The lab's detection limit is at or above the safe limit, so this result can't confirm the water is under the limit."), penalty: 0.35))
            }
        case .notDetected, .present, .absent:
            break
        }
        row.notes = notes
        return row
    }

    // MARK: Values

    private static let nonDetectWords: Set<String> = ["nd", "n.d.", "bdl", "<mdl", "<rl", "<pql", "non-detect", "nondetect"]
    private static let presentWords: Set<String> = ["present", "positive", "pos", "detected", "+", "p"]
    private static let absentWords: Set<String> = ["absent", "negative", "neg", "a"]
    private static let methodWords: Set<String> = ["epa", "sm", "method", "astm", "usgs", "hach"]

    /// Index of the first token that starts the result.
    static func firstValueIndex(_ tokens: [String]) -> Int? {
        for (i, raw) in tokens.enumerated() {
            let t = raw.lowercased()
            if i > 0, methodWords.contains(tokens[i - 1].lowercased().trimmingCharacters(in: .punctuationCharacters)) {
                continue  // "EPA 200.8" is a method, not a result
            }
            if i == 0 && (t == "a" || t == "p") { continue }   // single letters only count after a name
            if isDateLike(t) { return nil }
            if nonDetectWords.contains(t) || absentWords.contains(t) || presentWords.contains(t) { return i }
            if t == "not" || t == "none", i + 1 < tokens.count, tokens[i + 1].lowercased().hasPrefix("detect") { return i }
            if t.hasPrefix("<") || t.hasPrefix("≤") { return i }
            if repairedNumber(t) != nil { return i }
        }
        return nil
    }

    /// Reads the result starting at `tokens[0]`. Returns the reading, tokens consumed, and whether OCR repairs were needed.
    static func readValue(_ tokens: [String]) -> (Reading, Int, Bool)? {
        guard let first = tokens.first?.lowercased() else { return nil }
        if first == "not" || first == "none" { return (.notDetected, 2, false) }
        if nonDetectWords.contains(first) { return (.notDetected, 1, false) }
        if presentWords.contains(first) { return (.present, 1, false) }
        if absentWords.contains(first) { return (.absent, 1, false) }

        if first.hasPrefix("<") || first.hasPrefix("≤") {
            let remainder = String(first.drop { $0 == "<" || $0 == "≤" || $0 == "=" })
            if remainder.isEmpty, tokens.count > 1, let (n, repaired) = repairedNumber(tokens[1].lowercased()) {
                return (.belowDetection(limit: n), 2, repaired)
            }
            if let (n, repaired) = repairedNumber(remainder) { return (.belowDetection(limit: n), 1, repaired) }
            return (.notDetected, 1, false)
        }
        if let (n, repaired) = repairedNumber(first) { return (.value(n), 1, repaired) }
        return nil
    }

    /// Parses a number, fixing common OCR letter-for-digit swaps. Nil if it isn't number-like.
    static func repairedNumber(_ token: String) -> (Double, Bool)? {
        var t = token.trimmingCharacters(in: CharacterSet(charactersIn: "*,;:)("))
        guard !t.isEmpty, t.count <= 12 else { return nil }
        let digits = t.filter(\.isNumber).count
        guard digits >= 1 else { return nil }
        let allowed = Set("0123456789.,oOlIi|sSbB")
        guard t.allSatisfy(allowed.contains), digits * 2 >= t.filter({ $0 != "." && $0 != "," }).count else { return nil }
        let swaps: [Character: Character] = ["o": "0", "O": "0", "l": "1", "I": "1", "i": "1", "|": "1", "s": "5", "S": "5", "b": "8", "B": "8"]
        var repaired = false
        t = String(t.map { c in
            if let d = swaps[c] { repaired = true; return d }
            return c
        })
        // "0,005" is a decimal comma; "1,200" is a thousands separator.
        if t.contains(",") {
            t = t.hasPrefix("0,") && !t.contains(".") ? t.replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        }
        guard t.filter({ $0 == "." }).count <= 1, let value = Double(t), value.isFinite, value >= 0 else { return nil }
        return (value, repaired)
    }

    // MARK: Units

    static func readUnit(_ tokens: [String]) -> ReportedUnit? {
        for raw in tokens {
            var t = raw.lowercased().replacingOccurrences(of: "μ", with: "u").replacingOccurrences(of: "µ", with: "u")
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: "(),;:"))
            // OCR often reads the "l" in "mg/l" as "1" or "i".
            t = t.replacingOccurrences(of: "/1", with: "/l").replacingOccurrences(of: "/i", with: "/l")
            switch t {
            case "mg/l", "mgl", "mg/liter": return .mgL
            case "ug/l", "ugl", "mcg/l": return .ugL
            case "ppm": return .ppm
            case "ppb": return .ppb
            case "ppt": return .ppt
            case "ng/l", "ngl": return .ngL
            case "pci/l", "pcil": return .pCiL
            case "gpg", "grains/gal": return .gpg
            case "s.u.", "su", "s.u", "units", "std.units": return .su
            default: continue
            }
        }
        return nil
    }

    /// Converts a reported value to ContaminantInfo's unit.
    static func normalize(_ value: Double, from unit: ReportedUnit?, to target: MeasurementUnit,
                          contaminant: ContaminantID) -> (Double?, [Note]) {
        switch target {
        case .pH:
            return (value, [])
        case .presence:
            return (nil, [])
        case .pCiL:
            if unit == nil || unit == .pCiL { return (value, unit == nil ? [missingUnit(assumed: "pCi/L")] : []) }
            return (value, [incompatible(unit)])
        case .mgLAsCaCO3:
            switch unit {
            case .mgL?, .ppm?: return (value, [])
            case .gpg?: return (value * 17.1, [])
            case nil: return (value, [missingUnit(assumed: "mg/L")])
            default:
                if let ug = unit?.microgramsPerLiter { return (value * ug / 1000, []) }
                return (value, [incompatible(unit)])
            }
        case .ppb, .mgL, .ppt:
            let targetUG: Double = target == .ppb ? 1 : (target == .mgL ? 1000 : 0.001)
            if let unit {
                guard let ug = unit.microgramsPerLiter else { return (value, [incompatible(unit)]) }
                return (value * ug / targetUG, [])
            }
            // No unit printed: metals reported below 1 are almost always mg/L (e.g. arsenic 0.004).
            if target == .ppb && value < 1 {
                return (value * 1000, [missingUnit(assumed: "mg/L")])
            }
            return (value, [missingUnit(assumed: MeasurementUnit.label(for: target))])
        }
    }

    private static func missingUnit(assumed: String) -> Note {
        Note(text: String(localized: "No unit was found, so we assumed \(assumed)."), penalty: 0.35)
    }

    private static func incompatible(_ unit: ReportedUnit?) -> Note {
        Note(text: String(localized: "The unit (\(unit?.label ?? "")) doesn't fit this test."), penalty: 0.4)
    }

    /// Flags values that are probably a misread decimal point.
    private static func plausibility(_ value: Double, info: ContaminantInfo) -> [Note] {
        switch info.limit {
        case .range:
            return (0...14).contains(value) ? [] : [Note(text: String(localized: "pH should be between 0 and 14."), penalty: 0.5)]
        case .maximum(let limit) where value > limit * 100:
            return [Note(text: String(localized: "This is unusually high. Check the decimal point and unit."), penalty: 0.3)]
        default:
            return []
        }
    }

    // MARK: Names

    /// Lowercase, letters and digits only, with OCR digit-for-letter swaps undone.
    static func squash(_ text: String, fixOCR: Bool) -> String {
        let lowered = text.lowercased()
        let swapped: String = fixOCR
            ? String(lowered.map { c in ["1": "i", "0": "o", "5": "s", "|": "l"][c] ?? c })
            : lowered
        return swapped.filter { $0.isLetter || $0.isNumber }
    }

    /// Best contaminant for a printed name, with a confidence penalty for fuzzy matches.
    static func matchContaminant(_ name: String) -> (id: ContaminantID, penalty: Double)? {
        let lower = name.lowercased()
        // "Fecal coliform" is a different test; keep it unrecognized rather than mislabel it.
        if lower.contains("fecal") { return nil }
        let exact = squash(name, fixOCR: false)
        let fixed = squash(name, fixOCR: true)
        let words = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)

        var best: (id: ContaminantID, penalty: Double, length: Int)?
        func consider(_ id: ContaminantID, penalty: Double, length: Int) {
            if best == nil || penalty < best!.penalty || (penalty == best!.penalty && length > best!.length) {
                best = (id, penalty, length)
            }
        }

        for id in ContaminantID.allCases {
            for alias in id.aliases {
                let a = squash(alias, fixOCR: false)
                guard !a.isEmpty else { continue }
                if a.count <= 3 {
                    // Short symbols ("As", "Pb", "pH") only count as the whole name, never inside words.
                    if exact == a || (words.count == 1 && words[0] == a) { consider(id, penalty: 0, length: a.count) }
                    continue
                }
                if exact == a { consider(id, penalty: 0, length: a.count); continue }
                if fixed == a { consider(id, penalty: 0.1, length: a.count); continue }
                if exact.hasPrefix(a) || exact.contains(a) { consider(id, penalty: 0.05, length: a.count); continue }
                if fixed.contains(a) { consider(id, penalty: 0.15, length: a.count); continue }
                // Fuzzy: compare against the start of the name, allowing 1–2 typos depending on length.
                let allowed = a.count >= 7 ? 2 : 1
                let head = String(fixed.prefix(a.count))
                if editDistance(head, a) <= allowed || editDistance(fixed, a) <= allowed {
                    consider(id, penalty: 0.25, length: a.count)
                }
            }
        }
        return best.map { ($0.id, $0.penalty) }
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Metadata

    private static let metadataWords = ["page", "phone", "fax", "address", "client", "sample id", "lab id", "report",
                                        "received", "analyst", "signature", "county", "zip", "result units",
                                        "analyte", "parameter", "approved", "certification", "time"]

    static func isMetadata(_ line: String) -> Bool {
        let lower = line.lowercased()
        return metadataWords.contains { lower.hasPrefix($0) || lower.contains("\($0):") }
    }

    static func isDateLike(_ token: String) -> Bool {
        token.range(of: #"^\d{1,4}[/-]\d{1,2}[/-]\d{1,4}$"#, options: .regularExpression) != nil
            || token.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) != nil
    }

    static func collectionDate(in line: String) -> Date? {
        let lower = line.lowercased()
        guard lower.contains("collect") || lower.contains("sampled") || lower.contains("sample date") else { return nil }
        guard let range = line.range(of: #"\d{1,2}/\d{1,2}/\d{2,4}"#, options: .regularExpression) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["MM/dd/yyyy", "M/d/yyyy", "MM/dd/yy", "M/d/yy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: String(line[range])) { return date }
        }
        return nil
    }

    static func labName(in line: String) -> String? {
        let lower = line.lowercased()
        guard lower.contains("laborator"), !line.contains(where: \.isNumber) else { return nil }
        return line.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Cleanup

    static func clean(_ line: String) -> String {
        line.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "|", with: " ")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// One row per contaminant: the most confident wins. Unrecognized rows are all kept.
    static func dedupe(_ rows: [ParsedRow]) -> [ParsedRow] {
        var bestIndex: [ContaminantID: Int] = [:]
        var output: [ParsedRow] = []
        for row in rows {
            guard let id = row.contaminant else { output.append(row); continue }
            if let i = bestIndex[id] {
                if row.confidence > output[i].confidence { output[i] = row }
            } else {
                bestIndex[id] = output.count
                output.append(row)
            }
        }
        return output
    }
}

nonisolated extension MeasurementUnit {
    static func label(for unit: MeasurementUnit) -> String { unit.label }
}
