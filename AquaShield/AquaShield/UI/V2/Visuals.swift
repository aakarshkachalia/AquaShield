//
//  Visuals.swift
//  AquaShield
//
//  Show, don't tell: small charts and gauges used across the app. Each one has a VoiceOver summary, uses
//  icon + word + color for status, and respects Dynamic Type, Dark Mode and Reduce Motion.
//

import Charts
import SwiftUI

// MARK: - Tap rings

/// Drinking vs shower vs whole house, side by side.
struct TapRingsRow: View {
    let results: [TapScoreResult]

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            ForEach(results.prefix(3), id: \.tap) { result in
                VStack(spacing: DS.Space.xs) {
                    DS.ScoreRing(score: result.score, level: result.dsLevel, title: result.tap.name, scale: 0.42)
                    Label(result.tap.isDrinking ? String(localized: "Drinking") : result.tap.name,
                          systemImage: result.tap.kind == .shower ? "shower.fill" : "drop.fill")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Confidence

/// One segment per recommended test: filled = done, outlined = missing.
struct ConfidenceBar: View {
    let recommended: [ClaimTarget]
    let missing: [ClaimTarget]

    private var done: Int { recommended.count - missing.count }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: 3) {
                ForEach(recommended, id: \.self) { target in
                    let isMissing = missing.contains(target)
                    Capsule()
                        .fill(isMissing ? Color.clear : DS.Colors.accent)
                        .overlay(Capsule().strokeBorder(isMissing ? DS.Colors.textSecondary.opacity(0.5) : .clear,
                                                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])))
                        .frame(height: 8)
                }
            }
            Text("\(done) of \(recommended.count) key tests done")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(done) of \(recommended.count) key tests done"))
        .accessibilityValue(missing.isEmpty ? Text("") : Text("Missing \(missing.map(\.name).formatted(.list(type: .and)))"))
    }
}

// MARK: - What drives the score

/// Top 3 contaminants by points taken off the score.
struct DriversChart: View {
    struct Driver: Identifiable {
        let name: String
        let points: Double
        let level: DS.Level?
        var id: String { name }
    }

    let drivers: [Driver]

    init(drivers: [Driver]) {
        self.drivers = Array(drivers.filter { $0.points > 0.5 }.sorted { $0.points > $1.points }.prefix(3))
    }

    var body: some View {
        if drivers.isEmpty {
            EmptyView()
        } else {
            Chart(drivers) { driver in
                BarMark(x: .value(String(localized: "Points off"), driver.points),
                        y: .value(String(localized: "Contaminant"), driver.name))
                    .foregroundStyle(driver.level?.color ?? DS.Colors.accent)
                    .annotation(position: .trailing) {
                        Text("−\(Int(driver.points.rounded()))")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.textPrimary)
                    }
                    .cornerRadius(4)
            }
            .chartXAxisLabel(String(localized: "Points off the score"))
            .chartXScale(domain: 0...max(30, (drivers.first?.points ?? 0) + 4))
            .frame(height: CGFloat(drivers.count) * 44 + 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("What lowers the score"))
            .accessibilityValue(Text(drivers.map { "\($0.name): \(Int($0.points.rounded())) points" }
                .joined(separator: ", ")))
        }
    }
}

extension DriversChart {
    init(items: [TapItem]) {
        self.init(drivers: items.map { Driver(name: $0.target.name, points: $0.penalty, level: $0.level.dsLevel) })
    }

    init(factors: [WellHealthScore.Factor]) {
        self.init(drivers: factors.map {
            Driver(name: $0.id.info.name, points: $0.penalty, level: DS.Level($0.interpretation.tier))
        })
    }
}

// MARK: - Filter effect

/// "From tap" vs "After filter" for one contaminant, with the limit as a dashed line.
struct FilterEffectChart: View {
    let item: TapItem

    var body: some View {
        if let influent = item.influent, let residual = item.residual, influent > 0 {
            let unit = ReadingUnit.canonical(for: item.target).label
            let rows = [(String(localized: "From tap"), influent), (String(localized: "After filter"), residual)]
            Chart {
                ForEach(rows, id: \.0) { label, value in
                    BarMark(x: .value(unit, value), y: .value("", label))
                        .foregroundStyle(label == rows[0].0 ? DS.Colors.textSecondary.opacity(0.5) : DS.Colors.accent)
                        .annotation(position: .trailing) {
                            Text("\(formatNumber(value)) \(unit)").font(DS.Typography.caption)
                        }
                        .cornerRadius(4)
                }
                if let limit = item.limit, limit.value > 0 {
                    RuleMark(x: .value(String(localized: "Limit"), limit.value))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("Limit").font(DS.Typography.caption)
                        }
                }
            }
            .chartXAxisLabel(unit)
            .frame(height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(item.target.name) filter effect"))
            .accessibilityValue(Text("From tap \(formatNumber(influent)) \(unit), after filter \(formatNumber(residual)) \(unit)"))
        }
    }
}

// MARK: - Filter life

/// Circular progress: how much of the filter's life is left, with days in the middle.
struct FilterLifeRing: View {
    let daysLeft: Int?
    let totalDays: Int?
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 58
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var fraction: Double {
        guard let daysLeft, let totalDays, totalDays > 0 else { return 0 }
        return min(max(Double(daysLeft) / Double(totalDays), 0), 1)
    }
    private var level: DS.Level {
        guard let daysLeft else { return .fair }
        return daysLeft <= 0 ? .unsafe : (daysLeft <= 14 ? .fair : .good)
    }

    var body: some View {
        ZStack {
            Circle().stroke(DS.Colors.track, lineWidth: 6)
            Circle().trim(from: 0, to: shown)
                .stroke(level.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(daysLeft.map { "\(max($0, 0))" } ?? "—")
                    .font(DS.Typography.headline.monospacedDigit())
                Text("days").font(.caption2).foregroundStyle(DS.Colors.textSecondary)
            }
            .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { shown = fraction } else { withAnimation(DS.Motion.reveal) { shown = fraction } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Filter life"))
        .accessibilityValue(daysLeft.map { $0 <= 0 ? Text("Replace now") : Text("\($0) days left, \(level.label)") }
                            ?? Text("No date"))
    }
}

// MARK: - Coverage grid

/// Products (columns) × contaminants (rows): a check seal where a certified claim covers it.
struct CoverageGrid: View {
    let products: [FilterProduct]
    let targets: [ClaimTarget]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.s) {
            GridRow {
                Text("")
                ForEach(products, id: \.id) { product in
                    Text(product.model).font(DS.Typography.caption).lineLimit(2).minimumScaleFactor(0.7)
                }
            }
            Divider()
            ForEach(targets, id: \.self) { target in
                GridRow {
                    Text(target.name).font(DS.Typography.subheadline)
                    ForEach(products, id: \.id) { product in
                        let covered = product.claims.contains { $0.target == target && $0.standard.allowedTargets.contains(target) }
                        Image(systemName: covered ? "checkmark.seal.fill" : "minus")
                            .foregroundStyle(covered ? DS.Colors.good : DS.Colors.textSecondary)
                            .accessibilityLabel(Text(covered ? "\(product.model) covers \(target.name)"
                                                             : "\(product.model) does not cover \(target.name)"))
                    }
                }
            }
        }
        .foregroundStyle(DS.Colors.textPrimary)
    }
}

// MARK: - Test timeline

/// The next 12 months as a strip, with a dot for each test due. Overdue tests sit at "Now".
struct TestTimeline: View {
    let dues: [TestDue]
    let now: Date

    private func position(_ date: Date) -> Double {
        min(max(date.timeIntervalSince(now) / (365 * 86_400), 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Colors.track).frame(height: 6)
                    ForEach(dues) { due in
                        let overdue = due.isOverdue(at: now)
                        Image(systemName: overdue ? "exclamationmark.circle.fill" : "circle.fill")
                            .font(.caption)
                            .foregroundStyle(overdue ? DS.Colors.fair : DS.Colors.accent)
                            .background(Circle().fill(DS.Colors.surface))
                            .offset(x: geo.size.width * position(due.due) - 7)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
            HStack {
                Text("Now")
                Spacer()
                Text("6 months")
                Spacer()
                Text("1 year")
            }
            .font(.caption2)
            .foregroundStyle(DS.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Upcoming tests"))
        .accessibilityValue(Text(dues.map { due in
            due.isOverdue(at: now) ? "\(due.title): due now" : "\(due.title): \(due.due.formatted(date: .abbreviated, time: .omitted))"
        }.joined(separator: ", ")))
    }
}

// MARK: - Household avatars

/// Initials in a circle, with a status badge: a flag icon if anything needs checking.
struct MemberAvatar: View {
    let member: HouseholdMember
    let flagged: Bool
    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = 44

    private var initials: String {
        let words = member.displayName.split(separator: " ").prefix(2)
        return words.compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(initials.isEmpty ? "?" : initials)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Colors.accent)
                .frame(width: size, height: size)
                .background(DS.Colors.accentSoft, in: Circle())
            Image(systemName: flagged ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(flagged ? DS.Colors.fair : DS.Colors.good)
                .background(Circle().fill(DS.Colors.surface))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(member.displayName))
        .accessibilityValue(flagged ? Text("Has risk flags") : Text("No risk flags"))
    }
}

// MARK: - Body systems

/// Where in the body a contaminant can have effects, as an icon grid. Plain summaries of CDC/ATSDR and
/// EPA health information; needs verification (listed in Data Review).
nonisolated enum BodyArea: String, CaseIterable, Sendable, Identifiable {
    case brain, kidneys, liver, blood, stomach, skin, lungs, bones, heart, growth, immune, cancer

    var id: Self { self }

    var label: String {
        switch self {
        case .brain: String(localized: "Brain and nerves")
        case .kidneys: String(localized: "Kidneys")
        case .liver: String(localized: "Liver")
        case .blood: String(localized: "Blood")
        case .stomach: String(localized: "Stomach")
        case .skin: String(localized: "Skin")
        case .lungs: String(localized: "Lungs")
        case .bones: String(localized: "Bones and teeth")
        case .heart: String(localized: "Heart")
        case .growth: String(localized: "Growth in kids")
        case .immune: String(localized: "Immune system")
        case .cancer: String(localized: "Cancer risk")
        }
    }

    var symbol: String {
        switch self {
        case .brain: "brain.head.profile"
        case .kidneys: "drop.halffull"
        case .liver: "cross.case.fill"
        case .blood: "drop.fill"
        case .stomach: "fork.knife"
        case .skin: "hand.raised.fill"
        case .lungs: "lungs.fill"
        case .bones: "figure.walk"
        case .heart: "heart.fill"
        case .growth: "figure.child"
        case .immune: "shield.lefthalf.filled"
        case .cancer: "exclamationmark.shield.fill"
        }
    }

    static func areas(for id: ContaminantID) -> [BodyArea] {
        switch id {
        case .lead: [.brain, .growth, .kidneys, .blood]
        case .arsenic: [.skin, .cancer, .heart]
        case .nitrate, .nitrite: [.blood]
        case .uranium: [.kidneys, .cancer]
        case .radon: [.lungs, .cancer]
        case .manganese: [.brain]
        case .copper: [.stomach, .liver]
        case .fluoride: [.bones]
        case .totalColiform, .eColi: [.stomach]
        case .pfoa, .pfos, .genx: [.liver, .immune, .growth, .cancer]
        case .iron, .pH, .hardness: []
        }
    }
}

struct BodyAreaGrid: View {
    let areas: [BodyArea]

    var body: some View {
        if areas.isEmpty {
            Label("Not a health concern at typical levels", systemImage: "checkmark.circle.fill")
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.textPrimary)
        } else {
            TileGrid(columns: 3, spacing: DS.Space.s) {
                ForEach(areas) { area in
                    VStack(spacing: DS.Space.xs) {
                        Image(systemName: area.symbol)
                            .font(.title2)
                            .foregroundStyle(DS.Colors.accent)
                            .accessibilityHidden(true)
                        Text(area.label)
                            .font(DS.Typography.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(DS.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(DS.Colors.accentSoft, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Alerts

/// One line, one action. The full message opens in a sheet.
struct AlertBanner: View {
    let alert: SafetyAlert
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: DS.Level.unsafe.symbol).font(.title3).accessibilityHidden(true)
                Text(alert.title)
                    .font(DS.Typography.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: DS.Space.s)
                Text("What to do")
                    .font(DS.Typography.subheadline.weight(.semibold))
                    .padding(.horizontal, DS.Space.m)
                    .padding(.vertical, DS.Space.s)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(DS.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xB3161F), in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
        }
        .buttonStyle(DS.PressableCardStyle())
        .accessibilityHint(Text("Shows what to do"))
        .sheet(isPresented: $showing) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        SafetyAlertCard(alert: alert)
                        MedicalDisclaimer()
                    }
                    .dsScreen()
                }
                .background(DS.Colors.background)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { DS.Haptics.warning() }
    }
}
