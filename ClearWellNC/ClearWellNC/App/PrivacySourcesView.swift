//
//  PrivacySourcesView.swift
//  ClearWellNC
//
//  Settings > Privacy & Sources: every request that leaves the phone, each switch, and what never leaves.
//

import SwiftUI

struct PrivacySourcesView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List { Group {
            Section {
                ForEach(NetworkFeature.allCases) { feature in
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Toggle(isOn: Binding(get: { settings.networkOptIns.contains(feature) },
                                             set: { on in
                                                 if on { settings.networkOptIns.insert(feature) } else { settings.networkOptIns.remove(feature) }
                                             })) {
                            Label(feature.title, systemImage: feature.symbol)
                        }
                        .frame(minHeight: DS.Size.tapTarget)
                        Text("To: \(feature.outboundRequest.recipient)")
                            .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                        Text("Sends: \(feature.outboundRequest.sends)")
                            .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label("Maps", systemImage: "map")
                    Text("To: Apple Maps. Sends: the map area on screen, to load map images, whenever a map is shown.")
                        .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label("Links you tap", systemImage: "safari")
                    Text("Opening a link (NC DHHS, EPA, NSF) opens that website in your browser.")
                        .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                }
            } header: {
                Text("What leaves this phone")
            } footer: {
                Text("Each feature is off until you turn it on. Location is rounded before it's sent.")
            }

            Section("What never leaves this phone") {
                Label("Lab results and scanned reports", systemImage: "doc.text.fill")
                Label("Household members, symptoms and health answers", systemImage: "person.2.fill")
                Label("Filters, home and plumbing answers", systemImage: "house.fill")
                Label("Your utility report numbers", systemImage: "building.2.fill")
            }

            Section("Sources") {
                NavigationLink("Sources and data") { SourcesView() }
                #if DEBUG
                NavigationLink("Data review (needs verification)") { DataReviewView() }
                #endif
            }
        }
        .listRowBackground(M.Colors.surface)
        }
        .modernistList()
        .navigationTitle("Privacy & Sources")
    }
}
