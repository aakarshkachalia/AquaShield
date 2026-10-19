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
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure
    @State private var selectedTab: AppTab = .home

    /// Changes whenever the saved location does, so alerts are re-checked.
    private var wellKey: String? {
        savedWells.first.map { "\($0.latitude),\($0.longitude)" }
    }

    var body: some View {
        // Five tabs, so nothing hides behind "More". How It Works lives inside Learn.
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
                .badge(alertsStore.relevantAlerts.count)
            CheckAreaView()
                .tabItem { Label("Check My Area", systemImage: "magnifyingglass") }
                .tag(AppTab.checkArea)
            MyWellView()
                .tabItem { Label(waterSource.homeTitle, systemImage: waterSource.tabSymbol) }
                .tag(AppTab.myWater)
            LearnView()
                .tabItem { Label("Learn", systemImage: "book.fill") }
                .tag(AppTab.learn)
            RemindersView()
                .tabItem { Label("Reminders", systemImage: "bell.fill") }
                .tag(AppTab.reminders)
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
        .environment(WellCareStore())
        .modelContainer(for: [SavedWell.self, LabResult.self, TreatmentSystem.self], inMemory: true)
}
