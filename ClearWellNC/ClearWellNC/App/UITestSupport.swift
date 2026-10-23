//
//  UITestSupport.swift
//  ClearWellNC
//
//  Launch arguments used only by UI tests (debug builds). They run before any settings are read.
//    -uiTestReset           Clears saved settings, drafts and draft photos (the first launch of a test).
//    -uiTestSkipOnboarding  Marks onboarding as done, saved like a real user's answer.
//

import Foundation

enum UITestSupport {
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
        #endif
    }
}
