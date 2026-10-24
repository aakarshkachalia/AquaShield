//
//  SourceRef.swift
//  ClearWellNC
//
//  Where a regulatory value, certification note or fact comes from. Every such value carries one, so the
//  Data Review screen can list what still needs checking against the source.
//

import Foundation

nonisolated struct SourceRef: Codable, Sendable, Hashable {
    let sourceName: String
    let sourceURL: URL?
    /// When someone last checked the value against the source. Nil until a person verifies it.
    let lastVerified: Date?
    /// True until a person has checked the value against `sourceURL`.
    let needsVerification: Bool

    init(_ sourceName: String, url: String? = nil, lastVerified: Date? = nil, needsVerification: Bool = true) {
        self.sourceName = sourceName
        self.sourceURL = url.flatMap(URL.init(string:))
        self.lastVerified = lastVerified
        self.needsVerification = needsVerification
    }
}

/// A number with its unit and source.
nonisolated struct SourcedValue: Codable, Sendable, Hashable {
    let value: Double
    let unit: String
    let source: SourceRef
}

extension SourceRef {
    // Common sources. URLs point at the agency page that states the value; each still needs a person to
    // confirm the value and date before release.
    nonisolated static let epaNPDWR = SourceRef("EPA National Primary Drinking Water Regulations",
                                    url: "https://www.epa.gov/ground-water-and-drinking-water/national-primary-drinking-water-regulations")
    nonisolated static let epaLeadCopper = SourceRef("EPA Lead and Copper Rule",
                                         url: "https://www.epa.gov/dwreginfo/lead-and-copper-rule")
    nonisolated static let epaPFAS = SourceRef("EPA PFAS National Primary Drinking Water Regulation",
                                   url: "https://www.epa.gov/sdwa/and-polyfluoroalkyl-substances-pfas")
    nonisolated static let epaDBP = SourceRef("EPA Stage 2 Disinfectants and Disinfection Byproducts Rule",
                                  url: "https://www.epa.gov/dwreginfo/stage-1-and-stage-2-disinfectants-and-disinfection-byproducts-rules")
    nonisolated static let epaCCR = SourceRef("EPA Consumer Confidence Reports",
                                  url: "https://www.epa.gov/ccr")
    nonisolated static let nsfStandards = SourceRef("NSF drinking water treatment standards",
                                        url: "https://www.nsf.org/consumer-resources/articles/standards-water-treatment-systems")
    nonisolated static let cdcBoilWater = SourceRef("CDC: boil water advisories",
                                        url: "https://www.cdc.gov/healthywater/emergency/drinking/drinking-water-advisories/boil-water-advisory.html")
    nonisolated static let ncdhhsWells = SourceRef("NC DHHS private well program",
                                       url: "https://epi.dph.ncdhhs.gov/oee/programs/private_well.html")
}
