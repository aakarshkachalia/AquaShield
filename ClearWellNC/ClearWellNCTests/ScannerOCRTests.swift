//
//  ScannerOCRTests.swift
//  ClearWellNCTests
//
//  End to end: OCR of the bundled SAMPLE REPORT image on device, and saving reviewed rows.
//

import SwiftData
import UIKit
import XCTest
@testable import ClearWellNC

final class ScannerOCRTests: XCTestCase {

    func testSampleReportImageIsReadOnDevice() async throws {
        let image = try XCTUnwrap(UIImage(named: "sample_lab_report", in: .main, with: nil), "sample_lab_report.png not bundled")
        let page = try XCTUnwrap(image.visionPage)
        let lines = try await ReportOCR.recognizeLines(in: [page])
        let result = LabReportParser.parse(lines: lines)

        let found = Set(result.recognized.compactMap(\.contaminant))
        for id in [ContaminantID.arsenic, .lead, .nitrate, .manganese, .iron, .pH, .totalColiform, .eColi] {
            XCTAssertTrue(found.contains(id), "OCR + parser missed \(id). Lines: \(lines)")
        }
        let arsenic = try XCTUnwrap(result.rows.first { $0.contaminant == .arsenic })
        XCTAssertEqual(arsenic.normalizedValue ?? -1, 2, accuracy: 1e-9)
        let lead = try XCTUnwrap(result.rows.first { $0.contaminant == .lead })
        XCTAssertEqual(lead.normalizedDetectionLimit ?? -1, 1, accuracy: 1e-9)
    }

    func testGroupIntoLinesRebuildsTableRows() {
        // Two table rows; each cell is its own OCR box, slightly misaligned vertically.
        let boxes = [
            ReportOCR.TextBox(text: "0.002", box: CGRect(x: 0.40, y: 0.795, width: 0.10, height: 0.03)),
            ReportOCR.TextBox(text: "Arsenic", box: CGRect(x: 0.05, y: 0.80, width: 0.20, height: 0.03)),
            ReportOCR.TextBox(text: "mg/L", box: CGRect(x: 0.60, y: 0.802, width: 0.08, height: 0.03)),
            ReportOCR.TextBox(text: "Lead", box: CGRect(x: 0.05, y: 0.75, width: 0.12, height: 0.03)),
            ReportOCR.TextBox(text: "<0.001", box: CGRect(x: 0.40, y: 0.751, width: 0.10, height: 0.03)),
        ]
        XCTAssertEqual(ReportOCR.groupIntoLines(boxes), ["Arsenic  0.002  mg/L", "Lead  <0.001"])
    }

    @MainActor
    func testSavingReviewedRowsFeedsTheScore() throws {
        let text = """
        Arsenic  0.002  mg/L
        Lead  <0.001  mg/L
        Nitrate as N  1.2  mg/L
        Manganese  0.018  mg/L
        pH  7.1  s.u.
        Total Coliform  Absent
        E. coli  Absent
        Lead2  <0.020  mg/L
        """
        let rows = LabReportParser.parse(text: text).rows.map(ReviewRow.init(parsed:))
        let result = ScanDraft.makeResult(rows: rows, date: .now, labName: "Test Lab")

        XCTAssertEqual(result.arsenicPPB ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(result.leadPPB, 0)
        XCTAssertEqual(result.nonDetects[.lead] ?? nil, 1)
        XCTAssertEqual(result.totalColiform, .absent)
        XCTAssertEqual(result.eColi, .absent)
        let score = WellHealthScore.compute([result].latestScoreInput)
        XCTAssertTrue(score.isComplete)
        XCTAssertFalse(score.healthLimitExceeded)
        XCTAssertEqual(result.displayInterpretations.first { $0.id == .lead }?.chipLabel, "Not detected")
    }

    @MainActor
    func testDetectionLimitAboveSafeLimitIsNotSavedAsSafe() {
        var row = ReviewRow(parsed: LabReportParser.parse(text: "Lead  <0.020  mg/L").rows[0])
        row.edited = true
        let result = ScanDraft.makeResult(rows: [row], date: .now, labName: "")
        XCTAssertNil(result.leadPPB, "A <20 ppb result can't confirm lead is under 15 ppb")
    }
}
