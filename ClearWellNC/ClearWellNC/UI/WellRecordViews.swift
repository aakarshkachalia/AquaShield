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
            ForEach(Analyte.allCases) { analyte in
                if let value = result.value(for: analyte) {
                    row(name: analyte.name, value: analyte.format(value), status: analyte.evaluate(value))
                }
            }
            if let coliform = result.totalColiform {
                row(name: String(localized: "Total coliform"), value: coliform.label, status: Analyte.evaluate(bacteria: coliform))
            }
            if let eColi = result.eColi {
                row(name: String(localized: "E. coli"), value: eColi.label, status: Analyte.evaluate(bacteria: eColi))
            }
        }
        .card()
    }

    private var subtitle: String {
        let date = result.date.formatted(date: .abbreviated, time: .omitted)
        return result.labName.isEmpty ? date : "\(date) · \(result.labName)"
    }

    private func row(name: String, value: String, status: ResultStatus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.body.weight(.medium))
                    Spacer()
                    Text(value).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.medium))
                    Text(value).monospacedDigit()
                }
            }
            ResultStatusLabel(status: status)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
            .chartYAxisLabel(analyte.storedUnit?.label ?? "")
            .frame(height: 190)
            .accessibilityLabel(Text("\(analyte.name) results over time"))

            Text(analyte.limitDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

struct EColiUrgentCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("E. coli was found in your latest test", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                bullet("Do not drink your well water.")
                bullet("Use bottled water instead.")
                bullet("Call your county health department.")
                bullet("Shock-chlorinate your well, then retest.")
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RiskLevel.high.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
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
