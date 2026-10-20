//
//  LabResultForm.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

/// Add a new lab result, or edit an existing one.
struct LabResultForm: View {
    /// Nil to add a new result.
    let existing: LabResult?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var date = Date.now
    @State private var labName = ""
    @State private var entries: [Analyte: Entry] = [:]
    @State private var totalColiform: BacteriaResult?
    @State private var eColi: BacteriaResult?
    @State private var confirmingDelete = false
    @State private var loaded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    struct Entry {
        var text = ""
        var unit: ConcentrationUnit?
    }

    init(existing: LabResult? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Test date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    TextField("Lab name (optional)", text: $labName)
                        .textContentType(.organizationName)
                }

                Section {
                    ForEach(Analyte.allCases.filter(\.isCommon)) { analyte in
                        analyteRow(analyte)
                    }
                } header: {
                    Text("Common NC well tests")
                } footer: {
                    Text("Leave blank anything your lab didn't test. 1 mg/L = 1000 ppb.")
                }

                Section("Other tests") {
                    ForEach(Analyte.allCases.filter { !$0.isCommon }) { analyte in
                        analyteRow(analyte)
                    }
                }

                Section("Bacteria") {
                    bacteriaPicker("Total coliform", selection: $totalColiform)
                    bacteriaPicker("E. coli", selection: $eColi)
                }

                if existing != nil {
                    Section {
                        Button("Delete this result", role: .destructive) { confirmingDelete = true }
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add lab result" : "Edit lab result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this lab result?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Rows

    private func analyteRow(_ analyte: Analyte) -> some View {
        let entry = entries[analyte] ?? Entry(unit: analyte.storedUnit)
        let invalid = !entry.text.isEmpty && parse(entry.text) == nil
        // Stack name, field and unit vertically at accessibility text sizes so nothing truncates.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s)) : AnyLayout(HStackLayout())
        return VStack(alignment: .leading, spacing: Spacing.s) {
            layout {
                Text(analyte.name)
                    .frame(minWidth: stacked ? nil : 90, alignment: .leading)
                TextField(analyte.name, text: binding(for: analyte).text, prompt: Text("Not tested"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(stacked ? .leading : .trailing)
                    .accessibilityLabel(entry.unit.map { Text("\(analyte.name), in \($0.label)") }
                        ?? (analyte.unitLabel.isEmpty ? Text(analyte.name) : Text("\(analyte.name), in \(analyte.unitLabel)")))
                if analyte.storedUnit != nil {
                    Picker("Unit", selection: binding(for: analyte).unit) {
                        ForEach(ConcentrationUnit.allCases) { unit in
                            Text(unit.label).tag(Optional(unit))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(Text("\(analyte.name) unit"))
                } else if !analyte.unitLabel.isEmpty {
                    // Fixed units (pCi/L, mg/L as CaCO₃) can't be converted, so just show them.
                    Text(analyte.unitLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44)
            Text(analyte.limitDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            if invalid {
                Label("Enter a number of 0 or more.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(RiskLevel.high.color)
            }
            // Live meaning of what was just typed.
            if let value = storedValue(for: analyte) {
                let interpretation = analyte.interpret(value)
                HStack(spacing: Spacing.s) {
                    StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                    if let percent = interpretation.percentText {
                        Text(percent).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func bacteriaPicker(_ title: LocalizedStringKey, selection: Binding<BacteriaResult?>) -> some View {
        Picker(title, selection: selection) {
            Text("Not tested").tag(BacteriaResult?.none)
            ForEach(BacteriaResult.allCases) { result in
                Text(result.label).tag(Optional(result))
            }
        }
        .frame(minHeight: 44)
    }

    private func binding(for analyte: Analyte) -> Binding<Entry> {
        Binding {
            entries[analyte] ?? Entry(unit: analyte.storedUnit)
        } set: {
            entries[analyte] = $0
        }
    }

    // MARK: Parsing and saving

    private func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = try? FloatingPointFormatStyle<Double>(locale: .current).parseStrategy.parse(trimmed),
              value >= 0, value.isFinite
        else { return nil }
        return value
    }

    /// The value converted to the analyte's stored unit, or nil if blank or invalid.
    private func storedValue(for analyte: Analyte) -> Double? {
        guard let entry = entries[analyte], let value = parse(entry.text) else { return nil }
        guard let stored = analyte.storedUnit, let unit = entry.unit else { return value }
        return ConcentrationUnit.convert(value, from: unit, to: stored)
    }

    private var hasInvalidEntry: Bool {
        entries.values.contains { !$0.text.isEmpty && parse($0.text) == nil }
    }

    private var canSave: Bool {
        guard !hasInvalidEntry else { return false }
        let anyValue = Analyte.allCases.contains { storedValue(for: $0) != nil }
        return anyValue || totalColiform != nil || eColi != nil
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        date = existing.date
        labName = existing.labName
        totalColiform = existing.totalColiform
        eColi = existing.eColi
        for analyte in Analyte.allCases {
            if let value = existing.value(for: analyte) {
                entries[analyte] = Entry(text: value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)),
                                         unit: analyte.storedUnit)
            }
        }
    }

    private func save() {
        let result = existing ?? LabResult()
        result.date = date
        result.labName = labName.trimmingCharacters(in: .whitespacesAndNewlines)
        for analyte in Analyte.allCases {
            result.setValue(storedValue(for: analyte), for: analyte)
        }
        result.totalColiform = totalColiform
        result.eColi = eColi
        if existing == nil { modelContext.insert(result) }
        try? modelContext.save()
        Task { await ReminderSync.refresh(using: modelContext) }
        dismiss()
    }

    private func delete() {
        guard let existing else { return }
        modelContext.delete(existing)
        try? modelContext.save()
        Task { await ReminderSync.refresh(using: modelContext) }
        dismiss()
    }
}
