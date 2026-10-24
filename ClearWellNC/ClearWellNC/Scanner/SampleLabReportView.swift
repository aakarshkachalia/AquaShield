//
//  SampleLabReportView.swift
//  ClearWellNC
//
//  A made-up, clearly labeled "SAMPLE REPORT" lab report, drawn in SwiftUI. The app renders it to an
//  image for the scanner demo; the same view was rendered once to sample_lab_report.png (bundled).
//  Uses only cross-platform SwiftUI so it can also be rendered on a Mac.
//

import SwiftUI

struct SampleLabReportView: View {
    struct Row {
        let analyte: String
        let result: String
        let units: String
        let mcl: String
    }

    /// A clean report: everything under its limit, lead below detection.
    static let rows: [Row] = [
        Row(analyte: "Arsenic", result: "0.002", units: "mg/L", mcl: "0.010"),
        Row(analyte: "Lead", result: "<0.001", units: "mg/L", mcl: "0.015"),
        Row(analyte: "Nitrate as N", result: "1.2", units: "mg/L", mcl: "10"),
        Row(analyte: "Manganese", result: "0.018", units: "mg/L", mcl: "0.05"),
        Row(analyte: "Iron", result: "0.11", units: "mg/L", mcl: "0.3"),
        Row(analyte: "Copper", result: "0.05", units: "mg/L", mcl: "1.3"),
        Row(analyte: "pH", result: "7.1", units: "s.u.", mcl: "6.5-8.5"),
        Row(analyte: "Total Coliform", result: "Absent", units: "", mcl: "Absent"),
        Row(analyte: "E. coli", result: "Absent", units: "", mcl: "Absent"),
    ]

    static let collectionDate = "09/12/2026"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("SAMPLE REPORT - NOT A REAL TEST RESULT")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color(red: 0.70, green: 0.09, blue: 0.12))
            Text("Sample Water Testing Laboratory")
                .font(.system(size: 34, weight: .bold))
            Text("Private Well Water Analysis")
                .font(.system(size: 26))
            Text("Date Collected: \(Self.collectionDate)")
                .font(.system(size: 26))
            Rectangle().frame(height: 2)
            row(Row(analyte: "Analyte", result: "Result", units: "Units", mcl: "MCL"), bold: true)
            Rectangle().frame(height: 1)
            ForEach(Self.rows, id: \.analyte) { r in
                row(r, bold: false)
            }
            Rectangle().frame(height: 2)
            Text("This sample was made for the \(AppName.display) app demo. It is not a real lab result.")
                .font(.system(size: 22))
                .foregroundStyle(Color(white: 0.3))
        }
        .padding(48)
        .frame(width: 1000, alignment: .leading)
        .foregroundStyle(.black)
        .background(.white)
    }

    private func row(_ r: Row, bold: Bool) -> some View {
        HStack(spacing: 0) {
            Text(r.analyte).frame(width: 380, alignment: .leading)
            Text(r.result).frame(width: 200, alignment: .leading)
            Text(r.units).frame(width: 160, alignment: .leading)
            Text(r.mcl).frame(width: 160, alignment: .leading)
        }
        .font(.system(size: 30, weight: bold ? .bold : .regular, design: .monospaced))
    }
}

#if canImport(UIKit)
import UIKit

enum SampleLabReport {
    /// Renders the sample report to an image (for the scanner demo and "Save to Photos").
    @MainActor
    static func render() -> UIImage? {
        if let bundled = UIImage(named: "sample_lab_report") { return bundled }
        let renderer = ImageRenderer(content: SampleLabReportView())
        renderer.scale = 2
        return renderer.uiImage
    }
}
#endif
