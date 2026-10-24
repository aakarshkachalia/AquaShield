//
//  ExposureRisk.swift
//  ClearWellNC
//
//  Per-member exposure risk from the water at that member's drinking tap. Never a diagnosis: the output is
//  hard safety alerts, risk flags, rough dose estimates and "worth discussing with your doctor" notes.
//

import Foundation

nonisolated struct SafetyAlert: Sendable, Equatable, Identifiable {
    enum Kind: String, Sendable {
        case formulaNitrate, arsenicSkin, bacteriaBoil
    }

    let kind: Kind
    let memberIDs: [UUID]
    let title: String
    let message: String
    var id: Kind { kind }
}

nonisolated struct MemberRiskFlag: Sendable, Equatable, Identifiable {
    let target: ClaimTarget
    /// Elevated means at least half its limit; untested means no usable result.
    let isUntested: Bool
    let reason: String
    var id: ClaimTarget { target }
}

nonisolated struct DoctorNote: Sendable, Equatable, Identifiable {
    let symptom: Symptom
    let targets: [ClaimTarget]
    let text: String
    var id: Symptom { symptom }
}

nonisolated struct MemberExposure: Sendable, Equatable, Identifiable {
    let memberID: UUID
    let flags: [MemberRiskFlag]
    let notes: [DoctorNote]
    /// Daily dose per kilogram of body weight, in the target's unit per kg (e.g. µg/kg/day for ppb).
    /// Only when the member's weight is given.
    let dosePerKg: [ClaimTarget: Double]
    var id: UUID { memberID }
}

nonisolated enum ExposureRisk {
    static let disclaimer = String(localized: "Educational information, not medical advice.")

    /// Nitrate health limit for formula, mg/L as N.
    static let formulaNitrateLimit = 10.0

    /// residual (per liter) × liters per day ÷ kg.
    static func dose(residual: Double, litersPerDay: Double, weightKg: Double?) -> Double? {
        guard let weightKg, weightKg > 0 else { return nil }
        return residual * litersPerDay / weightKg
    }

    /// The tap result for the member's drinking water. Bottled water returns nil (no tap exposure).
    static func drinkingResult(for member: HouseholdMember, results: [TapLocation: TapScoreResult]) -> TapScoreResult? {
        switch member.drinkingSource {
        case .bottled: nil
        case .tap(let tap): results[tap] ?? results[.kitchen]
        }
    }

    // MARK: Hard alerts

    static func safetyAlerts(members: [HouseholdMember], source: WaterSource,
                             results: [TapLocation: TapScoreResult]) -> [SafetyAlert] {
        var alerts: [SafetyAlert] = []

        // Formula + nitrate.
        let formulaBabies = members.filter(\.infantOnFormula).filter { member in
            guard let result = drinkingResult(for: member, results: results) ?? results[.kitchen] else { return source.showsWellCare }
            guard let nitrate = result.items.first(where: { $0.target == .nitrate }), nitrate.level != .inconclusive,
                  let residual = nitrate.residual else {
                return source.showsWellCare   // untested on a well
            }
            return residual > formulaNitrateLimit
        }
        if !formulaBabies.isEmpty {
            alerts.append(SafetyAlert(kind: .formulaNitrate, memberIDs: formulaBabies.map(\.id),
                                      title: String(localized: "Don't use this water for formula"),
                                      message: String(localized: "Use bottled water until a lab shows nitrate is under 10 mg/L. Boiling does NOT remove nitrate — it concentrates it.")))
        }

        // Arsenic skin signs in a well home.
        if source.showsWellCare {
            let skin = members.filter { $0.symptoms.contains(where: \.isArsenicSkinRedFlag) }
            if !skin.isEmpty {
                alerts.append(SafetyAlert(kind: .arsenicSkin, memberIDs: skin.map(\.id),
                                          title: String(localized: "See a doctor and test for arsenic"),
                                          message: String(localized: "Dark patches or thick skin on the palms or soles are worth showing a doctor. Ask a certified lab to test your well for arsenic.")))
            }
        }

        // Germs at any drinking tap.
        let germs = results.values.contains { result in
            result.tap.isDrinking && result.items.contains { $0.target.isMicrobial && $0.present == true }
        }
        if germs {
            alerts.append(SafetyAlert(kind: .bacteriaBoil, memberIDs: members.map(\.id),
                                      title: String(localized: "Boil water before drinking"),
                                      message: String(localized: "Germs were found. Bring water to a rolling boil for 1 minute, or use bottled water, until a new test is clear.")))
        }
        return alerts
    }

    // MARK: Per member

    static func exposure(for member: HouseholdMember, source: WaterSource,
                         results: [TapLocation: TapScoreResult]) -> MemberExposure {
        let result = drinkingResult(for: member, results: results)
        let items = result?.items ?? []
        let untested = Set(result?.missingTests ?? (member.drinkingSource == .bottled ? [] :
            WellHealthScore.recommendedTargets(for: source, isShower: false)))
        let elevated = Set(items.filter { $0.level == .unsafe || $0.level == .fair || $0.level == .poor }.map(\.target))

        var flags: [MemberRiskFlag] = []
        func flag(_ target: ClaimTarget, _ reason: String) {
            guard !flags.contains(where: { $0.target == target }) else { return }
            if elevated.contains(target) {
                flags.append(MemberRiskFlag(target: target, isUntested: false, reason: reason))
            } else if untested.contains(target) {
                flags.append(MemberRiskFlag(target: target, isUntested: true, reason: reason))
            }
        }
        let young = member.ageBand.isChild
        if member.pregnant || member.breastfeeding || young {
            flag(.lead, String(localized: "Lead harms growing brains most."))
        }
        if member.pregnant || member.ageBand == .infant || member.infantOnFormula {
            flag(.nitrate, String(localized: "Nitrate is most dangerous for babies and in pregnancy."))
        }
        if member.pregnant || young {
            flag(.arsenic, String(localized: "Children and pregnancy are more sensitive to arsenic."))
        }
        if member.immunocompromised || member.ageBand == .infant || member.ageBand == .olderAdult {
            flag(.bacteria, String(localized: "Germs can cause serious illness for this person."))
        }
        if member.kidneyDisease {
            flag(.uranium, String(localized: "Uranium mostly affects the kidneys."))
        }
        if member.eczema {
            flag(.hardness, String(localized: "Hard water can make eczema feel worse."))
        }

        // Symptoms only become notes when they match something elevated or untested here.
        let concern = elevated.union(untested)
        let notes: [DoctorNote] = member.symptoms.sorted { $0.rawValue < $1.rawValue }.compactMap { symptom in
            let matches = symptom.relatedTargets.intersection(concern).sorted { $0.rawValue < $1.rawValue }
            guard !matches.isEmpty else { return nil }
            let names = matches.map(\.name).formatted(.list(type: .or))
            return DoctorNote(symptom: symptom, targets: matches,
                              text: String(localized: "\(symptom.label) is worth discussing with your doctor. It can be linked to \(names), which is high or untested here."))
        }

        var doses: [ClaimTarget: Double] = [:]
        if member.drinkingSource != .bottled {
            for item in items {
                guard let residual = item.residual, item.level != .notScored,
                      let dose = dose(residual: residual, litersPerDay: member.dailyLiters, weightKg: member.weightKg)
                else { continue }
                doses[item.target] = dose
            }
        }
        return MemberExposure(memberID: member.id, flags: flags, notes: notes, dosePerKg: doses)
    }
}
