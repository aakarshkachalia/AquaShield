//
//  FindTestingView.swift
//  AquaShield
//
//  Who to call for a test, and how to take each kind of sample. Lab and health department details are
//  samples to replace with real NC data (needsVerification = true); the user enters or confirms them.
//

import SwiftUI

/// A place that can test water. Bundled entries are samples only.
nonisolated struct TestingContact: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let url: URL?
    let source: SourceRef

    var needsVerification: Bool { source.needsVerification }

    static func samples(county: String?, source: WaterSource = .notSure) -> [TestingContact] {
        let countyName = county.map { String(localized: "\($0) County Health Department") }
            ?? String(localized: "Your county health department")
        return [
            TestingContact(id: "county", name: countyName,
                           detail: source.showsWellCare
                               ? String(localized: "Sample entry: most NC counties test private wells. Call to ask about kits, fees and free testing.")
                               : String(localized: "Sample entry: ask where to test your tap for lead and other concerns."),
                           url: WellResources.ncCountyHealthDepartments,
                           source: SourceRef(String(localized: "NC DHHS county health department list"),
                                             url: WellResources.ncCountyHealthDepartments.absoluteString)),
            TestingContact(id: "state-lab", name: String(localized: "NC State Laboratory of Public Health"),
                           detail: String(localized: "Sample entry: tests samples sent by county health departments."),
                           url: WellResources.ncStateLab,
                           source: SourceRef(String(localized: "NC State Laboratory of Public Health"),
                                             url: WellResources.ncStateLab.absoluteString)),
            TestingContact(id: "sample-lab", name: String(localized: "Sample Certified Lab A"),
                           detail: String(localized: "Placeholder. Replace with a lab certified by NC for drinking water."),
                           url: nil, source: SourceRef(String(localized: "Sample data — not a real lab"))),
        ]
    }
}

/// How to take a sample, by test. General guidance; the lab's own instructions come first.
nonisolated struct SamplingInstruction: Identifiable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let steps: [String]
    let source: SourceRef

    static let all: [SamplingInstruction] = [
        SamplingInstruction(id: "bacteria", title: String(localized: "Bacteria (coliform, E. coli)"),
                            symbol: DS.Icon.category(.bacteria), steps: [
            String(localized: "Use the sterile bottle from the lab. Don't touch the inside or the cap."),
            String(localized: "Remove the faucet aerator and run cold water for 2 to 3 minutes."),
            String(localized: "Fill to the line, cap it, keep it cold, and get it to the lab within a day."),
        ], source: SourceRef(String(localized: "NC DHHS private well sampling guidance"))),
        SamplingInstruction(id: "lead", title: String(localized: "Lead and copper"),
                            symbol: DS.Icon.category(.metals), steps: [
            String(localized: "Take the first water out of the tap after it sat 6 hours or more, like first thing in the morning."),
            String(localized: "Don't run the water first. Use the kitchen tap you drink from."),
        ], source: SourceRef(String(localized: "EPA lead sampling guidance"))),
        SamplingInstruction(id: "nitrate", title: String(localized: "Nitrate, arsenic and other metals"),
                            symbol: DS.Icon.category(.nitrates), steps: [
            String(localized: "Run cold water for a few minutes, then fill the lab's bottle."),
            String(localized: "Keep it cold and deliver it when the lab says."),
        ], source: SourceRef(String(localized: "NC DHHS private well sampling guidance"))),
        SamplingInstruction(id: "pfas", title: String(localized: "PFAS"),
                            symbol: DS.Icon.category(.pfas), steps: [
            String(localized: "Use only the lab's PFAS bottle. Wash your hands and skip lotion first."),
            String(localized: "Keep the bottle away from nonstick pans, food wrappers and waterproof clothing."),
        ], source: SourceRef(String(localized: "NC DEQ / lab PFAS sampling guidance"))),
        SamplingInstruction(id: "radon", title: String(localized: "Radon in water"),
                            symbol: DS.Icon.category(.radioactive), steps: [
            String(localized: "Use the lab's vial. Fill it slowly with no air bubbles."),
            String(localized: "Send it the same day. Radon escapes from water quickly."),
        ], source: SourceRef(String(localized: "NC Radon Program"), url: WellResources.ncRadon.absoluteString)),
    ]
}

struct FindTestingView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                DS.InfoCard(systemImage: DS.Icon.test, title: String(localized: "Use a state-certified lab"),
                            message: Wording.adapt(String(localized: "Start with your county health department. Many test wells for free or low cost."), for: settings.waterSource),
                            level: nil)
                DSSectionTitle(String(localized: "Who to call"))
                ForEach(TestingContact.samples(county: settings.county, source: settings.waterSource)) { contact in
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text(contact.name).font(DS.Typography.headline)
                        Text(contact.detail).font(DS.Typography.subheadline).foregroundStyle(DS.Colors.textSecondary)
                        if contact.needsVerification {
                            FlagChip(text: String(localized: "Sample, needs verification"), systemImage: "questionmark.circle.fill")
                        }
                        if let url = contact.url {
                            Link(destination: url) {
                                Label("Open website", systemImage: "arrow.up.right.square")
                                    .frame(minHeight: DS.Size.tapTarget)
                            }
                        }
                    }
                    .foregroundStyle(DS.Colors.textPrimary)
                    .dsCard()
                }
                DSSectionTitle(String(localized: "How to take a sample"))
                Text("Your lab's instructions come first. These are the basics.")
                    .font(DS.Typography.body).foregroundStyle(DS.Colors.textSecondary)
                ForEach(SamplingInstruction.all) { instruction in
                    DS.InfoCard(systemImage: instruction.symbol, title: instruction.title,
                                message: instruction.steps.first,
                                learnMore: instruction.steps.dropFirst().joined(separator: "\n").nilIfEmpty)
                }
                DisclaimerFooter()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("Find testing")
    }
}

extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
