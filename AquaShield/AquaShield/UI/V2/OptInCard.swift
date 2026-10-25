//
//  OptInCard.swift
//  AquaShield
//
//  One-time explanation before a feature sends anything off the phone. "Not now" shows the fallback.
//

import SwiftUI

struct OptInCard: View {
    let feature: NetworkFeature
    @Environment(AppSettings.self) private var settings
    @State private var declined = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(alignment: .top, spacing: DS.Space.m) {
                DS.IconBadge(systemImage: feature.symbol)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(feature.title).font(DS.Typography.headline).accessibilityAddTraits(.isHeader)
                    Text(feature.explanation).font(DS.Typography.subheadline).foregroundStyle(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label {
                Text("Sends: \(feature.outboundRequest.sends) To: \(feature.outboundRequest.recipient).")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.up.forward.circle")
            }
            .font(DS.Typography.footnote)
            .foregroundStyle(DS.Colors.textSecondary)
            if declined {
                Text(feature.fallback).font(DS.Typography.subheadline).foregroundStyle(DS.Colors.textPrimary)
            } else {
                Button("Turn on") {
                    settings.networkOptIns.insert(feature)
                    DS.Haptics.success()
                }
                .buttonStyle(DS.PrimaryButtonStyle())
                .accessibilityIdentifier("optIn.\(feature.rawValue)")
                Button("Not now") { declined = true }
                    .font(DS.Typography.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
            }
        }
        .foregroundStyle(DS.Colors.textPrimary)
        .dsCard()
    }
}
