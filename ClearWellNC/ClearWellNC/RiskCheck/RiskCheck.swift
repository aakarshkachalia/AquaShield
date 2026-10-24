//
//  RiskCheck.swift
//  ClearWellNC
//
//  "Should I test?" logic. Pure: answers + county data in, recommendations out. It never says a well
//  is safe; it only says what to test for and why.
//

import Foundation

// MARK: - County data (CountyWellData.json)

nonisolated struct CountyWellRecord: Codable, Sendable, Hashable {
    let county: String
    /// A ContaminantID raw value ("arsenic", "pfoa", …).
    let contaminant: String
    let pctAboveStandard: Double
    let meanConcentration: Double
    let unit: String
    let nWells: Int
    let sample: Bool

    var contaminantID: ContaminantID? { ContaminantID(rawValue: contaminant) }
}

nonisolated struct CountyWellData: Codable, Sendable {
    let sample: Bool
    let source: String
    let records: [CountyWellRecord]

    static let resourceName = "CountyWellData"
    /// Stats from fewer tested wells than this are hidden.
    static let minimumWells = 10

    static func loadBundled(from bundle: Bundle = .main) -> CountyWellData? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CountyWellData.self, from: data)
    }

    /// Records for a county with enough wells to report.
    func reportable(for county: String) -> [CountyWellRecord] {
        records.filter { $0.county == county && $0.nWells >= Self.minimumWells && $0.contaminantID != nil }
    }
}

// MARK: - Answers

nonisolated struct RiskCheckAnswers: Codable, Sendable, Equatable {
    enum WellAge: String, Codable, Sendable, CaseIterable { case before2008, after2008, unknown }
    enum LastTest: String, Codable, Sendable, CaseIterable { case never, oneToThreeYears, threePlusYears }

    var county: String?
    var wellAge: WellAge?
    var pregnantOrInfant: Bool?
    var flooding: Bool?
    var nearbySources: Bool?
    var lastTest: LastTest?
    var noticedChanges: Bool?

    static let storageKey = "riskCheckAnswers"
}

// MARK: - Flow

nonisolated enum RiskCheckStep: String, Codable, Hashable, Sendable, CaseIterable {
    case county, wellAge, pregnancy, flooding, nearbySources, lastTest, noticedChanges, results

    static let questions = allCases.filter { $0 != .results }
}

/// In-progress Risk Check: answers plus where the user is. Saved on every answer.
nonisolated struct RiskCheckDraft: Codable, Sendable, Equatable {
    var answers: RiskCheckAnswers
    var flow = StepFlow(root: RiskCheckStep.county)

    static let key = DraftKey<RiskCheckDraft>(name: "riskCheck", schemaVersion: 1)

    init(answers: RiskCheckAnswers = RiskCheckAnswers()) {
        self.answers = answers
    }

    /// Whether the current question has an answer (so Next can skip re-tapping it).
    func isAnswered(_ step: RiskCheckStep) -> Bool {
        switch step {
        case .county, .results: true
        case .wellAge: answers.wellAge != nil
        case .pregnancy: answers.pregnantOrInfant != nil
        case .flooding: answers.flooding != nil
        case .nearbySources: answers.nearbySources != nil
        case .lastTest: answers.lastTest != nil
        case .noticedChanges: answers.noticedChanges != nil
        }
    }

    /// A restored draft is only usable if its steps still exist and it isn't already finished.
    var isResumable: Bool {
        flow.isValid(in: RiskCheckStep.allCases) && flow.current != .results
    }
}

// MARK: - Output

nonisolated enum RecommendedTestID: String, Sendable, CaseIterable {
    case bacteria, nitrate, arsenic, lead, manganese, pH, iron, hardness, uranium, radon, pfas

    var name: String {
        switch self {
        case .bacteria: String(localized: "Bacteria (total coliform / E. coli)")
        case .nitrate: ContaminantID.nitrate.info.name
        case .arsenic: ContaminantID.arsenic.info.name
        case .lead: ContaminantID.lead.info.name
        case .manganese: ContaminantID.manganese.info.name
        case .pH: ContaminantID.pH.info.name
        case .iron: ContaminantID.iron.info.name
        case .hardness: ContaminantID.hardness.info.name
        case .uranium: ContaminantID.uranium.info.name
        case .radon: ContaminantID.radon.info.name
        case .pfas: String(localized: "PFAS (\"forever chemicals\")")
        }
    }

    /// The test a county-data contaminant maps to.
    static func forContaminant(_ id: ContaminantID) -> RecommendedTestID? {
        switch id {
        case .arsenic: .arsenic
        case .nitrate, .nitrite: .nitrate
        case .lead: .lead
        case .manganese: .manganese
        case .uranium: .uranium
        case .radon: .radon
        case .pfoa, .pfos, .genx: .pfas
        case .iron: .iron
        case .pH: .pH
        case .hardness: .hardness
        default: nil
        }
    }
}

nonisolated struct RecommendedTest: Sendable, Identifiable, Equatable {
    let id: RecommendedTestID
    /// Most specific reason first.
    let reasons: [String]
    var reason: String { reasons.first ?? "" }
    var line: String { "\(id.name) — \(reason)" }
}

nonisolated struct CountyFact: Sendable, Identifiable, Equatable {
    let contaminant: ContaminantID
    let text: String
    let isSample: Bool
    var id: ContaminantID { contaminant }
}

nonisolated struct RiskCheckResult: Sendable {
    let tests: [RecommendedTest]
    let countyFacts: [CountyFact]
    let bestTimeToTest: String
    let isSampleData: Bool
    static let disclaimer = String(localized: "Only a lab test can tell you what's in your water.")
}

// MARK: - Logic

nonisolated enum RiskCheckEngine {
    /// County share above the standard that adds a test to the list.
    static let countyFlagPercent = 5.0
    /// Shown as county facts.
    static let maxFacts = 4

    static func recommend(answers: RiskCheckAnswers, countyData: CountyWellData?, trends: CountyTrendData?,
                          pfasCounties: Set<String>) -> RiskCheckResult {
        var reasons: [RecommendedTestID: [(priority: Int, text: String)]] = [:]
        func add(_ id: RecommendedTestID, _ priority: Int, _ text: String) {
            reasons[id, default: []].append((priority, text))
        }
        let county = answers.county

        // Always: bacteria, nitrate, arsenic.
        add(.bacteria, 0, String(localized: "Every well should be tested for bacteria every year."))
        add(.nitrate, 0, String(localized: "Nitrate has no taste or smell and is most dangerous for babies."))
        add(.arsenic, 0, String(localized: "Arsenic comes from bedrock in parts of North Carolina and has no taste or smell."))

        if answers.pregnantOrInfant == true {
            add(.nitrate, 9, String(localized: "An infant or pregnant person lives in your home, and nitrate is most dangerous for babies under 6 months."))
            add(.lead, 8, String(localized: "Lead is most harmful during pregnancy and for babies and young children."))
            add(.manganese, 6, String(localized: "High manganese is a concern for infants."))
        }
        if answers.flooding == true {
            add(.bacteria, 9, String(localized: "Floodwater can carry germs into a well. Test after disinfecting."))
            add(.nitrate, 5, String(localized: "Flooding can wash nitrate into wells."))
        }
        if answers.nearbySources == true {
            add(.nitrate, 7, String(localized: "Farm fields, livestock and septic systems can raise nitrate."))
            add(.bacteria, 7, String(localized: "Septic systems and livestock can let germs reach a well."))
        }
        // SOURCE vr-062 (needs verification, see VerificationRegister.json): NC began requiring testing of newly constructed private wells in July 2008 (NC DHHS / 15A NCAC 18A).
        if answers.wellAge == .before2008 || answers.wellAge == .unknown {
            let text = String(localized: "Wells drilled before 2008 weren't required to be tested when built, so a full panel is a good start.")
            add(.lead, 5, text)
            add(.manganese, 4, text)
            add(.pH, 4, text)
        }
        if answers.lastTest == .never || answers.lastTest == .threePlusYears {
            let text = answers.lastTest == .never
                ? String(localized: "Your well has never been tested, so start with a full standard panel.")
                : String(localized: "It's been 3 or more years since your last test, so a full standard panel is due.")
            add(.lead, 4, text)
            add(.manganese, 3, text)
            add(.pH, 3, text)
        }
        if answers.noticedChanges == true {
            add(.iron, 6, String(localized: "Orange stains or a metallic taste can mean iron."))
            add(.manganese, 6, String(localized: "Black or brown stains can mean manganese."))
            add(.pH, 6, String(localized: "Blue-green stains or a sour taste can mean acidic water that corrodes pipes."))
            add(.hardness, 5, String(localized: "White scale or poor soap lather can mean hard water."))
        }

        // County data.
        var facts: [CountyFact] = []
        let isSample = countyData?.sample ?? false
        if let county, let countyData {
            let records = countyData.reportable(for: county).sorted { $0.pctAboveStandard > $1.pctAboveStandard }
            for record in records {
                guard let contaminant = record.contaminantID else { continue }
                let pct = record.pctAboveStandard.formatted(.number.precision(.fractionLength(0...1)))
                let text = String(localized: "In \(county) County, \(pct)% of tested wells were above the \(contaminant.info.name.inSentence) standard.")
                if facts.count < maxFacts { facts.append(CountyFact(contaminant: contaminant, text: text, isSample: record.sample)) }
                if record.pctAboveStandard >= countyFlagPercent, let test = RecommendedTestID.forContaminant(contaminant) {
                    add(test, 10, text)
                }
            }
        }
        // SOURCE vr-063 (needs verification, see VerificationRegister.json): PFAS from the Chemours Fayetteville Works plant has been found in private wells in the lower Cape Fear area.
        if let county, pfasCounties.contains(county) {
            add(.pfas, 10, String(localized: "\(county) County is in the lower Cape Fear area, where PFAS from industry has been found in wells. Free testing may be available."))
        }

        let order = RecommendedTestID.allCases
        let tests = order.compactMap { id -> RecommendedTest? in
            guard let list = reasons[id] else { return nil }
            var seen = Set<String>()
            let sorted = list.sorted { $0.priority > $1.priority }.map(\.text).filter { seen.insert($0).inserted }
            return RecommendedTest(id: id, reasons: sorted)
        }

        return RiskCheckResult(tests: tests, countyFacts: facts,
                               bestTimeToTest: bestTime(county: county, trends: trends),
                               isSampleData: isSample || (trends?.isSample ?? false))
    }

    /// From the seasonal model when the county has trend data; otherwise general advice.
    static func bestTime(county: String?, trends: CountyTrendData?) -> String {
        if let county, let trends {
            let fits = trends.contaminants(in: county).compactMap { id -> (ContaminantID, SeasonalForecast.Result)? in
                guard let fit = SeasonalForecast.fit(trends.series(county: county, contaminant: id)),
                      SeasonalInsight.hasStrongPattern(fit) else { return nil }
                return (id, fit)
            }
            if let (id, fit) = fits.max(by: { $0.1.amplitude / max($0.1.meanLevel, 1e-9) < $1.1.amplitude / max($1.1.meanLevel, 1e-9) }) {
                let range = SeasonalInsight.peakRange(fit)
                return String(localized: "\(id.info.name) in \(county) County wells is usually highest in \(range). Testing then shows you the high point.")
            }
        }
        return String(localized: "Any time of year works. Also test for bacteria after flooding or heavy storms.")
    }
}
