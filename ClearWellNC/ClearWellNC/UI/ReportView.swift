//
//  ReportView.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

struct ReportView: View {
    let selection: AreaSelection
    let meta: Meta

    @AppStorage(StorageKey.infantInHome) private var infantInHome = false
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure
    @Environment(\.modelContext) private var modelContext
    @Query private var savedWells: [SavedWell]

    private var report: RiskReport { RiskEngine.report(for: selection.tract, meta: meta) }

    private var isSaved: Bool {
        savedWells.contains {
            $0.fips == selection.tract.fips
                && $0.latitude == selection.coordinate.latitude
                && $0.longitude == selection.coordinate.longitude
        }
    }

    var body: some View {
        let report = report
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(report)
                if !waterSource.showsWellCare {
                    cityWaterNote
                }
                disclaimer
                if infantInHome, let nitrate = report.risk(for: .nitrate), nitrate.level.isTypicalOrHigher {
                    InfantNitrateNote()
                }
                ForEach(report.risks) { risk in
                    ContaminantCard(risk: risk)
                }
                TestPlanCard(plan: report.testPlan)
                saveSection
                Text("Data: \(meta.dataSource)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Your area's report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ report: RiskReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.countyName.map { String(localized: "\($0) County") } ?? String(localized: "North Carolina"))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Census tract \(report.fips)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(selection.placeName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var disclaimer: some View {
        Label {
            Text(RiskReport.disclaimer)
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
        }
        .font(.callout.weight(.medium))
        .card()
        .accessibilityElement(children: .combine)
    }

    private var cityWaterNote: some View {
        Label {
            Text("These estimates come from private well tests. If your home uses city or county water, they don't describe your tap water. Your utility's yearly water quality report does.")
        } icon: {
            Image(systemName: "building.2.fill").foregroundStyle(Color.statusWatch)
        }
        .font(.callout.weight(.medium))
        .card()
        .accessibilityElement(children: .combine)
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: save) {
                Label(isSaved ? waterSource.savedLocationTitle : waterSource.saveLocationTitle,
                      systemImage: isSaved ? "checkmark.circle.fill" : "house.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaved)
            Text("Saving keeps this location on this device only. Saving again replaces your saved home.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// There is one My Well; saving replaces any previous one.
    private func save() {
        for well in savedWells { modelContext.delete(well) }
        modelContext.insert(SavedWell(fips: selection.tract.fips,
                                      latitude: selection.coordinate.latitude,
                                      longitude: selection.coordinate.longitude,
                                      placeName: selection.placeName))
        try? modelContext.save()
    }
}

// MARK: - Cards

struct ContaminantCard: View {
    let risk: ContaminantRisk
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer()
                    RiskBadge(level: risk.level)
                }
                VStack(alignment: .leading, spacing: 6) {
                    title
                    RiskBadge(level: risk.level)
                }
            }

            Text(risk.estimateSentence)

            RiskComparisonBar(risk: risk)
            ChartCaptionView(text: ChartCaption.areaComparison(risk))

            if let observed = risk.observedText {
                Text(observed)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("\(risk.confidence.level.phrase). \(risk.confidence.note)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(risk.contaminant.whyItMatters)
                    Text("If your test is high")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    Text(risk.contaminant.ifHigh)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Why it matters and what to do")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        }
        .card()
    }

    private var title: some View {
        Text(risk.contaminant.name)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }
}

/// Horizontal bar for this area's estimated share, with a marker line at the statewide rate.
struct RiskComparisonBar: View {
    let risk: ContaminantRisk

    /// Leave headroom past the larger value so the marker never sits on the edge.
    private var scaleMax: Double {
        let top = max(risk.estimate, risk.statewide) * 1.25
        return top > 0 ? min(1, top) : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 14)
                    Capsule()
                        .fill(risk.level.color)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                        .frame(width: max(6, width * risk.estimate / scaleMax), height: 14)
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 24)
                        .offset(x: width * risk.statewide / scaleMax - 1)
                }
                .frame(height: 24)
            }
            .frame(height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Capsule().fill(risk.level.color)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.2)))
                        .frame(width: 16, height: 8)
                    Text("Your area: \(risk.oneInText)")
                }
                HStack(spacing: 6) {
                    Rectangle().fill(Color.primary).frame(width: 2, height: 14)
                        .frame(width: 16)
                    Text("Statewide: \(risk.statewideOneInText)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Comparison with the statewide rate"))
        .accessibilityValue(Text("Your area: \(risk.oneInText) wells. Statewide: \(risk.statewideOneInText) wells."))
    }
}

struct InfantNitrateNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("A baby under 6 months lives here", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            Text("Nitrate is most dangerous for babies under 6 months. Test your well for nitrate before using it to mix infant formula, and use bottled water for formula until you know your result. Never boil water to remove nitrate; boiling concentrates it.")
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RiskLevel.high.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct TestPlanCard: View {
    let plan: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your test plan")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(plan.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1).")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(step)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}
