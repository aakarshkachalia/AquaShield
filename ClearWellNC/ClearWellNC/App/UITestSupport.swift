//
//  UITestSupport.swift
//  ClearWellNC
//
//  Launch arguments used only by UI tests (debug builds). They run before any settings are read.
//    -uiTestReset           Clears saved settings, drafts and draft photos (the first launch of a test).
//    -uiTestSkipOnboarding  Marks onboarding as done, saved like a real user's answer.
//    -uiTestDemo <persona>  Turns on Demo Mode with that persona (neverTested, cleanReport, arsenicProblem).
//    -uiTestAppearance <light|dark>  Forces the color scheme, for screenshots.
//

import SwiftUI

enum UITestSupport {
    /// Forced color scheme from `-uiTestAppearance`, or nil.
    static var forcedColorScheme: ColorScheme? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestAppearance"), i + 1 < args.count else { return nil }
        return args[i + 1] == "dark" ? .dark : .light
        #else
        return nil
        #endif
    }

    static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        let defaults = UserDefaults.standard
        if arguments.contains("-uiTestReset"), let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
            ScanPhotoStore(scope: "real").deleteAll()
        }
        if arguments.contains("-uiTestSkipOnboarding") {
            defaults.set(true, forKey: StorageKey.hasOnboarded)
        }
        if let i = arguments.firstIndex(of: "-uiTestDemo"), i + 1 < arguments.count {
            defaults.set(true, forKey: "settings.demoEnabled")
            defaults.set(arguments[i + 1], forKey: "settings.demoPersona")
        }
        #endif
    }
}
