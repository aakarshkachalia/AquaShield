//
//  AppName.swift
//  ClearWellNC
//
//  The app's name, in one place. To rename the app, change APP_DISPLAY_NAME in the target's build
//  settings (Xcode > target > Build Settings, or project.pbxproj): it sets CFBundleDisplayName and the
//  permission strings, and every screen reads it from here. The bundle identifier, target and file
//  names are unchanged.
//

import Foundation

nonisolated enum AppName {
    /// Used if the bundle has no display name (unit tests, previews).
    static let fallback = "ClearWell NC"

    static let display: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? fallback
}
