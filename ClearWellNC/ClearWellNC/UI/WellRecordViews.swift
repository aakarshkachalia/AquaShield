//
//  WellRecordViews.swift
//  ClearWellNC
//

import Charts
import SwiftData
import SwiftUI

/// The newest lab result, every value compared with its limit.
struct LatestResultCard: View {
    let result: LabResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest result")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Every value gets its meaning: chip, % of limit, limit, and a plain-English sentence.
            ForEach(Analyte.allCases) { analyte in
                if let value = result.value(for: analyte) {
                    InterpretationBlock(name: analyte.name, interpretation: analyte.interpret(value))
                    Divider()
                }
            }
            if let coliform = result.totalColiform {
                InterpretationBlock(name: ContaminantID.totalColiform.info.name,
                                    interpretation: .interpret(.totalColiform, present: coliform == .present))
                Divider()
            }
            if let eColi = result.eColi {
                InterpretationBlock(name: ContaminantID.eColi.info.name,
                                    interpretation: .interpret(.eColi, present: eColi == .present))
            }
        }
        .card()
    }

    private var subtitle: String {
        let date = result.date.formatted(date: .abbreviated, time: .omitted)
        return result.labName.isEmpty ? date : "\(date) · \(result.labName)"
    }
}

/// Trend of one analyte across all lab results, with dashed lines at its limits.
struct TrendChart: View {
    struct Point: Identifiable {
        let id: PersistentIdentifier
        let date: Date
        let value: Double
        let status: ResultStatus
    }

    let analyte: Analyte
    let results: [LabResult]

    private var points: [Point] {
        results
            .compactMap { r in
                r.value(for: analyte).map {
                    Point(id: r.persistentModelID, date: r.date, value: $0, status: analyte.evaluate($0))
                }
            }
            .sorted { $0.date < $1.date }
    }

    /// Generated "What this chart shows" text: trend direction, limit crossings, what to do.
    private var caption: String {
        ChartCaption.trend(for: analyte.contaminant, points: points.map { ($0.date, $0.value) })
    }

    var body: some View {
        let points = points
        VStack(alignment: .leading, spacing: 8) {
            Text(analyte.name)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value(analyte.name, point.value))
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value("Date", point.date), y: .value(analyte.name, point.value))
                        .foregroundStyle(point.status.isPass ? Color.accentColor : point.status.kind.color)
                        .symbol(point.status.isPass ? BasicChartSymbolShape.circle : BasicChartSymbolShape.triangle)
                        .symbolSize(90)
                        .accessibilityLabel(Text(point.date.formatted(date: .abbreviated, time: .omitted)))
                        .accessibilityValue(Text("\(analyte.format(point.value)), \(point.status.text)"))
                }
                ForEach(analyte.referenceLines) { line in
                    RuleMark(y: .value("Limit", line.value))
                        .foregroundStyle(RiskLevel.high.color.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text(line.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityHidden(true)
                }
            }
            .chartYAxisLabel(analyte.unitLabel)
            .frame(height: 190)
            .accessibilityLabel(Text("\(analyte.name) results over time"))
            // VoiceOver hears the same trend summary sighted users read below.
            .accessibilityValue(Text(caption))

            Text(analyte.limitDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            ChartCaptionView(text: caption)
        }
        .card()
    }
}

struct EColiUrgentCard: View {
    var body: some View {
        UrgentBanner {
            VStack(alignment: .leading, spacing: 10) {
                Label("E. coli was found in your latest test", systemImage: "exclamationmark.octagon.fill")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 6) {
                    bullet("Do not drink your well water.")
                    bullet("Use bottled water instead.")
                    bullet("Call your county health department.")
                    bullet("Shock-chlorinate your well, then retest.")
                }
            }
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").accessibilityHidden(true)
            Text(text)
        }
    }
}

/// Shown after the user logs a treatment system, until a newer lab result exists.
struct RetestReminderCard: View {
    let systems: [TreatmentSystem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Retest to confirm your treatment works", systemImage: "testtube.2")
                .font(.headline)
                .foregroundStyle(.tint)
            ForEach(systems) { system in
                Text("You added a \(system.displayName) on \(system.addedAt.formatted(date: .abbreviated, time: .omitted)).")
            }
            Text("Retest your water to confirm it works. Add the new result here when you get it.")
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// "What this chart shows" box placed under every chart.
struct ChartCaptionView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What this chart shows")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
