//
//  LocationFetcher.swift
//  ClearWellNC
//

import CoreLocation

/// One-shot "where am I" using When In Use permission.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    enum LocationError: Error {
        case denied
        case unavailable
    }

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        // Tract-level accuracy is plenty, and it resolves faster.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        guard locationContinuation == nil, authContinuation == nil else { throw LocationError.unavailable }

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw LocationError.denied }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // CLLocationManager calls back on the thread it was created on (main), so assumeIsolated is safe.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            // This also fires once when the delegate is set; ignore the undetermined state.
            guard status != .notDetermined, let continuation = authContinuation else { return }
            authContinuation = nil
            continuation.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated {
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            if let location {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated {
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(throwing: denied ? LocationError.denied : LocationError.unavailable)
        }
    }
}
