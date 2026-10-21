//
//  SourcesView.swift
//  ClearWellNC
//
//  Every program and data source, with links, and which datasets are sample data.
//

import SwiftUI

struct SourcesView: View {
    @State private var programs = HelpLibrary.loadBundled().programs
    @State private var countyData = CountyWellData.loadBundled()
    @State private var trends = CountyTrendData.loadBundled()

    private struct DataSource: Identifiable {
        let id: String
        let name: String
        let detail: String
        let isSample: Bool
    }

    private var dataSources: [DataSource] {
        [
            DataSource(id: "tracts", name: String(localized: "Census-tract well risk map"),
                       detail: String(localized: "NCWELL database (Eaves et al. 2021, UNC Superfund Research Program), 1998–2019, with ClearWell's model estimates."),
                       isSample: false),
            DataSource(id: "county", name: String(localized: "County well facts (Risk Check)"),
                       detail: countyData?.source ?? "", isSample: countyData?.sample ?? true),
            DataSource(id: "trends", name: String(localized: "Seasonal trends and forecast"),
                       detail: String(localized: "Monthly county medians used by the seasonal model. Placeholder values for development."),
                       isSample: trends?.isSample ?? true),
            DataSource(id: "sampleReport", name: String(localized: "Sample lab report"),
                       detail: String(localized: "A made-up report for trying the scanner. Not a real test result."),
                       isSample: true),
            DataSource(id: "demo", name: String(localized: "Demo Mode personas"),
                       detail: String(localized: "Made-up households and results, kept separate from your real data."),
                       isSample: true),
            DataSource(id: "limits", name: String(localized: "Limits and health information"),
                       detail: String(localized: "EPA drinking water standards and health advisories, CDC and NC DHHS guidance. See each Learn card for links."),
                       isSample: false),
        ]
    }

    private var references: [(String, URL)] {
        [
            (String(localized: "NC DHHS: private well testing"), WellResources.ncdhhsPrivateWells),
            (String(localized: "NC county health departments"), WellResources.ncCountyHealthDepartments),
            (String(localized: "NC State Laboratory of Public Health"), WellResources.ncStateLab),
            (String(localized: "EPA: private drinking water wells"), WellResources.epaPrivateWells),
            (String(localized: "EPA: primary drinking water standards"), WellResources.epaPrimaryStandards),
            (String(localized: "EPA: secondary drinking water standards"), WellResources.epaSecondaryStandards),
            (String(localized: "CDC: private water systems"), WellResources.cdcPrivateWells),
            (String(localized: "NC Radon Program"), WellResources.ncRadon),
            (String(localized: "NC Attorney General: report a scam"), WellResources.ncAttorneyGeneralComplaint),
        ]
    }

    var body: some View {
        List {
            Section("Data in this app") {
                ForEach(dataSources) { source in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text(source.name).font(.headline)
                            Spacer()
                            if source.isSample { SampleDataTag() }
                        }
                        Text(source.detail)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Help programs") {
                ForEach(programs) { program in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(program.name).font(.headline)
                        Text(program.agency).font(.subheadline).foregroundStyle(Color.textSecondary)
                        if let phone = program.phone { Text(phone).font(.subheadline) }
                        if let email = program.email { Text(email).font(.subheadline) }
                        if let url = program.websiteURL {
                            Link(url.host() ?? url.absoluteString, destination: url)
                                .font(.subheadline)
                                .frame(minHeight: TapTarget.minimum)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }

            Section("References") {
                ForEach(references, id: \.1) { title, url in
                    Link(destination: url) {
                        Label(title, systemImage: "arrow.up.right.square")
                            .frame(minHeight: TapTarget.minimum)
                    }
                }
            }

            Section {
                Text(DisclaimerFooter.standardText)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle("Sources and data")
    }
}
