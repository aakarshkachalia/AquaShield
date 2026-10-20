//
//  ScanReportSheet.swift
//  ClearWellNC
//
//  "Scan Report": [Scan with camera] [Choose photo] [Enter manually] → read on device → review → save
//  → "See my results" or "Play Report Quest".
//

import PhotosUI
import SwiftData
import SwiftUI

struct ScanReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var store
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]

    private enum Step {
        case choose
        case reading
        case review(LabReportParser.Result, [UIImage])
        case manual
        case saved(LabResult)
    }

    @State private var step: Step = .choose
    @State private var showingCamera = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var cameraDenied = false
    @State private var questSession: QuestSession?

    var body: some View {
        switch step {
        case .manual:
            LabResultForm()
        default:
            NavigationStack {
                content
                    .background(Color.appBackground)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentCameraView(onFinish: { images in
                    showingCamera = false
                    read(images)
                }, onCancel: { showingCamera = false })
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $questSession) { session in
                ReportQuestView(report: session.report,
                                context: WellCareContext.make(
                                    results: results,
                                    county: settings.effectiveCounty(savedWellCounty: savedWellCounty(savedWells, store: store)),
                                    trends: CountyTrendData.loadBundled()))
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                loadPhotos(items)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .choose:
            chooser
        case .reading:
            VStack(spacing: Spacing.l) {
                ProgressView()
                    .controlSize(.large)
                Text("Reading your report…")
                    .font(.headline)
                Text("This happens on your phone. Nothing is uploaded.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .navigationTitle("Scan Report")
        case .review(let result, let images):
            ScanReviewView(result: result, images: images) { save($0) }
        case .saved(let result):
            saved(result)
        case .manual:
            EmptyView()
        }
    }

    // MARK: Choose

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Take a photo of each page of your lab report, or pick photos you already have. ClearWell reads it on your phone and lets you check every number before saving.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    InfoCard(style: .status(.watch), systemImage: "exclamationmark.circle.fill",
                             title: String(localized: "Something went wrong"), message: errorMessage) {
                        if cameraDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                            SecondaryButton(title: "Open Settings", systemImage: "gear") { openURL(url) }
                        }
                        SecondaryButton(title: "Enter manually", systemImage: "keyboard") { step = .manual }
                    }
                }

                PrimaryButton(title: "Scan with camera", systemImage: "camera.fill") { startCamera() }
                PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                    Label("Choose photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(SecondaryButtonStyle())
                SecondaryButton(title: "Enter manually", systemImage: "keyboard") { step = .manual }

                VStack(alignment: .leading, spacing: Spacing.s) {
                    SampleDataTag()
                    Text("No report yet? Try the scanner with a made-up sample report.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    SecondaryButton(title: "Use the sample report", systemImage: "doc.text") {
                        if let image = SampleLabReport.render() { read([image]) }
                    }
                }
                .card()

                Text("Tip: lay the report flat in good light. Multi-page reports are fine.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .screenContainer()
        }
        .navigationTitle("Scan Report")
    }

    // MARK: Saved

    private func saved(_ result: LabResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                InfoCard(style: .status(.safe), systemImage: "checkmark.circle.fill",
                         title: String(localized: "Results saved"),
                         message: String(localized: "Your score and explanations are updated."))
                if !result.healthFindings.isEmpty {
                    InfoCard(style: .danger, systemImage: "exclamationmark.octagon.fill",
                             title: String(localized: "A result is above a health limit"),
                             message: String(localized: "See what to do now on your results."))
                }
                PrimaryButton(title: "See my results", systemImage: "drop.fill") {
                    router.selectedTab = .myWater
                    dismiss()
                }
                SecondaryButton(title: "Play Report Quest", systemImage: "map.fill") {
                    questSession = QuestSession(report: QuestReport(result: result).markingSample(settings.demoEnabled))
                }
            }
            .screenContainer()
        }
        .navigationTitle("Saved")
        .navigationBarBackButtonHidden()
    }

    // MARK: Actions

    private func startCamera() {
        errorMessage = nil
        Task {
            switch await DocumentCameraView.availability() {
            case .available:
                showingCamera = true
            case .denied:
                cameraDenied = true
                errorMessage = String(localized: "ClearWell doesn't have permission to use the camera. You can allow it in Settings, choose a photo, or enter results manually.")
            case .unsupported:
                errorMessage = String(localized: "This device can't scan documents. Choose a photo or enter results manually.")
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        errorMessage = nil
        step = .reading
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            photoItems = []
            if images.isEmpty {
                fail(String(localized: "We couldn't open that photo. Try another photo or enter manually."))
            } else {
                read(images)
            }
        }
    }

    private func read(_ images: [UIImage]) {
        errorMessage = nil
        step = .reading
        Task {
            do {
                let pages = images.compactMap(\.visionPage)
                let lines = try await ReportOCR.recognizeLines(in: pages)
                let result = LabReportParser.parse(lines: lines)
                if result.rows.isEmpty {
                    fail(ReportOCR.OCRError.unreadable.errorDescription ?? "")
                } else {
                    step = .review(result, images)
                }
            } catch {
                fail((error as? LocalizedError)?.errorDescription ?? ReportOCR.OCRError.unreadable.errorDescription ?? "")
            }
        }
    }

    private func fail(_ message: String) {
        cameraDenied = false
        errorMessage = message
        step = .choose
    }

    private func save(_ result: LabResult) {
        modelContext.insert(result)
        try? modelContext.save()
        let context = modelContext
        Task { await ReminderSync.refresh(using: context) }
        step = .saved(result)
    }
}
