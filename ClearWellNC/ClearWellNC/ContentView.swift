//
//  ContentView.swift
//  ClearWellNC
//
//  Created by Aakarsh Kachalia on 10/2/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @AppStorage(StorageKey.hasOnboarded) private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]

    /// Changes whenever the saved location does, so alerts are re-checked.
    private var wellKey: String? {
        savedWells.first.map { "\($0.latitude),\($0.longitude)" }
    }

    var body: some View {
        TabView {
            CheckAreaView()
                .tabItem { Label("Check My Area", systemImage: "magnifyingglass") }
            MyWellView()
                .tabItem { Label("My Well", systemImage: "drop.fill") }
                .badge(alertsStore.relevantAlerts.count)
            LearnView()
                .tabItem { Label("Learn", systemImage: "book.fill") }
            RemindersView()
                .tabItem { Label("Reminders", systemImage: "bell.fill") }
            HowItWorksView()
                .tabItem { Label("How It Works", systemImage: "info.circle.fill") }
        }
        // Keep scheduled notifications in step with stored data on every launch.
        .task { await ReminderSync.refresh(using: modelContext) }
        // Check NWS alerts for the saved well on launch and whenever it changes.
        .task(id: wellKey) {
            if let well = savedWells.first {
                await alertsStore.refresh(latitude: well.latitude, longitude: well.longitude)
            } else {
                alertsStore.clear()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(TractStore())
        .environment(WeatherAlertsStore())
        .modelContainer(for: [SavedWell.self, LabResult.self, TreatmentSystem.self], inMemory: true)
}
