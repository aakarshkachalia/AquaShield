//
//  DraftAndFlowTests.swift
//  ClearWellNCTests
//
//  Drafts (save/restore, schema versions, real/demo separation), StepFlow navigation, and the draft
//  payloads for each flow.
//

import XCTest
@testable import ClearWellNC

final class DraftStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "DraftStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private struct Payload: Codable, Equatable {
        var step: Int
        var note: String
    }

    private let key = DraftKey<Payload>(name: "test", schemaVersion: 1)

    func testSaveAndLoadRoundTrip() throws {
        let store = DraftStore(defaults: defaults, prefix: "p.")
        store.save(Payload(step: 2, note: "hi"), for: key)
        let draft = try XCTUnwrap(store.load(key))
        XCTAssertEqual(draft.payload, Payload(step: 2, note: "hi"))
        XCTAssertEqual(draft.schemaVersion, 1)
    }

    func testStartDateIsKeptAcrossSaves() throws {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var store = DraftStore(defaults: defaults, prefix: "p.")
        store.now = { start }
        store.save(Payload(step: 1, note: ""), for: key)
        store.now = { start.addingTimeInterval(3_600) }
        store.save(Payload(step: 2, note: ""), for: key)
        let draft = try XCTUnwrap(store.load(key))
        XCTAssertEqual(draft.startedAt, start)
        XCTAssertEqual(draft.updatedAt, start.addingTimeInterval(3_600))
        XCTAssertEqual(draft.payload.step, 2)
    }

    func testOtherSchemaVersionIsDiscardedQuietly() {
        let store = DraftStore(defaults: defaults, prefix: "p.")
        store.save(Payload(step: 5, note: "old"), for: key)
        let newer = DraftKey<Payload>(name: "test", schemaVersion: 2)
        XCTAssertNil(store.load(newer))
        // Removed, so even the old version can't come back.
        XCTAssertNil(defaults.data(forKey: "p.test"))
        XCTAssertNil(store.load(key))
    }

    func testUndecodableDraftIsDiscarded() {
        defaults.set(Data("not json".utf8), forKey: "p.test")
        XCTAssertNil(DraftStore(defaults: defaults, prefix: "p.").load(key))
        XCTAssertNil(defaults.data(forKey: "p.test"))
    }

    func testRiskCheckDraftFromOlderSchemaStartsFresh() {
        let store = DraftStore(defaults: defaults, prefix: "p.")
        // A v0 draft whose steps no longer exist.
        let stale = #"{"schemaVersion":0,"startedAt":0,"updatedAt":0,"payload":{"answers":{},"flow":{"root":"gone","path":["missing"]}}}"#
        defaults.set(Data(stale.utf8), forKey: "p." + RiskCheckDraft.key.name)
        XCTAssertNil(store.load(RiskCheckDraft.key))
        XCTAssertNil(defaults.data(forKey: "p." + RiskCheckDraft.key.name))
    }

    func testDiscard() {
        let store = DraftStore(defaults: defaults, prefix: "p.")
        store.save(Payload(step: 1, note: ""), for: key)
        store.discard(key)
        XCTAssertNil(store.load(key))
    }

    @MainActor
    func testDemoDraftsNeverMixWithRealOnes() throws {
        let settings = AppSettings(defaults: defaults)
        settings.drafts.save(Payload(step: 1, note: "real"), for: key)
        settings.demoEnabled = true
        XCTAssertNil(settings.drafts.load(key))
        settings.drafts.save(Payload(step: 9, note: "demo"), for: key)
        settings.demoEnabled = false
        XCTAssertEqual(try XCTUnwrap(settings.drafts.load(key)).payload.note, "real")
    }

    @MainActor
    func testResetRealDataRemovesDrafts() {
        let settings = AppSettings(defaults: defaults)
        settings.drafts.save(Payload(step: 1, note: ""), for: key)
        settings.resetRealData()
        XCTAssertNil(settings.drafts.load(key))
    }

    func testStartedText() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(DraftAge.startedText(now.addingTimeInterval(-10), now: now, locale: en), "Started just now")
        XCTAssertEqual(DraftAge.startedText(now.addingTimeInterval(-2 * 86_400), now: now, locale: en), "Started 2 days ago")
        XCTAssertEqual(DraftAge.startedText(now.addingTimeInterval(-3 * 3_600), now: now, locale: en), "Started 3 hours ago")
    }
}

final class HouseholdScopeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "HouseholdScopeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testDemoPersonaCannotOverwriteRealHouseholdFlags() {
        let settings = AppSettings(defaults: defaults)
        settings.infantInHome = true
        settings.pregnantInHome = true
        settings.lowIncome = true
        settings.county = "Wake"
        settings.waterSource = .publicWater

        settings.demoEnabled = true
        XCTAssertFalse(settings.infantInHome)
        XCTAssertEqual(settings.waterSource, .privateWell, "Demo personas have private wells")
        settings.waterSource = .notSure
        settings.infantInHome = false
        settings.pregnantInHome = false
        settings.lowIncome = false
        settings.county = "Union"

        settings.demoEnabled = false
        XCTAssertTrue(settings.infantInHome)
        XCTAssertTrue(settings.pregnantInHome)
        XCTAssertTrue(settings.lowIncome)
        XCTAssertEqual(settings.county, "Wake")
        XCTAssertEqual(settings.waterSource, .publicWater)
        XCTAssertEqual(defaults.string(forKey: AppSettings.realWaterSourceKey), WaterSource.publicWater.rawValue)
    }

    @MainActor
    func testLegacyGlobalInfantFlagMovesToRealScope() {
        defaults.set(true, forKey: StorageKey.infantInHome)
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.infantInHome)
        XCTAssertNil(defaults.object(forKey: StorageKey.infantInHome))
        settings.demoEnabled = true
        XCTAssertFalse(settings.infantInHome)
    }

    @MainActor
    func testLegacyGlobalWaterSourceMovesToRealScope() {
        defaults.set(WaterSource.publicWater.rawValue, forKey: StorageKey.waterSource)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.waterSource, .publicWater)
        XCTAssertNil(defaults.object(forKey: StorageKey.waterSource))
        settings.demoEnabled = true
        settings.waterSource = .notSure
        settings.demoEnabled = false
        XCTAssertEqual(settings.waterSource, .publicWater)
    }

    @MainActor
    func testUnansweredWaterSourceIsNotSure() {
        XCTAssertEqual(AppSettings(defaults: defaults).waterSource, .notSure)
    }
}

final class StepFlowTests: XCTestCase {
    private let order = RiskCheckStep.allCases

    func testLinearAdvanceBackAndProgress() throws {
        var flow = StepFlow(root: RiskCheckStep.county)
        XCTAssertFalse(flow.canGoBack)
        XCTAssertEqual(flow.progress(in: order), StepProgress(position: 1, total: 8))
        flow.advance(in: order)
        flow.advance(in: order)
        XCTAssertEqual(flow.current, .pregnancy)
        XCTAssertEqual(flow.path, [.wellAge, .pregnancy])
        flow.back()
        XCTAssertEqual(flow.current, .wellAge)
        flow.back()
        flow.back()
        XCTAssertEqual(flow.current, .county)
    }

    func testAdvanceStopsAtLastStep() {
        var flow = StepFlow(root: RiskCheckStep.results)
        flow.advance(in: order)
        XCTAssertEqual(flow.path, [])
    }

    func testRestartClearsBack() {
        var flow = StepFlow(root: QuestPhase.safety)
        flow.push(.fullReport)
        flow.restart(at: .map)
        XCTAssertEqual(flow.current, .map)
        XCTAssertFalse(flow.canGoBack)
    }

    func testCodableRoundTripRestoresPath() throws {
        var flow = StepFlow(root: QuestPhase.map)
        flow.push(.stop(2))
        let decoded = try JSONDecoder().decode(StepFlow<QuestPhase>.self, from: JSONEncoder().encode(flow))
        XCTAssertEqual(decoded, flow)
        XCTAssertEqual(decoded.current, .stop(2))
    }

    func testIsValid() {
        var flow = StepFlow(root: LabEntryStep.details)
        flow.advance(in: LabEntryStep.allCases)
        XCTAssertTrue(flow.isValid(in: LabEntryStep.allCases))
        XCTAssertFalse(flow.isValid(in: [.details]))
    }

    func testProgressFraction() {
        XCTAssertEqual(StepProgress(position: 2, total: 4).fraction, 0.5)
        XCTAssertEqual(StepProgress(position: 0, total: 0).fraction, 0)
        XCTAssertEqual(StepProgress(position: 3, total: 7).text, "Step 3 of 7")
    }
}

final class FlowDraftPayloadTests: XCTestCase {
    func testRiskCheckDraftResumability() {
        var draft = RiskCheckDraft()
        XCTAssertTrue(draft.isResumable)
        XCTAssertFalse(draft.isAnswered(.wellAge))
        draft.answers.wellAge = .before2008
        XCTAssertTrue(draft.isAnswered(.wellAge))
        for _ in RiskCheckStep.allCases { draft.flow.advance(in: RiskCheckStep.allCases) }
        XCTAssertEqual(draft.flow.current, .results)
        XCTAssertFalse(draft.isResumable)
    }

    func testLabEntryDraftParsingAndSaveRules() {
        var draft = LabEntryDraft()
        XCTAssertFalse(draft.canSave)
        draft.entries[.arsenic] = LabEntryDraft.Entry(text: "abc", unit: .ppb)
        XCTAssertTrue(draft.isInvalid(.arsenic))
        XCTAssertFalse(draft.canSave)
        draft.entries[.arsenic] = LabEntryDraft.Entry(text: "0.012", unit: .mgL)
        XCTAssertEqual(draft.storedValue(for: .arsenic) ?? 0, 12, accuracy: 0.0001)
        XCTAssertTrue(draft.canSave)
        XCTAssertNil(LabEntryDraft.parse("-1"))
    }

    func testLabEntryDraftCodableRoundTrip() throws {
        var draft = LabEntryDraft(date: Date(timeIntervalSinceReferenceDate: 0))
        draft.entries[.nitrate] = LabEntryDraft.Entry(text: "4.2", unit: .mgL)
        draft.eColi = .absent
        draft.flow.advance(in: LabEntryStep.allCases)
        let decoded = try JSONDecoder().decode(LabEntryDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)
    }

    func testLabEntryKeysSeparateNewAndEdits() {
        XCTAssertEqual(LabEntryDraft.key(editingCreatedAt: nil).name, "labEntry.new")
        XCTAssertNotEqual(LabEntryDraft.key(editingCreatedAt: Date(timeIntervalSinceReferenceDate: 1)).name,
                          LabEntryDraft.key(editingCreatedAt: Date(timeIntervalSinceReferenceDate: 2)).name)
    }

    func testScanReviewDraftRoundTripKeepsEdits() throws {
        var row = ReviewRow()
        row.contaminant = .arsenic
        row.valueText = "7"
        row.unit = .ugL
        var draft = ScanFlowDraft()
        draft.review = ScanReviewDraft(result: LabReportParser.Result(rows: [], collectionDate: nil, labName: "Lab"))
        draft.review?.rows = [row]
        draft.flow.push(.review)
        XCTAssertTrue(draft.isResumable)
        let decoded = try JSONDecoder().decode(ScanFlowDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(decoded, draft)
        XCTAssertTrue(decoded.review?.canSave ?? false)
    }

    func testQuestProgressRestores() throws {
        var report = QuestReport(date: Date(timeIntervalSinceReferenceDate: 0))
        report.values[.arsenic] = 2
        report.values[.nitrate] = 1
        var run = QuestRun(report: report)
        let stop = try XCTUnwrap(run.stops.first)
        run.answer(stop, with: .safe)
        let saved = try JSONDecoder().decode(QuestRun.Progress.self, from: JSONEncoder().encode(run.progress))
        let resumed = QuestRun(report: report, progress: saved)
        XCTAssertEqual(resumed.answer(for: stop), .safe)
        XCTAssertEqual(resumed.points, run.points)
        XCTAssertEqual(resumed.completedCount, 1)
    }

    func testQuestDraftIDChangesWithReadings() {
        var a = QuestReport(date: Date(timeIntervalSinceReferenceDate: 0))
        a.values[.arsenic] = 2
        var b = a
        XCTAssertEqual(a.draftID, b.draftID)
        b.values[.arsenic] = 3
        XCTAssertNotEqual(a.draftID, b.draftID)
    }
}

final class ScanPhotoStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appending(path: "ScanPhotoStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }

    func testSaveLoadDeleteAndBackupExclusion() throws {
        let store = ScanPhotoStore(scope: "real", root: root)
        XCTAssertEqual(store.save([image(), image()]), 2)
        XCTAssertEqual(store.load().count, 2)
        let file = try XCTUnwrap(store.pageURLs().first)
        XCTAssertEqual(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        store.deleteAll()
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path(percentEncoded: false)))
    }

    func testSaveReplacesOlderPages() {
        let store = ScanPhotoStore(scope: "real", root: root)
        store.save([image(), image(), image()])
        store.save([image()])
        XCTAssertEqual(store.load().count, 1)
    }

    func testScopesAreSeparate() {
        let real = ScanPhotoStore(scope: "real", root: root)
        let demo = ScanPhotoStore(scope: "demo-cleanReport", root: root)
        real.save([image()])
        demo.deleteAll()
        XCTAssertEqual(real.load().count, 1)
    }
}
