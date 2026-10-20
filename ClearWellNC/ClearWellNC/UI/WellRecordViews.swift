//
//  WellRecordViews.swift
//  ClearWellNC
//

import Charts
import SwiftData
import SwiftUI

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
        VStack(alignment: .leading, spacing: Spacing.s) {
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
                                .font(.caption)
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
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure

    var body: some View {
        UrgentBanner {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("E. coli was found in your latest test", systemImage: "exclamationmark.octagon.fill")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if waterSource.showsWellCare {
                        bullet("Do not drink your well water.")
                        bullet("Use bottled water instead.")
                        bullet("Call your county health department.")
                        bullet("Shock-chlorinate your well, then retest.")
                    } else {
                        bullet("Do not drink your tap water.")
                        bullet("Use bottled water instead.")
                        bullet("Call your water utility and your county health department.")
                        bullet("Retest after the problem is fixed.")
                    }
                }
            }
        }
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
            Text("•").accessibilityHidden(true)
            Text(text)
        }
    }
}

/// Shown after the user logs a treatment system, until a newer lab result exists.
struct RetestReminderCard: View {
    let systems: [TreatmentSystem]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("What this chart shows")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
