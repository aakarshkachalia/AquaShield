//
//  WordingTests.swift
//  AquaShieldTests
//
//  City users never read "your well"; well users see the original text.
//

import XCTest
@testable import AquaShield

final class WordingTests: XCTestCase {
    override func tearDown() {
        Wording.source = .notSure
    }

    private let wellWord = try! NSRegularExpression(pattern: "\\bwells?\\b", options: .caseInsensitive)

    private func hasWellWord(_ text: String) -> Bool {
        let cleaned = text.replacingOccurrences(of: "as well", with: "")
        return wellWord.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) != nil
    }

    func testCityWordingForEveryContaminant() {
        Wording.source = .publicWater
        for id in ContaminantID.allCases {
            let info = ContaminantInfo.info(for: id)
            for text in [info.plainSummary, info.actionIfAbove, info.actionIfWatch,
                         info.practicalImpact ?? "", info.seasonalContext ?? ""] {
                XCTAssertFalse(hasWellWord(text), "\(id): \(text)")
            }
            let interpretation = id == .totalColiform || id == .eColi
                ? Interpretation.interpret(id, present: true) : Interpretation.interpret(id, value: 1)
            XCTAssertFalse(hasWellWord(interpretation.sentence), "\(id): \(interpretation.sentence)")
        }
    }

    func testWellUsersKeepOriginalWording() {
        Wording.source = .privateWell
        XCTAssertTrue(hasWellWord(ContaminantInfo.info(for: .eColi).plainSummary))
        Wording.source = .notSure
        XCTAssertEqual(ContaminantInfo.info(for: .lead).plainSummary, ContaminantInfo.compiledInfo(for: .lead).plainSummary)
    }

    func testWholeWordsOnly() {
        XCTAssertEqual(Wording.adapt("Check your wellness.", for: .publicWater), "Check your wellness.")
        XCTAssertEqual(Wording.adapt("Test your well water.", for: .publicWater), "Test your tap water.")
        XCTAssertEqual(Wording.adapt("Test your well water.", for: .privateWell), "Test your well water.")
    }
}

final class InSentenceTests: XCTestCase {
    func testAbbreviationsKeepCapitals() {
        XCTAssertEqual("Arsenic".inSentence, "arsenic")
        XCTAssertEqual("Total coliform".inSentence, "total coliform")
        XCTAssertEqual("PFOS".inSentence, "PFOS")
        XCTAssertEqual("GenX".inSentence, "GenX")
        XCTAssertEqual("pH".inSentence, "pH")
        XCTAssertEqual("E. coli".inSentence, "E. coli")
    }
}
