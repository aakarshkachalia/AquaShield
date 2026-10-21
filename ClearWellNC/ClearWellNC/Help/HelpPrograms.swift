//
//  HelpPrograms.swift
//  ClearWellNC
//
//  Help programs (HelpPrograms.json) and the pure matching/ranking logic.
//

import Foundation

nonisolated struct HelpProgram: Codable, Sendable, Identifiable, Hashable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case testing, treatment, alternateWater, emergency

        var label: String {
            switch self {
            case .testing: String(localized: "Testing")
            case .treatment: String(localized: "Pays for treatment")
            case .alternateWater: String(localized: "Pays for testing or safe water")
            case .emergency: String(localized: "Emergency")
            }
        }

        var symbol: String {
            switch self {
            case .testing: "testtube.2"
            case .treatment: "dollarsign.circle.fill"
            case .alternateWater: "drop.circle.fill"
            case .emergency: "exclamationmark.triangle.fill"
            }
        }

        /// Programs that pay for something.
        var pays: Bool { self == .treatment || self == .alternateWater }
    }

    let id: String
    let name: String
    let agency: String
    let type: Kind
    /// County names, or ["statewide"].
    let counties: [String]
    let triggers: [String]
    let eligibilitySummary: String
    let phone: String?
    let url: String?
    let email: String?
    /// Web search to open when there's no direct contact. "{county}" is replaced with the user's county.
    let searchQuery: String?
    let relatedProgramID: String?

    var isStatewide: Bool { counties.contains("statewide") }

    func serves(_ county: String?) -> Bool {
        isStatewide || (county.map(counties.contains) ?? false)
    }

    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    var websiteURL: URL? { url.flatMap(URL.init(string:)) }
    var emailURL: URL? { email.flatMap { URL(string: "mailto:\($0)") } }

    func searchText(county: String?) -> String? {
        guard let searchQuery else { return nil }
        return searchQuery.replacingOccurrences(of: "{county}", with: county ?? String(localized: "my"))
    }

    func searchURL(county: String?) -> URL? {
        guard let text = searchText(county: county) else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        return components?.url
    }
}

nonisolated struct HelpLibrary: Codable, Sendable {
    let programs: [HelpProgram]

    static func loadBundled(from bundle: Bundle = .main) -> HelpLibrary {
        guard let url = bundle.url(forResource: "HelpPrograms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(HelpLibrary.self, from: data) else { return HelpLibrary(programs: []) }
        return library
    }

    /// Counties eligible for free PFAS sampling (from the program's own data).
    static var pfasTestingCounties: Set<String> {
        Set(loadBundled().programs.first { $0.triggers.contains("pfas") && !$0.isStatewide }?.counties ?? [])
    }

    func program(id: String) -> HelpProgram? { programs.first { $0.id == id } }
}

// MARK: - Matching

/// Everything the matcher knows about the household.
nonisolated struct HelpContext: Sendable, Equatable {
    var county: String?
    /// Contaminants at or above a health limit on the latest report.
    var exceedances: Set<ContaminantID> = []
    var eColiPositive = false
    var floodingReported = false
    var lowIncome = false
    var hasResults = false

    static let pfas: Set<ContaminantID> = [.pfoa, .pfos, .genx]
    var pfasExceeded: Bool { !exceedances.isDisjoint(with: Self.pfas) }
}

nonisolated struct HelpMatch: Sendable, Identifiable, Equatable {
    let program: HelpProgram
    /// "Why this matches you". Empty = available to everyone in the county, not specifically matched.
    let reasons: [String]
    var id: String { program.id }
    var isMatched: Bool { !reasons.isEmpty }
}

nonisolated enum HelpMatcher {
    /// Programs available in the user's county, filtered, ranked emergency → programs that pay → general testing,
    /// with specific matches ahead of general availability inside each group.
    static func matches(programs: [HelpProgram], context: HelpContext, filter: HelpFilter = .all) -> [HelpMatch] {
        programs
            .filter { $0.serves(context.county) }
            .map { HelpMatch(program: $0, reasons: reasons(for: $0, context: context)) }
            .filter { include($0, filter: filter, context: context) }
            .sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                if a.isMatched != b.isMatched { return a.isMatched }
                return a.reasons.count > b.reasons.count
            }
    }

    static func rank(_ match: HelpMatch) -> Int {
        switch match.program.type {
        case .emergency: 0
        case .treatment, .alternateWater: 1
        case .testing: 2
        }
    }

    static func reasons(for program: HelpProgram, context: HelpContext) -> [String] {
        var reasons: [String] = []
        let county = context.county
        let exceeded = context.exceedances.sorted { $0.rawValue < $1.rawValue }.map(\.info.name)
        for trigger in program.triggers {
            switch trigger {
            case "county":
                if let county, !program.isStatewide, program.counties.contains(county) {
                    reasons.append(String(localized: "You live in \(county) County, which this program serves."))
                }
            case "pfas":
                if context.pfasExceeded {
                    reasons.append(String(localized: "Your latest test found PFAS above the limit."))
                }
            case "pfasExceedance":
                if context.pfasExceeded {
                    reasons.append(String(localized: "Your latest test found PFAS above the EPA standard."))
                }
            case "healthExceedance":
                if !exceeded.isEmpty {
                    reasons.append(String(localized: "Your latest test found \(exceeded.formatted(.list(type: .and))) above a health limit."))
                } else if context.eColiPositive {
                    reasons.append(String(localized: "Your latest test found E. coli."))
                }
            case "lowIncome":
                if context.lowIncome && (!exceeded.isEmpty || context.eColiPositive) {
                    reasons.append(String(localized: "You said your household may qualify for income-based help."))
                }
            case "flooding":
                if context.floodingReported {
                    reasons.append(String(localized: "You said flooding or a hurricane affected your well."))
                }
            case "testing":
                reasons.append(context.hasResults
                               ? String(localized: "Every well should be retested regularly, and this is the place to start.")
                               : String(localized: "You haven't added test results yet, and this is the place to start."))
            case "results":
                if context.hasResults {
                    reasons.append(String(localized: "You have test results and may want help understanding them."))
                }
            default:
                break
            }
        }
        // County-only matches (e.g. PFAS sampling) still list the county even without a PFAS result.
        return reasons
    }

    static func include(_ match: HelpMatch, filter: HelpFilter, context: HelpContext) -> Bool {
        switch filter {
        case .all: true
        case .testing: match.program.type == .testing
        case .payToFix: match.program.type.pays
        case .emergency: match.program.type == .emergency || match.program.type == .alternateWater
        case .contaminant(let id):
            // From the safety override: programs that act on a health exceedance of this contaminant.
            match.program.triggers.contains("healthExceedance")
                || match.program.triggers.contains("results")
                || (HelpContext.pfas.contains(id) && (match.program.triggers.contains("pfasExceedance") || match.program.triggers.contains("pfas")))
                || match.program.id == "county-health"
        }
    }
}
