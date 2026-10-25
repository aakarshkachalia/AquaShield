//
//  DemoPersona.swift
//  AquaShield
//
//  Demo Mode personas. Each runs on its own in-memory data store, so real data is never touched.
//

import Foundation
import SwiftData

enum DemoPersona: String, CaseIterable, Identifiable, Sendable {
    /// A) Never tested, rural county → Risk Check path.
    case neverTested
    /// B) Has a clean lab report to scan → score → Report Quest.
    case cleanReport
    /// C) Arsenic above the limit → safety override → Help Finder.
    case arsenicProblem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neverTested: String(localized: "A: Never tested (rural county)")
        case .cleanReport: String(localized: "B: Clean report to scan")
        case .arsenicProblem: String(localized: "C: Arsenic above the limit")
        }
    }

    var summary: String {
        switch self {
        case .neverTested: String(localized: "No results yet. Start with the Risk Check.")
        case .cleanReport: String(localized: "Scan the bundled sample report, see the score, then play Report Quest.")
        case .arsenicProblem: String(localized: "A report with arsenic over the limit: the safety alert, then Help Finder.")
        }
    }

    /// Sample county for each persona.
    var county: String {
        switch self {
        case .neverTested: "Stokes"
        case .cleanReport: "Wake"
        case .arsenicProblem: "Union"
        }
    }

    /// A fresh in-memory store, seeded for the persona.
    @MainActor
    func makeContainer() -> ModelContainer {
        let schema = Schema([SavedWell.self, LabResult.self, TreatmentSystem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create the demo store: \(error)")
        }
        if self == .arsenicProblem {
            let date = Calendar.current.date(byAdding: .day, value: -10, to: .now) ?? .now
            let result = LabResult(date: date, labName: String(localized: "SAMPLE — Demo Lab"))
            result.arsenicPPB = 18
            result.leadPPB = 2
            result.nitrateMgL = 1.5
            result.manganesePPB = 30
            result.pH = 6.9
            result.totalColiform = .absent
            result.eColi = .absent
            container.mainContext.insert(result)
            try? container.mainContext.save()
        }
        return container
    }
}
