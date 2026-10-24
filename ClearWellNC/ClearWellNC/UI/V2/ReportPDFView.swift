//
//  ReportPDFView.swift
//  ClearWellNC
//
//  A shareable PDF made on the phone (nothing is uploaded): scores per tap, readings vs limits with
//  sources, filters and next steps, plus the household members the user chooses to include.
//

import SwiftData
import SwiftUI

struct ReportExportView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var included: Set<UUID> = []
    @State private var pdfURL: URL?

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Text("Make a PDF to share with a doctor, landlord, well contractor or utility.")
                    .font(DS.Typography.body).foregroundStyle(DS.Colors.textSecondary)
                if !snapshot.members.isEmpty {
                    DSSectionTitle(String(localized: "Include people"))
                    ForEach(snapshot.members) { member in
                        DS.ChoiceCard(title: member.displayName, subtitle: member.ageBand.label, systemImage: "person.fill",
                                      isSelected: included.contains(member.id)) {
                            if included.contains(member.id) { included.remove(member.id) } else { included.insert(member.id) }
                            pdfURL = nil
                        }
                    }
                    Text("Only nicknames and risk flags are included, never symptoms.")
                        .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                }
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up") }
                        .buttonStyle(DS.PrimaryButtonStyle())
                } else {
                    Button {
                        pdfURL = Self.render(ReportPDFPage(snapshot: snapshot, includedMembers: included))
                        DS.Haptics.success()
                    } label: {
                        Label("Make PDF", systemImage: "doc.richtext")
                    }
                    .buttonStyle(DS.PrimaryButtonStyle())
                    .accessibilityIdentifier("report.makePDF")
                }
                PrivacyNote()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle("Share a report")
    }

    /// Renders a US Letter PDF into the temporary folder (cleared by iOS; nothing leaves the phone
    /// unless the user shares it).
    @MainActor
    static func render(_ page: ReportPDFPage) -> URL? {
        let width: CGFloat = 612
        let renderer = ImageRenderer(content: page.frame(width: width).environment(\.colorScheme, .light))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        let name = "\(AppName.display) report \(Date.now.formatted(.iso8601.year().month().day())).pdf"
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: width, height: max(size.height, 792)))
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

/// The printed page. Light colors only, plain layout.
struct ReportPDFPage: View {
    let snapshot: WaterSnapshot
    let includedMembers: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(AppName.display) water report").font(.title.bold())
                Text("\(snapshot.source.settingName) · made \(snapshot.now.formatted(date: .long, time: .omitted))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            section(String(localized: "Scores")) {
                ForEach(snapshot.taps.values.sorted { $0.tap.rawValue < $1.tap.rawValue }, id: \.tap) { tap in
                    Text("\(tap.tap.name): \(tap.score)/100, \(tap.band.label). Confidence: \(tap.confidenceText).")
                }
            }
            if let drinking = snapshot.drinking {
                section(String(localized: "Readings at the kitchen tap")) {
                    ForEach(drinking.items.filter { $0.level != .notScored }) { item in
                        let unit = ReadingUnit.canonical(for: item.target).label
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.target.name): \(item.present.map { $0 ? String(localized: "found") : String(localized: "not found") } ?? item.residual.map { "\(formatNumber($0)) \(unit)" } ?? "—")")
                                .font(.body.weight(.semibold))
                            if let limit = item.limit {
                                Text("Limit \(limit.value > 0 ? "\(formatNumber(limit.value)) \(unit)" : String(localized: "none detected")) (\(limit.source)). \(item.explanation)")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            if !snapshot.filters.isEmpty {
                section(String(localized: "Filters")) {
                    ForEach(snapshot.filters) { filter in
                        let certs = Set((filter.product?.claims ?? []).map(\.standard.name)).sorted().joined(separator: ", ")
                        Text("\(filter.name) (\(filter.location.name)): \(certs.isEmpty ? String(localized: "uncertified") : certs)")
                    }
                }
            }
            let members = snapshot.members.filter { includedMembers.contains($0.id) }
            if !members.isEmpty {
                section(String(localized: "Household")) {
                    ForEach(members) { member in
                        let flags = snapshot.exposures[member.id]?.flags ?? []
                        Text("\(member.displayName), \(member.ageBand.label): \(flags.isEmpty ? String(localized: "no risk flags") : flags.map { $0.isUntested ? String(localized: "\($0.target.name) untested") : String(localized: "\($0.target.name) high") }.joined(separator: ", "))")
                    }
                }
            }
            section(String(localized: "Next steps")) {
                ForEach(snapshot.alerts) { Text("• \($0.title). \($0.message)") }
                ForEach(snapshot.plan.fixes) { Text("• \($0.title). \($0.detail)") }
                if snapshot.alerts.isEmpty && snapshot.plan.fixes.isEmpty { Text("• \(snapshot.topNextStep)") }
            }
            Text("\(ExposureRisk.disclaimer) \(DisclaimerFooter.standardText) Limits are from EPA and NC sources listed in the app and still need verification before release.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .foregroundStyle(.black)
        .padding(36)
        .background(.white)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content().font(.callout)
        }
    }
}
