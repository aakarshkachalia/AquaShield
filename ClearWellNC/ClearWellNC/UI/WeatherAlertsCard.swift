//
//  WeatherAlertsCard.swift
//  ClearWellNC
//

import SwiftUI

/// Alert status for the saved well, with the before/after well checklist when a flood or storm alert is active.
struct WeatherAlertsCard: View {
    let store: WeatherAlertsStore
    let onRetry: () -> Void
    @Environment(AppSettings.self) private var settings
    private var waterSource: WaterSource { settings.waterSource }

    var body: some View {
        let relevant = store.relevantAlerts
        if relevant.isEmpty {
            statusCard
        } else {
            alertCard(relevant)
        }
    }

    // MARK: No relevant alerts / loading / error

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Weather alerts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            switch store.state {
            case .idle, .loading:
                ProgressView("Checking the National Weather Service…")
            case .loaded(_, let checkedAt):
                Label {
                    Text(waterSource.showsWellCare
                         ? String(localized: "No flood, hurricane or tropical storm alerts for your well right now.")
                         : String(localized: "No flood, hurricane or tropical storm alerts for your home right now."))
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.statusSafe)
                }
                Text("Checked \(checkedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed:
                Label {
                    Text("We couldn't check weather alerts. Check your internet connection.")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(RiskLevel.elevated.color)
                }
                Button("Try again", action: onRetry)
                    .frame(minHeight: 44)
            }
            Text("Your saved location is sent to the National Weather Service to check for alerts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: Active alert

    private func alertCard(_ alerts: [WeatherAlert]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Label(waterSource.showsWellCare ? String(localized: "Weather alert for your well")
                                            : String(localized: "Weather alert for your home"),
                  systemImage: "cloud.bolt.rain.fill")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(alerts) { alert in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(alert.event)
                        .font(.body.weight(.semibold))
                    if let headline = alert.headline {
                        Text(headline)
                            .font(.subheadline)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            if waterSource.showsWellCare {
                checklist(title: "Before the storm", items: [
                    "Fill clean containers with drinking water.",
                    "Know where your well cap is.",
                ])
                checklist(title: "After the storm", items: [
                    "If your wellhead was underwater, do not drink the water.",
                    "Disinfect your well.",
                    "Test for bacteria before using it again.",
                ])
            } else {
                checklist(title: "Before the storm", items: [
                    "Fill clean containers with drinking water.",
                ])
                checklist(title: "After the storm", items: [
                    "Follow any boil-water notice from your water utility.",
                ])
            }

            Text("Alerts from the National Weather Service.")
                .font(.caption)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.brandPrimaryFixed, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func checklist(title: LocalizedStringKey, items: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    Image(systemName: "checkmark.square")
                        .accessibilityHidden(true)
                    Text(items[index])
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
