//
//  RemindersView.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI
import UserNotifications

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TreatmentSystem.lastServiced) private var systems: [TreatmentSystem]
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Environment(AppSettings.self) private var settings
    private var waterSource: WaterSource { settings.waterSource }

    @State private var addingSystem = false
    @State private var editingSystem: TreatmentSystem?
    @State private var notificationStatus: UNAuthorizationStatus?
    /// Bumped when a manual "done" date changes, so well-care rows re-read UserDefaults.
    @State private var careRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                notificationCard

                sectionHeader("Filters & treatment", action: { addingSystem = true },
                              actionLabel: "Add filter")
                if systems.isEmpty {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        IconTile(systemImage: "line.3.horizontal.decrease.circle")
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("No filters yet")
                                .font(.headline)
                            Text("Add a pitcher, faucet, fridge or under-sink filter, or well treatment like UV or a softener, to get a reminder when it's due.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .card()
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(systems) { system in
                        TreatmentRow(system: system,
                                     onEdit: { editingSystem = system },
                                     onServiced: { markServiced(system) })
                    }
                }

                if waterSource.showsWellCare {
                    Text("Well care")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Spacing.s)
                    ForEach(WellCareTask.allCases) { task in
                        CareRow(task: task, results: results, revision: careRevision) {
                            task.markDone()
                            careRevision += 1
                            refresh()
                        }
                    }
                }
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Reminders")
        .sheet(isPresented: $addingSystem) { TreatmentForm() }
        .sheet(item: $editingSystem) { TreatmentForm(existing: $0) }
        .task { notificationStatus = await NotificationScheduler.authorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            // Pick up permission changes made in Settings.
            if phase == .active {
                Task { notificationStatus = await NotificationScheduler.authorizationStatus() }
            }
        }
        .onChange(of: addingSystem) { _, isAdding in
            if !isAdding { Task { notificationStatus = await NotificationScheduler.authorizationStatus() } }
        }
    
    }

    // MARK: Pieces

    @ViewBuilder
    private var notificationCard: some View {
        switch notificationStatus {
        case .notDetermined?:
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Get reminders on time", systemImage: "bell.badge")
                    .font(.headline)
                Text(waterSource.showsWellCare
                     ? String(localized: "\(AppName.display) can send a notification when a filter is due or it's time to test your well.")
                     : String(localized: "\(AppName.display) can send a notification when a filter is due."))
                Button {
                    Task {
                        await NotificationScheduler.requestAuthorization()
                        notificationStatus = await NotificationScheduler.authorizationStatus()
                        await ReminderSync.refresh(using: modelContext)
                    }
                } label: {
                    Text("Turn on notifications")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .card()
        case .denied?:
            VStack(alignment: .leading, spacing: Spacing.m) {
                Label("Notifications are off", systemImage: "bell.slash")
                    .font(.headline)
                Text("Reminders still show here, but you won't get alerts. You can turn notifications on in Settings.")
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { openURL(url) }
                        .frame(minHeight: 44)
                }
            }
            .card()
        default:
            EmptyView()
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, action: @escaping () -> Void,
                               actionLabel: LocalizedStringKey) -> some View {
        let titleView = Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
        let button = Button(action: action) {
            Label(actionLabel, systemImage: "plus").frame(minHeight: 44)
        }
        .buttonStyle(SecondaryButtonStyle())
        return ViewThatFits(in: .horizontal) {
            HStack { titleView; Spacer(); button }
            VStack(alignment: .leading, spacing: Spacing.s) { titleView; button }
        }
    }

    private func markServiced(_ system: TreatmentSystem) {
        system.lastServiced = .now
        try? modelContext.save()
        refresh()
    }

    private func refresh() {
        let context = modelContext
        Task { await ReminderSync.refresh(using: context) }
    }
}

struct TreatmentRow: View {
    let system: TreatmentSystem
    let onEdit: () -> Void
    let onServiced: () -> Void

    var body: some View {
        let days = DueText.daysRemaining(until: system.dueDate)
        VStack(alignment: .leading, spacing: Spacing.m) {
            Button(action: onEdit) {
                HStack(alignment: .top, spacing: Spacing.m) {
                    Image(systemName: system.kind.symbol)
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(system.displayName)
                            .font(.headline)
                        if let product = system.trimmedProductName {
                            Text(product)
                                .font(.subheadline)
                        }
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        dueLabel(days: days)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Edit or delete this filter"))

            Button(action: onServiced) {
                Label(system.kind.isCheck ? "Mark checked today" : "Mark replaced today",
                      systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private var detail: String {
        let date = system.lastServiced.formatted(date: .abbreviated, time: .omitted)
        return system.kind.isCheck
            ? String(localized: "Last checked \(date) · every \(system.intervalMonths) months")
            : String(localized: "Last replaced \(date) · every \(system.intervalMonths) months")
    }

    private func dueLabel(days: Int) -> some View {
        Label {
            Text(DueText.text(daysRemaining: days, isCheck: system.kind.isCheck))
                .font(.subheadline.weight(.semibold))
        } icon: {
            Image(systemName: days < 0 ? "exclamationmark.triangle.fill" : (days <= 7 ? "clock.badge.exclamationmark" : "clock"))
                .foregroundStyle(days < 0 ? Color.statusAbove : Color.accentColor)
        }
    }
}

struct CareRow: View {
    let task: WellCareTask
    let results: [LabResult]
    /// Not displayed; changing it forces a re-read of the manual done date.
    let revision: Int
    let onDone: () -> Void

    var body: some View {
        let last = task.lastDone(results: results)
        let days = DueText.daysRemaining(until: task.dueDate(results: results))
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: task.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.frequency)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let last {
                        Text("Last done \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Label {
                        Text(last == nil ? String(localized: "Not recorded yet: due now") : DueText.careText(daysRemaining: days))
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: (last == nil || days < 0) ? "exclamationmark.triangle.fill" : "clock")
                            .foregroundStyle((last == nil || days < 0) ? Color.statusAbove : Color.accentColor)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Button(action: onDone) {
                Label("Mark done today", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(Text("Mark \(task.title) done today"))
        }
        .card()
    }
}
