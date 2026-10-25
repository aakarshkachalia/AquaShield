//
//  AppName.swift
//  AquaShield
//
//  The app's name, in one place. To rename the app, change APP_DISPLAY_NAME in the target's build
//  settings (Xcode > target > Build Settings, or project.pbxproj): it sets CFBundleDisplayName and the
//  permission strings, and every screen reads it from here. The bundle identifier keeps its original
//  value so installed copies update in place and keep their data.
//

import Foundation

nonisolated enum AppName {
    /// Used if the bundle has no display name (unit tests, previews).
    static let fallback = "AquaShield"

    static let display: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fallback
}
