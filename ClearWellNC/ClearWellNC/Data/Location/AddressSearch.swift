//
//  AddressSearch.swift
//  ClearWellNC
//
//  Address autocomplete (MKLocalSearchCompleter) and lookup (MKLocalSearch), biased to North Carolina.
//  The typed text goes to Apple only; the chosen address and its coordinates are stored on this phone.
//

import MapKit
import Observation

@MainActor
@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var isSearching = false
    private(set) var failed = false

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    /// About North Carolina.
    static let ncRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 35.5, longitude: -79.4),
                                             span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 9))

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = Self.ncRegion
    }

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.count < 3 { suggestions = [] } else { completer.queryFragment = trimmed }
        }
    }

    /// The coordinates and full address for a suggestion.
    func resolve(_ suggestion: MKLocalSearchCompletion) async -> (address: String, coordinate: CLLocationCoordinate2D)? {
        isSearching = true
        failed = false
        defer { isSearching = false }
        let request = MKLocalSearch.Request(completion: suggestion)
        request.region = Self.ncRegion
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            failed = true
            return nil
        }
        let address = [suggestion.title, suggestion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        return (address, item.location.coordinate)
    }

    // The completer calls back on the main thread (it was created there), so assumeIsolated is safe.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { self.suggestions = Array(completer.results.prefix(5)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.suggestions = [] }
    }
}
