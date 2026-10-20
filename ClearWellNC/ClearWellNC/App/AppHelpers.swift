//
//  AppHelpers.swift
//  ClearWellNC
//

import Foundation

/// County of the saved home, if one is saved and the tract data has loaded.
@MainActor
func savedWellCounty(_ wells: [SavedWell], store: TractStore) -> String? {
    wells.first.flatMap { store.database?.tract(fips: $0.fips)?.countyName }
}

extension QuestReport {
    /// The same report, flagged as sample data (Demo Mode), so Report Quest never saves its progress.
    func markingSample(_ sample: Bool) -> QuestReport {
        var copy = self
        copy.isSample = copy.isSample || sample
        return copy
    }
}

extension LabResult {
    /// Readings at or above a health limit, including bacteria.
    var healthFindings: [Interpretation] {
        QuestEngine.safetyFindings(for: QuestReport(result: self))
    }
}
