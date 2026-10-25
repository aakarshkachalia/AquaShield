//
//  RemediationPlanView.swift
//  ClearWellNC
//
//  What to do (Redesign 5c): the plan as a vertical line of steps. Tap a node to mark a step done (saved per
//  household). The best certified filter sits inside the plan; "Compare filters" opens every option.
//

import SwiftData
import SwiftUI

struct RemediationView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]

    private func when(_ kind: FixStep.Kind) -> String {
        switch kind {
        case .bottledWater, .flushTaps, .coldWaterOnly: String(localized: "Today")
        case .askUtilityLeadLine, .shockChlorinate, .checkWellCap, .checkSeptic: String(localized: "This week")
        case .retest: String(localized: "After fixing")
        }
    }

    var body: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        let plan = snapshot.plan
        let best = plan.allMatches.max { a, b in
            a.coveragePercent != b.coveragePercent ? a.coveragePercent < b.coveragePercent
                : (a.annualCost ?? .infinity) > (b.annualCost ?? .infinity)
        }
        let done = plan.fixes.filter { settings.fixesDone.contains($0.kind.rawValue) }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to do").font(M.Font.screenTitle).accessibilityAddTraits(.isHeader)
                    HStack {
                        Text(plan.drivers.isEmpty ? String(localized: "Nothing to fix right now")
                             : String(localized: "Plan for \(plan.drivers.map(\.name).map(\.inSentence).formatted(.list(type: .and)))"))
                            .font(M.Font.row).foregroundStyle(M.Colors.muted)
                        Spacer()
                        if !plan.fixes.isEmpty {
                            Text("\(done) of \(plan.fixes.count) done").font(M.Font.label).foregroundStyle(M.Colors.muted)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 18)

                ForEach(snapshot.alerts) { SafetyAlertCard(alert: $0).padding(.horizontal, 16).padding(.bottom, 12) }

                if !snapshot.hasReadings {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test first. Then we can show what fixes it.").font(.system(.title3, weight: .light))
                        Button("Find testing →") { router.openHelp(.testing) }.buttonStyle(M.InkButtonStyle())
                    }
                    .padding(.horizontal, 20)
                }

                // The plan.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(plan.fixes.enumerated()), id: \.element.id) { index, fix in
                        step(fix, last: index == plan.fixes.count - 1 && best == nil)
                        if index == 0, let best {
                            filterStep(best, last: plan.fixes.count == 1)
                        }
                    }
                    if plan.fixes.isEmpty, let best { filterStep(best, last: true) }
                }
                .padding(.horizontal, 20)

                if let note = plan.volatileNote {
                    row(symbol: "humidity", title: String(localized: "In the shower"), detail: note)
                }
                if let skin = plan.skinCare {
                    row(symbol: "hand.raised", title: String(localized: "Skin care"), detail: skin.tips.first ?? "")
                }
                if !plan.drivers.isEmpty {
                    Button { router.openHelp(plan.drivers.first?.contaminantID.map { .contaminant($0) } ?? .payToFix) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dollarsign.circle").font(.system(.title3, weight: .light))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Help paying").font(M.Font.section)
                                Text("Programs that may cover testing, safe water or treatment")
                                    .font(M.Font.small).foregroundStyle(M.Colors.muted)
                            }
                            Spacer()
                            Text("→")
                        }
                        .padding(14)
                        .background(M.Colors.surface)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.top, 20)
                }
                Text("No affiliate links. \(AppName.display) earns nothing from these products.")
                    .font(M.Font.tiny).foregroundStyle(M.Colors.muted).padding(.horizontal, 20).padding(.top, 16)
                M.Footer().padding(.horizontal, 20)
            }
            .frame(maxWidth: DS.Size.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .modernistScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Steps

    private func node(done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? M.Colors.ink : M.Colors.ground)
            Circle().stroke(M.Colors.ink, lineWidth: 1)
            if done { Image(systemName: "checkmark").font(.system(.caption2, weight: .bold)).foregroundStyle(M.Colors.ground) }
        }
        .frame(width: 22, height: 22)
    }

    private func step(_ fix: FixStep, last: Bool) -> some View {
        let done = settings.fixesDone.contains(fix.kind.rawValue)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Button {
                    if done { settings.fixesDone.remove(fix.kind.rawValue) } else {
                        settings.fixesDone.insert(fix.kind.rawValue)
                        DS.Haptics.success()
                    }
                } label: { node(done: done).frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(fix.title))
                .accessibilityValue(done ? Text("Done") : Text("Not done"))
                .accessibilityHint(Text("Marks this step done"))
                .accessibilityIdentifier("plan.step.\(fix.kind.rawValue)")
                if !last { Rectangle().fill(M.Colors.line).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: DS.Size.tapTarget)
            VStack(alignment: .leading, spacing: 4) {
                Text(when(fix.kind).uppercased()).font(M.Font.label).tracking(0.8).foregroundStyle(M.Colors.muted)
                Text(fix.title).font(M.Font.section).strikethrough(done, color: M.Colors.muted)
                    .foregroundStyle(done ? M.Colors.muted : M.Colors.ink)
                Text(fix.detail).font(M.Font.small).foregroundStyle(M.Colors.muted).fixedSize(horizontal: false, vertical: true)
                if fix.kind == .shockChlorinate {
                    NavigationLink("Step-by-step guide →") { StormModeView() }.font(M.Font.value).padding(.top, 4)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
    }

    private func filterStep(_ match: ProductMatch, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(M.Colors.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    Image(systemName: "line.3.horizontal.decrease").font(.system(.caption2, weight: .semibold))
                }
                .frame(width: 22, height: 22)
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                .accessibilityHidden(true)
                if !last { Rectangle().fill(M.Colors.line).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: DS.Size.tapTarget)
            VStack(alignment: .leading, spacing: 10) {
                Text("THIS MONTH").font(M.Font.label).tracking(0.8).foregroundStyle(M.Colors.muted)
                Text("Install a certified filter").font(M.Font.section)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.product.displayName).font(M.Font.section)
                            Text("Covers \(match.covered.map(\.name).map(\.inSentence).formatted(.list(type: .and)))"
                                 + (match.product.needsVerification ? String(localized: " · sample data") : ""))
                                .font(M.Font.small).foregroundStyle(M.Colors.muted)
                        }
                        Spacer()
                        Text("\(match.coveragePercent)%").font(M.Font.bigNumber)
                    }
                    HStack(spacing: 6) {
                        if let cost = match.annualCost {
                            chip("\(cost.formatted(.currency(code: "USD").precision(.fractionLength(0))))/yr")
                        }
                        chip(match.product.type.installDifficulty.label)
                        ForEach(Array(Set(match.product.claims.map(\.standard.name))).sorted().prefix(2), id: \.self) { chip($0) }
                    }
                    NavigationLink { FilterOptionsView() } label: {
                        HStack { Text("Compare filters"); Spacer(); Text("→") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(M.InkButtonStyle())
                    .accessibilityIdentifier("plan.compare")
                }
                .padding(14)
                .background(M.Colors.surface)
            }
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(M.Font.tiny).padding(.horizontal, 7).padding(.vertical, 4)
            .overlay(Rectangle().strokeBorder(M.Colors.line, lineWidth: 1))
    }

    private func row(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(.body, weight: .light)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(M.Font.section)
                Text(detail).font(M.Font.small).foregroundStyle(M.Colors.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { M.Rule(color: M.Colors.hairline) }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }
}
