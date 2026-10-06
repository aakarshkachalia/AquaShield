//
//  MyWellView.swift
//  ClearWellNC
//

import CoreLocation
import SwiftData
import SwiftUI

/// Shows the saved My Well and links to its report. The Well Record arrives in a later milestone.
struct MyWellView: View {
    @Environment(TractStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]

    var body: some View {
        NavigationStack {
            Group {
                if let well = savedWells.first {
                    savedWell(well)
                } else {
                    ContentUnavailableView {
                        Label("No well saved yet", systemImage: "drop")
                    } description: {
                        Text("Check your area, then tap Save as My Well on the report.")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .navigationTitle("My Well")
        }
    }

    private func savedWell(_ well: SavedWell) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(well.placeName)
                        .font(.title2.bold())
                    if let county = CountyNames.name(forFIPS: String(well.fips.dropFirst(2).prefix(3))) {
                        Text("\(county) County")
                            .foregroundStyle(.secondary)
                    }
                    Text("Census tract \(well.fips)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .card()

                if let db = store.database, let tract = db.tract(fips: well.fips) {
                    NavigationLink {
                        ReportView(selection: AreaSelection(
                            tract: tract,
                            coordinate: CLLocationCoordinate2D(latitude: well.latitude, longitude: well.longitude),
                            placeName: well.placeName), meta: db.meta)
                    } label: {
                        Label("View my area's report", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    modelContext.delete(well)
                    try? modelContext.save()
                } label: {
                    Label("Remove My Well", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .readableWidth()
        }
    }
}
