//
//  GetHelpView.swift
//  ClearWellNC
//
//  Get Help tab: who can test your well, who may pay to fix it, and what to do after a flood.
//

import SwiftUI

struct GetHelpView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    private var source: WaterSource { settings.waterSource }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    Text("Testing, help paying for fixes, emergencies.")
                        .font(DS.Typography.lightBody)
                        .foregroundStyle(DS.Colors.textSecondary)

                    TileGrid(columns: 2, spacing: DS.Space.m) {
                        NavigationLink { FindTestingView() } label: {
                            ShortcutTile(title: String(localized: "Find testing"), systemImage: "testtube.2",
                                         caption: String(localized: "Who to call"))
                        }
                        .buttonStyle(DS.PressableCardStyle())
                        .accessibilityIdentifier("getHelp.findTesting")
                        if source.showsWellCare {
                            Button { router.showingRiskCheck = true } label: {
                                ShortcutTile(title: String(localized: "Should I test my well?"), systemImage: "checklist",
                                             caption: String(localized: "7 questions"))
                            }
                            .buttonStyle(DS.PressableCardStyle())
                            .accessibilityIdentifier("getHelp.riskCheck")
                            NavigationLink { StormModeView() } label: {
                                ShortcutTile(title: String(localized: "My well flooded"), systemImage: "water.waves",
                                             caption: String(localized: "Step by step"), tint: DS.Colors.fair)
                            }
                            .buttonStyle(DS.PressableCardStyle())
                        }
                        if source.showsCityContent {
                            NavigationLink { UtilityReportView() } label: {
                                ShortcutTile(title: String(localized: "My water utility"), systemImage: "building.2",
                                             caption: String(localized: "Boil notices, lead"))
                            }
                            .buttonStyle(DS.PressableCardStyle())
                        }
                        NavigationLink { ResourcesView() } label: {
                            ShortcutTile(title: String(localized: "Help near you"), systemImage: "mappin.and.ellipse",
                                         caption: String(localized: "Labs and plumbers"))
                        }
                        .buttonStyle(DS.PressableCardStyle())
                    }

                    // Every bundled help program is for private wells.
                    if source.showsWellCare {
                        HelpFinderSection()
                    } else {
                        DS.InfoCard(systemImage: "building.2.fill", title: String(localized: "Your water utility is your first call"),
                                    message: String(localized: "For boil notices, lead pipes or a change in your water."))
                    }

                    if source.showsWellCare {
                        NavigationLink {
                            CheckAreaView()
                        } label: {
                            NavigationCardLabel(title: Text("Well risk in my area"),
                                                subtitle: Text("Look up any NC address on the risk map."),
                                                systemImage: "map.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    DisclaimerFooter()
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Get Help")
        }
    }
}
