//
//  TreatmentForm.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

struct TreatmentForm: View {
    /// Nil to add a new system.
    let existing: TreatmentSystem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var kind: TreatmentKind = WaterSource.current.isWell ? .sedimentFilter : .pitcherFilter
    @State private var customName = ""
    @State private var productName = ""
    @State private var lastServiced = Date.now
    @State private var intervalMonths = (WaterSource.current.isWell ? TreatmentKind.sedimentFilter : .pitcherFilter).defaultIntervalMonths
    @State private var intervalEdited = false
    @State private var confirmingDelete = false
    @State private var loaded = false

    init(existing: TreatmentSystem? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(TreatmentKind.allCases) { kind in
                            Label(kind.name, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .frame(minHeight: 44)
                    if kind == .other {
                        TextField("Name, for example \"Iron filter\"", text: $customName)
                    }
                    TextField("Brand and model (optional)", text: $productName)
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: 44)
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(kind.certificationNote)
                        Link("Look up certified filters (NSF)", destination: WellResources.nsfCertifiedFilters)
                    }
                }

                Section {
                    DatePicker(kind.isCheck ? "Last checked" : "Installed or last replaced",
                               selection: $lastServiced, in: ...Date.now, displayedComponents: .date)
                    Stepper(value: $intervalMonths, in: 1...60) {
                        Text(kind.isCheck ? "Check every \(intervalMonths) months" : "Replace every \(intervalMonths) months")
                    }
                    .frame(minHeight: 44)
                } footer: {
                    if existing == nil {
                        Text("After you add a filter or treatment system, retest your water to confirm it works.")
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete this system", role: .destructive) { confirmingDelete = true }
                            .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add filter or treatment" : "Edit filter or treatment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .confirmationDialog("Delete this treatment system?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
            .onChange(of: kind) { _, newKind in
                // Follow the type's default until the user picks their own interval.
                if !intervalEdited { intervalMonths = newKind.defaultIntervalMonths }
            }
            .onChange(of: intervalMonths) { _, newValue in
                if newValue != kind.defaultIntervalMonths { intervalEdited = true }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        kind = existing.kind
        customName = existing.customName
        productName = existing.productName
        lastServiced = existing.lastServiced
        intervalMonths = existing.intervalMonths
        intervalEdited = true
    }

    private func save() {
        if let existing {
            existing.kind = kind
            existing.customName = kind == .other ? customName : ""
            existing.productName = productName
            existing.lastServiced = lastServiced
            existing.intervalMonths = intervalMonths
        } else {
            modelContext.insert(TreatmentSystem(kind: kind,
                                                customName: kind == .other ? customName : "",
                                                productName: productName,
                                                lastServiced: lastServiced,
                                                intervalMonths: intervalMonths))
        }
        try? modelContext.save()
        let context = modelContext
        Task {
            // Ask for notification permission the first time someone adds a system.
            if await NotificationScheduler.authorizationStatus() == .notDetermined {
                await NotificationScheduler.requestAuthorization()
            }
            await ReminderSync.refresh(using: context)
        }
        dismiss()
    }

    private func delete() {
        guard let existing else { return }
        modelContext.delete(existing)
        try? modelContext.save()
        let context = modelContext
        Task { await ReminderSync.refresh(using: context) }
        dismiss()
    }
}
