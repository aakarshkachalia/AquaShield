//
//  ReferenceDataStore.swift
//  ClearWellNC
//
//  Bundled reference data (versioned JSON, never SwiftData): filter products and, over time, limits,
//  standards and Learn content. User data (installed filters, the user's own products) stays in
//  SwiftData / AppSettings and only refers to reference items by ID.
//

import Foundation
import Observation

/// Every bundled reference file has a version, so an app update can tell old from new data.
nonisolated struct FilterCatalog: Codable, Sendable {
    let version: Int
    let products: [FilterProduct]
}

nonisolated enum ReferenceData {
    /// Decodes `name.json` from the bundle. Nil (and a debug message) if missing or malformed.
    static func load<T: Decodable>(_ name: String, as type: T.Type, bundle: Bundle = .main) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            debugPrint("ReferenceData: \(name).json not found")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            debugPrint("ReferenceData: \(name).json: \(error)")
            return nil
        }
    }
}

@MainActor
@Observable
final class ReferenceDataStore {
    static let shared = ReferenceDataStore()

    /// Bundled sample products. Every one is labeled "Sample" and needs verification; real products are
    /// entered by the user ("Add my own filter").
    let sampleFilters: [FilterProduct]
    let filterCatalogVersion: Int

    init(bundle: Bundle = .main) {
        let catalog = ReferenceData.load("SampleFilterProducts", as: FilterCatalog.self, bundle: bundle)
        sampleFilters = catalog?.products ?? []
        filterCatalogVersion = catalog?.version ?? 0
    }

    /// All products the user can pick: their own first, then the samples.
    func filterProducts(custom: [FilterProduct]) -> [FilterProduct] {
        custom + sampleFilters
    }

    func product(id: String, custom: [FilterProduct]) -> FilterProduct? {
        guard !id.isEmpty else { return nil }
        return custom.first { $0.id == id } ?? sampleFilters.first { $0.id == id }
    }
}
