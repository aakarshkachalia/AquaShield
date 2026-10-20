//
//  ReportOCR.swift
//  ClearWellNC
//
//  On-device text recognition with Vision (VNRecognizeTextRequest, accurate mode). Nothing is uploaded.
//  Lab reports are tables, and Vision returns each cell as its own box, so boxes are regrouped into
//  rows by vertical position before parsing.
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

nonisolated enum ReportOCR {
    enum OCRError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "We couldn't read this photo. Try better lighting or enter manually.")
        }
    }

    /// A recognized piece of text and its box (Vision's normalized coordinates, origin bottom-left).
    struct TextBox: Sendable {
        let text: String
        let box: CGRect
    }

    /// Text lines, top to bottom, for every page in order.
    static func recognizeLines(in pages: [(image: CGImage, orientation: CGImagePropertyOrientation)]) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            var lines: [String] = []
            for page in pages {
                lines += try recognize(page.image, orientation: page.orientation)
            }
            guard lines.contains(where: { $0.contains(where: \.isLetter) }) else { throw OCRError.unreadable }
            return lines
        }.value
    }

    static func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Help the language model with lab vocabulary.
        request.customWords = Array(Set(ContaminantID.allCases.flatMap(\.aliases).filter { $0.count > 3 }))
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        try handler.perform([request])
        let boxes = (request.results ?? []).compactMap { observation -> TextBox? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextBox(text: text, box: observation.boundingBox)
        }
        return groupIntoLines(boxes)
    }

    /// Rebuilds table rows: boxes whose vertical centers are within half a line height share a row,
    /// then each row is read left to right. Cells are joined with two spaces so columns stay apart.
    static func groupIntoLines(_ boxes: [TextBox]) -> [String] {
        let sorted = boxes.sorted { $0.box.midY > $1.box.midY }   // top first (origin is bottom-left)
        var rows: [[TextBox]] = []
        for box in sorted {
            if let lastIndex = rows.indices.last {
                let row = rows[lastIndex]
                let rowMid = row.map(\.box.midY).reduce(0, +) / Double(row.count)
                let height = min(row.map(\.box.height).min() ?? box.box.height, box.box.height)
                if abs(box.box.midY - rowMid) < height * 0.5 {
                    rows[lastIndex].append(box)
                    continue
                }
            }
            rows.append([box])
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "  ")
        }
    }
}
