//
//  TapScoreView.swift
//  ClearWellNC
//
//  One tap's score: the ring, confidence, every reading after filters with a plain explanation, flags,
//  and the tests still missing.
//

import SwiftData
import SwiftUI

struct TapScoreView: View {
    let tap: TapLocation

    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let result = snapshot.taps[tap] {
                    header(result)
                    DSSectionTitle(String(localized: "Each result"))
                    ForEach(result.items.filter { $0.level != .notScored }) { ItemCard(item: $0) }
                    let notScored = result.items.filter { $0.level == .notScored }
                    if !notScored.isEmpty {
                        DS.InfoCard(systemImage: DS.Icon.info, title: String(localized: "Not part of this score"),
                                    message: notScored.map(\.target.name).formatted(.list(type: .and)),
                                    learnMore: notScored.map { "\($0.target.name): \($0.explanation)" }.joined(separator: "\n"))
                    }
                    if !result.missingTests.isEmpty {
                        DSSectionTitle(String(localized: "Tests still needed"))
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            ForEach(result.missingTests, id: \.self) { target in
                                Label(String(localized: "Test for \(target.name.lowercased())"), systemImage: "circle.dashed")
                                    .font(DS.Typography.headline)
                                    .foregroundStyle(DS.Colors.textPrimary)
                            }
                            Text("Missing tests lower confidence, not the score.")
                                .font(DS.Typography.footnote)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                        .dsCard()
                    }
                    NavigationLink {
                        RemediationView()
                    } label: {
                        Text("What to do")
                    }
                    .buttonStyle(DS.PrimaryButtonStyle())
                    DS.InfoCard(systemImage: DS.Icon.score, title: String(localized: "How this score works"),
                                message: String(localized: "It starts at 100. Results near a limit take points away."),
                                learnMore: String(localized: "Filters count only if certified for that contaminant, tested at or above your level, and not expired. Health results take away up to 30 points each. Taste and staining issues take away 10 at most, all together. Anything over a health limit holds the score at 40 or lower; germs at a drinking tap hold it at 20 or lower."))
                } else {
                    DS.EmptyStateView(systemImage: "drop", message: String(localized: "No results for this tap yet."),
                                      actionTitle: String(localized: "Scan a report"), actionImage: DS.Icon.scan) {
                        router.showingScanner = true
                    }
                }
                DisclaimerFooter()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle(tap.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ result: TapScoreResult) -> some View {
        VStack(spacing: DS.Space.m) {
            DS.ScoreRing(score: result.score, level: result.dsLevel,
                         title: tap.isDrinking ? String(localized: "Drinking water score") : String(localized: "Shower water score"))
            Text("Confidence: \(result.confidenceText)")
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text(result.explanation)
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .dsCard(padding: DS.Space.xl)
    }
}

/// One reading at a tap.
private struct ItemCard: View {
    let item: TapItem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if let level = item.level.dsLevel, let residual = item.residual, let limit = item.limit, limit.value > 0 {
                let unit = ReadingUnit.canonical(for: item.target).label
                DS.LevelMeter(name: item.target.name, level: level,
                              valueText: "\(formatNumber(residual)) \(unit)",
                              limitText: "\(formatNumber(limit.value)) \(unit)",
                              ratio: residual / limit.value)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.target.name)
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Spacer()
                    if let level = item.level.dsLevel {
                        DS.StatusBadge(level: level, text: item.present == true ? String(localized: "Found") : nil)
                    } else if item.level == .inconclusive {
                        FlagChip(text: String(localized: "Inconclusive"), systemImage: "questionmark.circle.fill")
                    }
                }
            }
            Text(item.explanation)
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !item.flags.isEmpty {
                FlowChips(flags: item.flags)
            }
        }
        .dsCard()
    }
}

private struct FlowChips: View {
    let flags: [FilterFlag]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { ForEach(flags, id: \.self) { FlagChip(text: $0.label, systemImage: $0.symbol) } }
            VStack(alignment: .leading) { ForEach(flags, id: \.self) { FlagChip(text: $0.label, systemImage: $0.symbol) } }
        }
    }
}

/// Every tap's score, drinking first.
struct TapScoresListView: View {
    @Environment(AppSettings.self) private var settings
    @State private var editingHome = false
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        let taps = snapshot.taps.values.sorted { a, b in
            if a.tap.isDrinking != b.tap.isDrinking { return a.tap.isDrinking }
            return a.tap.rawValue < b.tap.rawValue
        }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("Filters change what comes out of each tap, so each one has its own score.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                ForEach(taps, id: \.tap) { result in
                    NavigationLink {
                        TapScoreView(tap: result.tap)
                    } label: {
                        HStack(spacing: DS.Space.l) {
                            DS.ScoreRing(score: result.score, level: result.dsLevel, scale: 0.45)
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                Text(result.tap.name).font(DS.Typography.headline)
                                Text(result.tap.isDrinking ? String(localized: "Drinking and cooking")
                                                           : String(localized: "Showering: steam and skin"))
                                    .font(DS.Typography.subheadline)
                                    .foregroundStyle(DS.Colors.textSecondary)
                                Text("Confidence: \(result.confidenceText)")
                                    .font(DS.Typography.footnote)
                                    .foregroundStyle(DS.Colors.textSecondary)
                            }
                            .foregroundStyle(DS.Colors.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .dsCard()
                    }
                    .buttonStyle(DS.PressableCardStyle())
                }
                Button {
                    editingHome = true
                } label: {
                    NavigationCardLabel(title: Text("Add showers and sinks"),
                                        subtitle: Text("Tell us about your home's taps and pipes."),
                                        systemImage: "house.fill")
                }
                .buttonStyle(.plain)
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("Every tap")
        .fullScreenCover(isPresented: $editingHome) { HomeProfileFlow() }
    }
}
