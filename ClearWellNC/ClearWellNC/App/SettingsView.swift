//
//  SettingsView.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WellCareStore.self) private var wellCare
    @Environment(\.modelContext) private var modelContext
    @State private var changingSource = false
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]

    @State private var confirmingReset = false
    @State private var editingHome = false
    @State private var photoMessage: String?

    var body: some View {
        @Bindable var settings = settings
        Form { Group {
            Section {
                Picker("County", selection: $settings.county) {
                    Text("Not set").tag(String?.none)
                    ForEach(CountyNames.all, id: \.self) { county in
                        Text(String(localized: "\(county) County")).tag(Optional(county))
                    }
                }
                .frame(minHeight: TapTarget.minimum)
            } header: {
                Text("Location")
            } footer: {
                Text("Used for county facts, the seasonal outlook and matching help programs. Stored only on this device.")
            }

            Section {
                Picker("Water source", selection: $settings.waterSource) {
                    ForEach(WaterSource.allCases) { source in
                        Text(source.settingName).tag(source)
                    }
                }
                Toggle("A baby under 6 months lives here", isOn: $settings.infantInHome)
                Toggle("Someone in the home is pregnant", isOn: $settings.pregnantInHome)
                Toggle("Our household may qualify for income-based help", isOn: $settings.lowIncome)
            } header: {
                Text("Household")
            } footer: {
                Text("These answers tailor test advice and help programs. They never leave this device.")
            }

            Section("Your home") {
                Button("Change address or water source") { changingSource = true }
                    .frame(minHeight: TapTarget.minimum)
                    .accessibilityIdentifier("settings.changeSource")
                NavigationLink("Household") { HouseholdView() }
                Button("Home and plumbing") { editingHome = true }
                    .frame(minHeight: TapTarget.minimum)
                NavigationLink("Filters") { FiltersView() }
                NavigationLink("Testing and modes") { ModesView() }
            }

            Section("Notifications") {
                NavigationLink("Filters & reminders") {
                    RemindersView().navigationTitle("Filters & reminders")
                }
                NavigationLink("Report Quest reminders & badges") {
                    WellCareProgressView(context: WellCareContext.make(results: results, county: settings.county,
                                                                      trends: CountyTrendData.loadBundled()))
                        .navigationTitle(settings.waterSource.careTitle)
                }
            }

            Section {
                Toggle("Demo Mode", isOn: $settings.demoEnabled)
                if settings.demoEnabled {
                    Picker("Persona", selection: $settings.demoPersona) {
                        ForEach(DemoPersona.allCases) { persona in
                            Text(persona.title).tag(persona)
                        }
                    }
                    Text(settings.demoPersona.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                Button("Save sample report to Photos") { saveSampleToPhotos() }
                    .frame(minHeight: TapTarget.minimum)
                if let photoMessage {
                    Text(photoMessage).font(.subheadline).foregroundStyle(Color.textSecondary)
                }
            } header: {
                Text("Demo Mode")
            } footer: {
                Text("Demo Mode uses separate sample data. Your real results are hidden, not changed, and come back when you turn it off.")
            }

            Section("About") {
                NavigationLink("Privacy & Sources") { PrivacySourcesView() }
                NavigationLink("Sources and data") { SourcesView() }
                if settings.waterSource.showsWellCare {
                    NavigationLink("How the estimates work") { HowItWorksView() }
                }
                #if DEBUG
                NavigationLink("Design System Gallery") { DesignSystemGalleryView() }
                #endif
            }

            Section {
                Button("Reset app", role: .destructive) { confirmingReset = true }
                    .frame(minHeight: TapTarget.minimum)
                    .disabled(settings.demoEnabled)
            } footer: {
                Text(settings.demoEnabled
                     ? String(localized: "Turn off Demo Mode to reset your real data.")
                     : String(localized: "Deletes your lab results, address, filters, household, answers, badges and reminders from this device, and starts the welcome screens again."))
            }
        }
        .listRowBackground(M.Colors.surface)
        }
        .modernistList()
        .navigationTitle("Settings")
        .fullScreenCover(isPresented: $editingHome) { HomeProfileFlow() }
        .fullScreenCover(isPresented: $changingSource) { OnboardingView(mode: .changeSource) }
        // City water has no well-care reminders; reschedule when the answer changes.
        .onChange(of: settings.waterSource) { _, _ in
            let context = modelContext
            Task { await ReminderSync.refresh(using: context) }
        }
        .confirmationDialog("Delete all \(AppName.display) data on this device?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive, action: resetAll)
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Puts the SAMPLE REPORT image in Photos so the scanner's "Choose photo" path can be demoed.
    private func saveSampleToPhotos() {
        guard let image = SampleLabReport.render() else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        photoMessage = String(localized: "Saved. In Scan Report, tap Choose photo and pick the SAMPLE REPORT image.")
    }

    private func resetAll() {
        try? modelContext.delete(model: LabResult.self)
        try? modelContext.delete(model: SavedWell.self)
        try? modelContext.delete(model: TreatmentSystem.self)
        try? modelContext.save()
        settings.resetRealData()
        WellCareState().save()
        wellCare.reload()
        for task in WellCareTask.allCases { UserDefaults.standard.removeObject(forKey: task.manualKey) }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
