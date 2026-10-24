//
//  ModesView.swift
//  ClearWellNC
//
//  The testing calendar, "something happened" retest prompts, and the three modes: flood/hurricane,
//  baby in the home, and boil-water advisory.
//

import SwiftData
import SwiftUI

struct ModesView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DSSectionTitle(String(localized: "Testing calendar"))
                if snapshot.testsDue.isEmpty {
                    Text("Add a test result to start your calendar.")
                        .font(DS.Typography.body).foregroundStyle(DS.Colors.textSecondary)
                }
                ForEach(snapshot.testsDue) { due in
                    let overdue = due.isOverdue(at: snapshot.now)
                    DS.InfoCard(systemImage: overdue ? "exclamationmark.circle.fill" : "calendar",
                                title: "\(due.title): \(overdue ? String(localized: "due now") : due.due.formatted(date: .abbreviated, time: .omitted))",
                                message: due.detail, level: overdue ? .fair : nil)
                }

                DSSectionTitle(String(localized: "Something happened?"))
                Text("Tell us, and we'll remind you to retest.")
                    .font(DS.Typography.body).foregroundStyle(DS.Colors.textSecondary)
                ForEach(RetestEvent.Kind.allCases, id: \.self) { kind in
                    DS.ActionCard(systemImage: icon(kind), title: kind.label(for: settings.waterSource),
                                  subtitle: lastLogged(kind).map { String(localized: "Logged \($0.formatted(date: .abbreviated, time: .omitted))") }) {
                        log(kind)
                    }
                }

                DSSectionTitle(String(localized: "Modes"))
                ForEach(WaterMode.allCases, id: \.self) { mode in
                    if mode != .flood || settings.waterSource.showsWellCare {
                        modeCard(mode)
                    }
                }
                if settings.activeModes.contains(.flood) && settings.waterSource.showsWellCare { floodGuidance }
                if settings.activeModes.contains(.infant) { infantGuidance }
                if settings.activeModes.contains(.boilWater) { boilGuidance }
                MedicalDisclaimer()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("Testing and modes")
    }

    private func modeCard(_ mode: WaterMode) -> some View {
        let on = settings.activeModes.contains(mode)
        return DS.ChoiceCard(title: mode.label, subtitle: on ? String(localized: "On") : String(localized: "Off"),
                             systemImage: mode.symbol, isSelected: on) {
            if on {
                settings.activeModes.remove(mode)
            } else {
                settings.activeModes.insert(mode)
                if mode == .flood { log(.flood) }
            }
        }
        .accessibilityIdentifier("mode.\(mode.rawValue)")
    }

    private var floodGuidance: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DS.InfoCard(systemImage: "xmark.octagon.fill", title: String(localized: "Don't drink the well water yet"),
                        message: String(localized: "Use bottled water until a bacteria test after the flood is clear."), level: .unsafe)
            NavigationLink { StormModeView() } label: {
                NavigationCardLabel(title: Text("Flood checklist and shock chlorination"),
                                    subtitle: Text("Stay safe, disinfect the well, then retest."),
                                    systemImage: "checklist")
            }
            .buttonStyle(.plain)
        }
    }

    private var infantGuidance: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DS.InfoCard(systemImage: DS.Icon.contaminant(.nitrate), title: String(localized: "Nitrate and formula"),
                        message: String(localized: "Use water tested under 10 mg/L nitrate, or bottled water, for formula."),
                        learnMore: String(localized: "Babies under 6 months are most at risk from nitrate. Boiling does not remove nitrate — it concentrates it."))
            DS.InfoCard(systemImage: DS.Icon.contaminant(.lead), title: String(localized: "Lead"),
                        message: String(localized: "Use cold water for formula. Run the tap first if it sat for hours."),
                        learnMore: String(localized: "No level of lead is known to be safe for children. Test your tap, and use a filter certified for lead if it's found."))
        }
    }

    private var boilGuidance: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            DS.InfoCard(systemImage: "flame.fill", title: String(localized: "Boiling helps with germs"),
                        message: String(localized: "Bring water to a rolling boil for 1 minute, then let it cool."), level: .good)
            DS.InfoCard(systemImage: "xmark.circle.fill", title: String(localized: "Boiling doesn't help with chemicals"),
                        message: String(localized: "Don't boil for nitrate, lead, arsenic or PFAS. It can concentrate them."),
                        learnMore: String(localized: "For those, use bottled water or a filter certified for that contaminant."), level: .fair)
        }
    }

    private func icon(_ kind: RetestEvent.Kind) -> String {
        switch kind {
        case .flood: DS.Icon.alert(.flood)
        case .repair: "wrench.and.screwdriver.fill"
        case .tasteColorSmell: "nose.fill"
        }
    }

    private func lastLogged(_ kind: RetestEvent.Kind) -> Date? {
        settings.retestEvents.filter { $0.kind == kind }.map(\.date).max()
    }

    private func log(_ kind: RetestEvent.Kind) {
        settings.retestEvents.append(RetestEvent(kind: kind, date: .now))
        DS.Haptics.selection()
    }
}

// MARK: - Home and plumbing

nonisolated enum HomeStep: String, Codable, Hashable, Sendable, CaseIterable {
    case built, pipes, well, taps
}

/// Year built, service line, plumbing, well and septic, and how many showers and sinks.
struct HomeProfileFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var profile = HomeProfile()
    @State private var flow = StepFlow(root: HomeStep.built)
    @State private var loaded = false

    private var order: [HomeStep] {
        settings.waterSource.showsWellCare ? HomeStep.allCases : HomeStep.allCases.filter { $0 != .well }
    }

    var body: some View {
        StepFlowContainer(flow: $flow, progress: { _ in flow.progress(in: order) }, primaryAction: action,
                          onClose: { dismiss() }) { step in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    page(step)
                    PrivacyNote().padding(.top, DS.Space.l)
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Your home")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            profile = settings.homeProfile
        }
    }

    private func action(_ step: HomeStep) -> StepAction? {
        step == order.last
            ? StepAction(title: "Save", systemImage: "checkmark", identifier: "flow.save") {
                settings.homeProfile = profile
                DS.Haptics.success()
                dismiss()
            }
            : StepAction(title: "Next", systemImage: "arrow.right") { flow.advance(in: order) }
    }

    @ViewBuilder
    private func page(_ step: HomeStep) -> some View {
        switch step {
        case .built:
            heading(String(localized: "When was your home built?"), String(localized: "Homes built before 1986 may have lead solder."))
            DS.ChoiceCard(title: String(localized: "Before 1986"), systemImage: "clock.arrow.circlepath",
                          isSelected: profile.yearBuilt.map { $0 < 1986 } == true) { profile.yearBuilt = 1980 }
            DS.ChoiceCard(title: String(localized: "1986 or later"), systemImage: "calendar",
                          isSelected: profile.yearBuilt.map { $0 >= 1986 } == true) { profile.yearBuilt = 2000 }
            DS.ChoiceCard(title: String(localized: "Not sure"), systemImage: "questionmark",
                          isSelected: profile.yearBuilt == nil) { profile.yearBuilt = nil }
        case .pipes:
            heading(String(localized: "What are your pipes made of?"), String(localized: "Look where the water line enters the house."))
            if settings.waterSource.showsCityContent {
                Text("Pipe from the street (service line)").font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
                ForEach(HomeProfile.ServiceLine.allCases, id: \.self) { line in
                    DS.ChoiceCard(title: line.label, isSelected: profile.serviceLine == line) { profile.serviceLine = line }
                }
            }
            Text("Pipes inside the house").font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
            ForEach(HomeProfile.Plumbing.allCases, id: \.self) { pipe in
                DS.ChoiceCard(title: pipe.label, isSelected: profile.plumbing == pipe) { profile.plumbing = pipe }
            }
        case .well:
            heading(String(localized: "About your well"), String(localized: "Skip anything you don't know."))
            number(String(localized: "Well depth (feet)"), $profile.wellDepthFeet)
            number(String(localized: "Year drilled"), Binding(get: { profile.wellYearDrilled.map(Double.init) },
                                                             set: { profile.wellYearDrilled = $0.map { Int($0) } }))
            number(String(localized: "Distance to septic system (feet)"), $profile.septicDistanceFeet)
        case .taps:
            heading(String(localized: "Showers and sinks"), String(localized: "Each one gets its own score if it has a filter."))
            Stepper("Showers: \(profile.showerCount)", value: $profile.showerCount, in: 1...10)
                .font(DS.Typography.body).frame(minHeight: DS.Size.tapTarget).dsCard(padding: DS.Space.m)
            Stepper("Bathroom sinks: \(profile.bathroomSinkCount)", value: $profile.bathroomSinkCount, in: 1...10)
                .font(DS.Typography.body).frame(minHeight: DS.Size.tapTarget).dsCard(padding: DS.Space.m)
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).font(DS.Typography.title).foregroundStyle(DS.Colors.textPrimary).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(DS.Typography.body).foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(.bottom, DS.Space.s)
    }

    private func number(_ label: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(label).font(DS.Typography.body).foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            TextField("—", value: value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
        .frame(minHeight: DS.Size.tapTarget)
        .dsCard(padding: DS.Space.m)
    }
}
