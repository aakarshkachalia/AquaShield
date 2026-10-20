//
//  GetHelpView.swift
//  ClearWellNC
//
//  Get Help tab: who can test your well, who may pay to fix it, and what to do after a flood.
//

import SwiftUI

struct GetHelpView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text("Find free or low-cost testing, programs that may pay to fix a problem, and help after a flood.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    Button {
                        router.showingRiskCheck = true
                    } label: {
                        NavigationCardLabel(title: Text("Should I test?"),
                                            subtitle: Text("A 7-question Risk Check."),
                                            systemImage: "checklist")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StormModeView()
                    } label: {
                        NavigationCardLabel(title: Text("My well flooded"),
                                            subtitle: Text("Step-by-step: stay safe, disinfect, and retest."),
                                            systemImage: "cloud.heavyrain.fill")
                    }
                    .buttonStyle(.plain)

                    HelpFinderSection()

                    SectionHeader(title: "More help")
                    NavigationLink {
                        ResourcesView()
                    } label: {
                        NavigationCardLabel(title: Text("Labs and services near you"),
                                            subtitle: Text("Testing labs, well services, plumbers and filter dealers on the map."),
                                            systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        CheckAreaView()
                    } label: {
                        NavigationCardLabel(title: Text("Well risk in my area"),
                                            subtitle: Text("Look up any NC address on the census-tract risk map."),
                                            systemImage: "map.fill")
                    }
                    .buttonStyle(.plain)

                    DisclaimerFooter()
                }
                .screenContainer()
            }
            .background(Color.appBackground)
            .navigationTitle("Get Help")
        }
    }
}
