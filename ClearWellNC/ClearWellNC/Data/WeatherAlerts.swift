//
//  WeatherAlerts.swift
//  ClearWellNC
//
//  Active alerts from the free National Weather Service API for the saved My Well location.
//

import Foundation
import Observation

nonisolated struct WeatherAlert: Sendable, Identifiable, Hashable {
    let id: String
    let event: String
    let headline: String?
    let areaDescription: String?
    let ends: Date?

    /// Flood watches and warnings, hurricanes and tropical storms are the alerts that put wells at risk.
    var isWellRelevant: Bool { Self.isWellRelevant(event: event) }

    static func isWellRelevant(event: String) -> Bool {
        let e = event.lowercased()
        if e.contains("hurricane") || e.contains("tropical storm") { return true }
        return e.contains("flood") && (e.contains("watch") || e.contains("warning"))
    }
}

nonisolated enum NWSClient {
    /// NWS asks every client to identify itself with contact information in the User-Agent.
    /// TODO: replace with the app's real support email before release.
    static let contact = "support@example.com"
    static var userAgent: String { "ClearWellNC (\(contact))" }

    enum NWSError: Error {
        case badResponse
    }

    private struct Response: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let id: String?
                let event: String?
                let headline: String?
                let areaDesc: String?
                let ends: String?
                let expires: String?
            }
            let id: String?
            let properties: Properties
        }
        let features: [Feature]
    }

    static func activeAlerts(latitude: Double, longitude: Double,
                             session: URLSession = .shared) async throws -> [WeatherAlert] {
        // The API expects at most 4 decimal places; more triggers a redirect.
        let point = String(format: "%.4f,%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        components.queryItems = [URLQueryItem(name: "point", value: point)]
        guard let url = components.url else { throw NWSError.badResponse }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NWSError.badResponse
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> [WeatherAlert] {
        let iso = ISO8601DateFormatter()
        return try JSONDecoder().decode(Response.self, from: data).features.compactMap { feature in
            let p = feature.properties
            guard let event = p.event, let id = p.id ?? feature.id else { return nil }
            return WeatherAlert(id: id, event: event, headline: p.headline, areaDescription: p.areaDesc,
                                ends: (p.ends ?? p.expires).flatMap { iso.date(from: $0) })
        }
    }
}

/// Holds the latest alert check for the saved well. Checked on launch and on pull-to-refresh.
@MainActor
@Observable
final class WeatherAlertsStore {
    enum State {
        case idle
        case loading
        case loaded(alerts: [WeatherAlert], checkedAt: Date)
        case failed
    }

    private(set) var state: State = .idle

    var relevantAlerts: [WeatherAlert] {
        if case .loaded(let alerts, _) = state { return alerts.filter(\.isWellRelevant) }
        return []
    }

    func refresh(latitude: Double, longitude: Double) async {
        state = .loading
        do {
            let alerts = try await NWSClient.activeAlerts(latitude: latitude, longitude: longitude)
            state = .loaded(alerts: alerts, checkedAt: .now)
        } catch {
            state = .failed
        }
    }

    func clear() {
        state = .idle
    }
}
