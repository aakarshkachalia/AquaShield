//
//  ReportQuestView.swift
//  ClearWellNC
//
//  Report Quest container, presented full screen. Flow: safety alert (only when needed) → path map
//  → stops → score → end, on a StepFlowContainer (Back, progress, saved after every answer).
//  "Skip to full report" and "Close" are on every screen, and sample reports show a "Sample data"
//  label on every screen.
//

import SwiftData
import SwiftUI

nonisolated enum QuestPhase: Codable, Hashable, Sendable {
    case safety, map, stop(Int), score, end, fullReport
}

/// A Report Quest in progress, saved after every answer. Sample reports are never saved.
nonisolated struct QuestDraft: Codable, Sendable, Equatable {
    var reportID: String
    var progress = QuestRun.Progress()
    var flow: StepFlow<QuestPhase>

    static let key = DraftKey<QuestDraft>(name: "reportQuest", schemaVersion: 1)

    var isResumable: Bool { flow.current != .end && !flow.visited.contains(.end) }
}

struct ReportQuestView: View {
    let report: QuestReport
    /// Real test dates and county high seasons, for badges.
    let context: WellCareContext

    @Environment(\.dismiss) private var dismiss
    @Environment(WellCareStore.self) private var wellCare
    @Environment(AppSettings.self) private var settings
    private var waterSource: WaterSource { settings.waterSource }

    @State private var run: QuestRun
    @State private var flow: StepFlow<QuestPhase>
    @State private var resume: StepFlowResume?
    @State private var loaded = false
    @State private var newBadges: [Badge] = []
    @State private var recorded = false

    init(report: QuestReport, context: WellCareContext) {
        self.report = report
        self.context = context
        _run = State(initialValue: QuestRun(report: report))
        _flow = State(initialValue: StepFlow(root: Self.firstPhase(report)))
    }

    /// Safety override: the alert always comes first.
    private static func firstPhase(_ report: QuestReport) -> QuestPhase {
        QuestEngine.requiresSafetyAlert(report) ? .safety : .map
    }

    private var scoreTitle: String {
        waterSource.isWell ? String(localized: "Your Well's Score") : String(localized: "Your Water's Score")
    }

    var body: some View {
        StepFlowContainer(flow: $flow, resume: resume,
                          progress: progress,
                          onClose: { dismiss() }) { phase in
            screen(phase)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if report.isSample { SampleDataBanner() }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if phase != .fullReport {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Skip to full report") { flow.push(.fullReport) }
                        }
                    }
                }
        }
        .onAppear(perform: load)
        .onChange(of: run.progress) { _, _ in persist() }
        .onChange(of: flow) { _, _ in persist() }
    }

    @ViewBuilder
    private func screen(_ phase: QuestPhase) -> some View {
        switch phase {
        case .safety:
            QuestSafetyAlertView(report: report) { flow.restart(at: .map) }
        case .map:
            QuestMapView(run: run, scoreTitle: scoreTitle,
                         onPlayStop: { flow.push(.stop($0)) },
                         onPlayScore: { flow.push(.score) },
                         onFinish: finish)
        case .stop(let index):
            if run.stops.indices.contains(index) {
                QuestStopView(stop: run.stops[index], totalStops: run.stops.count + 1, run: $run) {
                    flow.back()
                }
            }
        case .score:
            QuestScoreStopView(title: scoreTitle, run: $run, onNext: finish)
        case .end:
            QuestEndView(run: run, newBadges: newBadges,
                         onFullReport: { flow.push(.fullReport) },
                         onDone: { dismiss() })
        case .fullReport:
            QuestFullReportView(report: report, scoreTitle: scoreTitle)
        }
    }

    private func progress(_ phase: QuestPhase) -> StepProgress? {
        guard phase != .safety, phase != .fullReport, run.totalCount > 0 else { return nil }
        return StepProgress(position: run.completedCount, total: run.totalCount,
                            label: String(localized: "\(run.completedCount) of \(run.totalCount) stops done"))
    }

    // MARK: Draft

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard !report.isSample else { return }
        if let saved = settings.drafts.load(QuestDraft.key), saved.payload.reportID == report.draftID,
           saved.payload.isResumable, saved.payload.progress != QuestRun.Progress() || saved.payload.flow.canGoBack {
            run = QuestRun(report: report, progress: saved.payload.progress)
            flow = saved.payload.flow
            resume = StepFlowResume(startedAt: saved.startedAt,
                                    onContinue: { resume = nil },
                                    onStartOver: {
                                        resume = nil
                                        settings.drafts.discard(QuestDraft.key)
                                        run = QuestRun(report: report)
                                        flow = StepFlow(root: Self.firstPhase(report))
                                    })
        }
    }

    private func persist() {
        guard loaded, !report.isSample, !recorded else { return }
        let draft = QuestDraft(reportID: report.draftID, progress: run.progress, flow: flow)
        guard draft.isResumable, draft.progress != QuestRun.Progress() || flow.canGoBack else { return }
        settings.drafts.save(draft, for: QuestDraft.key)
    }

    /// Saves points and checks badges once, then shows the end screen. Sample runs save nothing.
    private func finish() {
        if !recorded, run.isFinished {
            recorded = true
            settings.drafts.discard(QuestDraft.key)
            if !report.isSample {
                wellCare.recordQuest(run)
                newBadges = wellCare.refreshBadges(testDates: context.testDates, highRiskMonths: context.highRiskMonths)
            }
        }
        flow.restart(at: .end)
    }
}
