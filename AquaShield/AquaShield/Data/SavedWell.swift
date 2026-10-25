//
//  SavedWell.swift
//  AquaShield
//

import Foundation
import SwiftData

/// The user's "My Well". Only created when the user explicitly taps Save as My Well; kept on device only.
@Model
final class SavedWell {
    var fips: String
    var latitude: Double
    var longitude: Double
    var placeName: String
    var savedAt: Date

    init(fips: String, latitude: Double, longitude: Double, placeName: String, savedAt: Date = .now) {
        self.fips = fips
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.savedAt = savedAt
    }
}
