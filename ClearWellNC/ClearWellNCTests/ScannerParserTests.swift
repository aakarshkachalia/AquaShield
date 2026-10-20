//
//  ScannerParserTests.swift
//  ClearWellNCTests
//
//  OCR text fixtures for LabReportParser.
//

import XCTest
@testable import ClearWellNC

final class ScannerParserTests: XCTestCase {

    private func row(_ result: LabReportParser.Result, _ id: ContaminantID,
                     file: StaticString = #filePath, line: UInt = #line) throws -> LabReportParser.ParsedRow {
        try XCTUnwrap(result.rows.first { $0.contaminant == id }, "\(id) not found", file: file, line: line)
    }

    // 1. A clean report.
    func testCleanReport() throws {
        let text = """
        Sample Water Testing Laboratory
        Private Well Water Analysis
        Date Collected: 09/12/2026
        Analyte  Result  Units  MCL
        Arsenic  0.002  mg/L  0.010
        Lead  <0.001  mg/L  0.015
        Nitrate as N  1.2  mg/L  10
        Manganese  0.018  mg/L  0.05
        Iron  0.11  mg/L  0.3
        pH  7.1  s.u.  6.5-8.5
        Total Coliform  Absent  Absent
        E. coli  Absent  Absent
        """
        let result = LabReportParser.parse(text: text)
        XCTAssertEqual(result.labName, "Sample Water Testing Laboratory")
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: try XCTUnwrap(result.collectionDate))
        XCTAssertEqual([comps.year, comps.month, comps.day], [2026, 9, 12])
        XCTAssertEqual(result.recognized.count, 8)
        XCTAssertTrue(result.unrecognized.isEmpty)

        XCTAssertEqual(try row(result, .arsenic).normalizedValue ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .lead).reading, .belowDetection(limit: 0.001))
        XCTAssertEqual(try row(result, .lead).normalizedDetectionLimit ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .nitrate).normalizedValue ?? 0, 1.2, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .manganese).normalizedValue ?? 0, 18, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .iron).normalizedValue ?? 0, 110, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .pH).normalizedValue ?? 0, 7.1, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .totalColiform).reading, .absent)
        XCTAssertEqual(try row(result, .eColi).reading, .absent)
        for r in result.recognized {
            XCTAssertFalse(r.needsReview, "\(r.rawName) should not need review: \(r.notes)")
        }
    }

    // 2. OCR errors in names and numbers.
    func testOCRErrors() throws {
        let text = """
        Arsen1c  0.0O5  mg/L
        Manganse  0.2  mg/l
        Lead  0.0I2  mg/1
        """
        let result = LabReportParser.parse(text: text)
        let arsenic = try row(result, .arsenic)
        XCTAssertEqual(arsenic.normalizedValue ?? 0, 5, accuracy: 1e-9)
        XCTAssertLessThan(arsenic.confidence, 1)
        XCTAssertEqual(try row(result, .manganese).normalizedValue ?? 0, 200, accuracy: 1e-9)
        let lead = try row(result, .lead)
        XCTAssertEqual(lead.unit, .mgL)
        XCTAssertEqual(lead.normalizedValue ?? 0, 12, accuracy: 1e-9)
    }

    // 3. Mixed units, all converted to the app's units.
    func testMixedUnits() throws {
        let text = """
        Arsenic  3  ug/L
        Uranium  12  µg/L
        Nitrate-N  4.5  ppm
        Copper  400  ppb
        Radon  1500  pCi/L
        PFOA  6.2  ng/L
        Hardness  9  gpg
        Fluoride  0.0007  ppt
        """
        let result = LabReportParser.parse(text: text)
        XCTAssertEqual(try row(result, .arsenic).normalizedValue ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .uranium).normalizedValue ?? 0, 12, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .nitrate).normalizedValue ?? 0, 4.5, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .copper).normalizedValue ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .radon).normalizedValue ?? 0, 1500, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .pfoa).normalizedValue ?? 0, 6.2, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .hardness).normalizedValue ?? 0, 153.9, accuracy: 1e-6)
        XCTAssertEqual(try row(result, .fluoride).normalizedValue ?? 0, 0.0007e-6, accuracy: 1e-15)
    }

    // 4. Non-detects in every common form.
    func testNonDetects() throws {
        let text = """
        Arsenic  ND  mg/L
        Lead  < 0.001  mg/L
        Nitrite  BDL
        Uranium  Not Detected
        Manganese  <0.010  mg/L
        Copper  <0.05  mg/L
        """
        let result = LabReportParser.parse(text: text)
        XCTAssertEqual(try row(result, .arsenic).reading, .notDetected)
        XCTAssertEqual(try row(result, .lead).normalizedDetectionLimit ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .nitrite).reading, .notDetected)
        XCTAssertEqual(try row(result, .uranium).reading, .notDetected)
        XCTAssertEqual(try row(result, .manganese).normalizedDetectionLimit ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(try row(result, .copper).normalizedDetectionLimit ?? 0, 0.05, accuracy: 1e-9)
    }

    func testDetectionLimitAboveSafeLimitNeedsReview() throws {
        let result = LabReportParser.parse(text: "Lead  <0.020  mg/L")
        let lead = try row(result, .lead)
        XCTAssertEqual(lead.normalizedDetectionLimit ?? 0, 20, accuracy: 1e-9)
        XCTAssertTrue(lead.needsReview)
    }

    // 5. Positive E. coli (and a fecal coliform line we don't guess at).
    func testPositiveEColi() throws {
        let text = """
        Total Coliform  Present
        E. coli  Positive
        Fecal Coliform  Present
        """
        let result = LabReportParser.parse(text: text)
        XCTAssertEqual(try row(result, .totalColiform).reading, .present)
        XCTAssertEqual(try row(result, .eColi).reading, .present)
        XCTAssertEqual(result.unrecognized.map(\.rawName), ["Fecal Coliform"])
    }

    // 6. Contaminants ClearWell doesn't track are kept as "unrecognized", not dropped.
    func testUnrecognizedContaminantsAreKept() throws {
        let text = """
        Strontium  0.25  mg/L
        Chloride  12  mg/L
        Barium  0.04  mg/L
        Arsenic  0.001  mg/L
        """
        let result = LabReportParser.parse(text: text)
        XCTAssertEqual(Set(result.unrecognized.map(\.rawName)), ["Strontium", "Chloride", "Barium"])
        XCTAssertTrue(result.unrecognized.allSatisfy(\.needsReview))
        XCTAssertEqual(result.recognized.map(\.contaminant), [.arsenic])
    }

    // Extras: method numbers, missing units, metadata lines.
    func testMethodNumberIsNotTheResult() throws {
        let result = LabReportParser.parse(text: "Arsenic  EPA 200.8  0.004  mg/L  0.010")
        XCTAssertEqual(try row(result, .arsenic).normalizedValue ?? 0, 4, accuracy: 1e-9)
    }

    func testMissingUnitIsGuessedAndFlagged() throws {
        let result = LabReportParser.parse(text: "Arsenic  0.004")
        let arsenic = try row(result, .arsenic)
        XCTAssertEqual(arsenic.normalizedValue ?? 0, 4, accuracy: 1e-9)
        XCTAssertTrue(arsenic.needsReview)
    }

    func testMetadataIsIgnored() {
        let text = """
        Page 1 of 2
        Phone: (919) 555-0100
        Sample ID: 2026-0912-01
        Received: 09/13/2026 10:30
        """
        XCTAssertTrue(LabReportParser.parse(text: text).rows.isEmpty)
    }

    func testOCRNumberRepair() {
        XCTAssertEqual(LabReportParser.repairedNumber("0.0O5")?.0, 0.005)
        XCTAssertEqual(LabReportParser.repairedNumber("0,005")?.0, 0.005)
        XCTAssertEqual(LabReportParser.repairedNumber("1,200")?.0, 1200)
        XCTAssertNil(LabReportParser.repairedNumber("Lead"))
        XCTAssertNil(LabReportParser.repairedNumber("radon-222"))
    }
}
