//
//  DataReviewView.swift
//  ClearWellNC
//
//  DEBUG only: every value with needsVerification = true, so a person can check each against its source
//  before release. Settings > Privacy & Sources > Data review.
//

#if DEBUG
import SwiftUI

struct DataReviewView: View {
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    private struct Row: Identifiable {
        let id: String
        let area: String
        let title: String
        let detail: String
        let source: String
    }

    private var rows: [Row] {
        var rows: [Row] = []
        for (id, record) in ReferenceLimits.table.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where record.source.needsVerification {
            let value = record.limit.value.map(formatNumber) ?? record.limit.kind
            rows.append(Row(id: "limit-\(id.rawValue)", area: "Contaminant limits (v\(ReferenceLimits.version))",
                            title: "\(id.info.name): \(value)\(record.healthAdvisory.map { " · advisory \(formatNumber($0))" } ?? "")",
                            detail: record.register.map { "Register \($0)" } ?? "", source: record.source.sourceName))
        }
        for (standard, record) in ReferenceStandards.table.sorted(by: { $0.key.rawValue < $1.key.rawValue })
        where record.source.needsVerification {
            rows.append(Row(id: "std-\(standard.rawValue)", area: "Certification standards", title: standard.name,
                            detail: record.allowedTargets.map(\.name).sorted().joined(separator: ", "),
                            source: record.source.sourceName))
        }
        for kind in UtilityFinding.Kind.allCases {
            let limit = UtilityReportRules.limit(for: kind)
            if limit.source.needsVerification {
                rows.append(Row(id: "ccr-\(kind.rawValue)", area: "Utility report limits",
                                title: "\(kind.rawValue): \(formatNumber(limit.value)) \(limit.unit)", detail: "",
                                source: limit.source.sourceName))
            }
        }
        for target in [ClaimTarget.tthm, .haa5, .freeChlorine, .chloramine] {
            if let limit = TargetLimit.limit(for: target) {
                rows.append(Row(id: "tap-\(target.rawValue)", area: "Tap score limits",
                                title: "\(target.name): \(formatNumber(limit.value))", detail: "", source: limit.source))
            }
        }
        for product in ReferenceDataStore.shared.filterProducts(custom: settings.customFilterProducts) where product.needsVerification {
            rows.append(Row(id: "product-\(product.id)", area: product.isUserEntered ? "Your filters" : "Sample filter products",
                            title: product.displayName,
                            detail: product.claims.map { "\($0.target.name) \(formatNumber($0.reductionPercent))% (\($0.standard.name))" }
                                .joined(separator: ", "),
                            source: product.source.sourceName))
        }
        rows.append(Row(id: "household-typical", area: "Household defaults", title: "Typical liters per day by age",
                        detail: HouseholdMember.AgeBand.allCases.map { "\($0.label) \(formatNumber($0.typicalLitersPerDay))" }
                            .joined(separator: ", "),
                        source: "EPA Exposure Factors Handbook (rounded)"))
        rows.append(Row(id: "septic", area: "Household defaults", title: "Well to septic distance",
                        detail: "\(formatNumber(HomeProfile.septicSetbackFeet)) feet", source: "NC well construction rules"))
        for contact in TestingContact.samples(county: settings.county) where contact.needsVerification {
            rows.append(Row(id: "contact-\(contact.id)", area: "Find testing", title: contact.name, detail: contact.detail,
                            source: contact.source.sourceName))
        }
        for instruction in SamplingInstruction.all where instruction.source.needsVerification {
            rows.append(Row(id: "sampling-\(instruction.id)", area: "Sampling instructions", title: instruction.title,
                            detail: instruction.steps.joined(separator: " "), source: instruction.source.sourceName))
        }
        for id in ContaminantID.allCases where !BodyArea.areas(for: id).isEmpty {
            rows.append(Row(id: "body-\(id.rawValue)", area: "Learn: body areas", title: id.info.name,
                            detail: BodyArea.areas(for: id).map(\.label).joined(separator: ", "),
                            source: "CDC / ATSDR and EPA health summaries"))
        }
        if let info = WaterSystemIndex.info {
            rows.append(Row(id: "epa-cws", area: "Water system boundaries", title: info.sourceName,
                            detail: "\(info.systems) NC systems · \(info.version) · downloaded \(info.downloaded)",
                            source: info.sourceURL))
        }
        for entry in VerificationRegister.entries where entry.needsVerification {
            rows.append(Row(id: entry.id, area: "Notes in code (\(entry.file.split(separator: "/").last ?? ""))",
                            title: entry.id, detail: entry.note, source: entry.sourceName))
        }
        guard !query.isEmpty else { return rows }
        return rows.filter { "\($0.title) \($0.detail) \($0.area)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let rows = rows
        let areas = rows.map(\.area).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        List {
            Section {
                Text("\(rows.count) values need a person to check them against their source.")
            }
            ForEach(areas, id: \.self) { area in
                Section(area) {
                    ForEach(rows.filter { $0.area == area }) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title).font(.headline)
                            if !row.detail.isEmpty { Text(row.detail).font(.subheadline) }
                            if !row.source.isEmpty {
                                Text("Source: \(row.source)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Data review")
    }
}
#endif
