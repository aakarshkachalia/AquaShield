//
//  StormModeView.swift
//  ClearWellNC
//
//  "My well flooded": a step-by-step checklist, saved on the device.
//

import SwiftUI

nonisolated enum StormChecklist {
    struct Step: Identifiable, Sendable {
        let id: Int
        let title: String
        let detail: String
        let symbol: String
    }

    // VERIFY: steps follow CDC / NC DHHS private-well guidance after flooding.
    static let steps: [Step] = [
        Step(id: 1, title: String(localized: "Don't drink or cook with your well water"),
             detail: String(localized: "Use bottled water for drinking, cooking, brushing teeth and baby formula until your well is tested."),
             symbol: "waterbottle.fill"),
        Step(id: 2, title: String(localized: "Check for damage around the wellhead"),
             detail: String(localized: "Look for a loose cap, cracks or debris. Don't use electricity or the pump near standing water."),
             symbol: "bolt.slash.fill"),
        Step(id: 3, title: String(localized: "Disinfect the well (shock chlorination)"),
             detail: String(localized: "Follow your county health department's instructions, or hire a licensed well contractor."),
             symbol: "drop.degreesign.fill"),
        Step(id: 4, title: String(localized: "Test for bacteria after disinfecting"),
             detail: String(localized: "Use a lab test from your county health department once the chlorine has been flushed out."),
             symbol: "testtube.2"),
        Step(id: 5, title: String(localized: "Retest in 1–2 weeks"),
             detail: String(localized: "A second bacteria test confirms the well stayed clean."),
             symbol: "calendar.badge.clock"),
    ]

    static func progress(_ checked: Set<Int>) -> Double {
        Double(checked.intersection(steps.map(\.id)).count) / Double(steps.count)
    }
}

struct StormModeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var store
    @State private var library = HelpLibrary.loadBundled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                InfoCard(style: .danger, systemImage: "exclamationmark.octagon.fill",
                         title: String(localized: "If your wellhead was underwater, don't drink the water"),
                         message: String(localized: "Floodwater can carry germs and chemicals into your well. Work through these steps in order."))

                VStack(alignment: .leading, spacing: 0) {
                    let done = settings.stormChecked.count
                    Text("\(done) of \(StormChecklist.steps.count) done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.bottom, Spacing.s)
                    ForEach(StormChecklist.steps) { step in
                        checkRow(step)
                        if step.id != StormChecklist.steps.last?.id { Divider() }
                    }
                }
                .card()

                SectionHeader(title: "Get help")
                ForEach(["post-flood-kits", "county-health"], id: \.self) { id in
                    if let program = library.program(id: id) {
                        HelpProgramCard(match: HelpMatch(program: program, reasons: id == "post-flood-kits"
                                                         ? [String(localized: "You're dealing with a flooded well.")] : []),
                                        county: settings.county,
                                        related: program.relatedProgramID.flatMap(library.program(id:)))
                    }
                }

                if !settings.stormChecked.isEmpty {
                    SecondaryButton(title: "Clear checklist", systemImage: "arrow.counterclockwise") {
                        settings.stormChecked = []
                    }
                }

                DisclaimerFooter(lead: String(localized: "Follow your county health department's instructions. This checklist doesn't replace them."))
            }
            .screenContainer()
        }
        .background(Color.appBackground)
        .navigationTitle("My well flooded")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func checkRow(_ step: StormChecklist.Step) -> some View {
        let checked = settings.stormChecked.contains(step.id)
        return Button {
            if checked { settings.stormChecked.remove(step.id) } else { settings.stormChecked.insert(step.id) }
        } label: {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(checked ? Color.statusSafe : Color.brandPrimary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("\(step.id). \(step.title)")
                        .font(.headline)
                        .strikethrough(checked)
                    Text(step.detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.textPrimary)
            .padding(.vertical, Spacing.m)
            .frame(minHeight: TapTarget.minimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .accessibilityValue(Text(checked ? "Done" : "Not done"))
        .accessibilityHint(Text("Double-tap to mark this step done"))
    }
}

/// Home card shown when the Risk Check reported flooding.
struct StormHomeCard: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if settings.riskAnswers?.flooding == true {
            NavigationLink {
                StormModeView()
            } label: {
                NavigationCardLabel(
                    title: Text("My well flooded"),
                    subtitle: Text("\(settings.stormChecked.count) of \(StormChecklist.steps.count) steps done. Don't drink the water until it's tested."),
                    systemImage: "cloud.heavyrain.fill")
            }
            .buttonStyle(.plain)
        }
    }
}
