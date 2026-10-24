//
//  UITestSupport.swift
//  ClearWellNC
//
//  Launch arguments used only by UI tests (debug builds). They run before any settings are read.
//  Any -uiTest… argument switches the app to its own test storage (a separate UserDefaults suite and
//  SwiftData file), so running UI tests on a real phone never touches the owner's data.
//    -uiTestReset           Clears the test storage (the first launch of a test).
//    -uiTestSkipOnboarding  Marks onboarding as done, saved like a real user's answer.
//    -uiTestDemo <persona>  Turns on Demo Mode with that persona (neverTested, cleanReport, arsenicProblem).
//    -uiTestAppearance <light|dark>  Forces the color scheme, for screenshots.
//    -uiTestSource <publicWater|privateWell|both|notSure>  Sets the confirmed water source.
//    -uiTestSeedResults     Adds one lab result labeled "SAMPLE — UI test" if there are none.
//

import SwiftData
import SwiftUI

enum UITestSupport {
    static let suiteName = "ClearWellUITests"

    /// True when launched by a UI test (debug builds only).
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-uiTest") }
        #else
        false
        #endif
    }

    /// Where settings live: the real defaults, or the separate test suite during UI tests.
    static var defaults: UserDefaults {
        isUITesting ? (UserDefaults(suiteName: suiteName) ?? .standard) : .standard
    }

    /// SwiftData file for UI tests, kept apart from the real store.
    static var testStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "UITests.store")
    }

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

    /// One clearly labeled sample result, so result screens have something to show in UI tests.
    @MainActor
    static func seedResultsIfAsked(_ context: ModelContext) {
        guard isUITesting, ProcessInfo.processInfo.arguments.contains("-uiTestSeedResults"),
              ((try? context.fetchCount(FetchDescriptor<LabResult>())) ?? 0) == 0 else { return }
        let result = LabResult(date: .now.addingTimeInterval(-30 * 86_400), labName: "SAMPLE — UI test")
        result.leadPPB = 3
        result.copperMgL = 0.2
        result.nitrateMgL = 1
        result.pfoaPPT = 2
        result.totalColiform = .absent
        result.eColi = .absent
        context.insert(result)
        try? context.save()
    }

    static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        guard isUITesting else { return }
        let defaults = Self.defaults
        if arguments.contains("-uiTestReset") {
            defaults.removePersistentDomain(forName: suiteName)
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: testStoreURL.path + suffix))
            }
        }
        if arguments.contains("-uiTestSkipOnboarding") {
            defaults.set(true, forKey: AppSettings.onboardingKey)
        }
        if let i = arguments.firstIndex(of: "-uiTestSource"), i + 1 < arguments.count {
            defaults.set(arguments[i + 1], forKey: AppSettings.realWaterSourceKey)
        }
        if let i = arguments.firstIndex(of: "-uiTestDemo"), i + 1 < arguments.count {
            defaults.set(true, forKey: "settings.demoEnabled")
            defaults.set(arguments[i + 1], forKey: "settings.demoPersona")
        }
        #endif
    }
}
