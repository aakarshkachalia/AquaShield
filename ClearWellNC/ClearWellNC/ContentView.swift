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
    var body: some View {
        TabView {
            CheckAreaView()
                .tabItem { Label("Check My Area", systemImage: "magnifyingglass") }
            MyWellView()
                .tabItem { Label("My Well", systemImage: "drop.fill") }
            // Placeholders until their milestones.
            NavigationStack {
                ContentUnavailableView("Reminders", systemImage: "bell",
                                       description: Text("Filter replacement and testing reminders will appear here."))
                    .navigationTitle("Reminders")
            }
            .tabItem { Label("Reminders", systemImage: "bell.fill") }
            NavigationStack {
                ContentUnavailableView("How It Works", systemImage: "info.circle",
                                       description: Text("How ClearWell NC estimates your area's risk will appear here."))
                    .navigationTitle("How It Works")
            }
            .tabItem { Label("How It Works", systemImage: "info.circle.fill") }
        }
    }
}

#Preview {
    ContentView()
        .environment(TractStore())
        .modelContainer(for: SavedWell.self, inMemory: true)
}
