//
//  ScanReviewView.swift
//  ClearWellNC
//
//  Required before saving: every parsed row, editable, with low-confidence rows flagged.
//

import SwiftUI

struct ScanReviewView: View {
    let images: [UIImage]
    let onSave: (LabResult) -> Void

    @State private var rows: [ReviewRow]
    @State private var date: Date
    @State private var labName: String
    @State private var showingOriginal = false

    init(result: LabReportParser.Result, images: [UIImage], onSave: @escaping (LabResult) -> Void) {
        self.images = images
        self.onSave = onSave
        _rows = State(initialValue: result.rows.map(ReviewRow.init(parsed:)))
        _date = State(initialValue: min(result.collectionDate ?? .now, .now))
        _labName = State(initialValue: result.labName ?? "")
    }

    private var flaggedCount: Int { rows.filter(\.needsReview).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                summary

                VStack(alignment: .leading, spacing: Spacing.m) {
                    DatePicker("Test date", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .frame(minHeight: TapTarget.minimum)
                    TextField("Lab name (optional)", text: $labName)
                        .frame(minHeight: TapTarget.minimum)
                }
                .card()

                if !images.isEmpty {
                    Toggle("Show original photo", isOn: $showingOriginal)
                        .frame(minHeight: TapTarget.minimum)
                        .card()
                    if showingOriginal {
                        ForEach(images.indices, id: \.self) { i in
                            Image(uiImage: images[i])
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                .accessibilityLabel(Text("Original report photo, page \(i + 1)"))
                        }
                    }
                }

                SectionHeader(title: "Results we found")
                ForEach($rows) { $row in
                    ReviewRowEditor(row: $row) { rows.removeAll { $0.id == row.id } }
                }
                SecondaryButton(title: "Add a result", systemImage: "plus") {
                    rows.append(ReviewRow())
                }

                PrimaryButton(title: "Save results", systemImage: "checkmark") { save() }
                    .disabled(!rows.contains(where: \.isSavable))
                DisclaimerFooter(showsLinks: false)
            }
            .screenContainer()
        }
        .background(Color.appBackground)
        .navigationTitle("Check your results")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        let found = rows.filter { $0.contaminant != nil }.count
        return InfoCard(style: flaggedCount > 0 ? .status(.watch) : .status(.safe),
                        systemImage: flaggedCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill",
                        title: String(localized: "We read \(found) results"),
                        message: flaggedCount > 0
                            ? String(localized: "\(flaggedCount) need a quick check. Compare them with your report and fix anything we misread.")
                            : String(localized: "Compare them with your report before saving."))
    }

    private func save() {
        onSave(ScanDraft.makeResult(rows: rows, date: date, labName: labName))
    }
}

private struct ReviewRowEditor: View {
    @Binding var row: ReviewRow
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if row.needsReview {
                Label(row.contaminant == nil ? "We don't recognize this test" : "Please check this",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .symbolRenderingMode(.multicolor)
            }

            HStack {
                Picker("Test", selection: edited(\.contaminant)) {
                    Text("Choose a test").tag(ContaminantID?.none)
                    ForEach(ContaminantID.allCases) { id in
                        Text(id.info.name).tag(Optional(id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.headline)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(minWidth: TapTarget.minimum, minHeight: TapTarget.minimum)
                }
                .accessibilityLabel(Text("Remove this result"))
            }

            if row.contaminant != nil {
                if row.isPresenceTest {
                    Picker("Result", selection: edited(\.kind)) {
                        Text(ReviewRow.Kind.absent.label).tag(ReviewRow.Kind.absent)
                        Text(ReviewRow.Kind.present.label).tag(ReviewRow.Kind.present)
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: TapTarget.minimum)
                } else {
                    Picker("Result type", selection: edited(\.kind)) {
                        ForEach([ReviewRow.Kind.number, .belowDetection, .notDetected]) { Text($0.label).tag($0) }
                    }
                    .frame(minHeight: TapTarget.minimum)
                    if row.kind != .notDetected {
                        HStack {
                            TextField(row.kind == .belowDetection ? "Detection limit" : "Value", text: edited(\.valueText))
                                .keyboardType(.decimalPad)
                                .frame(minHeight: TapTarget.minimum)
                                .accessibilityLabel(Text(row.kind == .belowDetection ? "Detection limit" : "Value"))
                            if !row.unitChoices.isEmpty {
                                Picker("Unit", selection: edited(\.unit)) {
                                    Text("Unit?").tag(LabReportParser.ReportedUnit?.none)
                                    ForEach(row.unitChoices) { Text($0.label).tag(Optional($0)) }
                                }
                                .pickerStyle(.menu)
                                .accessibilityLabel(Text("Unit"))
                            }
                        }
                    }
                }
                if let preview = row.preview {
                    HStack(spacing: Spacing.s) {
                        StatusChip(tier: preview.tier, label: preview.chipLabel)
                        Text(preview.readingText)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                Text("ClearWell doesn't track this test, so it won't be saved. If we misread the name, choose the right test above.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if row.needsReview {
                ForEach(row.notes, id: \.self) { note in
                    Text("• \(note)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !row.rawText.isEmpty {
                Text("Read as: \(row.rawText)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.needsReview ? Color.statusWatch.opacity(0.12) : Color.surface,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(row.needsReview ? Color.statusWatch : Color.cardBorder, lineWidth: row.needsReview ? 2 : 1))
    }

    /// A binding that also marks the row as checked by the user.
    private func edited<T>(_ keyPath: WritableKeyPath<ReviewRow, T>) -> Binding<T> {
        Binding {
            row[keyPath: keyPath]
        } set: { newValue in
            row[keyPath: keyPath] = newValue
            row.edited = true
            if keyPath == \ReviewRow.contaminant, row.isPresenceTest, row.kind != .present, row.kind != .absent {
                row.kind = .absent
            }
        }
    }
}
