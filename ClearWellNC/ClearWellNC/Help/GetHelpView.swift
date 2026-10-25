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
                VStack(alignment: .leading, spacing: 0) {
                    Text("Help").font(M.Font.screenTitle).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
                    NavigationLink { ResourcesView() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.system(.subheadline, weight: .light))
                            Text("Labs, programs, plumbers…").font(M.Font.row).foregroundStyle(M.Colors.muted)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: DS.Size.tapTarget)
                        .overlay(Rectangle().strokeBorder(M.Colors.line, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    TileGrid(columns: 2, spacing: 8) {
                        NavigationLink { FindTestingView() } label: {
                            cell("testtube.2", String(localized: "Find testing"), String(localized: "Who to call"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("getHelp.findTesting")
                        if source.showsWellCare {
                            Button { router.showingRiskCheck = true } label: {
                                cell("checklist", String(localized: "Should I test?"), String(localized: "7 questions"))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("getHelp.riskCheck")
                            NavigationLink { StormModeView() } label: {
                                cell("water.waves", String(localized: "Well flooded"), String(localized: "Step by step"))
                            }
                            .buttonStyle(.plain)
                        }
                        if source.showsCityContent {
                            NavigationLink { UtilityReportView() } label: {
                                cell("building.2", String(localized: "My water utility"), String(localized: "Boil notices, lead"))
                            }
                            .buttonStyle(.plain)
                        }
                        NavigationLink { ResourcesView() } label: {
                            cell("mappin.and.ellipse", String(localized: "Help near you"), String(localized: "Labs & plumbers"))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 12) {
                        M.SectionHeader(title: String(localized: "Programs"), note: settings.county.map { String(localized: "\($0) County") })
                        // Every bundled help program is for private wells.
                        if source.showsWellCare {
                            HelpFinderSection()
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "building.2").font(.system(.body, weight: .light))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Your water utility is your first call").font(M.Font.section)
                                    Text("For boil notices, lead pipes or a change in your water.")
                                        .font(M.Font.small).foregroundStyle(M.Colors.muted)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(M.Colors.surface)
                        }
                        if source.showsWellCare {
                            NavigationLink { CheckAreaView() } label: {
                                HStack {
                                    Image(systemName: "map").font(.system(.body, weight: .light))
                                    Text("Well risk in my area").font(M.Font.section)
                                    Spacer()
                                    Text("→")
                                }
                                .frame(minHeight: 48)
                                .overlay(alignment: .top) { M.Rule() }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    M.Footer().padding(.horizontal, 20)
                }
                .frame(maxWidth: DS.Size.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .modernistScreen()
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    private func cell(_ symbol: String, _ title: String, _ caption: String) -> some View {
        M.Cell {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(.title3, weight: .light)).accessibilityHidden(true)
                Text(title).font(M.Font.section).lineLimit(2)
                Text(caption).font(M.Font.tiny).foregroundStyle(M.Colors.muted)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
