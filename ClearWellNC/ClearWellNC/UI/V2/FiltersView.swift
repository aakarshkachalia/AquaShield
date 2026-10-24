//
//  FiltersView.swift
//  ClearWellNC
//
//  Installed filters by where they are (whole house, kitchen, each shower), what they're certified for,
//  and days until replacement. Add one, or add your own product from a certifier's listing.
//

import SwiftData
import SwiftUI

struct FiltersView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var editing: TreatmentSystem?
    @State private var adding = false
    @State private var addingCustom = false

    private let reference = ReferenceDataStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if systems.isEmpty {
                    DS.EmptyStateView(systemImage: DS.Icon.filter(.underSinkFilter),
                                      message: String(localized: "Add your filters to see what they really remove."),
                                      actionTitle: String(localized: "Add a filter"), actionImage: "plus") {
                        adding = true
                    }
                } else {
                    ForEach(groups, id: \.location) { group in
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            DSSectionTitle(group.location.name)
                            ForEach(group.systems) { system in
                                Button { editing = system } label: { row(system) }
                                    .buttonStyle(DS.PressableCardStyle())
                            }
                        }
                    }
                    Button { adding = true } label: { Label("Add a filter", systemImage: "plus") }
                        .buttonStyle(DS.PrimaryButtonStyle())
                }
                Button { addingCustom = true } label: { Label("Add my own filter", systemImage: "square.and.pencil") }
                    .buttonStyle(DS.SecondaryButtonStyle())
                    .accessibilityIdentifier("filters.addCustom")

                DS.InfoCard(systemImage: "shower.fill", title: String(localized: "Shower filters reduce chlorine only"),
                            message: String(localized: "NSF/ANSI 177 covers free chlorine. It doesn't cover lead, arsenic or germs."),
                            learnMore: String(localized: "Radon and some chemicals rise into the air as steam. Only a whole-house system treats the water before it reaches the shower."))
                DS.InfoCard(systemImage: "checkmark.seal.fill", title: String(localized: "Only certified claims count"),
                            message: String(localized: "A filter without certification lowers nothing in your score."),
                            learnMore: String(localized: "Look for NSF/ANSI 53 or 58 for lead, arsenic and PFAS, NSF/ANSI 55 for UV, and NSF/ANSI 42 for taste and chlorine. A claim also has to be tested at or above your level, and the filter must not be expired."))
                if !settings.customFilterProducts.isEmpty {
                    DSSectionTitle(String(localized: "Products you added"))
                    ForEach(settings.customFilterProducts) { product in
                        HStack {
                            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                Text(product.displayName).font(DS.Typography.headline)
                                Text(product.claims.map { "\($0.target.name) · \($0.standard.name)" }.joined(separator: ", "))
                                    .font(DS.Typography.footnote)
                                    .foregroundStyle(DS.Colors.textSecondary)
                            }
                            Spacer()
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                settings.customFilterProducts.removeAll { $0.id == product.id }
                            }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: DS.Size.tapTarget, minHeight: DS.Size.tapTarget)
                        }
                        .foregroundStyle(DS.Colors.textPrimary)
                        .dsCard()
                    }
                }
                NavigationLink("Replacement reminders") { RemindersView().navigationTitle("Reminders") }
                    .font(DS.Typography.headline)
                    .frame(minHeight: DS.Size.tapTarget)
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("Filters")
        .sheet(item: $editing) { TreatmentForm(existing: $0) }
        .sheet(isPresented: $adding) { TreatmentForm() }
        .fullScreenCover(isPresented: $addingCustom) { CustomFilterFlow() }
    }

    private var groups: [(location: TapLocation, systems: [TreatmentSystem])] {
        var order: [TapLocation] = []
        var map: [TapLocation: [TreatmentSystem]] = [:]
        for system in systems {
            let location = system.location
            if map[location] == nil { order.append(location) }
            map[location, default: []].append(system)
        }
        order.sort { a, b in
            if (a == .wholeHouse) != (b == .wholeHouse) { return a == .wholeHouse }
            return a.rawValue < b.rawValue
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func row(_ system: TreatmentSystem) -> some View {
        let product = reference.product(id: system.productID, custom: settings.customFilterProducts)
        let installed = system.installed(product: product)
        let days = installed.daysUntilDue(from: .now)
        let standards = Array(Set((product?.claims ?? []).map(\.standard))).sorted { $0.rawValue < $1.rawValue }
        return HStack(alignment: .top, spacing: DS.Space.m) {
            DS.IconBadge(systemImage: DS.Icon.filter(system.kind))
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(installed.name)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Colors.textPrimary)
                if standards.isEmpty {
                    FlagChip(text: String(localized: "Uncertified"), systemImage: FilterFlag.uncertified.symbol)
                } else {
                    Text(standards.map(\.name).joined(separator: " · "))
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                if product?.needsVerification == true {
                    Text("Sample or unverified data")
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                if let days {
                    Text(days <= 0 ? String(localized: "Replace now") : String(localized: "\(days) days"))
                        .font(DS.Typography.headline)
                        .foregroundStyle(days <= 0 ? DS.Colors.poor : DS.Colors.textPrimary)
                    Text(days <= 0 ? String(localized: "expired") : String(localized: "left"))
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
        }
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add my own filter

nonisolated enum CustomFilterStep: String, Codable, Hashable, Sendable, CaseIterable {
    case product, claims, ratings, review
}

/// Enter a product and its claims from a certifier's listing (NSF, IAPMO, WQA, CSA or UL).
struct CustomFilterFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var flow = StepFlow(root: CustomFilterStep.product)
    @State private var product = FilterProduct(id: "custom-\(UUID().uuidString)", brand: "", model: "", type: .pitcher,
                                               claims: [], isUserEntered: true,
                                               source: SourceRef(String(localized: "Entered by you from a certifier listing")))
    @State private var checkedListing = false
    @State private var newClaim = ClaimDraft()

    private let order = CustomFilterStep.allCases

    var body: some View {
        StepFlowContainer(flow: $flow, progress: { _ in flow.progress(in: order) },
                          primaryAction: primaryAction, onClose: { dismiss() }) { step in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    page(step)
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Add my own filter")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func primaryAction(_ step: CustomFilterStep) -> StepAction? {
        switch step {
        case .product:
            StepAction(title: "Next", systemImage: "arrow.right", isEnabled: !product.model.isEmpty || !product.brand.isEmpty) {
                flow.advance(in: order)
            }
        case .claims, .ratings:
            StepAction(title: "Next", systemImage: "arrow.right") { flow.advance(in: order) }
        case .review:
            StepAction(title: "Save filter", systemImage: "checkmark", identifier: "flow.save") { save() }
        }
    }

    @ViewBuilder
    private func page(_ step: CustomFilterStep) -> some View {
        switch step {
        case .product:
            title(String(localized: "What's the filter?"), String(localized: "Copy it from the box or the certifier's website."))
            field(String(localized: "Brand"), text: $product.brand)
            field(String(localized: "Model"), text: $product.model)
            Text("Type").font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
            ForEach(FilterType.allCases) { type in
                DS.ChoiceCard(title: type.name, systemImage: DS.Icon.filter(TreatmentKind.matching(type)),
                              isSelected: product.type == type) { product.type = type }
            }
        case .claims:
            title(String(localized: "What is it certified to reduce?"), String(localized: "Add each line from the certifier's listing. Skip if it has none."))
            ForEach(product.claims) { claim in
                HStack {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("\(claim.target.name): \(formatNumber(claim.reductionPercent))%").font(DS.Typography.headline)
                        Text("\(claim.standard.name) · \(claim.certifier.name)"
                             + (claim.influentChallengeConcentration.map { " · tested at \(formatNumber($0)) \(ReadingUnit.canonical(for: claim.target).label)" } ?? ""))
                            .font(DS.Typography.footnote)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    Spacer()
                    Button("Remove", systemImage: "minus.circle.fill") { product.claims.removeAll { $0.id == claim.id } }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: DS.Size.tapTarget, minHeight: DS.Size.tapTarget)
                }
                .foregroundStyle(DS.Colors.textPrimary)
                .dsCard()
            }
            claimEditor
        case .ratings:
            title(String(localized: "How long does it last?"), String(localized: "Leave blank anything the listing doesn't say."))
            number(String(localized: "Rated capacity (gallons)"), value: $product.ratedCapacityGallons)
            number(String(localized: "Rated life (months)"), value: Binding(get: { product.ratedLifeMonths.map(Double.init) },
                                                       set: { product.ratedLifeMonths = $0.map { Int($0) } }))
            number(String(localized: "Price (US dollars)"), value: $product.priceUSD)
            number(String(localized: "Replacement cost per year (US dollars)"), value: $product.annualCostUSD)
        case .review:
            title(product.displayName.isEmpty ? String(localized: "Your filter") : product.displayName,
                  product.claims.isEmpty ? String(localized: "No certification claims: it won't lower anything in your score.")
                                         : String(localized: "\(product.claims.count) certified claims."))
            Toggle("I checked these against the certifier's listing", isOn: $checkedListing)
                .font(DS.Typography.headline)
                .frame(minHeight: DS.Size.tapTarget)
                .dsCard()
            Text("Unchecked products are marked \"needs verification\".")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }

    private var claimEditor: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Picker("Contaminant", selection: $newClaim.target) {
                ForEach(ClaimTarget.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            Picker("Standard", selection: $newClaim.standard) {
                ForEach(CertificationStandard.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            Picker("Certified by", selection: $newClaim.certifier) {
                ForEach(Certifier.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            number(String(localized: "Reduction (%)"), value: $newClaim.reduction)
            number(String(localized: "Tested at (\(ReadingUnit.canonical(for: newClaim.target).label))"), value: $newClaim.challenge)
            if !newClaim.standard.allowedTargets.contains(newClaim.target) {
                FlagChip(text: String(localized: "\(newClaim.standard.name) doesn't cover \(newClaim.target.name.lowercased()), so this claim won't count."))
            }
            Button {
                product.claims.append(CertificationClaim(
                    standard: newClaim.standard, certifier: newClaim.certifier, target: newClaim.target,
                    reductionPercent: newClaim.reduction ?? 0, influentChallengeConcentration: newClaim.challenge,
                    source: SourceRef(String(localized: "\(newClaim.certifier.name) listing, entered by you"))))
                newClaim = ClaimDraft()
                DS.Haptics.selection()
            } label: {
                Label("Add this claim", systemImage: "plus")
            }
            .buttonStyle(DS.SecondaryButtonStyle())
            .disabled(newClaim.reduction == nil)
        }
        .dsCard()
    }

    private func save() {
        let source = SourceRef(String(localized: "Entered by you from a certifier listing"), needsVerification: !checkedListing)
        product.source = source
        product.claims = product.claims.map { claim in
            var claim = claim
            claim.source = SourceRef(claim.source.sourceName, needsVerification: !checkedListing)
            return claim
        }
        settings.customFilterProducts.append(product)
        DS.Haptics.success()
        dismiss()
    }

    private func title(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title)
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .font(DS.Typography.body)
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: DS.Size.largeTapTarget)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous).strokeBorder(DS.Colors.separator))
    }

    private func number(_ label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label).font(DS.Typography.body).foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
        }
        .frame(minHeight: DS.Size.tapTarget)
    }
}

private struct ClaimDraft {
    var target: ClaimTarget = .lead
    var standard: CertificationStandard = .nsf53
    var certifier: Certifier = .nsf
    var reduction: Double?
    var challenge: Double?
}

extension TreatmentKind {
    /// The closest treatment kind for a filter type (for icons).
    nonisolated static func matching(_ type: FilterType) -> TreatmentKind {
        switch type {
        case .pitcher: .pitcherFilter
        case .faucet: .faucetFilter
        case .countertop: .other
        case .underSinkCarbon: .underSinkFilter
        case .reverseOsmosis: .roMembrane
        case .wholeHouse: .carbonFilter
        case .shower: .showerFilter
        case .uv: .uvBulb
        case .softener: .softenerSalt
        case .refrigerator: .refrigeratorFilter
        }
    }
}
