//
//  DraftStore.swift
//  ClearWellNC
//
//  In-progress answers for every flow (Risk Check, onboarding, lab entry, scanner review, Report Quest,
//  quizzes, filters), saved on every change so they survive closing or force-quitting the app.
//  Small JSON blobs in UserDefaults, under the real/demo scope from AppSettings. Never leaves the device.
//

import Foundation

/// Names one flow's draft and the shape of its saved data.
nonisolated struct DraftKey<Payload: Codable>: Sendable {
    let name: String
    /// Bump when a flow's steps or payload change. Saved drafts with another version are discarded.
    let schemaVersion: Int
}

nonisolated struct Draft<Payload: Codable>: Codable {
    var schemaVersion: Int
    /// When the user first changed something. Shown as "Started 2 days ago".
    var startedAt: Date
    var updatedAt: Date
    var payload: Payload
}

nonisolated struct DraftStore {
    let defaults: UserDefaults
    /// Real/demo scope, for example "settings.real.draft.".
    let prefix: String
    var now: () -> Date = { .now }

    /// Just enough to check the version without decoding the payload.
    private struct Header: Decodable {
        var schemaVersion: Int
        var startedAt: Date
    }

    private func storageKey<P>(_ key: DraftKey<P>) -> String { prefix + key.name }

    /// The saved draft, or nil. A draft from another schema version, or one that can't be decoded,
    /// is removed quietly so the flow starts fresh instead of restoring a step that no longer exists.
    func load<P>(_ key: DraftKey<P>) -> Draft<P>? {
        guard let data = defaults.data(forKey: storageKey(key)) else { return nil }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.schemaVersion == key.schemaVersion,
              let draft = try? JSONDecoder().decode(Draft<P>.self, from: data)
        else {
            discard(key)
            return nil
        }
        return draft
    }

    /// Saves the payload, keeping the original start date.
    func save<P>(_ payload: P, for key: DraftKey<P>) {
        let started = startedAt(key) ?? now()
        let draft = Draft(schemaVersion: key.schemaVersion, startedAt: started, updatedAt: now(), payload: payload)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: storageKey(key))
    }

    func discard<P>(_ key: DraftKey<P>) {
        defaults.removeObject(forKey: storageKey(key))
    }

    private func startedAt<P>(_ key: DraftKey<P>) -> Date? {
        guard let data = defaults.data(forKey: storageKey(key)),
              let header = try? JSONDecoder().decode(Header.self, from: data),
              header.schemaVersion == key.schemaVersion else { return nil }
        return header.startedAt
    }
}

/// "Started 2 days ago" for the Continue / Start over prompt.
nonisolated enum DraftAge {
    static func startedText(_ startedAt: Date, now: Date = .now, locale: Locale = .current) -> String {
        if now.timeIntervalSince(startedAt) < 60 { return String(localized: "Started just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: startedAt, relativeTo: now)
        return String(localized: "Started \(relative)")
    }
}
