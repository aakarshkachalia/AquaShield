//
//  HowItWorksView.swift
//  ClearWellNC
//
//  Copy matches the web app's "How it works" section.
//

import SwiftUI

struct HowItWorksView: View {
    @Environment(TractStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                explainers
                if let meta = store.database?.meta {
                    accuracySection(meta)
                } else {
                    ProgressView("Loading well data…")
                        .frame(maxWidth: .infinity)
                        .card()
                }
                figures
                auditNote
                if let meta = store.database?.meta {
                    Text("Data: \(meta.dataSource). Tract estimates generated \(meta.generated).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text(RiskReport.disclaimer)
                    .font(.footnote.weight(.semibold))
            }
            .padding()
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("How It Works")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Explainer cards

    private var explainers: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExplainerCard(number: 1, title: "Real test results", symbol: "testtube.2",
                          text: "The NC State Laboratory of Public Health tested private wells from 1998 to 2019. UNC researchers geocoded 117,960 of those tests (the NCWELL database). ClearWell uses the census-tract summaries.")
            ExplainerCard(number: 2, title: "The rock beneath you", symbol: "mountain.2",
                          text: "Arsenic follows geology. Tracts on the Carolina Slate Belt's metasedimentary rock have about 12% of wells over the arsenic limit, roughly 5 times the state average.")
            ExplainerCard(number: 3, title: "A model that fills the gaps", symbol: "square.grid.3x3.middle.filled",
                          text: "A gradient-boosted model learns from rock types, location and nearby test results, then estimates every tract in the state, including tracts with few or no tests.")
            ExplainerCard(number: 4, title: "Honest confidence", symbol: "gauge.with.dots.needle.50percent",
                          text: "Where many wells were tested, your estimate leans on those tests. Where few were, it leans on the model, and the report tells you so.")
        }
    }

    // MARK: Scores

    private func accuracySection(_ meta: Meta) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How accurate is it?")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Tested on census tracts the model never saw. The score is how much of the gap between a statewide guess (0%) and the best possible area-level estimate (100%) each method closes.")
            ScoresTable(scores: meta.modelScores)
        }
        .card()
    }

    // MARK: Figures

    private var figures: some View {
        VStack(alignment: .leading, spacing: 16) {
            FigureView(imageName: "arsenic_map",
                       altText: "Map of North Carolina showing the share of tested wells above the arsenic limit by census tract, with a hotspot east of Charlotte",
                       caption: "Arsenic test results by census tract. The dark band follows the Carolina Slate Belt.")
            FigureView(imageName: "calibration",
                       altText: "Calibration charts: predicted versus actual share of wells above the limit, for four contaminants",
                       caption: "Calibration: when the model says 10%, about 10% of wells are actually above the limit.")
            FigureView(imageName: "importance",
                       altText: "Bar charts of which feature groups drive each contaminant's prediction",
                       caption: "What drives each prediction.")
        }
    }

    private var auditNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data we checked and excluded")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("While auditing the public data, we found three columns where the lab's reporting limit is above the state standard (silver, cadmium and chromium), which makes almost every test look contaminated. We excluded them. The tract file's manganese health-limit column also duplicates the 50 ppb column, so ClearWell uses the 50 ppb NC standard.")
        }
        .card()
    }
}

private struct ExplainerCard: View {
    let number: Int
    let title: LocalizedStringKey
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(number). \(Text(title))")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Grid table on wide screens; one block per contaminant on iPhone or at large text sizes.
private struct ScoresTable: View {
    let scores: [ModelScore]

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let columns: [LocalizedStringKey] = [
        "County average", "Nearby tracts only", "ClearWell model", "Stress test: unseen county",
    ]

    var body: some View {
        if sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            grid
        } else {
            stacked
        }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                Text("Contaminant")
                ForEach(columns.indices, id: \.self) { Text(columns[$0]) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach(scores) { score in
                GridRow {
                    Text(score.contaminant.name).font(.body.weight(.medium))
                    cell(score.countyAverage, best: isBest(score.countyAverage, in: score))
                    cell(score.neighborsOnly, best: isBest(score.neighborsOnly, in: score))
                    cell(score.model, best: isBest(score.model, in: score))
                    Text(score.stressTestText)
                        .monospacedDigit()
                        .accessibilityLabel(Text(score.stressTestAccessibilityText))
                }
            }
            bestNote.gridCellColumns(5)
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(scores) { score in
                VStack(alignment: .leading, spacing: 6) {
                    Text(score.contaminant.name)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    row(columns[0], value: ModelScore.percent(score.countyAverage), best: isBest(score.countyAverage, in: score))
                    row(columns[1], value: ModelScore.percent(score.neighborsOnly), best: isBest(score.neighborsOnly, in: score))
                    row(columns[2], value: ModelScore.percent(score.model), best: isBest(score.model, in: score))
                    row(columns[3], value: score.stressTestText, best: false,
                        spoken: score.stressTestAccessibilityText)
                }
            }
            bestNote
        }
    }

    private var bestNote: some View {
        Text("Bold with a star: best of the first three methods.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// Best among the three methods compared on unseen tracts (the stress test is reported separately).
    private func isBest(_ value: Double, in score: ModelScore) -> Bool {
        value == max(score.countyAverage, score.neighborsOnly, score.model)
    }

    private func cell(_ value: Double, best: Bool) -> some View {
        Text(best ? "\(ModelScore.percent(value)) ★" : ModelScore.percent(value))
            .fontWeight(best ? .bold : .regular)
            .monospacedDigit()
            .accessibilityLabel(best ? Text("\(ModelScore.percent(value)), best") : Text(ModelScore.percent(value)))
    }

    private func row(_ label: LocalizedStringKey, value: String, best: Bool, spoken: String? = nil) -> some View {
        let valueText = Text(best ? "\(value) ★" : value)
            .fontWeight(best ? .bold : .regular)
            .monospacedDigit()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                valueText
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(.secondary)
                valueText
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(best ? Text("\(spoken ?? value), best") : Text(spoken ?? value))
    }
}

private struct FigureView: View {
    let imageName: String
    let altText: LocalizedStringKey
    let caption: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The PNGs ship as loose bundle files, not asset-catalog images.
            if let image = UIImage(named: imageName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(Text(altText))
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}
