//
//  ResourcesView.swift
//  ClearWellNC
//

import MapKit
import SwiftData
import SwiftUI

/// Help near the saved location: live Apple Maps results by category, plus official NC resources.
struct ResourcesView: View {
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]
    @Environment(AppSettings.self) private var settings
    private var waterSource: WaterSource { settings.waterSource }

    @State private var search = LocalResourceSearch()
    @State private var category: ResourceCategory = .testingLabs
    @State private var currentLocation: CLLocationCoordinate2D?
    @State private var locationFetcher = LocationFetcher()
    @State private var locating = false
    @State private var locationFailed = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedPlaceID: LocalPlace.ID?

    private var center: CLLocationCoordinate2D? {
        savedWells.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } ?? currentLocation
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if !settings.isOptedIn(.helpNearYou) {
                    OptInCard(feature: .helpNearYou)
                } else if let center {
                    Text(savedWells.first.map { String(localized: "Places within about 25 miles of \($0.placeName).") }
                         ?? String(localized: "Places within about 25 miles of your current location."))
                        .foregroundStyle(.secondary)
                    categoryPicker
                    Text(category.hint)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    results(center: center)
                } else {
                    locationPrompt
                }
                officialResources
                Text("Listings come from Apple Maps. \(AppName.display) does not review or endorse these businesses. For water tests, choose a lab certified by the State of North Carolina.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Help near you")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(searchKey)|\(settings.isOptedIn(.helpNearYou))") {
            guard settings.isOptedIn(.helpNearYou), let center else { return }
            await search.search(category, near: center)
            cameraPosition = .automatic
        }
    }

    private var searchKey: String {
        "\(category.rawValue)|\(center.map { "\($0.latitude),\($0.longitude)" } ?? "none")"
    }

    // MARK: Pieces

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(ResourceCategory.available(for: waterSource)) { option in
                    let selected = option == category
                    Button {
                        category = option
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .frame(minHeight: 44)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color.cardBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.cardBorder))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    @ViewBuilder
    private func results(center: CLLocationCoordinate2D) -> some View {
        switch search.state {
        case .idle, .loading:
            ProgressView("Searching nearby…")
                .frame(maxWidth: .infinity, minHeight: 120)
                .card()
        case .failed:
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label {
                    Text("We couldn't search right now. Check your internet connection.")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.statusWatch)
                }
                Button("Try again") {
                    Task { await search.search(category, near: center) }
                }
                .frame(minHeight: 44)
            }
            .card()
        case .loaded(let places):
            map(places: places, center: center)
            if places.isEmpty {
                Text("No \(category.title.lowercased()) found nearby. Try another category, or use the official resources below.")
                    .card()
            } else {
                ForEach(places) { place in
                    PlaceCard(place: place)
                }
            }
        }
    }

    private func map(places: [LocalPlace], center: CLLocationCoordinate2D) -> some View {
        Map(position: $cameraPosition, selection: $selectedPlaceID) {
            Annotation(String(localized: "Home"), coordinate: center) {
                Image(systemName: "house.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(Spacing.s)
                    .background(Color.brandPrimaryFixed, in: Circle())
            }
            ForEach(places) { place in
                Marker(place.name, systemImage: category.symbol, coordinate: place.coordinate)
                    .tag(place.id)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardBorder))
        .accessibilityLabel(Text("Map of \(places.count) places near your home"))
    }

    private var locationPrompt: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                IconTile(systemImage: "location.fill")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Where should we look?")
                        .font(.headline)
                    Text("Save your home on the Check My Area tab, or use your current location. Your location is only used for this search.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: useMyLocation) {
                Label("Use my location", systemImage: "location.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(locating)
            if locationFailed {
                Text("We couldn't get your location. Check that location access is on for \(AppName.display) in Settings.")
                    .font(.caption)
                    .foregroundStyle(Color.statusAbove)
            }
        }
        .card()
    }

    private var officialResources: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionHeader(title: "Official resources")
            VStack(alignment: .leading, spacing: 0) {
                resourceLink("Your county health department",
                             detail: waterSource.showsWellCare ? "Well testing kits, sample pickup and advice" : "Advice on testing your tap",
                             systemImage: "cross.case", url: WellResources.ncCountyHealthDepartments)
                Divider()
                resourceLink("NC State Laboratory of Public Health", detail: "The state's public health lab",
                             systemImage: "testtube.2", url: WellResources.ncStateLab)
                Divider()
                if waterSource.showsWellCare {
                    resourceLink("NC DHHS: private well testing", detail: "What to test for and how often",
                                 systemImage: "drop.circle", url: WellResources.ncdhhsPrivateWells)
                } else {
                    resourceLink("Find your water quality report", detail: "Your utility's yearly Consumer Confidence Report",
                                 systemImage: "building.2", url: WellResources.epaConsumerConfidenceReports)
                }
                Divider()
                resourceLink("Look up certified filters (NSF)", detail: "Check what a filter is certified to remove",
                             systemImage: "checkmark.seal", url: WellResources.nsfCertifiedFilters)
            }
            .card()
        }
    }

    private func resourceLink(_ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: Spacing.m) {
                IconTile(systemImage: systemImage)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.s)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }

    private func useMyLocation() {
        locating = true
        locationFailed = false
        Task {
            defer { locating = false }
            do {
                currentLocation = try await locationFetcher.currentLocation().coordinate
            } catch {
                locationFailed = true
            }
        }
    }
}

/// One business: name, address, distance, and call / website / directions.
private struct PlaceCard: View {
    let place: LocalPlace
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name)
                        .font(.headline)
                    Spacer(minLength: Spacing.s)
                    Text(place.distanceText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let address = place.address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { actions }
                VStack(alignment: .leading, spacing: Spacing.s) { actions }
            }
        }
        .card()
    }

    @ViewBuilder
    private var actions: some View {
        if let call = place.callURL {
            actionButton("Call", systemImage: "phone.fill") { openURL(call) }
        }
        if let website = place.website {
            actionButton("Website", systemImage: "safari") { openURL(website) }
        }
        actionButton("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
            place.item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        }
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, Spacing.xs)
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
