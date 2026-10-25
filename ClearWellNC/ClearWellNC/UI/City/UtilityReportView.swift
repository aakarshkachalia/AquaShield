//
//  UtilityReportView.swift
//  ClearWellNC
//
//  City/public water: copy numbers from your utility's yearly water quality report (CCR) and see each one
//  against its federal limit, plus what your utility's numbers can't tell you (your own pipes).
//

import SwiftUI

struct UtilityReportView: View {
    @Environment(AppSettings.self) private var settings
    @State private var editing = false

    private var report: UtilityReport { settings.utilityReport }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if report.isEmpty {
                    DS.EmptyStateView(systemImage: "doc.text.fill",
                                      message: String(localized: "Add the numbers from your utility's yearly water report."),
                                      actionTitle: String(localized: "Add my report"), actionImage: "plus") {
                        editing = true
                    }
                    Link(destination: WellResources.epaConsumerConfidenceReports) {
                        Label("Find your water report", systemImage: "arrow.up.right.square")
                            .font(DS.Typography.subheadline.weight(.semibold))
                            .frame(minHeight: DS.Size.tapTarget)
                    }
                } else {
                    summary
                    findings
                }
                CityTopicCards()
                PrivacyNote()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("My water utility")
        .toolbar {
            if !report.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                }
            }
        }
        .sheet(isPresented: $editing) {
            UtilityReportForm(report: report) { settings.utilityReport = $0 }
        }
    }

    private var summary: some View {
        let above = UtilityReportRules.findings(for: report).filter(\.isAbove)
        return DS.InfoCard(systemImage: above.isEmpty ? DS.Level.good.symbol : DS.Level.unsafe.symbol,
                           title: above.isEmpty
                               ? String(localized: "Your utility's numbers meet federal limits")
                               : String(localized: "\(above.count) of your utility's numbers are over a limit"),
                           message: [report.utilityName, report.reportYear.map { String($0) }]
                               .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "),
                           level: above.isEmpty ? .good : .unsafe)
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("From your report")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(UtilityReportRules.findings(for: report)) { finding in
                DS.LevelMeter(name: finding.name,
                              level: finding.isAbove ? .unsafe : (finding.ratio >= 0.5 ? .fair : .good),
                              valueText: "\(formatNumber(finding.value)) \(finding.limit.unit)",
                              limitText: "\(formatNumber(finding.limit.value)) \(finding.limit.unit)",
                              ratio: finding.ratio)
                    .dsCard()
            }
            if report.listedViolations == true {
                DS.InfoCard(systemImage: "exclamationmark.bubble.fill",
                            title: String(localized: "Your report lists a violation"),
                            message: String(localized: "Call your utility and ask what they're doing about it."),
                            level: .fair)
            }
            Text("These are your utility's numbers, not your tap's. Pipes inside your home can add lead.")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Colors.textSecondary)
        }
    }
}

/// Lead pipes, disinfection byproducts and boil-water advisories, for anyone on city water.
struct CityTopicCards: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Good to know")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            DS.InfoCard(systemImage: DS.Icon.contaminant(.lead), title: String(localized: "Lead pipes and plumbing"),
                        message: String(localized: "Homes built before 1986 may have lead pipes or solder."),
                        learnMore: String(localized: "Your utility can tell you if your street has a lead service line, the pipe from the main to your house. Inside, older solder and brass faucets can add lead. Run cold water for 30 seconds before drinking, use only cold water for cooking, and test your own tap."))
            DS.InfoCard(systemImage: "flask.fill", title: String(localized: "Disinfection byproducts"),
                        message: String(localized: "Made when chlorine mixes with natural matter in water."),
                        learnMore: String(localized: "Trihalomethanes (TTHM) and haloacetic acids (HAA5) are limited because years of drinking water above the limit may raise cancer risk. Your utility tests for them. A carbon filter certified for them can lower them at your tap."))
            DS.InfoCard(systemImage: "flame.fill", title: String(localized: "Boil-water advisories"),
                        message: String(localized: "When your utility says boil, boil water 1 minute before drinking."),
                        learnMore: String(localized: "Boiling kills germs. It does not remove lead, nitrate or chemicals like PFAS, and can concentrate them. Follow your utility's notice for when it ends, then run your taps for a few minutes."))
        }
    }
}

/// Shown on every screen that collects health or household information.
struct PrivacyNote: View {
    var body: some View {
        Label("Stays on this phone. \(AppName.display) never uploads your health or household information.",
              systemImage: "lock.fill")
            .font(DS.Typography.footnote)
            .foregroundStyle(DS.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Enter or edit the report's values.
struct UtilityReportForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var report: UtilityReport
    let onSave: (UtilityReport) -> Void

    var body: some View {
        NavigationStack {
            Form { Group {
                Section {
                    TextField("Utility name", text: $report.utilityName)
                    TextField("Report year", value: $report.reportYear, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    TextField("Link to the report (optional)", text: $report.reportURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Utilities post this every year, often called a Consumer Confidence Report.")
                }
                Section {
                    number("Lead, 90th percentile", unit: "ppb", value: $report.leadP90PPB)
                    number("Copper, 90th percentile", unit: "mg/L", value: $report.copperP90MgL)
                    number("TTHM", unit: "ppb", value: $report.tthmPPB)
                    number("HAA5", unit: "ppb", value: $report.haa5PPB)
                    number("PFOA", unit: "ppt", value: $report.pfoaPPT)
                    number("PFOS", unit: "ppt", value: $report.pfosPPT)
                    number("Nitrate", unit: "mg/L", value: $report.nitrateMgL)
                } header: {
                    Text("Numbers from the report")
                } footer: {
                    Text("Leave blank anything your report doesn't list. Use the highest number shown.")
                }
                Section {
                    Picker("Any violations listed?", selection: $report.listedViolations) {
                        Text("Not sure").tag(Bool?.none)
                        Text("Yes").tag(Bool?.some(true))
                        Text("No").tag(Bool?.some(false))
                    }
                }
            }
            .listRowBackground(M.Colors.surface)
            }
            .modernistList()
            .navigationTitle("Water report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        DS.Haptics.success()
                        onSave(report)
                        dismiss()
                    }
                }
            }
        }
    }

    private func number(_ title: LocalizedStringKey, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(DS.Colors.textSecondary)
        }
    }
}
