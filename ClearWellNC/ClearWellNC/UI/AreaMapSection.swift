//
//  AreaMapSection.swift
//  ClearWellNC
//

import CoreLocation
import SwiftUI

/// Contaminant picker, tract map, legend and the card for the tapped tract.
struct AreaMapSection: View {
    let database: TractDatabase
    @Binding var contaminant: Contaminant
    @Binding var selection: AreaSelection?
    let onOpenReport: (AreaSelection) -> Void

    @State private var tapError: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore the map")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Tap a census tract to see its estimate.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            contaminantPicker

            TractMapView(database: database,
                         contaminant: contaminant,
                         selectedFIPS: selection?.tract.fips,
                         onTap: select)
                .frame(height: sizeClass == .regular ? 520 : 380)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(Text("Map of estimated \(contaminant.name) risk by census tract"))
                .accessibilityHint(Text("Tap a tract to select it. You can also search by address above."))
                // Lets VoiceOver users tap tracts directly; the selected tract is then described below.
                .accessibilityAddTraits(.allowsDirectInteraction)

            MapLegend(contaminant: contaminant)

            if let tapError {
                Label {
                    Text(tapError)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(RiskLevel.elevated.color)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }

            if let selection {
                SelectedTractCard(selection: selection, contaminant: contaminant, meta: database.meta) {
                    onOpenReport(selection)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private var contaminantPicker: some View {
        let picker = Picker("Contaminant", selection: $contaminant) {
            ForEach(Contaminant.allCases) { c in
                Text(c.name).tag(c)
            }
        }
        // Four segments don't fit at accessibility text sizes; fall back to a menu.
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
                .frame(minHeight: 44)
        } else {
            picker.pickerStyle(.segmented)
                .frame(minHeight: 44)
        }
    }

    private func select(_ coordinate: CLLocationCoordinate2D) {
        do {
            selection = try AreaLookup.selection(at: coordinate,
                                                 placeName: String(localized: "Point selected on the map"),
                                                 in: database)
            tapError = nil
        } catch {
            selection = nil
            tapError = (error as? AreaLookupError)?.errorDescription
        }
    }
}

struct MapLegend: View {
    let contaminant: Contaminant

    private let levels: [RiskLevel] = [.lowerThanTypical, .typical, .elevated, .high]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(levels, id: \.self) { level in
                    HStack(spacing: 8) {
                        swatch(level.color.opacity(0.75))
                        Text(level.label)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            HStack(spacing: 8) {
                swatch(RiskLevel.elevated.color.opacity(0.35))
                Text("Faded: no wells tested in that tract (model estimate only)")
            }
            .accessibilityElement(children: .combine)
            if contaminant == .lead {
                Text("Lead depends on household plumbing, not location, so every home should test for it.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.25)))
            .frame(width: 22, height: 14)
            .accessibilityHidden(true)
    }
}

struct SelectedTractCard: View {
    let selection: AreaSelection
    let contaminant: Contaminant
    let meta: Meta
    let onOpenReport: () -> Void

    var body: some View {
        let report = RiskEngine.report(for: selection.tract, meta: meta)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.countyName.map { String(localized: "\($0) County") } ?? String(localized: "North Carolina"))
                    .font(.title3.bold())
                Text("Census tract \(report.fips)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let risk = report.risk(for: contaminant) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(contaminant.name).font(.headline)
                        Spacer()
                        RiskBadge(level: risk.level)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(contaminant.name).font(.headline)
                        RiskBadge(level: risk.level)
                    }
                }
                Text(risk.estimateSentence)
                    .font(.subheadline)
                if let observed = risk.observedText {
                    Text(observed)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                // Spells out what the map's faded fill means, so it isn't conveyed by opacity alone.
                Text("\(risk.confidence.level.phrase). \(risk.confidence.note)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: onOpenReport) {
                Text("View full report")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
