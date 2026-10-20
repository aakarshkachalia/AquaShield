//
//  WellCareViews.swift
//  ClearWellNC
//
//  Well Care progression: the progress screen (streak, points, badges, test reminders) and the
//  Home cards that lead into Report Quest and the seasonal challenge.
//

import SwiftData
import SwiftUI

/// Badges, yearly testing streak, points, and the opt-in test reminder.
struct WellCareProgressView: View {
    let context: WellCareContext

    @Environment(WellCareStore.self) private var wellCare
    @Environment(\.modelContext) private var modelContext

    private var streak: Int { WellCareStreak.years(testDates: context.testDates) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(spacing: Spacing.m) {
                    stat(value: "\(streak)", label: streak == 1 ? String(localized: "year in a row") : String(localized: "years in a row"),
                         systemImage: "calendar")
                    stat(value: "\(wellCare.state.points)", label: String(localized: "points"), systemImage: "star.fill")
                }
                Text("Your Well Care streak counts years in a row with at least one water test. Opening the app doesn't count. Testing does.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SectionHeader(title: "Badges")
                VStack(spacing: Spacing.m) {
                    ForEach(Badge.allCases) { badge in
                        badgeRow(badge)
                    }
                }

                SectionHeader(title: "Test reminders")
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Toggle("Remind me when it's time to test", isOn: Binding(
                        get: { wellCare.state.testRemindersEnabled },
                        set: setReminders))
                        .frame(minHeight: 44)
                    Text("Off unless you turn it on. At most one reminder a month, only about testing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card()
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Well Care")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            wellCare.reload()
            wellCare.refreshBadges(testDates: context.testDates, highRiskMonths: context.highRiskMonths)
        }
    }

    private func stat(value: String, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func badgeRow(_ badge: Badge) -> some View {
        let earnedOn = wellCare.state.unlocked[badge.rawValue]
        return HStack(alignment: .top, spacing: Spacing.m) {
            IconTile(systemImage: earnedOn == nil ? "lock.fill" : badge.symbol,
                     color: earnedOn == nil ? .secondary : .accentColor)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(badge.title)
                    .font(.headline)
                    .foregroundStyle(earnedOn == nil ? .secondary : .primary)
                Text(badge.howToEarn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let earnedOn {
                    Label("Earned \(earnedOn.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.statusSafe)
                } else {
                    Text("Not earned yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func setReminders(_ enabled: Bool) {
        wellCare.setTestReminders(enabled)
        let context = modelContext
        Task {
            if enabled, await NotificationScheduler.authorizationStatus() == .notDetermined {
                await NotificationScheduler.requestAuthorization()
            }
            await ReminderSync.refresh(using: context)
        }
    }
}

// MARK: - Home cards

/// Report Quest entry: play with the latest real report, or try a sample.
struct ReportQuestCard: View {
    let latest: LabResult?
    let context: WellCareContext

    @Environment(AppSettings.self) private var settings
    @State private var playing: QuestSession?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                IconTile(systemImage: "map.fill")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Report Quest")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(latest == nil
                         ? String(localized: "Learn to read a water test in about 3 minutes, with a sample report.")
                         : String(localized: "Learn to read your latest test in about 3 minutes, one result at a time."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let latest {
                Button {
                    playing = QuestSession(report: QuestReport(result: latest).markingSample(settings.demoEnabled))
                } label: {
                    Text("Play with my latest test")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            Menu {
                ForEach(DemoReport.allCases) { demo in
                    Button {
                        playing = QuestSession(report: demo.report())
                    } label: {
                        Text(demo.title)
                        Text(demo.subtitle)
                    }
                }
            } label: {
                Label("Try a sample report", systemImage: "doc.badge.ellipsis")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
        .fullScreenCover(item: $playing) { session in
            ReportQuestView(report: session.report, context: context)
        }
    }
}

/// Identifiable wrapper so a report can drive `fullScreenCover(item:)`.
struct QuestSession: Identifiable {
    let id = UUID()
    let report: QuestReport
}

/// Streak, points and badges at a glance; opens the progress screen.
struct WellCareSummaryCard: View {
    let context: WellCareContext
    @Environment(WellCareStore.self) private var wellCare

    var body: some View {
        let streak = WellCareStreak.years(testDates: context.testDates)
        let earned = Badge.allCases.filter(wellCare.state.isUnlocked).count
        NavigationLink {
            WellCareProgressView(context: context)
        } label: {
            NavigationCardLabel(
                title: Text("Well Care"),
                subtitle: Text("\(streak)-year testing streak · \(earned) of \(Badge.allCases.count) badges · \(wellCare.state.points) points"),
                systemImage: "rosette")
        }
        .buttonStyle(.plain)
    }
}

/// Seasonal challenge from the forecast model, e.g. "Spring Nitrate Check".
struct SeasonalChallengeCard: View {
    let challenge: SeasonalChallenge
    @Environment(WellCareStore.self) private var wellCare

    var body: some View {
        let earned = wellCare.state.isUnlocked(.seasonalScout)
        VStack(alignment: .leading, spacing: 0) {
            if challenge.isSampleData {
                SampleDataBanner(text: "Sample data: forecast uses placeholder numbers")
            }
            HStack(alignment: .top, spacing: Spacing.m) {
                IconTile(systemImage: "leaf.fill", color: .statusSafe)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Seasonal challenge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(challenge.title)
                        .font(.headline)
                    Text(challenge.detail)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if earned {
                        Label("Seasonal Scout badge earned", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.statusSafe)
                    }
                }
            }
            .padding(Spacing.l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardBorder))
        .accessibilityElement(children: .combine)
    }
}
