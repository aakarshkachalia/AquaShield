//
//  Household.swift
//  ClearWellNC
//
//  Household members (nickname only, on this device), the home's plumbing, and app modes. Stored in
//  AppSettings, scoped so Demo Mode never touches real answers.
//

import Foundation

nonisolated struct HouseholdMember: Codable, Equatable, Sendable, Identifiable {
    enum AgeBand: String, Codable, CaseIterable, Sendable {
        case infant, toddler, child, teen, adult, olderAdult

        var label: String {
            switch self {
            case .infant: String(localized: "Baby under 1")
            case .toddler: String(localized: "1–5 years")
            case .child: String(localized: "6–12 years")
            case .teen: String(localized: "13–17 years")
            case .adult: String(localized: "18–64 years")
            case .olderAdult: String(localized: "65 or older")
            }
        }

        var isChild: Bool { self == .infant || self == .toddler || self == .child }

        /// Typical drinking water per day in liters when the user doesn't say (rounded EPA Exposure Factors
        /// Handbook values; needs verification).
        var typicalLitersPerDay: Double {
            switch self {
            case .infant: 0.7
            case .toddler: 0.5
            case .child: 0.6
            case .teen: 0.8
            case .adult, .olderAdult: 1.2
            }
        }
    }

    enum Sex: String, Codable, CaseIterable, Sendable {
        case female, male, notSaying
        var label: String {
            switch self {
            case .female: String(localized: "Female")
            case .male: String(localized: "Male")
            case .notSaying: String(localized: "Prefer not to say")
            }
        }
    }

    /// Where this person's drinking water comes from.
    enum DrinkingSource: Codable, Hashable, Sendable {
        case tap(TapLocation)
        case bottled
    }

    var id = UUID()
    var nickname = ""
    var ageBand: AgeBand = .adult
    var sex: Sex = .notSaying
    var pregnant = false
    var breastfeeding = false
    var infantOnFormula = false
    var weightKg: Double?
    /// Drinking water per day; nil = typical for age.
    var drinkingLitersPerDay: Double?
    /// Water used in food and drinks they cook, per day.
    var cookingLitersPerDay: Double = 0
    var drinkingSource: DrinkingSource = .tap(.kitchen)
    var showerMinutes: Double = 10
    var showersPerWeek: Double = 7
    var immunocompromised = false
    var kidneyDisease = false
    var eczema = false
    var symptoms: Set<Symptom> = []

    var dailyLiters: Double { (drinkingLitersPerDay ?? ageBand.typicalLitersPerDay) + cookingLitersPerDay }

    var displayName: String {
        let name = nickname.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? ageBand.label : name
    }
}

/// Optional, by body system. Symptoms only ever lead to "worth discussing with your doctor".
nonisolated enum Symptom: String, Codable, CaseIterable, Sendable, Identifiable {
    // Stomach
    case nausea, diarrhea, stomachCramps
    // Skin
    case skinDarkening, skinThickening, rash, drySkin
    // Breathing
    case cough
    // Blood (infants)
    case blueTingeLipsOrSkin
    // Nerves and growth
    case tiredness, troubleConcentrating

    var id: Self { self }

    enum BodySystem: String, CaseIterable, Sendable {
        case stomach, skin, breathing, blood, nerves
        var label: String {
            switch self {
            case .stomach: String(localized: "Stomach")
            case .skin: String(localized: "Skin")
            case .breathing: String(localized: "Breathing")
            case .blood: String(localized: "Color (babies)")
            case .nerves: String(localized: "Energy and focus")
            }
        }
    }

    var system: BodySystem {
        switch self {
        case .nausea, .diarrhea, .stomachCramps: .stomach
        case .skinDarkening, .skinThickening, .rash, .drySkin: .skin
        case .cough: .breathing
        case .blueTingeLipsOrSkin: .blood
        case .tiredness, .troubleConcentrating: .nerves
        }
    }

    var label: String {
        switch self {
        case .nausea: String(localized: "Nausea")
        case .diarrhea: String(localized: "Diarrhea")
        case .stomachCramps: String(localized: "Stomach cramps")
        case .skinDarkening: String(localized: "Dark patches on skin")
        case .skinThickening: String(localized: "Thick, rough skin on palms or soles")
        case .rash: String(localized: "Rash or irritation")
        case .drySkin: String(localized: "Dry, itchy skin")
        case .cough: String(localized: "Cough")
        case .blueTingeLipsOrSkin: String(localized: "Bluish lips or skin")
        case .tiredness: String(localized: "Tiredness")
        case .troubleConcentrating: String(localized: "Trouble concentrating")
        }
    }

    /// Contaminants with this among their known effects (CDC/ATSDR summaries; needs verification).
    var relatedTargets: Set<ClaimTarget> {
        switch self {
        case .nausea, .diarrhea, .stomachCramps: [.bacteria, .copper, .nitrate]
        case .skinDarkening, .skinThickening: [.arsenic]
        case .rash: [.freeChlorine, .chloramine, .hardness]
        case .drySkin: [.hardness, .freeChlorine]
        case .cough: [.radon]
        case .blueTingeLipsOrSkin: [.nitrate, .nitrite]
        case .tiredness, .troubleConcentrating: [.lead, .manganese]
        }
    }

    /// Skin signs that should route straight to a doctor in a well home.
    var isArsenicSkinRedFlag: Bool { self == .skinDarkening || self == .skinThickening }
}

/// The home and its plumbing. Feeds recommended tests and score confidence.
nonisolated struct HomeProfile: Codable, Equatable, Sendable {
    enum ServiceLine: String, Codable, CaseIterable, Sendable {
        case unknown, lead, galvanized, notLead
        var label: String {
            switch self {
            case .unknown: String(localized: "Not sure")
            case .lead: String(localized: "Lead")
            case .galvanized: String(localized: "Galvanized steel")
            case .notLead: String(localized: "Not lead (copper or plastic)")
            }
        }
    }

    enum Plumbing: String, Codable, CaseIterable, Sendable {
        case unknown, copper, plastic, galvanized, lead
        var label: String {
            switch self {
            case .unknown: String(localized: "Not sure")
            case .copper: String(localized: "Copper")
            case .plastic: String(localized: "Plastic (PEX or PVC)")
            case .galvanized: String(localized: "Galvanized steel")
            case .lead: String(localized: "Lead")
            }
        }
    }

    var yearBuilt: Int?
    var serviceLine: ServiceLine = .unknown
    var plumbing: Plumbing = .unknown
    var wellDepthFeet: Double?
    var wellYearDrilled: Int?
    var septicDistanceFeet: Double?
    var showerCount = 1
    var bathroomSinkCount = 1

    static let storageKey = "homeProfile"

    /// Lead solder was banned in drinking water plumbing in 1986.
    var mayHaveLeadSolder: Bool? { yearBuilt.map { $0 < 1986 } }

    var leadPlumbingRisk: Bool {
        serviceLine == .lead || serviceLine == .galvanized || plumbing == .lead || plumbing == .galvanized
            || mayHaveLeadSolder == true
    }

    /// NC rules generally ask for at least 100 feet between a well and a septic system (needs verification).
    static let septicSetbackFeet = 100.0
    var septicTooClose: Bool { (septicDistanceFeet ?? .infinity) < Self.septicSetbackFeet }

    /// Every tap in the home, for per-tap scores.
    var taps: [TapLocation] {
        var taps: [TapLocation] = [.kitchen]
        for i in 1...max(1, showerCount) { taps.append(TapLocation(kind: .shower, index: i)) }
        return taps
    }
}

/// Situations that change what the app shows first.
nonisolated enum WaterMode: String, Codable, CaseIterable, Sendable {
    case flood, infant, boilWater

    var label: String {
        switch self {
        case .flood: String(localized: "Flood or hurricane")
        case .infant: String(localized: "Baby in the home")
        case .boilWater: String(localized: "Boil-water advisory")
        }
    }

    var symbol: String {
        switch self {
        case .flood: "water.waves"
        case .infant: "figure.and.child.holdinghands"
        case .boilWater: "flame.fill"
        }
    }
}
