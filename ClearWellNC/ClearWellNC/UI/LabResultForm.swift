//
//  LabResultForm.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

/// Add a new lab result, or edit an existing one, in four short steps. Everything typed is kept as a
/// draft until Save, so closing or force-quitting loses nothing.
struct LabResultForm: View {
    /// Nil to add a new result.
    let existing: LabResult?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft = LabEntryDraft()
    @State private var pristine = LabEntryDraft()
    @State private var resume: StepFlowResume?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private let order = LabEntryStep.allCases
    private var draftKey: DraftKey<LabEntryDraft> { LabEntryDraft.key(editingCreatedAt: existing?.createdAt) }

    init(existing: LabResult? = nil) {
        self.existing = existing
    }

    var body: some View {
        StepFlowContainer(flow: $draft.flow, resume: resume,
                          progress: { _ in draft.flow.progress(in: order) },
                          primaryAction: primaryAction,
                          onClose: { dismiss() }) { step in
            Form { Group { section(for: step) }
            .listRowBackground(M.Colors.surface)
            }
            .modernistList()
                .navigationTitle(existing == nil ? "Add lab result" : "Edit lab result")
                .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog("Delete this lab result?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        }
        .onAppear(perform: load)
        .onChange(of: draft) { _, newValue in
            guard loaded, newValue != pristine else { return }
            settings.drafts.save(newValue, for: draftKey)
        }
    }

    @ViewBuilder
    private func section(for step: LabEntryStep) -> some View {
        switch step {
        case .details:
            Section {
                DatePicker("Test date", selection: $draft.date, in: ...Date.now, displayedComponents: .date)
                TextField("Lab name (optional)", text: $draft.labName)
                    .textContentType(.organizationName)
                Picker("How was it tested?", selection: Binding(get: { draft.testMethod ?? .certifiedLab },
                                                                set: { draft.testMethod = $0 })) {
                    ForEach([TestMethod.certifiedLab, .homeKit, .unknown], id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("About the test")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Home test kits and strips can show a problem, but can't clear lead, arsenic, PFAS, nitrate or uranium.")
                    PrivacyNote()
                }
            }
            if existing != nil {
                Section {
                    Button("Delete this result", role: .destructive) { confirmingDelete = true }
                        .frame(minHeight: 44)
                }
            }
        case .commonTests:
            Section {
                ForEach(Analyte.allCases.filter(\.isCommon)) { analyte in
                    analyteRow(analyte)
                }
            } header: {
                Text("Common NC well tests")
            } footer: {
                Text("Leave blank anything your lab didn't test. 1 mg/L = 1000 ppb.")
            }
        case .otherTests:
            Section {
                ForEach(Analyte.allCases.filter { !$0.isCommon }) { analyte in
                    analyteRow(analyte)
                }
            } header: {
                Text("Other tests")
            } footer: {
                Text("Leave blank anything your lab didn't test.")
            }
        case .bacteria:
            Section("Bacteria") {
                bacteriaPicker("Total coliform", selection: $draft.totalColiform)
                bacteriaPicker("E. coli", selection: $draft.eColi)
            }
            if !draft.canSave {
                Section {
                    Text(draft.hasInvalidEntry ? "Fix the numbers marked in red before saving."
                                               : "Enter at least one result to save.")
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    private func primaryAction(_ step: LabEntryStep) -> StepAction? {
        if step == .bacteria {
            return StepAction(title: "Save", systemImage: "checkmark", isEnabled: draft.canSave,
                              identifier: "labEntry.save", action: save)
        }
        return StepAction(title: "Next", systemImage: "arrow.right") { draft.flow.advance(in: order) }
    }

    // MARK: Rows

    private func analyteRow(_ analyte: Analyte) -> some View {
        let entry = draft.entry(for: analyte)
        let invalid = draft.isInvalid(analyte)
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
                        .foregroundStyle(M.Colors.muted)
                }
            }
            .frame(minHeight: 44)
            Text(analyte.limitDescription)
                .font(.caption)
                .foregroundStyle(M.Colors.muted)
            if invalid {
                Label("Enter a number of 0 or more.", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(RiskLevel.high.color)
            }
            // Live meaning of what was just typed.
            if let value = draft.storedValue(for: analyte) {
                let interpretation = analyte.interpret(value)
                HStack(spacing: Spacing.s) {
                    StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                    if let percent = interpretation.percentText {
                        Text(percent).font(.caption).foregroundStyle(M.Colors.muted)
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

    private func binding(for analyte: Analyte) -> Binding<LabEntryDraft.Entry> {
        Binding {
            draft.entry(for: analyte)
        } set: {
            draft.entries[analyte] = $0
        }
    }

    // MARK: Draft and saving

    private func load() {
        guard !loaded else { return }
        loaded = true
        let fresh = existing.map(LabEntryDraft.init(editing:)) ?? LabEntryDraft()
        if let saved = settings.drafts.load(draftKey), saved.payload.flow.isValid(in: order) {
            draft = saved.payload
            resume = StepFlowResume(startedAt: saved.startedAt,
                                    onContinue: { resume = nil },
                                    onStartOver: {
                                        resume = nil
                                        settings.drafts.discard(draftKey)
                                        draft = fresh
                                    })
        } else {
            settings.drafts.discard(draftKey)
            draft = fresh
        }
        pristine = fresh
    }

    private func save() {
        guard draft.canSave else { return }
        let result = existing ?? LabResult()
        draft.apply(to: result)
        if existing == nil { modelContext.insert(result) }
        try? modelContext.save()
        settings.drafts.discard(draftKey)
        Task { await ReminderSync.refresh(using: modelContext) }
        dismiss()
    }

    private func delete() {
        guard let existing else { return }
        settings.drafts.discard(draftKey)
        modelContext.delete(existing)
        try? modelContext.save()
        Task { await ReminderSync.refresh(using: modelContext) }
        dismiss()
    }
}
