//
//  TreatmentForm.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

/// Unsaved filter/treatment edits, kept until Save so closing the form loses nothing.
nonisolated struct TreatmentDraft: Codable, Sendable, Equatable {
    var kind: TreatmentKind
    var customName = ""
    var productName = ""
    var lastServiced = Date.now
    var intervalMonths: Int
    var intervalEdited = false
    /// FilterProduct.id, or "" for none.
    var productID = ""
    /// TapLocation.rawValue, or "" for the type's usual place.
    var locationRaw = ""
    var gallonsPerDay: Double = 0

    init(kind: TreatmentKind) {
        self.kind = kind
        intervalMonths = kind.defaultIntervalMonths
    }

    /// One draft for a new system, and one per system being edited.
    static func key(editing reminderID: UUID?) -> DraftKey<TreatmentDraft> {
        DraftKey(name: reminderID.map { "treatment.edit.\($0.uuidString)" } ?? "treatment.new", schemaVersion: 2)
    }
}

struct TreatmentForm: View {
    /// Nil to add a new system.
    let existing: TreatmentSystem?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @State private var draft = TreatmentDraft(kind: .other)
    @State private var pristine = TreatmentDraft(kind: .other)
    /// When a restored draft was started, to offer "Discard changes".
    @State private var restoredFrom: Date?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var draftKey: DraftKey<TreatmentDraft> { TreatmentDraft.key(editing: existing?.reminderID) }

    init(existing: TreatmentSystem? = nil) {
        self.existing = existing
    }

    var body: some View {
        NavigationStack {
            Form { Group {
                if let restoredFrom {
                    Section {
                        Label {
                            Text("Unsaved changes restored. \(DraftAge.startedText(restoredFrom)).")
                        } icon: {
                            Image(systemName: "arrow.uturn.forward.circle.fill").foregroundStyle(Color.brandPrimary)
                        }
                        Button("Discard changes", role: .destructive, action: discardChanges)
                            .frame(minHeight: 44)
                    }
                }
                Section {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(TreatmentKind.allCases) { kind in
                            Label(kind.name, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .frame(minHeight: 44)
                    if draft.kind == .other {
                        TextField("Name, for example \"Iron filter\"", text: $draft.customName)
                    }
                    TextField("Brand and model (optional)", text: $draft.productName)
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: 44)
                } footer: {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(draft.kind.certificationNote)
                        Link("Look up certified filters (NSF)", destination: WellResources.nsfCertifiedFilters)
                    }
                }

                Section {
                    Picker("Certified product", selection: $draft.productID) {
                        Text("None or not sure").tag("")
                        ForEach(productChoices) { product in
                            Text(product.isCertified ? product.displayName
                                 : String(localized: "\(product.displayName) (uncertified)")).tag(product.id)
                        }
                    }
                    .frame(minHeight: 44)
                    Picker("Where it's installed", selection: $draft.locationRaw) {
                        Text("Usual place (\(FilterType(kind: draft.kind).defaultLocation.name))").tag("")
                        ForEach(locationChoices) { tap in
                            Text(tap.name).tag(tap.rawValue)
                        }
                    }
                    .frame(minHeight: 44)
                    HStack {
                        Text("Gallons per day (optional)")
                        Spacer()
                        TextField("—", value: $draft.gallonsPerDay, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("For your score")
                } footer: {
                    Text("Only certified claims count. A filter with no certification lowers nothing in your score. Can't find yours? Add it from Filters > Add my own filter.")
                }

                Section {
                    DatePicker(draft.kind.isCheck ? "Last checked" : "Installed or last replaced",
                               selection: $draft.lastServiced, in: ...Date.now, displayedComponents: .date)
                    Stepper(value: $draft.intervalMonths, in: 1...60) {
                        Text(draft.kind.isCheck ? "Check every \(draft.intervalMonths) months" : "Replace every \(draft.intervalMonths) months")
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
            .listRowBackground(M.Colors.surface)
            }
            .modernistList()
            .navigationTitle(existing == nil ? "Add filter or treatment" : "Edit filter or treatment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Unsaved changes stay as a draft.
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .confirmationDialog("Delete this treatment system?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .onAppear(perform: load)
            .onChange(of: draft.kind) { _, newKind in
                // Follow the type's default until the user picks their own interval.
                if !draft.intervalEdited { draft.intervalMonths = newKind.defaultIntervalMonths }
            }
            .onChange(of: draft.intervalMonths) { _, newValue in
                if newValue != draft.kind.defaultIntervalMonths { draft.intervalEdited = true }
            }
            .onChange(of: draft) { _, newValue in
                guard loaded, newValue != pristine else { return }
                settings.drafts.save(newValue, for: draftKey)
            }
        }
    }

    private var productChoices: [FilterProduct] {
        let type = FilterType(kind: draft.kind)
        let all = ReferenceDataStore.shared.filterProducts(custom: settings.customFilterProducts)
        let sameType = all.filter { $0.type == type }
        return sameType.isEmpty ? all : sameType
    }

    private var locationChoices: [TapLocation] {
        var taps: [TapLocation] = [.wholeHouse, .kitchen, TapLocation(kind: .fridge)]
        for i in 1...max(1, settings.homeProfile.bathroomSinkCount) { taps.append(TapLocation(kind: .bathroomSink, index: i)) }
        for i in 1...max(1, settings.homeProfile.showerCount) { taps.append(TapLocation(kind: .shower, index: i)) }
        return taps
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        var fresh = TreatmentDraft(kind: settings.waterSource.isWell ? .sedimentFilter : .pitcherFilter)
        if let existing {
            fresh = TreatmentDraft(kind: existing.kind)
            fresh.customName = existing.customName
            fresh.productName = existing.productName
            fresh.lastServiced = existing.lastServiced
            fresh.intervalMonths = existing.intervalMonths
            fresh.intervalEdited = true
            fresh.productID = existing.productID
            fresh.locationRaw = existing.locationRaw
            fresh.gallonsPerDay = existing.gallonsPerDay
        }
        pristine = fresh
        if let saved = settings.drafts.load(draftKey) {
            draft = saved.payload
            restoredFrom = saved.startedAt
        } else {
            draft = fresh
        }
    }

    private func discardChanges() {
        settings.drafts.discard(draftKey)
        draft = pristine
        restoredFrom = nil
    }

    private func save() {
        let kind = draft.kind
        let customName = kind == .other ? draft.customName : ""
        if let existing {
            existing.kind = kind
            existing.customName = customName
            existing.productName = draft.productName
            existing.lastServiced = draft.lastServiced
            existing.intervalMonths = draft.intervalMonths
            existing.productID = draft.productID
            existing.locationRaw = draft.locationRaw
            existing.gallonsPerDay = draft.gallonsPerDay
        } else {
            let system = TreatmentSystem(kind: kind,
                                         customName: customName,
                                         productName: draft.productName,
                                         lastServiced: draft.lastServiced,
                                         intervalMonths: draft.intervalMonths)
            system.productID = draft.productID
            system.locationRaw = draft.locationRaw
            system.gallonsPerDay = draft.gallonsPerDay
            modelContext.insert(system)
        }
        try? modelContext.save()
        settings.drafts.discard(draftKey)
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
        settings.drafts.discard(draftKey)
        modelContext.delete(existing)
        try? modelContext.save()
        let context = modelContext
        Task { await ReminderSync.refresh(using: context) }
        dismiss()
    }
}
