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
                    Text("Free or low-cost testing, help paying for fixes, and what to do in an emergency.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)

                    VStack(spacing: DS.Space.m) {
                        NavigationLink {
                            FindTestingView()
                        } label: {
                            NavigationCardLabel(title: Text("Find testing"),
                                                subtitle: Text("Who to call, and how to take a sample."),
                                                systemImage: DS.Icon.test)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("getHelp.findTesting")
                        if source.showsWellCare {
                            Button {
                                router.showingRiskCheck = true
                            } label: {
                                NavigationCardLabel(title: Text("Should I test my well?"),
                                                    subtitle: Text("7 quick questions"),
                                                    systemImage: DS.Icon.riskCheck)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("getHelp.riskCheck")

                            NavigationLink {
                                StormModeView()
                            } label: {
                                NavigationCardLabel(title: Text("My well flooded"),
                                                    subtitle: Text("Stay safe, disinfect, then retest."),
                                                    systemImage: DS.Icon.alert(.flood))
                            }
                            .buttonStyle(.plain)
                        }
                        if source.showsCityContent {
                            NavigationLink {
                                UtilityReportView()
                            } label: {
                                NavigationCardLabel(title: Text("My water utility"),
                                                    subtitle: Text("Your yearly water report, lead pipes, boil notices."),
                                                    systemImage: "building.2.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HelpFinderSection()

                    SectionHeader(title: "More help")
                    NavigationLink {
                        ResourcesView()
                    } label: {
                        NavigationCardLabel(title: Text("Labs and services near you"),
                                            subtitle: Text("Labs, plumbers and filter dealers on a map."),
                                            systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.plain)
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
