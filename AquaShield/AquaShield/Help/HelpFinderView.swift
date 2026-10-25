//
//  HelpFinderView.swift
//  AquaShield
//
//  Help Finder: programs matched to the user's county, latest report and Risk Check answers.
//

import SwiftData
import SwiftUI

/// Builds the matcher's context from stored data.
@MainActor
struct HelpContextBuilder {
    static func make(results: [LabResult], county: String?, settings: AppSettings) -> HelpContext {
        let latest = results.first
        let findings = latest?.healthFindings ?? []
        return HelpContext(county: county,
                           exceedances: Set(findings.map(\.id)),
                           eColiPositive: latest?.eColi == .present,
                           floodingReported: settings.riskAnswers?.flooding == true,
                           lowIncome: settings.lowIncome,
                           hasResults: latest != nil)
    }
}

/// Help Finder as a section of the Get Help tab. Applies a filter handed over by the router.
struct HelpFinderSection: View {
    @Environment(AppRouter.self) private var router
    @State private var filter: HelpFilter = .all

    var body: some View {
        HelpFinderContent(filter: $filter)
            .onAppear(perform: applyPending)
            .onChange(of: router.pendingHelpFilter) { _, _ in applyPending() }
    }

    private func applyPending() {
        if let pending = router.pendingHelpFilter {
            filter = pending
            router.pendingHelpFilter = nil
        }
    }
}

/// Help Finder as its own screen (pushed from the safety override).
struct HelpFinderView: View {
    @State var filter: HelpFilter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HelpFinderContent(filter: $filter)
                DisclaimerFooter()
            }
            .screenContainer()
        }
        .background(Color.appBackground)
        .navigationTitle("Get help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpFinderContent: View {
    @Binding var filter: HelpFilter

    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var store
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]
    @State private var library = HelpLibrary.loadBundled()

    private var county: String? {
        settings.effectiveCounty(savedWellCounty: savedWellCounty(savedWells, store: store))
    }

    var body: some View {
        let context = HelpContextBuilder.make(results: results, county: county, settings: settings)
        let matches = HelpMatcher.matches(programs: library.programs, context: context, filter: filter)
        VStack(alignment: .leading, spacing: Spacing.l) {
            SectionHeader(title: "Programs that can help",
                          subtitle: county.map { String(localized: "Showing programs for \($0) County.") }
                              ?? String(localized: "Set your county in Settings to see local programs."))
            filterBar
            ScamWarningCard()
            if matches.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "No programs match this filter",
                               message: "Try All to see every program for your county.",
                               actionTitle: "Show all") { filter = .all }
            } else {
                ForEach(matches) { match in
                    HelpProgramCard(match: match, county: county,
                                    related: match.program.relatedProgramID.flatMap(library.program(id:)))
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                if case .contaminant(let id) = filter {
                    chip(String(localized: "For \(id.info.name)"), value: filter)
                }
                chip(String(localized: "All"), value: .all)
                chip(String(localized: "Testing"), value: .testing)
                chip(String(localized: "Pay to fix"), value: .payToFix)
                chip(String(localized: "Emergency"), value: .emergency)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Filter programs"))
    }

    private func chip(_ title: String, value: HelpFilter) -> some View {
        let selected = filter == value
        return Button {
            filter = value
        } label: {
            Label(title, systemImage: selected ? "checkmark" : "circle")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.onBrand : Color.brandPrimary)
                .padding(.horizontal, Spacing.m)
                .frame(minHeight: TapTarget.minimum)
                .background(selected ? Color.brandPrimary : Color.brandPrimary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Always visible above the programs.
struct ScamWarningCard: View {
    var body: some View {
        InfoCard(style: .status(.watch), systemImage: "exclamationmark.shield.fill",
                 title: String(localized: "Watch out for water scams"),
                 message: String(localized: "Accurate testing needs a state-certified lab, and there are no miracle products. Be wary of companies offering free in-home \"tests\" or pressuring you to buy filters. Report suspicious offers to the NC Attorney General's office.")) {
            Link(destination: WellResources.ncAttorneyGeneralComplaint) {
                Label("Report a scam to the NC Attorney General", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: TapTarget.minimum)
            }
        }
    }
}

struct HelpProgramCard: View {
    let match: HelpMatch
    let county: String?
    let related: HelpProgram?

    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    private var program: HelpProgram { match.program }

    var body: some View {
        let saved = settings.savedProgramIDs.contains(program.id)
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(program.type.label, systemImage: program.type.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(program.type == .emergency ? Color.statusDanger : Color.brandPrimary)
                Text(program.name)
                    .font(M.Font.section)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(program.agency)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(program.eligibilitySummary)
                .font(M.Font.row)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(match.isMatched ? "Why this matches you" : "Who it's for")
                    .font(.subheadline.weight(.semibold))
                if match.isMatched {
                    ForEach(match.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .symbolRenderingMode(.hierarchical)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(program.isStatewide ? "Available to households anywhere in North Carolina." : "Available in your county.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if let related {
                Text("Contact: \(related.name), below.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            buttons(saved: saved)
        }
        .card()
    }

    @ViewBuilder
    private func buttons(saved: Bool) -> some View {
        let actions = ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s) { actionButtons }
            VStack(spacing: Spacing.s) { actionButtons }
        }
        VStack(spacing: Spacing.s) {
            if let search = program.searchURL(county: county), let text = program.searchText(county: county) {
                Button {
                    openURL(search)
                } label: {
                    Label("Search \"\(text)\"", systemImage: "magnifyingglass")
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            actions
            Button {
                if saved { settings.savedProgramIDs.remove(program.id) } else { settings.savedProgramIDs.insert(program.id) }
            } label: {
                Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(Text(saved ? "Saved. Tap to remove from saved programs." : "Save this program"))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let phone = program.phoneURL {
            Button { openURL(phone) } label: { Label("Call", systemImage: "phone.fill") }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel(Text("Call \(program.phone ?? "")"))
        }
        if let web = program.websiteURL {
            Button { openURL(web) } label: { Label("Website", systemImage: "safari") }
                .buttonStyle(SecondaryButtonStyle())
        }
        if let email = program.emailURL {
            Button { openURL(email) } label: { Label("Email", systemImage: "envelope") }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel(Text("Email \(program.email ?? "")"))
        }
    }
}
