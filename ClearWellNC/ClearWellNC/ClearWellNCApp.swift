//
//  ClearWellNCApp.swift
//  ClearWellNC
//
//  Created by Aakarsh Kachalia on 10/2/26.
//

import SwiftUI
import SwiftData

@main
struct ClearWellNCApp: App {
    @State private var tractStore = TractStore()
    @State private var alertsStore = WeatherAlertsStore()
    @State private var wellCareStore = WellCareStore()
    @State private var router = AppRouter()
    @State private var settings: AppSettings
    @State private var demoStores = DemoStores()

    init() {
        UITestSupport.applyLaunchArguments()
        _settings = State(initialValue: AppSettings())
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedWell.self,
            LabResult.self,
            TreatmentSystem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                // A fresh view tree per data store, so switching Demo Mode never mixes real and sample data.
                .id(settings.demoEnabled ? "demo-\(settings.demoPersona.rawValue)" : "real")
                .environment(router)
                .environment(settings)
                .environment(demoStores)
                .environment(tractStore)
                .environment(alertsStore)
                .environment(wellCareStore)
                // Parse the bundled tract data once at launch, off the main thread.
                .task { await tractStore.load() }
        }
        .modelContainer(settings.demoEnabled ? demoStores.container(for: settings.demoPersona) : sharedModelContainer)
    }
}
