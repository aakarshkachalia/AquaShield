//
//  HouseholdView.swift
//  AquaShield
//
//  Household members (nickname only, on this device), each with exposure-risk flags, hard safety alerts,
//  and "worth discussing with your doctor" notes. Never a diagnosis.
//

import SwiftData
import SwiftUI

struct HouseholdView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var editing: HouseholdMember?

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                ForEach(snapshot.alerts) { SafetyAlertCard(alert: $0) }
                if settings.householdMembers.isEmpty {
                    DS.EmptyStateView(systemImage: "person.2.fill",
                                      message: String(localized: "Add the people who drink this water to see risks for each one."),
                                      actionTitle: String(localized: "Add a person"), actionImage: "plus") {
                        editing = HouseholdMember()
                    }
                } else {
                    ForEach(settings.householdMembers) { member in
                        NavigationLink {
                            MemberDetailView(memberID: member.id)
                        } label: {
                            memberRow(member, exposure: snapshot.exposures[member.id])
                        }
                        .buttonStyle(DS.PressableCardStyle())
                    }
                    Button { editing = HouseholdMember() } label: { Label("Add a person", systemImage: "plus") }
                        .buttonStyle(DS.SecondaryButtonStyle())
                        .accessibilityIdentifier("household.add")
                }
                PrivacyNote()
                MedicalDisclaimer()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("Household")
        .fullScreenCover(item: $editing) { member in
            MemberFlow(member: member)
        }
    }

    private func memberRow(_ member: HouseholdMember, exposure: MemberExposure?) -> some View {
        HStack(spacing: DS.Space.m) {
            MemberAvatar(member: member, flagged: !(exposure?.flags.isEmpty ?? true))
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(member.displayName).font(DS.Typography.headline)
                Text(member.ageBand.label).font(DS.Typography.subheadline).foregroundStyle(DS.Colors.textSecondary)
            }
            .foregroundStyle(DS.Colors.textPrimary)
            Spacer(minLength: 0)
            let flags = exposure?.flags.count ?? 0
            if flags > 0 {
                FlagChip(text: String(localized: "\(flags) to check"))
            } else {
                DS.StatusBadge(level: .good, text: String(localized: "No flags"))
            }
        }
        .dsCard()
    }
}

struct MemberDetailView: View {
    let memberID: UUID

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var editing: HouseholdMember?

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        let member = settings.householdMembers.first { $0.id == memberID }
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if let member, let exposure = snapshot.exposures[member.id] {
                    ForEach(snapshot.alerts.filter { $0.memberIDs.contains(member.id) }) { SafetyAlertCard(alert: $0) }
                    if exposure.flags.isEmpty {
                        DS.InfoCard(systemImage: DS.Level.good.symbol, title: String(localized: "No risk flags right now"),
                                    message: String(localized: "Based on the tests on file for their drinking water."), level: .good)
                    } else {
                        DSSectionTitle(String(localized: "Worth checking"))
                        ForEach(exposure.flags) { flag in
                            DS.InfoCard(systemImage: DS.Icon.recommendedTestFallback(flag.target),
                                        title: flag.isUntested ? String(localized: "\(flag.target.name) hasn't been tested")
                                                               : String(localized: "\(flag.target.name) is high"),
                                        message: flag.reason, level: flag.isUntested ? .fair : .unsafe)
                        }
                    }
                    if !exposure.notes.isEmpty {
                        DSSectionTitle(String(localized: "To discuss with a doctor"))
                        ForEach(exposure.notes) { note in
                            DS.InfoCard(systemImage: "stethoscope", title: note.symptom.label, message: note.text)
                        }
                    }
                    if !exposure.dosePerKg.isEmpty {
                        DS.InfoCard(systemImage: "scalemass.fill", title: String(localized: "Estimated daily amount"),
                                    message: String(localized: "From \(formatNumber(member.dailyLiters)) liters a day."),
                                    learnMore: exposure.dosePerKg.sorted { $0.key.rawValue < $1.key.rawValue }.map { target, dose in
                                        "\(target.name): \(formatNumber(dose)) \(ReadingUnit.canonical(for: target).doseLabel)"
                                    }.joined(separator: "\n"))
                    }
                    Button { editing = member } label: { Label("Edit", systemImage: "pencil") }
                        .buttonStyle(DS.SecondaryButtonStyle())
                    Button("Remove \(member.displayName)", role: .destructive) {
                        settings.householdMembers.removeAll { $0.id == member.id }
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
                }
                PrivacyNote()
                MedicalDisclaimer()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle(member?.displayName ?? "")
        .fullScreenCover(item: $editing) { MemberFlow(member: $0) }
    }
}

extension DS.Icon {
    /// A contaminant category icon for any claim target.
    static func recommendedTestFallback(_ target: ClaimTarget) -> String {
        if let id = target.contaminantID { return contaminant(id) }
        return target.isMicrobial ? category(.bacteria) : test
    }
}

// MARK: - Add or edit a person

nonisolated enum MemberStep: String, Codable, Hashable, Sendable, CaseIterable {
    case basics, special, water, symptoms, review
}

struct MemberFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State var member: HouseholdMember
    @State private var flow = StepFlow(root: MemberStep.basics)

    private let order = MemberStep.allCases

    var body: some View {
        StepFlowContainer(flow: $flow, progress: { _ in flow.progress(in: order) },
                          primaryAction: action, onClose: { dismiss() }) { step in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    page(step)
                    PrivacyNote().padding(.top, DS.Space.l)
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle(member.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func action(_ step: MemberStep) -> StepAction? {
        step == order.last
            ? StepAction(title: "Save", systemImage: "checkmark", identifier: "flow.save") { save() }
            : StepAction(title: "Next", systemImage: "arrow.right") { flow.advance(in: order) }
    }

    @ViewBuilder
    private func page(_ step: MemberStep) -> some View {
        switch step {
        case .basics:
            heading(String(localized: "Who is this?"), String(localized: "A nickname is enough. It stays on this phone."))
            TextField("Nickname", text: $member.nickname)
                .font(DS.Typography.body)
                .padding(.horizontal, DS.Space.l)
                .frame(minHeight: DS.Size.largeTapTarget)
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                .accessibilityIdentifier("member.nickname")
            ForEach(HouseholdMember.AgeBand.allCases, id: \.self) { band in
                DS.ChoiceCard(title: band.label, isSelected: member.ageBand == band) { member.ageBand = band }
            }
            Picker("Sex", selection: $member.sex) {
                ForEach(HouseholdMember.Sex.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        case .special:
            heading(String(localized: "Anything that raises risk?"), String(localized: "Pick all that apply."))
            if member.ageBand == .infant {
                toggleCard(String(localized: "Drinks formula made with tap water"), "waterbottle.fill", $member.infantOnFormula)
            } else if member.ageBand == .adult || member.ageBand == .teen {
                toggleCard(String(localized: "Pregnant"), "figure.stand", $member.pregnant)
                toggleCard(String(localized: "Breastfeeding"), "heart.fill", $member.breastfeeding)
            }
            toggleCard(String(localized: "Weakened immune system"), "cross.case.fill", $member.immunocompromised)
            toggleCard(String(localized: "Kidney disease"), "drop.halffull", $member.kidneyDisease)
            toggleCard(String(localized: "Eczema"), "hand.raised.fill", $member.eczema)
        case .water:
            heading(String(localized: "How do they use the water?"), String(localized: "Rough guesses are fine."))
            DS.ChoiceCard(title: String(localized: "Drinks from the kitchen tap"), systemImage: "spigot.fill",
                          isSelected: member.drinkingSource == .tap(.kitchen)) { member.drinkingSource = .tap(.kitchen) }
            DS.ChoiceCard(title: String(localized: "Drinks fridge water"), systemImage: "refrigerator.fill",
                          isSelected: member.drinkingSource == .tap(TapLocation(kind: .fridge))) {
                member.drinkingSource = .tap(TapLocation(kind: .fridge))
            }
            DS.ChoiceCard(title: String(localized: "Drinks bottled water"), systemImage: "waterbottle.fill",
                          isSelected: member.drinkingSource == .bottled) { member.drinkingSource = .bottled }
            stepper(String(localized: "Glasses of water a day"),
                    value: Binding(get: { Int(((member.drinkingLitersPerDay ?? member.ageBand.typicalLitersPerDay) / 0.25).rounded()) },
                                   set: { member.drinkingLitersPerDay = Double($0) * 0.25 }), range: 0...20)
            stepper(String(localized: "Minutes per shower"),
                    value: Binding(get: { Int(member.showerMinutes) }, set: { member.showerMinutes = Double($0) }), range: 0...60)
            HStack {
                Text("Weight in kg (optional)").font(DS.Typography.body)
                Spacer()
                TextField("—", value: $member.weightKg, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }
            .frame(minHeight: DS.Size.tapTarget)
            Text("With weight, we can estimate a daily amount. Without it, we skip that.")
                .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
        case .symptoms:
            heading(String(localized: "Symptoms (optional)"),
                    String(localized: "We only mention a symptom if it matches something high or untested here."))
            ForEach(Symptom.BodySystem.allCases, id: \.self) { system in
                Text(system.label).font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
                ForEach(Symptom.allCases.filter { $0.system == system }) { symptom in
                    DS.ChoiceCard(title: symptom.label, isSelected: member.symptoms.contains(symptom)) {
                        if member.symptoms.contains(symptom) { member.symptoms.remove(symptom) } else { member.symptoms.insert(symptom) }
                    }
                }
            }
        case .review:
            heading(String(localized: "All set"), ExposureRisk.disclaimer)
            DS.InfoCard(systemImage: "person.fill", title: member.displayName, message: member.ageBand.label)
        }
    }

    private func save() {
        if let index = settings.householdMembers.firstIndex(where: { $0.id == member.id }) {
            settings.householdMembers[index] = member
        } else {
            settings.householdMembers.append(member)
        }
        if member.ageBand == .infant { settings.activeModes.insert(.infant) }
        DS.Haptics.success()
        dismiss()
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).font(DS.Typography.title).foregroundStyle(DS.Colors.textPrimary).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(DS.Typography.body).foregroundStyle(DS.Colors.textSecondary)
        }
        .padding(.bottom, DS.Space.s)
    }

    private func toggleCard(_ title: String, _ symbol: String, _ isOn: Binding<Bool>) -> some View {
        DS.ChoiceCard(title: title, systemImage: symbol, isSelected: isOn.wrappedValue) { isOn.wrappedValue.toggle() }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            Text("\(title): \(value.wrappedValue)").font(DS.Typography.body)
        }
        .frame(minHeight: DS.Size.tapTarget)
        .dsCard(padding: DS.Space.m)
    }
}
