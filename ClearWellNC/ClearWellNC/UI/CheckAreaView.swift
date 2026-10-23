//
//  CheckAreaView.swift
//  ClearWellNC
//

import SwiftUI

struct CheckAreaView: View {
    @Environment(TractStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(AppSettings.self) private var settings

    @State private var address = ""
    @State private var isWorking = false
    @State private var error: AreaLookupError?
    @State private var selection: AreaSelection?
    @State private var mapSelection: AreaSelection?
    @State private var mapContaminant: Contaminant = .arsenic
    @State private var locationFetcher = LocationFetcher()
    @FocusState private var addressFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Find out what your area's well water is likely to contain, and what to test for.")
                    .foregroundStyle(.secondary)

                switch store.state {
                case .loading:
                    ProgressView("Loading well data…")
                        .frame(maxWidth: .infinity)
                        .card()
                case .failed(let message):
                    errorCard(message)
                case .loaded(let db):
                    searchCard
                    AreaMapSection(database: db,
                                   contaminant: $mapContaminant,
                                   selection: $mapSelection,
                                   onOpenReport: { selection = $0 })
                }

                if isWorking {
                    ProgressView("Looking up your area…")
                        .frame(maxWidth: .infinity)
                }

                if let error {
                    errorCard(error.errorDescription ?? "", showSettings: error == .locationDenied)
                }

                householdCard
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Check My Area")
        .navigationDestination(item: $selection) { selection in
            if let db = store.database {
                ReportView(selection: selection, meta: db.meta)
            }
        }
    
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Your address")
                .font(.headline)
            TextField("Street address, city or ZIP", text: $address)
                .textContentType(.fullStreetAddress)
                .submitLabel(.search)
                .focused($addressFocused)
                .onSubmit(checkAddress)
                .padding(Spacing.m)
                .frame(minHeight: 44)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .accessibilityLabel(Text("Address"))

            Button(action: checkAddress) {
                Text("Check this address")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: useMyLocation) {
                Label("Use my location", systemImage: "location.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("Your address or location is only used to find your census tract. It is not saved unless you choose to save it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(isWorking)
        .card()
    }

    private var householdCard: some View {
        @Bindable var settings = settings
        return Toggle("A baby under 6 months lives here", isOn: $settings.infantInHome)
            .frame(minHeight: 44)
            .card()
    }

    private func errorCard(_ message: String, showSettings: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(RiskLevel.elevated.color)
            }
            .accessibilityElement(children: .combine)
            if showSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .frame(minHeight: 44)
            }
        }
        .card()
    }

    private func checkAddress() {
        run { db in try await AreaLookup.lookup(address: address, in: db) }
    }

    private func useMyLocation() {
        run { db in try await AreaLookup.lookupCurrentLocation(using: locationFetcher, in: db) }
    }

    private func run(_ lookup: @escaping (TractDatabase) async throws -> AreaSelection) {
        guard let db = store.database, !isWorking else { return }
        addressFocused = false
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let result = try await lookup(db)
                mapSelection = result
                selection = result
            } catch let lookupError as AreaLookupError {
                error = lookupError
            } catch {
                self.error = .locationUnavailable
            }
        }
    }
}
