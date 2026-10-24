//
//  RemediationView.swift
//  ClearWellNC
//
//  What to do: free fixes first, then certified products that cover what's driving the risk here, grouped
//  by type, with a side-by-side comparison of up to three. No affiliate links.
//

import SwiftData
import SwiftUI

struct RemediationView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var compare: [String] = []
    @State private var showingCompare = false

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        let plan = snapshot.plan
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                ForEach(snapshot.alerts) { SafetyAlertCard(alert: $0) }

                if !snapshot.hasReadings {
                    DS.EmptyStateView(systemImage: DS.Icon.test,
                                      message: snapshot.source.showsWellCare
                                          ? String(localized: "Test your well first. Then we can show what fixes it.")
                                          : String(localized: "Add your water report or a tap test first."),
                                      actionTitle: String(localized: "Find testing"), actionImage: "arrow.right") {
                        router.openHelp(.testing)
                    }
                } else if plan.drivers.isEmpty && plan.fixes.isEmpty {
                    DS.InfoCard(systemImage: DS.Level.good.symbol, title: String(localized: "Nothing to fix right now"),
                                message: String(localized: "Keep testing on schedule and replace filters on time."), level: .good)
                }

                if !plan.fixes.isEmpty {
                    DSSectionTitle(String(localized: "Start here, for free"))
                    ForEach(plan.fixes) { fix in
                        DS.InfoCard(systemImage: fix.symbol, title: fix.title, message: fix.detail)
                    }
                    if plan.fixes.contains(where: { $0.kind == .shockChlorinate }) {
                        NavigationLink { StormModeView() } label: {
                            NavigationCardLabel(title: Text("Shock chlorination guide"),
                                                subtitle: Text("Step by step, then retest."),
                                                systemImage: "drop.triangle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let note = plan.volatileNote {
                    DS.InfoCard(systemImage: "humidity.fill", title: String(localized: "In the shower"), message: note, level: .fair)
                }

                if !plan.drivers.isEmpty {
                    DSSectionTitle(String(localized: "Filters that cover your water"))
                    Text("Only products certified for \(plan.drivers.map(\.name).formatted(.list(type: .and))) at your levels. Sorted by coverage, then yearly cost.")
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Colors.textSecondary)
                    if plan.allMatches.isEmpty {
                        DS.InfoCard(systemImage: "magnifyingglass", title: String(localized: "No matching products on file"),
                                    message: String(localized: "Search a certifier's listing, then add the product here."),
                                    learnMore: String(localized: "NSF, IAPMO, WQA, CSA and UL all list certified products online. Look for a claim for your contaminant tested at or above your level."))
                        NavigationLink { FiltersView() } label: {
                            Label("Add my own filter", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(DS.SecondaryButtonStyle())
                    }
                    if let pick = plan.affordablePick {
                        Text("Most affordable certified option").font(DS.Typography.caption).textCase(.uppercase)
                            .foregroundStyle(DS.Colors.textSecondary)
                        matchCard(pick)
                    }
                    ForEach(plan.productsByType, id: \.type) { group in
                        Text(group.type.name).font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
                            .padding(.top, DS.Space.s)
                        ForEach(group.matches) { matchCard($0) }
                    }
                    if compare.count >= 2 {
                        Button { showingCompare = true } label: {
                            Label("Compare \(compare.count)", systemImage: "rectangle.split.3x1")
                        }
                        .buttonStyle(DS.PrimaryButtonStyle())
                    }
                }

                if let skin = plan.skinCare {
                    DSSectionTitle(String(localized: "Skin care"))
                    if let redFlag = skin.redFlag {
                        DS.InfoCard(systemImage: "stethoscope", title: String(localized: "See a doctor"), message: redFlag, level: .unsafe)
                    }
                    DS.InfoCard(systemImage: "hand.raised.fill", title: String(localized: "For dry or irritated skin"),
                                message: skin.tips.first, learnMore: (skin.tips.dropFirst() + skin.avoid).joined(separator: "\n"))
                }

                MedicalDisclaimer()
                Text("No affiliate links. \(AppName.display) earns nothing from these products.")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("What to do")
        .sheet(isPresented: $showingCompare) {
            CompareProductsView(matches: plan.allMatches.filter { compare.contains($0.id) })
        }
    }

    private func matchCard(_ match: ProductMatch) -> some View {
        let selected = compare.contains(match.id)
        return VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(match.product.displayName).font(DS.Typography.headline)
                Spacer()
                Text("\(match.coveragePercent)%").font(DS.Typography.metric)
            }
            Text("Covers \(match.covered.map(\.name).formatted(.list(type: .and)))")
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.textSecondary)
            HStack(spacing: DS.Space.s) {
                if let cost = match.annualCost {
                    FlagChip(text: String(localized: "\(cost.formatted(.currency(code: "USD").precision(.fractionLength(0))))/yr"),
                             systemImage: "dollarsign.circle.fill", color: DS.Colors.accent)
                }
                FlagChip(text: match.product.type.installDifficulty.label, systemImage: "wrench.fill", color: DS.Colors.accent)
            }
            if match.product.needsVerification {
                Text("Sample or unverified data").font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
            }
            Button {
                if selected { compare.removeAll { $0 == match.id } } else if compare.count < 3 { compare.append(match.id) }
                DS.Haptics.selection()
            } label: {
                Label(selected ? "Added to compare" : "Compare", systemImage: selected ? "checkmark.circle.fill" : "plus.circle")
                    .frame(minHeight: DS.Size.tapTarget)
            }
            .disabled(!selected && compare.count >= 3)
            .accessibilityValue(selected ? Text("Selected") : Text(""))
        }
        .foregroundStyle(DS.Colors.textPrimary)
        .dsCard()
    }
}

/// Up to three products side by side.
struct CompareProductsView: View {
    let matches: [ProductMatch]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    row(String(localized: "Coverage")) { "\($0.coveragePercent)%" }
                    CoverageGrid(products: matches.map(\.product),
                                 targets: Array(Set(matches.flatMap(\.drivers))).sorted { $0.rawValue < $1.rawValue })
                        .dsCard()
                    row(String(localized: "Capacity")) { $0.capacityGallons.map { "\(formatNumber($0)) gal" } ?? "—" }
                    row(String(localized: "Yearly cost")) {
                        $0.annualCost.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) } ?? "—"
                    }
                    row(String(localized: "Install")) { $0.product.type.installDifficulty.label }
                    row(String(localized: "Certified by")) { $0.certifiers.map(\.name).joined(separator: ", ") }
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ title: String, value: @escaping (ProductMatch) -> String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).font(DS.Typography.caption).textCase(.uppercase).foregroundStyle(DS.Colors.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: DS.Space.m) { cells(value) }
                VStack(alignment: .leading, spacing: DS.Space.s) { cells(value) }
            }
        }
        .dsCard()
    }

    @ViewBuilder
    private func cells(_ value: @escaping (ProductMatch) -> String) -> some View {
        ForEach(matches) { match in
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(match.product.displayName).font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                Text(value(match)).font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
