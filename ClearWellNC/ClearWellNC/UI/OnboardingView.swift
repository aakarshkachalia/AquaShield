//
//  OnboardingView.swift
//  ClearWellNC
//
//  First launch: welcome → home address → water source estimate (on-device map lookup) → confirm the source
//  (always asked; the answer is the source of truth) → household basics. Saved on every change; a relaunch
//  resumes on the same step without showing the welcome again. Settings > "Change address or water source"
//  runs the address, estimate and confirm steps only.
//

import MapKit
import SwiftUI

nonisolated enum OnboardingStep: String, Codable, Hashable, Sendable, CaseIterable {
    case welcome, address, estimate, confirm, household
}

nonisolated struct OnboardingDraft: Codable, Sendable, Equatable {
    var flow = StepFlow(root: OnboardingStep.welcome)
    var location: HomeLocation?
    var county: String?
    var estimate: WaterSourceEstimate?
    var source: WaterSource?
    var showingHints = false
    var household: Set<HouseholdBasic> = []

    /// Version 2: the address-first flow. Version 1 drafts (old steps) are dropped.
    static let key = DraftKey<OnboardingDraft>(name: "onboarding", schemaVersion: 2)
    static let changeKey = DraftKey<OnboardingDraft>(name: "onboarding.change", schemaVersion: 2)
}

nonisolated enum HouseholdBasic: String, Codable, CaseIterable, Sendable {
    case baby, pregnant, children, adults

    var title: String {
        switch self {
        case .baby: String(localized: "A baby under 1")
        case .pregnant: String(localized: "Someone pregnant")
        case .children: String(localized: "Children 1–12")
        case .adults: String(localized: "Adults")
        }
    }

    var symbol: String {
        switch self {
        case .baby: "figure.and.child.holdinghands"
        case .pregnant: "figure.stand"
        case .children: "figure.child"
        case .adults: "person.2.fill"
        }
    }
}

struct OnboardingView: View {
    enum Mode { case firstLaunch, changeSource }

    var mode: Mode = .firstLaunch

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var tractStore

    @State private var draft = OnboardingDraft()
    @State private var loaded = false
    @State private var search = AddressSearch()
    @State private var locationFetcher = LocationFetcher()
    @State private var locating = false
    @State private var pickingCounty = false
    @State private var area: WaterSystemArea?
    @State private var lookingUp = false

    private var order: [OnboardingStep] {
        mode == .firstLaunch ? OnboardingStep.allCases : [.address, .estimate, .confirm]
    }
    private var draftKey: DraftKey<OnboardingDraft> { mode == .firstLaunch ? OnboardingDraft.key : OnboardingDraft.changeKey }

    var body: some View {
        StepFlowContainer(flow: $draft.flow,
                          progress: { step in step == .welcome ? nil : progress(step) },
                          primaryAction: primaryAction,
                          onClose: mode == .changeSource ? { dismiss() } : nil) { step in
            page(for: step)
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .onChange(of: draft) { _, newValue in
            // Saved on every change, so a force-quit resumes on the same step.
            guard loaded else { return }
            settings.drafts.save(newValue, for: draftKey)
        }
    }

    private func progress(_ step: OnboardingStep) -> StepProgress? {
        let steps = order.filter { $0 != .welcome }
        guard let index = steps.firstIndex(of: step) else { return nil }
        return StepProgress(position: index + 1, total: steps.count)
    }

    private func primaryAction(_ step: OnboardingStep) -> StepAction? {
        switch step {
        case .welcome:
            StepAction(title: "Get started", systemImage: "arrow.right", identifier: "onboarding.getStarted") {
                draft.flow.advance(in: order)
            }
        case .address:
            nil
        case .estimate:
            StepAction(title: "Next", systemImage: "arrow.right") { draft.flow.advance(in: order) }
        case .confirm:
            mode == .changeSource
                ? StepAction(title: "Save", systemImage: "checkmark", isEnabled: draft.source != nil,
                             identifier: "flow.save") { finish() }
                : StepAction(title: "Next", systemImage: "arrow.right", isEnabled: draft.source != nil) {
                    draft.flow.advance(in: order)
                }
        case .household:
            StepAction(title: "Finish", systemImage: "checkmark", identifier: "onboarding.finish") { finish() }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let saved = settings.drafts.load(draftKey), saved.payload.flow.isValid(in: order) {
            draft = saved.payload
        } else {
            draft = OnboardingDraft()
            if mode == .changeSource {
                draft.flow = StepFlow(root: .address)
                draft.location = settings.homeLocation
                draft.source = settings.waterSource
            }
        }
        refreshArea()
    }

    // MARK: Pages

    @ViewBuilder
    private func page(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome: welcome
        case .address: addressPage
        case .estimate: estimatePage
        case .confirm: confirmPage
        case .household: householdPage
        }
    }

    private var welcome: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer()
            Image(systemName: "drop.fill")
                .font(.system(.largeTitle, weight: .semibold))
                .imageScale(.large)
                .foregroundStyle(DS.Colors.onAccent)
                .frame(width: 128, height: 128)
                .background(LinearGradient(colors: [DS.Colors.water, DS.Colors.accent],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .accessibilityHidden(true)
            Text("\(AppName.display)")
                .font(DS.Typography.display)
                .foregroundStyle(DS.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.welcome")
            Text("Know what's in your water, and what to do about it.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textSecondary)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .dsScreen()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Colors.background)
    }

    private var addressPage: some View {
        content {
            title("What's your home address?")
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.Colors.textSecondary).accessibilityHidden(true)
                TextField("Street address", text: Binding(get: { search.query }, set: { search.query = $0 }))
                    .textContentType(.fullStreetAddress)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("onboarding.address.field")
            }
            .font(DS.Typography.body)
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: DS.Size.largeTapTarget)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous).strokeBorder(DS.Colors.separator))
            ForEach(search.suggestions, id: \.self) { suggestion in
                Button {
                    Task { await choose(suggestion) }
                } label: {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(DS.Colors.accent).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(suggestion.title).font(DS.Typography.headline)
                            Text(suggestion.subtitle).font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(DS.Colors.textPrimary)
                    .frame(minHeight: DS.Size.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if search.isSearching || locating { ProgressView().frame(maxWidth: .infinity) }
            if search.failed {
                Text("We couldn't find that address. Try again, or choose your county.")
                    .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
            }
            DS.ActionCard(systemImage: "location.fill", title: String(localized: "Use my current location")) {
                Task { await useCurrentLocation() }
            }
            .accessibilityIdentifier("onboarding.useLocation")
            Button(pickingCounty ? String(localized: "Hide county list") : String(localized: "Skip — choose my county instead")) {
                pickingCounty.toggle()
            }
            .font(DS.Typography.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
            .accessibilityIdentifier("onboarding.skipAddress")
            if pickingCounty {
                CountyPicker(selection: Binding(get: { draft.county }, set: { draft.county = $0 }),
                             noneLabel: String(localized: "Not sure"))
                Button {
                    draft.location = nil
                    draft.estimate = WaterSourceEstimate(kind: .unknown)
                    draft.flow.advance(in: order)
                } label: { Text("Continue without an address") }
                .buttonStyle(DS.PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding.continueWithoutAddress")
            }
            Label("Your address stays on this phone. It's only sent to Apple to find the location.", systemImage: "lock.fill")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }

    private var estimatePage: some View {
        let estimate = draft.estimate ?? WaterSourceEstimate(kind: .unknown)
        return content {
            title("Where your water likely comes from")
            if lookingUp {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if let location = draft.location {
                        SourceMap(location: location, area: area)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                    } else {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .accessibilityHidden(true)
                    }
                    HStack(alignment: .top, spacing: DS.Space.m) {
                        DS.IconBadge(systemImage: estimate.kind == .likelyWell ? "drop.circle.fill"
                                     : (estimate.kind == .unknown ? "questionmark.circle.fill" : "building.2.fill"))
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(estimate.headline).font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
                            if estimate.confidence != .none {
                                ConfidenceBadge(confidence: estimate.confidence)
                            }
                        }
                    }
                    if estimate.kind == .likelyWell, let tested = estimate.tractWellsTested, tested > 0 {
                        WellsTestedBar(count: tested)
                    }
                }
                .dsCard()
                .accessibilityIdentifier("onboarding.estimate")
                Text("From EPA water system maps, checked on your phone.")
                    .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
            }
        }
    }

    private var confirmPage: some View {
        content {
            title(draft.showingHints ? "Look for these" : "Does this look right?")
            if draft.showingHints {
                hint("doc.text.fill", String(localized: "A water bill"), String(localized: "City water"), .publicWater)
                hint("drop.circle.fill", String(localized: "A well head or pressure tank"), String(localized: "Private well"), .privateWell)
                Button("Still not sure") {
                    draft.source = .notSure
                    draft.showingHints = false
                }
                .font(DS.Typography.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
            } else {
                ForEach([WaterSource.publicWater, .privateWell, .both, .notSure]) { source in
                    DS.ChoiceCard(title: source.choiceTitle,
                                  subtitle: draft.estimate?.suggestedSource == source ? String(localized: "Our best guess") : nil,
                                  systemImage: source.symbol, isSelected: draft.source == source) {
                        draft.source = source
                        if source == .notSure { draft.showingHints = true }
                    }
                    .accessibilityIdentifier("onboarding.source.\(source.rawValue)")
                }
            }
        }
    }

    private var householdPage: some View {
        content {
            title("Who lives here?")
            ForEach(HouseholdBasic.allCases, id: \.self) { basic in
                DS.ChoiceCard(title: basic.title, systemImage: basic.symbol, isSelected: draft.household.contains(basic)) {
                    if draft.household.contains(basic) { draft.household.remove(basic) } else { draft.household.insert(basic) }
                }
                .accessibilityIdentifier("onboarding.household.\(basic.rawValue)")
            }
            PrivacyNote()
        }
    }

    // MARK: Helpers

    private func content<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) { content() }
                .dsScreen()
        }
        .background(DS.Colors.background)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(DS.Typography.title)
            .foregroundStyle(DS.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, DS.Space.s)
    }

    private func hint(_ symbol: String, _ title: String, _ meaning: String, _ source: WaterSource) -> some View {
        DS.ChoiceCard(title: title, subtitle: meaning, systemImage: symbol, isSelected: draft.source == source) {
            draft.source = source
            draft.showingHints = false
        }
    }

    private func choose(_ suggestion: MKLocalSearchCompletion) async {
        settings.networkOptIns.insert(.addressLookup)
        guard let result = await search.resolve(suggestion) else { return }
        await setLocation(address: result.address, coordinate: result.coordinate)
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard let location = try? await locationFetcher.currentLocation() else {
            search.query = ""
            return
        }
        await setLocation(address: String(localized: "Current location"), coordinate: location.coordinate)
    }

    private func setLocation(address: String, coordinate: CLLocationCoordinate2D) async {
        let tract = tractStore.database?.tract(containing: coordinate)
        draft.location = HomeLocation(address: address, latitude: coordinate.latitude, longitude: coordinate.longitude,
                                      county: tract?.countyName)
        draft.county = tract?.countyName ?? draft.county
        lookingUp = true
        draft.flow.advance(in: order)
        let tested = tract.map { $0.data.values.map(\.tests).max() ?? 0 }
        let lat = coordinate.latitude, lon = coordinate.longitude
        // Parsing the bundled boundaries takes a moment the first time: do it off the main thread.
        let estimate = await Task.detached(priority: .userInitiated) {
            WaterSourceEstimate.estimate(latitude: lat, longitude: lon, index: WaterSystemIndex.bundled,
                                         tractWellsTested: tested)
        }.value
        draft.estimate = estimate
        lookingUp = false
        refreshArea()
    }

    private func refreshArea() {
        guard let pwsid = draft.estimate?.pwsid else { area = nil; return }
        Task {
            area = await Task.detached { WaterSystemIndex.bundled?.areas.first { $0.pwsid == pwsid } }.value
        }
    }

    private func finish() {
        settings.homeLocation = draft.location
        settings.waterSourceEstimate = draft.estimate
        if let source = draft.source { settings.waterSource = source }
        // City water: start the utility report with the system the lookup found.
        if draft.source?.hasUtility == true, settings.utilityReport.utilityName.isEmpty,
           let name = draft.estimate?.systemName {
            settings.utilityReport.utilityName = name
        }
        if let county = draft.county ?? draft.location?.county { settings.county = county }
        settings.drafts.discard(draftKey)
        if mode == .firstLaunch {
            settings.infantInHome = draft.household.contains(.baby)
            settings.pregnantInHome = draft.household.contains(.pregnant)
            if settings.householdMembers.isEmpty {
                var members: [HouseholdMember] = []
                if draft.household.contains(.baby) {
                    var baby = HouseholdMember(); baby.ageBand = .infant; members.append(baby)
                }
                if draft.household.contains(.pregnant) {
                    var parent = HouseholdMember(); parent.pregnant = true; members.append(parent)
                }
                if draft.household.contains(.children) {
                    var child = HouseholdMember(); child.ageBand = .child; members.append(child)
                }
                settings.householdMembers = members
            }
            if draft.household.contains(.baby) { settings.activeModes.insert(.infant) }
            settings.hasCompletedOnboarding = true
        }
        DS.Haptics.success()
        if mode == .changeSource { dismiss() }
    }
}

// MARK: - Pieces

/// The home pin on a small map, with the water system's service area shaded.
struct SourceMap: View {
    let location: HomeLocation
    let area: WaterSystemArea?

    var body: some View {
        let home = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        Map(initialPosition: .region(MKCoordinateRegion(center: home, latitudinalMeters: 6000, longitudinalMeters: 6000)),
            interactionModes: []) {
            if let area {
                ForEach(Array(area.polygons.enumerated()), id: \.offset) { _, polygon in
                    MapPolygon(coordinates: polygon.outer.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                        .foregroundStyle(DS.Colors.accent.opacity(0.22))
                        .stroke(DS.Colors.accent, lineWidth: 1.5)
                }
            }
            Marker(String(localized: "Home"), systemImage: "house.fill", coordinate: home)
                .tint(DS.Colors.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(area.map { Text("Map: your home is inside \($0.displayName)'s service area") }
                            ?? Text("Map: your home"))
    }
}

/// High / Medium confidence with icon and words.
struct ConfidenceBadge: View {
    let confidence: WaterSourceEstimate.Confidence

    var body: some View {
        switch confidence {
        case .high: DS.StatusBadge(level: .good, text: String(localized: "High confidence"))
        case .medium: DS.StatusBadge(level: .fair, text: String(localized: "Medium confidence"))
        case .none: EmptyView()
        }
    }
}

/// How many private wells were tested in this area: a supporting signal shown as a short bar.
struct WellsTestedBar: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Colors.track)
                    Capsule().fill(DS.Colors.water)
                        .frame(width: geo.size.width * min(Double(count) / 200, 1))
                }
            }
            .frame(height: 8)
            Text("\(count) private wells tested in your area (1998–2019)")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
