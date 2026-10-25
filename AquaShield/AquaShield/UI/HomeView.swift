//
//  HomeView.swift
//  AquaShield
//
//  Shared lab-result helpers. The Home tab itself is DashboardView.
//  (Formerly the dashboard. Shows ONE of three states, most important first:
//    a) no results yet → "Should I test my well?" + scan;
//    b) results, no health problems → score ring, summary, next retest, seasonal tip;
//    c) a health limit exceeded → red status card, what to do now, help paying for a fix.
//

import SwiftData
import SwiftUI

extension LabResult {
    /// Values at or above a health limit, counting bacteria.
    var aboveLimitCount: Int {
        var count = Analyte.allCases.filter { a in
            value(for: a).map { a.evaluate($0).kind == .above } ?? false
        }.count
        if totalColiform == .present { count += 1 }
        if eColi == .present { count += 1 }
        return count
    }
}
