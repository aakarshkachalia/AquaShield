//
//  FilterModels.swift
//  AquaShield
//
//  Reference models for filters: certification standards, certifiers, claims and products. Products are
//  reference data (JSON via ReferenceDataStore, or entered by the user); installed filters are the user's
//  TreatmentSystem records, linked to a product and a tap.
//

import Foundation

/// What a certification claim reduces. Lab contaminants map in through `init?(contaminant:)`.
nonisolated enum ClaimTarget: String, Codable, CaseIterable, Sendable {
    case arsenic, lead, nitrate, nitrite, uranium, manganese, iron, copper, fluoride, radon
    case pfoa, pfos, genx, hardness
    case bacteria, viruses, cysts
    case freeChlorine, chloramine, tthm, haa5, vocs

    init?(contaminant: ContaminantID) {
        switch contaminant {
        case .arsenic: self = .arsenic
        case .lead: self = .lead
        case .nitrate: self = .nitrate
        case .nitrite: self = .nitrite
        case .uranium: self = .uranium
        case .manganese: self = .manganese
        case .iron: self = .iron
        case .copper: self = .copper
        case .fluoride: self = .fluoride
        case .radon: self = .radon
        case .pfoa: self = .pfoa
        case .pfos: self = .pfos
        case .genx: self = .genx
        case .hardness: self = .hardness
        case .totalColiform, .eColi: self = .bacteria
        case .pH: return nil
        }
    }

    var isMicrobial: Bool { self == .bacteria || self == .viruses || self == .cysts }

    /// Gases and volatile chemicals that also reach you as steam in the shower.
    var isVolatile: Bool { self == .radon || self == .vocs || self == .tthm }

    var name: String {
        switch self {
        case .arsenic: String(localized: "Arsenic")
        case .lead: String(localized: "Lead")
        case .nitrate: String(localized: "Nitrate")
        case .nitrite: String(localized: "Nitrite")
        case .uranium: String(localized: "Uranium")
        case .manganese: String(localized: "Manganese")
        case .iron: String(localized: "Iron")
        case .copper: String(localized: "Copper")
        case .fluoride: String(localized: "Fluoride")
        case .radon: String(localized: "Radon")
        case .pfoa: String(localized: "PFOA")
        case .pfos: String(localized: "PFOS")
        case .genx: String(localized: "GenX")
        case .hardness: String(localized: "Hardness")
        case .bacteria: String(localized: "Bacteria")
        case .viruses: String(localized: "Viruses")
        case .cysts: String(localized: "Cysts")
        case .freeChlorine: String(localized: "Chlorine")
        case .chloramine: String(localized: "Chloramine")
        case .tthm: String(localized: "Trihalomethanes")
        case .haa5: String(localized: "Haloacetic acids")
        case .vocs: String(localized: "VOCs")
        }
    }
}

nonisolated enum CertificationStandard: String, Codable, CaseIterable, Sendable {
    case nsf42, nsf53, nsf55, nsf58, nsf62, nsf177, nsf401, nsf44, nsf244, p231

    var name: String {
        switch self {
        case .nsf42: "NSF/ANSI 42"
        case .nsf53: "NSF/ANSI 53"
        case .nsf55: "NSF/ANSI 55"
        case .nsf58: "NSF/ANSI 58"
        case .nsf62: "NSF/ANSI 62"
        case .nsf177: "NSF/ANSI 177"
        case .nsf401: "NSF/ANSI 401"
        case .nsf44: "NSF/ANSI 44"
        case .nsf244: "NSF/ANSI 244"
        case .p231: "NSF P231"
        }
    }

    /// What each standard can certify, so a claim outside its standard never counts (for example, a
    /// shower filter's NSF/ANSI 177 claim covers free chlorine only). Read from CertificationStandards.json;
    /// `compiledAllowedTargets` is the fallback and must match it (tested).
    var allowedTargets: Set<ClaimTarget> {
        ReferenceStandards.table[self]?.allowedTargets ?? compiledAllowedTargets
    }

    /// Needs verification against NSF's standard descriptions (`SourceRef.nsfStandards`).
    var compiledAllowedTargets: Set<ClaimTarget> {
        switch self {
        case .nsf42: [.freeChlorine, .chloramine, .iron, .manganese]
        case .nsf53: [.lead, .arsenic, .copper, .uranium, .pfoa, .pfos, .genx, .tthm, .vocs, .cysts, .radon]
        case .nsf55: [.bacteria, .viruses, .cysts]
        case .nsf58: [.arsenic, .nitrate, .nitrite, .fluoride, .lead, .copper, .uranium, .pfoa, .pfos, .genx, .cysts]
        case .nsf62: [.arsenic, .nitrate, .nitrite, .fluoride, .lead, .copper, .uranium, .bacteria, .cysts]
        case .nsf177: [.freeChlorine]
        case .nsf401: []
        case .nsf44: [.hardness]
        case .nsf244, .p231: [.bacteria, .viruses, .cysts]
        }
    }
}

nonisolated enum Certifier: String, Codable, CaseIterable, Sendable {
    case nsf, iapmo, wqa, csa, ul

    var name: String {
        switch self {
        case .nsf: "NSF"
        case .iapmo: "IAPMO"
        case .wqa: "WQA"
        case .csa: "CSA"
        case .ul: "UL"
        }
    }
}

nonisolated struct CertificationClaim: Codable, Hashable, Sendable, Identifiable {
    var id = UUID().uuidString
    var standard: CertificationStandard
    var certifier: Certifier
    var target: ClaimTarget
    /// e.g. 99.3 for 99.3%.
    var reductionPercent: Double
    /// The concentration the product was tested against, in the target's usual unit
    /// (`ReadingUnit.canonical(for:)`). Nil means unknown: the claim then doesn't count.
    var influentChallengeConcentration: Double?
    var ratedCapacityGallons: Double?
    var ratedLifeMonths: Int?
    var source: SourceRef
}

nonisolated enum FilterType: String, Codable, CaseIterable, Sendable, Identifiable {
    case pitcher, faucet, countertop, underSinkCarbon, reverseOsmosis, wholeHouse, shower, uv, softener, refrigerator

    var id: Self { self }

    var name: String {
        switch self {
        case .pitcher: String(localized: "Pitcher")
        case .faucet: String(localized: "Faucet mount")
        case .countertop: String(localized: "Countertop")
        case .underSinkCarbon: String(localized: "Under-sink carbon")
        case .reverseOsmosis: String(localized: "Reverse osmosis")
        case .wholeHouse: String(localized: "Whole house")
        case .shower: String(localized: "Shower")
        case .uv: String(localized: "UV")
        case .softener: String(localized: "Water softener")
        case .refrigerator: String(localized: "Refrigerator")
        }
    }

    init(kind: TreatmentKind) {
        switch kind {
        case .pitcherFilter: self = .pitcher
        case .faucetFilter: self = .faucet
        case .refrigeratorFilter: self = .refrigerator
        case .underSinkFilter: self = .underSinkCarbon
        case .showerFilter: self = .shower
        case .sedimentFilter, .carbonFilter: self = .wholeHouse
        case .roMembrane: self = .reverseOsmosis
        case .uvBulb: self = .uv
        case .softenerSalt: self = .softener
        case .other: self = .countertop
        }
    }

    var defaultLocation: TapLocation {
        switch self {
        case .wholeHouse, .uv, .softener: .wholeHouse
        case .shower: TapLocation(kind: .shower)
        case .refrigerator: TapLocation(kind: .fridge)
        case .pitcher, .faucet, .countertop, .underSinkCarbon, .reverseOsmosis: .kitchen
        }
    }

    var installDifficulty: InstallDifficulty {
        switch self {
        case .pitcher, .refrigerator: .none
        case .faucet, .countertop, .shower: .easy
        case .underSinkCarbon: .moderate
        case .reverseOsmosis, .wholeHouse, .uv, .softener: .professional
        }
    }
}

nonisolated enum InstallDifficulty: String, Codable, Sendable, Comparable {
    case none, easy, moderate, professional

    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
    private var rank: Int {
        switch self {
        case .none: 0
        case .easy: 1
        case .moderate: 2
        case .professional: 3
        }
    }

    var label: String {
        switch self {
        case .none: String(localized: "No install")
        case .easy: String(localized: "Easy, no tools")
        case .moderate: String(localized: "Some plumbing")
        case .professional: String(localized: "Professional install")
        }
    }
}

nonisolated struct FilterProduct: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var brand: String
    var model: String
    var type: FilterType
    var claims: [CertificationClaim]
    var ratedCapacityGallons: Double?
    var ratedLifeMonths: Int?
    /// Up-front price in US dollars.
    var priceUSD: Double?
    /// Replacement cartridges per year, in US dollars.
    var annualCostUSD: Double?
    /// Entered by the user from a certifier listing (not bundled).
    var isUserEntered = false
    var source: SourceRef

    var displayName: String { "\(brand) \(model)".trimmingCharacters(in: .whitespaces) }
    var isCertified: Bool { !claims.isEmpty }
    var needsVerification: Bool { source.needsVerification || claims.contains { $0.source.needsVerification } }
}

/// Where water comes out: the whole house, or one tap. Stored as "kitchen", "shower.2"…
nonisolated struct TapLocation: Hashable, Codable, Sendable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case wholeHouse, kitchen, fridge, bathroomSink, shower
    }

    var kind: Kind
    /// 1-based, for homes with more than one shower or bathroom sink.
    var index = 1

    static let wholeHouse = TapLocation(kind: .wholeHouse)
    static let kitchen = TapLocation(kind: .kitchen)

    var id: String { rawValue }

    var rawValue: String { index > 1 ? "\(kind.rawValue).\(index)" : kind.rawValue }

    init(kind: Kind, index: Int = 1) {
        self.kind = kind
        self.index = max(1, index)
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".")
        guard let first = parts.first, let kind = Kind(rawValue: String(first)) else { return nil }
        self.init(kind: kind, index: parts.count > 1 ? Int(parts[1]) ?? 1 : 1)
    }

    /// Kitchen, fridge and bathroom sinks are drinking taps; showers are for washing.
    var isDrinking: Bool { kind != .shower && kind != .wholeHouse }

    var name: String {
        let base: String = switch kind {
        case .wholeHouse: String(localized: "Whole house")
        case .kitchen: String(localized: "Kitchen tap")
        case .fridge: String(localized: "Fridge water")
        case .bathroomSink: String(localized: "Bathroom sink")
        case .shower: String(localized: "Shower")
        }
        return index > 1 ? "\(base) \(index)" : base
    }
}
