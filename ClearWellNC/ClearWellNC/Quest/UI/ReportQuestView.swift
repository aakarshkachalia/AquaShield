//
//  ReportQuestView.swift
//  ClearWellNC
//
//  Report Quest container, presented full screen. Flow: safety alert (only when needed) → path map
//  → stops → score → end. "Skip to full report" and "Close" are on every screen, and sample reports
//  show a "Sample data" label on every screen.
//

import SwiftData
import SwiftUI

struct ReportQuestView: View {
    let report: QuestReport
    /// Real test dates and county high seasons, for badges.
    let context: WellCareContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WellCareStore.self) private var wellCare
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure

    @State private var run: QuestRun
    @State private var phase: Phase
    /// Where "Back to Report Quest" returns from the full report.
    @State private var phaseBeforeReport: Phase = .map
    @State private var newBadges: [Badge] = []
    @State private var recorded = false

    enum Phase: Hashable {
        case safety, map, stop(Int), score, end, fullReport
    }

    init(report: QuestReport, context: WellCareContext) {
        self.report = report
        self.context = context
        _run = State(initialValue: QuestRun(report: report))
        // Safety override: the alert always comes first.
        _phase = State(initialValue: QuestEngine.requiresSafetyAlert(report) ? .safety : .map)
    }

    private var scoreTitle: String {
        waterSource.isWell ? String(localized: "Your Well's Score") : String(localized: "Your Water's Score")
    }

    var body: some View {
        NavigationStack {
            screen
                .id(phase)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                  removal: .opacity))
                .safeAreaInset(edge: .top, spacing: 0) {
                    if report.isSample { SampleDataBanner() }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if phase == .fullReport {
                            if phaseBeforeReport != .end {
                                Button("Back to Report Quest") { go(to: phaseBeforeReport) }
                            }
                        } else {
                            Button("Skip to full report") {
                                phaseBeforeReport = phase == .safety ? .safety : phase
                                go(to: .fullReport)
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch phase {
        case .safety:
            QuestSafetyAlertView(report: report) { go(to: .map) }
        case .map:
            QuestMapView(run: run, scoreTitle: scoreTitle,
                         onPlayStop: { go(to: .stop($0)) },
                         onPlayScore: { go(to: .score) },
                         onFinish: finish)
        case .stop(let index):
            QuestStopView(stop: run.stops[index], totalStops: run.stops.count + 1, run: $run) {
                go(to: .map)
            }
        case .score:
            QuestScoreStopView(title: scoreTitle, run: $run, onNext: finish)
        case .end:
            QuestEndView(run: run, newBadges: newBadges,
                         onFullReport: {
                             phaseBeforeReport = .end
                             go(to: .fullReport)
                         },
                         onDone: { dismiss() })
        case .fullReport:
            QuestFullReportView(report: report, scoreTitle: scoreTitle)
        }
    }

    private func go(to next: Phase) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy) { phase = next }
    }

    /// Saves points and checks badges once, then shows the end screen. Sample runs save nothing.
    private func finish() {
        if !recorded, run.isFinished {
            recorded = true
            if !report.isSample {
                wellCare.recordQuest(run)
                newBadges = wellCare.refreshBadges(testDates: context.testDates, highRiskMonths: context.highRiskMonths)
            }
        }
        go(to: .end)
    }
}
