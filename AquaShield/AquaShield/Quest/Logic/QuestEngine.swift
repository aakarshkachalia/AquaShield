//
//  QuestEngine.swift
//  AquaShield
//
//  Report Quest game rules. Pure value types and functions: no UI, no storage, so every rule is
//  unit-testable. All classification comes from the existing interpretation layer
//  (`Interpretation.interpret`) and scoring from `WellHealthScore`; nothing is re-derived here.
//

import Foundation
import NaturalLanguage

// MARK: - Report

/// One lab report as the game sees it: the latest reading of each contaminant on that report.
nonisolated struct QuestReport: Sendable {
    let date: Date

    /// Identifies this report's readings, so a saved game is only resumed for the same report.
    var draftID: String {
        let readings = values.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }
        let bacteria = presence.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value)" }
        return ([String(Int(date.timeIntervalSinceReferenceDate))] + readings + bacteria).joined(separator: "|")
    }
    var values: [ContaminantID: Double] = [:]
    /// Bacteria: true = present.
    var presence: [ContaminantID: Bool] = [:]
    /// Demo data. Every screen labels it, and it never earns saved points or badges.
    var isSample = false

    /// Every reading on the report, interpreted, in report order (same order as the Well Record).
    var interpretations: [Interpretation] {
        var list: [Interpretation] = []
        for analyte in Analyte.allCases {
            if let value = values[analyte.contaminant] {
                list.append(Interpretation.interpret(analyte.contaminant, value: value))
            }
        }
        for id in [ContaminantID.totalColiform, .eColi] {
            if let present = presence[id] {
                list.append(Interpretation.interpret(id, present: present))
            }
        }
        return list
    }

    var scoreInput: WellHealthScore.Input {
        WellHealthScore.Input(values: values, presence: presence)
    }

    var isEmpty: Bool { values.isEmpty && presence.isEmpty }
}

// MARK: - Answers

/// The three choices at each stop. Icon + text, never color alone.
nonisolated enum QuestAnswer: String, CaseIterable, Sendable, Codable {
    case safe, watch, above

    var label: String {
        switch self {
        case .safe: String(localized: "Safe")
        case .watch: String(localized: "Watch")
        case .above: String(localized: "Above limit")
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .watch: "eye.fill"
        case .above: "exclamationmark.triangle.fill"
        }
    }

    var tier: Interpretation.Tier {
        switch self {
        case .safe: .safe
        case .watch: .watch
        case .above: .above
        }
    }

    /// The correct answer for a reading, straight from the app's classification.
    /// Over a cosmetic guideline (`.nuisance`) counts as "Above limit": it is over its guideline,
    /// and the reveal explains that it isn't a health limit. Classified-only readings (hardness) have
    /// no limit to compare against, so they are not game stops.
    static func correct(for tier: Interpretation.Tier) -> QuestAnswer? {
        switch tier {
        case .safe: .safe
        case .watch: .watch
        case .above, .nuisance: .above
        case .info: nil
        }
    }
}

// MARK: - Stops

nonisolated struct QuestStop: Sendable, Identifiable {
    let id: Int
    let interpretation: Interpretation
    let correctAnswer: QuestAnswer
    /// One "Did you know?" fact about this contaminant.
    let fact: String
    /// Optional multiple-choice question from the Learn quiz bank.
    let bonus: QuizQuestion?

    var contaminant: ContaminantID { interpretation.id }
    var name: String { contaminant.info.name }

    /// Health exceedance or bacteria: shown in a calm, neutral style with no celebration.
    var isSerious: Bool { interpretation.isHealthExceedance }

    /// Light haptics and sparkle only for correct Safe / Watch answers on non-serious stops.
    func celebrates(_ answer: QuestAnswer) -> Bool {
        !isSerious && answer == correctAnswer && (answer == .safe || answer == .watch)
    }

    /// Plain-English explanation, at most two sentences.
    var explanation: String { QuestText.firstSentences(interpretation.sentence, max: 2) }

    /// What to do, for anything above Safe.
    var action: String? {
        switch interpretation.tier {
        case .above, .nuisance, .watch: interpretation.nextAction
        case .safe, .info: nil
        }
    }
}

nonisolated enum QuestEngine {
    /// Contaminant stops on the path. Plus the final score stop, that's 2–8 nodes.
    static let maxContaminantStops = 7

    static let pointsCorrect = 10
    static let pointsTried = 3

    /// +10 for correct, +3 for trying. Points are never taken away.
    static func points(correct: Bool) -> Int { correct ? pointsCorrect : pointsTried }

    /// Builds the path. When a report has more readings than fit, serious and non-safe readings win
    /// the spots; the chosen stops keep report order.
    static func stops(for report: QuestReport) -> [QuestStop] {
        let playable = report.interpretations.compactMap { i -> (Interpretation, QuestAnswer)? in
            QuestAnswer.correct(for: i.tier).map { (i, $0) }
        }
        let chosen: [(offset: Int, element: (Interpretation, QuestAnswer))]
        if playable.count <= maxContaminantStops {
            chosen = Array(playable.enumerated())
        } else {
            chosen = playable.enumerated()
                .sorted { priority($0.element.0) > priority($1.element.0) ||
                    (priority($0.element.0) == priority($1.element.0) && $0.offset < $1.offset) }
                .prefix(maxContaminantStops)
                .sorted { $0.offset < $1.offset }
        }
        return chosen.enumerated().map { index, entry in
            let (interpretation, answer) = entry.element
            return QuestStop(id: index, interpretation: interpretation, correctAnswer: answer,
                             fact: fact(for: interpretation.id, index: index),
                             bonus: bonusQuestion(for: interpretation.id, index: index))
        }
    }

    private static func priority(_ i: Interpretation) -> Int {
        if i.isHealthExceedance { return 3 }
        switch i.tier {
        case .above, .nuisance: return 2
        case .watch: return 1
        case .safe, .info: return 0
        }
    }

    // SOURCE vr-059 (needs verification, see VerificationRegister.json): facts are reused from LearnContent / ContaminantInfo, which carry their own VERIFY notes.
    /// Alternates "where it comes from" and "who is most at risk" from the Learn article, falling back
    /// to the contaminant's summary. Short: at most two sentences.
    static func fact(for id: ContaminantID, index: Int) -> String {
        let article = LearnLibrary.article(for: id)
        let candidates = [article?.whereFrom, article?.mostAtRisk].compactMap { $0 }
        let text = candidates.isEmpty ? id.info.plainSummary : candidates[index % candidates.count]
        return QuestText.firstSentences(text, max: 2)
    }

    static func bonusQuestion(for id: ContaminantID, index: Int) -> QuizQuestion? {
        guard let quiz = LearnLibrary.article(for: id)?.quiz, !quiz.isEmpty else { return nil }
        return quiz[index % quiz.count]
    }

    // MARK: Safety override

    /// Readings that must be shown on the serious alert screen before the game: any health-based
    /// limit met or exceeded (including health advisories) and any bacteria detected.
    static func safetyFindings(for report: QuestReport) -> [Interpretation] {
        report.interpretations.filter(\.isHealthExceedance)
    }

    static func requiresSafetyAlert(_ report: QuestReport) -> Bool {
        !safetyFindings(for: report).isEmpty
    }

    static func eColiPositive(_ report: QuestReport) -> Bool {
        report.presence[.eColi] == true
    }

    // MARK: Final stop: guess the score

    /// The four score ranges the player picks from, best first.
    static let scoreChoices: [WellHealthScore.Band] = [.good, .fair, .poor, .unsafe]

    static func scoreRangeText(_ band: WellHealthScore.Band) -> String {
        switch band {
        case .good: String(localized: "80–100")
        case .fair: String(localized: "60–79")
        case .poor: String(localized: "41–59")
        case .unsafe: String(localized: "0–40")
        }
    }

    // MARK: End screen

    enum NextActionKind: Equatable, Sendable {
        case urgent, fix, test, retest, allSet
    }

    struct NextAction: Sendable {
        let kind: NextActionKind
        let text: String
    }

    /// ONE clear next step, most important first: a health problem, then anything to fix or watch,
    /// then missing key tests, then the yearly retest.
    static func nextAction(score: WellHealthScore.Result, reportDate: Date, now: Date = .now,
                           calendar: Calendar = .current) -> NextAction {
        if let urgent = score.factors.first(where: { $0.interpretation.isHealthExceedance }) {
            return NextAction(kind: .urgent, text: urgent.nextAction)
        }
        if let issue = score.factors.first(where: { [.above, .nuisance, .watch].contains($0.interpretation.tier) }) {
            return NextAction(kind: .fix, text: issue.nextAction)
        }
        if let missing = score.missingKeyTests.first {
            return NextAction(kind: .test, text: String(localized: "Next, get a test for \(missing.name). Your county health department can help."))
        }
        let due = calendar.date(byAdding: .year, value: 1, to: reportDate) ?? reportDate
        if due <= now {
            return NextAction(kind: .retest, text: String(localized: "It's been a year since this test. Time to test again."))
        }
        return NextAction(kind: .allSet, text: String(localized: "You're all set. Test again by \(due.formatted(date: .long, time: .omitted))."))
    }
}

// MARK: - A play-through

/// The state of one game. Value type, so views hold it in @State and tests can drive it directly.
nonisolated struct QuestRun: Sendable {
    let report: QuestReport
    let stops: [QuestStop]
    let score: WellHealthScore.Result
    private(set) var answers: [Int: QuestAnswer] = [:]
    private(set) var bonusAnswers: [Int: Int] = [:]
    private(set) var scoreGuess: WellHealthScore.Band?

    init(report: QuestReport) {
        self.report = report
        self.stops = QuestEngine.stops(for: report)
        self.score = WellHealthScore.compute(report.scoreInput)
    }

    /// The player's answers so far, for saving a game in progress.
    struct Progress: Codable, Sendable, Equatable {
        var answers: [Int: QuestAnswer] = [:]
        var bonusAnswers: [Int: Int] = [:]
        var scoreGuess: WellHealthScore.Band?
    }

    var progress: Progress {
        Progress(answers: answers, bonusAnswers: bonusAnswers, scoreGuess: scoreGuess)
    }

    /// Resumes a saved game. Answers for stops that no longer exist are dropped.
    init(report: QuestReport, progress: Progress) {
        self.init(report: report)
        let ids = Set(stops.map(\.id))
        answers = progress.answers.filter { ids.contains($0.key) }
        bonusAnswers = progress.bonusAnswers.filter { ids.contains($0.key) }
        scoreGuess = hasScoreGuess ? progress.scoreGuess : nil
    }

    /// Stops answered, plus the score guess, for the progress bar.
    var completedCount: Int { answers.count + (scoreGuess == nil ? 0 : 1) }
    var totalCount: Int { stops.count + (hasScoreGuess ? 1 : 0) }

    /// The score stop asks for a guess only when there is a score to reveal.
    var hasScoreGuess: Bool { score.band != nil }

    /// First unanswered stop; nil once all contaminant stops are done.
    var currentStopIndex: Int? { stops.indices.first { answers[$0] == nil } }

    var contaminantStopsDone: Bool { currentStopIndex == nil }

    var isFinished: Bool { contaminantStopsDone && (!hasScoreGuess || scoreGuess != nil) }

    func answer(for stop: QuestStop) -> QuestAnswer? { answers[stop.id] }

    func isCorrect(_ stop: QuestStop) -> Bool { answers[stop.id] == stop.correctAnswer }

    /// Records the first answer only; later taps can't change it.
    @discardableResult
    mutating func answer(_ stop: QuestStop, with answer: QuestAnswer) -> Int {
        guard answers[stop.id] == nil else { return 0 }
        answers[stop.id] = answer
        return QuestEngine.points(correct: answer == stop.correctAnswer)
    }

    @discardableResult
    mutating func answerBonus(_ stop: QuestStop, optionIndex: Int) -> Int {
        guard let bonus = stop.bonus, bonusAnswers[stop.id] == nil else { return 0 }
        bonusAnswers[stop.id] = optionIndex
        return QuestEngine.points(correct: optionIndex == bonus.correctIndex)
    }

    func bonusAnswer(for stop: QuestStop) -> Int? { bonusAnswers[stop.id] }

    @discardableResult
    mutating func guessScore(_ band: WellHealthScore.Band) -> Int {
        guard hasScoreGuess, scoreGuess == nil else { return 0 }
        scoreGuess = band
        return QuestEngine.points(correct: band == score.band)
    }

    var scoreGuessCorrect: Bool { scoreGuess != nil && scoreGuess == score.band }

    var points: Int {
        var total = 0
        for stop in stops {
            if let answer = answers[stop.id] { total += QuestEngine.points(correct: answer == stop.correctAnswer) }
            if let bonus = stop.bonus, let chosen = bonusAnswers[stop.id] {
                total += QuestEngine.points(correct: chosen == bonus.correctIndex)
            }
        }
        if let guess = scoreGuess { total += QuestEngine.points(correct: guess == score.band) }
        return total
    }

    var correctCount: Int { stops.filter(isCorrect).count }

    /// "Perfect Read": every contaminant stop and the score guess (when asked) right. Bonus doesn't count.
    var isPerfect: Bool {
        isFinished && correctCount == stops.count && (!hasScoreGuess || scoreGuessCorrect)
    }

    var nextAction: QuestEngine.NextAction {
        QuestEngine.nextAction(score: score, reportDate: report.date)
    }
}

// MARK: - Text

nonisolated enum QuestText {
    /// The first `max` sentences, using the system's sentence rules so it works in Spanish too.
    static func firstSentences(_ text: String, max: Int) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(text[range].trimmingCharacters(in: .whitespacesAndNewlines))
            return sentences.count < max
        }
        return sentences.isEmpty ? text : sentences.joined(separator: " ")
    }
}

nonisolated extension LearnLibrary {
    static func article(for id: ContaminantID) -> LearnArticle? {
        articles.first { $0.contaminants.contains(id) }
    }
}
