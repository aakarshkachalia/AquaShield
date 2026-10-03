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

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
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
                .environment(tractStore)
                // Parse the bundled tract data once at launch, off the main thread.
                .task { await tractStore.load() }
        }
        .modelContainer(sharedModelContainer)
    }
}
