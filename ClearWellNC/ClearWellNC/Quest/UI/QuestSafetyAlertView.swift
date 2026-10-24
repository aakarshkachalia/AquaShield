//
//  QuestSafetyAlertView.swift
//  ClearWellNC
//
//  Shown BEFORE the game when a health limit is met or bacteria are found. Deliberately plain:
//  no points, no game styling. The player must tap "I understand" to continue to the game.
//

import SwiftUI

struct QuestSafetyAlertView: View {
    let report: QuestReport
    let onUnderstand: () -> Void

    private var findings: [Interpretation] { QuestEngine.safetyFindings(for: report) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.statusAbove)
                        .accessibilityHidden(true)
                    Text("Important: your test found a problem")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Read this before anything else.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("What we found")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(findings, id: \.id) { finding in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.statusAbove)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(finding.id.info.name).font(.body.weight(.semibold))
                                Text("\(finding.readingText) · \(finding.chipLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("What to do now")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    // SOURCE vr-061 (needs verification, see VerificationRegister.json): CDC / NC DHHS guidance after a positive E. coli test: use bottled (or boiled) water
                    // for drinking, cooking and brushing teeth until the well is disinfected and retested.
                    Text(QuestEngine.eColiPositive(report)
                         ? String(localized: "Don't drink untreated water. Use bottled water for drinking, cooking and brushing teeth.")
                         : String(localized: "Don't drink this water untreated. Use bottled water for drinking and cooking until it's fixed."))
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(actions, id: \.self) { action in
                        Label {
                            Text(action).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 0) {
                    Link(destination: WellResources.ncCountyHealthDepartments) {
                        Label("Call your county health department", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    Divider()
                    Link(destination: WellResources.ncdhhsPrivateWells) {
                        Label("NC DHHS: private well safety", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .font(.body.weight(.semibold))
                .card()

                if let first = findings.first {
                    NavigationLink {
                        HelpFinderView(filter: .contaminant(first.id))
                    } label: {
                        Label("Get help paying for a fix", systemImage: "dollarsign.circle.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityHint(Text("Shows programs that may test or pay for treatment"))
                }

                Button(action: onUnderstand) {
                    Text("I understand")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint(Text("Continues to Report Quest"))
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
    }

    /// Each finding's own advice, without repeats.
    private var actions: [String] {
        var seen = Set<String>()
        return findings
            .map { QuestText.firstSentences($0.id.info.actionIfAbove, max: 2) }
            .filter { seen.insert($0).inserted }
    }
}
