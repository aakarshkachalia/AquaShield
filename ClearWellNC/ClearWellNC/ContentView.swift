//
//  ContentView.swift
//  ClearWellNC
//
//  Created by Aakarsh Kachalia on 10/2/26.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var router = router
        Group {
            if settings.hasCompletedOnboarding {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .demoBanner()
        // App-wide primary actions, reachable from Home, My Water, onboarding and Help.
        .sheet(isPresented: $router.showingScanner) {
            ScanReportSheet().demoBanner()
        }
        .fullScreenCover(isPresented: $router.showingRiskCheck) {
            RiskCheckView().demoBanner()
        }
    }
}

/// Exactly four tabs, in priority order.
struct RootTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]

    /// Changes whenever the saved location does, so alerts are re-checked.
    private var wellKey: String? {
        savedWells.first.map { "\($0.latitude),\($0.longitude)" }
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                DashboardView()
            }
            .badge(settings.isOptedIn(.stormAlerts) ? alertsStore.relevantAlerts.count : 0)
            Tab("My Water", systemImage: "drop.fill", value: AppTab.myWater) {
                MyWaterView()
            }
            Tab("Get Help", systemImage: "lifepreserver.fill", value: AppTab.help) {
                GetHelpView()
            }
            Tab("Learn", systemImage: "book.fill", value: AppTab.learn) {
                LearnView()
            }
        }
        // Keep scheduled notifications in step with stored data on every launch.
        .task {
            UITestSupport.seedResultsIfAsked(modelContext)
            await ReminderSync.refresh(using: modelContext)
        }
        // Check NWS alerts for the saved well on launch and whenever it changes.
        .task(id: "\(wellKey ?? "")|\(settings.isOptedIn(.stormAlerts))") {
            if let well = savedWells.first, settings.isOptedIn(.stormAlerts) {
                await alertsStore.refresh(latitude: NetworkFeature.coarse(well.latitude),
                                          longitude: NetworkFeature.coarse(well.longitude))
            } else {
                alertsStore.clear()
            }
        }
    }
}

// MARK: - Demo Mode

/// Holds one in-memory store per persona for the session, so demo data survives tab switches.
@MainActor
@Observable
final class DemoStores {
    private var containers: [DemoPersona: ModelContainer] = [:]

    func container(for persona: DemoPersona) -> ModelContainer {
        if let existing = containers[persona] { return existing }
        let container = persona.makeContainer()
        containers[persona] = container
        return container
    }

    /// Fresh sample data next time the persona is opened.
    func reset(_ persona: DemoPersona) {
        containers[persona] = nil
    }
}

private struct DemoBannerModifier: ViewModifier {
    @Environment(AppSettings.self) private var settings

    /// Stacked above the content (not a safe-area inset): navigation bars and their toolbar buttons then
    /// start below the banner instead of drawing over it.
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if settings.demoEnabled {
                SampleDataBanner(text: "Sample data · Demo Mode")
                    .background(DS.Colors.background)
                    // Tint the status bar area too, so the banner reads as one strip.
                    .background(Color.statusWatch.opacity(0.18).ignoresSafeArea(edges: .top))
                    .background(DS.Colors.background.ignoresSafeArea(edges: .top))
            }
            content
        }
    }
}

extension View {
    /// "Sample data" banner on every screen while Demo Mode is on.
    func demoBanner() -> some View { modifier(DemoBannerModifier()) }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .environment(AppSettings())
        .environment(TractStore())
        .environment(WeatherAlertsStore())
        .environment(WellCareStore())
        .modelContainer(for: [SavedWell.self, LabResult.self, TreatmentSystem.self], inMemory: true)
}
