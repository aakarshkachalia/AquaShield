//
//  Wording.swift
//  AquaShield
//
//  Shared explanations (contaminant summaries, actions, result sentences) were written for wells. This
//  adapts them for city water, in one place, so city users never read "your well". Well and "not sure"
//  users see the original text. AppSettings keeps `Wording.source` in step with the confirmed source.
//

import Foundation
import Synchronization

nonisolated enum Wording {
    private static let current = Mutex(WaterSource.notSure)

    /// The source wording follows. Set by AppSettings whenever the confirmed source changes.
    static var source: WaterSource {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    /// Whole sentences first, then phrases, most specific first. City water only.
    static let cityReplacements: [(String, String)] = [
        ("Lead in well water usually comes from pipes, solder and well parts, not the rock.",
         "Lead in tap water usually comes from service lines, pipes, solder and faucets."),
        ("look for nearby sources like septic systems or fertilizer", "ask your utility about its nitrate results"),
        ("at typical well levels", "at typical levels"),
        ("germs can get into your well, often through a damaged cap or after flooding",
         "germs may be getting into the water system or your home's pipes"),
        ("Shock-chlorinate the well, find how germs are getting in, and retest after the chlorine is flushed out.",
         "Call your water utility, run your taps for a few minutes, and retest."),
        (", shock-chlorinate the well and retest.", ", and call your water utility."),
        ("Shock-chlorinate your well, then retest.", "Call your water utility, then retest."),
        ("not test results for your well", "not test results for your tap"),
        ("This is well below", "This is far below"),
        ("were well under", "were far under"),
        ("Many test wells for free or low cost.", "Many can help you test your tap."),
        ("is getting into your well", "is getting into your water"),
        ("into your well", "into your water"),
        ("your well water", "your tap water"),
        ("Your well water", "Your tap water"),
        ("well water", "tap water"),
        ("your well", "your water"),
        ("Your well", "Your water"),
    ]

    static func adapt(_ text: String, for source: WaterSource = Wording.source) -> String {
        guard source == .publicWater, text.contains("well") || text.contains("Well") else { return text }
        var result = text
        for (from, to) in cityReplacements where result.contains(from) {
            // Whole words only, so "your wellness" is never touched.
            let pattern = NSRegularExpression.escapedPattern(for: from) + (from.last?.isLetter == true ? "\\b" : "")
            result = result.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: to),
                                                 options: .regularExpression)
        }
        return result
    }

    static func adaptOptional(_ text: String?, for source: WaterSource = Wording.source) -> String? {
        text.map { adapt($0, for: source) }
    }
}

extension String {
    /// A name as it reads mid-sentence: "Arsenic" → "arsenic", but abbreviations and mixed case stay
    /// ("PFOS", "GenX", "pH", "E. coli").
    nonisolated var inSentence: String {
        let keep = contains(".") || dropFirst().contains(where: \.isUppercase)
        return keep ? self : lowercased()
    }
}
