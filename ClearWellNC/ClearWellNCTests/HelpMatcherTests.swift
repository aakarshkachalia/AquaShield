//
//  HelpMatcherTests.swift
//  ClearWellNCTests
//

import XCTest
@testable import ClearWellNC

final class HelpMatcherTests: XCTestCase {

    private var programs: [HelpProgram] { HelpLibrary.loadBundled(from: .main).programs }

    private func ids(_ context: HelpContext, _ filter: HelpFilter = .all) -> [String] {
        HelpMatcher.matches(programs: programs, context: context, filter: filter).map(\.program.id)
    }

    func testSeedsExactlySixPrograms() {
        XCTAssertEqual(Set(programs.map(\.id)), ["chemours-pfas-sampling", "ncdeq-pfas-treatment", "bernard-allen-fund",
                                                 "county-health", "ncdhhs-oeeb", "post-flood-kits"])
        let oeeb = programs.first { $0.id == "ncdhhs-oeeb" }
        XCTAssertEqual(oeeb?.phone, "919-707-5900")
        XCTAssertEqual(oeeb?.email, "oeeb@dhhs.nc.gov")
        XCTAssertEqual(programs.first { $0.id == "chemours-pfas-sampling" }?.phone, "(910) 678-1100")
    }

    func testChemoursOnlyInLowerCapeFearCounties() {
        XCTAssertTrue(ids(HelpContext(county: "Bladen")).contains("chemours-pfas-sampling"))
        XCTAssertFalse(ids(HelpContext(county: "Wake")).contains("chemours-pfas-sampling"))
        XCTAssertFalse(ids(HelpContext(county: nil)).contains("chemours-pfas-sampling"))
    }

    func testRankingEmergencyThenPayThenTesting() {
        let context = HelpContext(county: "Union", exceedances: [.arsenic], floodingReported: true, hasResults: true)
        let matches = HelpMatcher.matches(programs: programs, context: context)
        let ranks = matches.map(HelpMatcher.rank)
        XCTAssertEqual(ranks, ranks.sorted(), "Emergency → programs that pay → testing")
        XCTAssertEqual(matches.first?.program.id, "post-flood-kits")
    }

    func testArsenicExceedanceMatchesBernardAllenWithReason() throws {
        let context = HelpContext(county: "Union", exceedances: [.arsenic], hasResults: true)
        let match = try XCTUnwrap(HelpMatcher.matches(programs: programs, context: context).first { $0.id == "bernard-allen-fund" })
        XCTAssertTrue(match.isMatched)
        XCTAssertTrue(match.reasons.contains { $0.contains("Arsenic") })
    }

    func testPFASExceedanceMatchesTreatmentProgram() throws {
        let context = HelpContext(county: "Pender", exceedances: [.pfoa], hasResults: true)
        let treatment = try XCTUnwrap(HelpMatcher.matches(programs: programs, context: context).first { $0.id == "ncdeq-pfas-treatment" })
        XCTAssertTrue(treatment.isMatched)
        XCTAssertTrue(ids(context, .contaminant(.pfoa)).contains("ncdeq-pfas-treatment"))
    }

    func testFiltersNarrowTheList() {
        let context = HelpContext(county: "Union", exceedances: [.arsenic], hasResults: true)
        XCTAssertTrue(HelpMatcher.matches(programs: programs, context: context, filter: .testing)
            .allSatisfy { $0.program.type == .testing })
        XCTAssertTrue(HelpMatcher.matches(programs: programs, context: context, filter: .payToFix)
            .allSatisfy { $0.program.type.pays })
        let arsenic = ids(context, .contaminant(.arsenic))
        XCTAssertTrue(arsenic.contains("bernard-allen-fund"))
        XCTAssertFalse(arsenic.contains("ncdeq-pfas-treatment"), "PFAS treatment isn't relevant to arsenic")
    }

    func testFloodingMatchesKitsLinkedToCountyHealth() throws {
        let kits = try XCTUnwrap(HelpMatcher.matches(programs: programs, context: HelpContext(county: "Dare", floodingReported: true))
            .first { $0.id == "post-flood-kits" })
        XCTAssertTrue(kits.isMatched)
        XCTAssertEqual(kits.program.relatedProgramID, "county-health")
    }

    func testContactButtonsOnlyWhenDetailsExist() throws {
        let county = try XCTUnwrap(programs.first { $0.id == "county-health" })
        XCTAssertNil(county.phoneURL)
        XCTAssertEqual(county.searchText(county: "Wake"), "Wake County health department well testing")
        let oeeb = try XCTUnwrap(programs.first { $0.id == "ncdhhs-oeeb" })
        XCTAssertEqual(oeeb.phoneURL?.absoluteString, "tel:9197075900")
        XCTAssertEqual(oeeb.emailURL?.absoluteString, "mailto:oeeb@dhhs.nc.gov")
        XCTAssertNil(oeeb.websiteURL)
    }
}
