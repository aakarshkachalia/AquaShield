//
//  ContaminantInfo.swift
//  ClearWellNC
//
//  THE single source of truth for limits and interpretation wording. Every screen that shows a
//  contaminant value reads from here. Values marked `// VERIFY` must be checked against the cited
//  source before release; none of them were invented, but regulations change.
//

import Foundation

// MARK: - Identifiers and units

nonisolated enum ContaminantID: String, CaseIterable, Sendable, Codable, Identifiable {
    case arsenic, lead, nitrate, nitrite, uranium, manganese, iron, copper, fluoride
    case totalColiform, eColi, pH, hardness, radon
    case pfoa, pfos, genx

    var id: String { rawValue }
    var info: ContaminantInfo { ContaminantInfo.info(for: self) }
}

nonisolated enum MeasurementUnit: Sendable {
    case ppb
    case mgL
    /// Hardness is reported as mg/L of calcium carbonate.
    case mgLAsCaCO3
    case pCiL
    /// Parts per trillion (ng/L), for PFAS.
    case ppt
    /// pH has no unit.
    case pH
    /// Bacteria: present / absent.
    case presence

    var label: String {
        switch self {
        case .ppb: String(localized: "ppb")
        case .mgL: String(localized: "mg/L")
        case .mgLAsCaCO3: String(localized: "mg/L as CaCO₃")
        case .pCiL: String(localized: "pCi/L")
        case .ppt: String(localized: "ppt")
        case .pH, .presence: ""
        }
    }

    /// Units the lab form can convert between (1 mg/L = 1000 ppb). Nil for fixed units.
    var concentration: ConcentrationUnit? {
        switch self {
        case .ppb: .ppb
        case .mgL: .mgL
        case .mgLAsCaCO3, .pCiL, .ppt, .pH, .presence: nil
        }
    }
}

nonisolated enum RegulatoryLimit: Sendable {
    /// At or above this value is over the limit.
    case maximum(Double)
    /// Recommended range (pH).
    case range(low: Double, high: Double)
    /// Any detection is over the limit (bacteria).
    case mustBeAbsent
    /// No federal or NC limit (hardness).
    case none
}

nonisolated enum LimitType: Sendable {
    /// Set to protect health (EPA MCL / action level, NC health standard).
    case health
    /// Cosmetic or practical only: taste, staining, scale, corrosion (EPA secondary standard).
    case aesthetic
}

nonisolated enum SensitiveGroup: Sendable, CaseIterable {
    case infants, children, pregnancy, olderAdults, weakenedImmunity

    /// Singular noun phrase for "…if ___ drinks this water."
    var phrase: String {
        switch self {
        case .infants: String(localized: "an infant")
        case .children: String(localized: "a child")
        case .pregnancy: String(localized: "someone who is pregnant")
        case .olderAdults: String(localized: "an older adult")
        case .weakenedImmunity: String(localized: "someone with a weakened immune system")
        }
    }

    var label: String {
        switch self {
        case .infants: String(localized: "Infants")
        case .children: String(localized: "Children")
        case .pregnancy: String(localized: "Pregnancy")
        case .olderAdults: String(localized: "Older adults")
        case .weakenedImmunity: String(localized: "Weakened immune systems")
        }
    }
}

/// A second reference value, e.g. manganese's health advisory above its aesthetic guideline.
nonisolated struct SecondaryLimit: Sendable {
    let value: Double
    let source: String
}

/// Labeled band for contaminants classified rather than limited (hardness).
nonisolated struct ClassBand: Sendable {
    /// Inclusive upper bound; nil for the last band.
    let upTo: Double?
    let label: String
    /// Whether this band is high enough to cause noticeable practical effects.
    let isNoticeable: Bool
}

// MARK: - Catalog entry

nonisolated struct ContaminantInfo: Sendable, Identifiable {
    let id: ContaminantID
    let name: String
    let unit: MeasurementUnit
    let limit: RegulatoryLimit
    let limitSource: String
    let limitType: LimitType
    /// How the limit is named in sentences ("safe limit", "action level", "guideline").
    let limitPhrase: String
    let healthAdvisory: SecondaryLimit?
    let sensitiveGroups: [SensitiveGroup]
    let plainSummary: String
    /// Practical effect for aesthetic contaminants (lowercase phrase), e.g. "orange-brown stains…".
    let practicalImpact: String?
    /// pH only: effect when the value is above the range.
    let practicalImpactHigh: String?
    /// Short, sourced explanation of seasonal behavior, used in forecast insights. Nil if none.
    let seasonalContext: String?
    let actionIfAbove: String
    let actionIfWatch: String
    let classBands: [ClassBand]

    /// "Limit: 10 ppb (EPA MCL)" style line for display.
    var limitDescription: String {
        switch limit {
        case .maximum(let value):
            let base = String(localized: "\(formatNumber(value)) \(unit.label) · \(limitSource)")
            if let advisory = healthAdvisory {
                return base + " · " + String(localized: "\(formatNumber(advisory.value)) \(unit.label) \(advisory.source)")
            }
            return base
        case .range(let low, let high):
            return String(localized: "\(formatNumber(low))–\(formatNumber(high)) · \(limitSource)")
        case .mustBeAbsent:
            return String(localized: "Must be absent · \(limitSource)")
        case .none:
            return limitSource
        }
    }

    var maximumLimit: Double? {
        if case .maximum(let value) = limit { return value }
        return nil
    }
}

nonisolated func formatNumber(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...3)))
}

// MARK: - The catalog

nonisolated extension ContaminantInfo {
    // swiftlint:disable function_body_length
    static func info(for id: ContaminantID) -> ContaminantInfo {
        switch id {
        case .arsenic:
            return ContaminantInfo(
                id: id, name: String(localized: "Arsenic"), unit: .ppb,
                // VERIFY: EPA MCL 0.010 mg/L (10 ppb), 40 CFR 141.62. NC 15A NCAC 02L groundwater standard is also 10 µg/L.
                limit: .maximum(10), limitSource: String(localized: "EPA MCL"), limitType: .health,
                limitPhrase: String(localized: "safe limit"), healthAdvisory: nil,
                // VERIFY: EPA / CDC list pregnancy and early childhood as sensitive periods for arsenic exposure.
                sensitiveGroups: [.pregnancy, .children],
                plainSummary: String(localized: "Arsenic comes from certain bedrock. It has no taste or smell, and long-term exposure raises cancer risk."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Use bottled water or a reverse osmosis filter certified to NSF/ANSI 58 for arsenic for drinking and cooking, then retest."),
                actionIfWatch: String(localized: "Retest within a year to see if it is changing."),
                classBands: [])

        case .lead:
            return ContaminantInfo(
                id: id, name: String(localized: "Lead"), unit: .ppb,
                // VERIFY: EPA Lead and Copper Rule action level 0.015 mg/L (15 ppb); MCLG is zero (no known safe level).
                // EPA's 2024 Lead and Copper Rule Improvements lower the action level to 10 ppb (compliance ~2027).
                limit: .maximum(15), limitSource: String(localized: "EPA action level"), limitType: .health,
                limitPhrase: String(localized: "action level"), healthAdvisory: nil,
                // VERIFY: EPA / CDC: infants, children and pregnancy are most at risk from lead.
                sensitiveGroups: [.infants, .children, .pregnancy],
                plainSummary: String(localized: "Lead in well water usually comes from pipes, solder and well parts, not the rock. EPA's health goal for lead is zero, because no level is known to be safe."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Use bottled water or a filter certified to NSF/ANSI 53 for lead for drinking and cooking, and retest after fixing the source."),
                actionIfWatch: String(localized: "Use only cold water for drinking and cooking, and retest, especially if children or a pregnant person live here."),
                classBands: [])

        case .nitrate:
            return ContaminantInfo(
                id: id, name: String(localized: "Nitrate"), unit: .mgL,
                // VERIFY: EPA MCL 10 mg/L as nitrogen (40 CFR 141.62). NC 02L standard is also 10 mg/L.
                limit: .maximum(10), limitSource: String(localized: "EPA MCL (as N)"), limitType: .health,
                limitPhrase: String(localized: "safe limit"), healthAdvisory: nil,
                // VERIFY: EPA / CDC: infants under 6 months are most at risk (methemoglobinemia); pregnancy also listed by CDC.
                sensitiveGroups: [.infants, .pregnancy],
                plainSummary: String(localized: "Nitrate comes from fertilizer, manure and septic systems. It is most dangerous for babies under 6 months."),
                practicalImpact: nil, practicalImpactHigh: nil,
                // VERIFY: USGS / NC DEQ: fertilizer application and recharge from rain can raise shallow-groundwater nitrate in spring.
                seasonalContext: String(localized: "Spring fertilizing and heavy rain can carry nitrate into groundwater."),
                actionIfAbove: String(localized: "Do not use this water for baby formula. Use bottled water for drinking and cooking, and look for nearby sources like septic systems or fertilizer."),
                actionIfWatch: String(localized: "Retest in spring, and before using this water for baby formula."),
                classBands: [])

        case .nitrite:
            return ContaminantInfo(
                id: id, name: String(localized: "Nitrite"), unit: .mgL,
                // VERIFY: EPA MCL 1 mg/L as nitrogen (40 CFR 141.62).
                limit: .maximum(1), limitSource: String(localized: "EPA MCL (as N)"), limitType: .health,
                limitPhrase: String(localized: "safe limit"), healthAdvisory: nil,
                // VERIFY: same sensitive groups as nitrate (EPA / CDC).
                sensitiveGroups: [.infants, .pregnancy],
                plainSummary: String(localized: "Nitrite comes from the same sources as nitrate and is even more harmful at lower levels, especially for babies."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Do not use this water for baby formula. Use bottled water for drinking and cooking, and retest."),
                actionIfWatch: String(localized: "Retest, and before using this water for baby formula."),
                classBands: [])

        case .uranium:
            return ContaminantInfo(
                id: id, name: String(localized: "Uranium"), unit: .ppb,
                // VERIFY: EPA MCL 30 µg/L (ppb), Radionuclides Rule (40 CFR 141.66).
                limit: .maximum(30), limitSource: String(localized: "EPA MCL"), limitType: .health,
                limitPhrase: String(localized: "safe limit"), healthAdvisory: nil,
                sensitiveGroups: [],
                plainSummary: String(localized: "Uranium comes from granite and other bedrock. Over many years it can harm the kidneys and raise cancer risk."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Use bottled water or a certified reverse osmosis or anion exchange system for drinking water, then retest."),
                actionIfWatch: String(localized: "Retest with your next metals panel."),
                classBands: [])

        case .manganese:
            return ContaminantInfo(
                id: id, name: String(localized: "Manganese"), unit: .ppb,
                // VERIFY: EPA secondary standard (SMCL) 0.05 mg/L (50 ppb), aesthetic. NC 02L groundwater standard is also 50 µg/L.
                limit: .maximum(50), limitSource: String(localized: "EPA secondary standard"), limitType: .aesthetic,
                limitPhrase: String(localized: "guideline"),
                // VERIFY: EPA lifetime health advisory 0.3 mg/L (300 ppb); EPA advises applying it to infants under 6 months.
                healthAdvisory: SecondaryLimit(value: 300, source: String(localized: "EPA health advisory")),
                sensitiveGroups: [.infants],
                plainSummary: String(localized: "Manganese comes from rock and soil. Low levels mostly cause stains, but high levels are a concern for infants."),
                practicalImpact: String(localized: "black or brown stains on sinks and laundry and a bitter taste"),
                practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Use bottled water for infants and consider treatment such as oxidation/filtration (greensand)."),
                actionIfWatch: String(localized: "Consider a softener or oxidizing filter if staining bothers you."),
                classBands: [])

        case .iron:
            return ContaminantInfo(
                id: id, name: String(localized: "Iron"), unit: .ppb,
                // VERIFY: EPA secondary standard (SMCL) 0.3 mg/L (300 ppb), aesthetic only.
                limit: .maximum(300), limitSource: String(localized: "EPA secondary standard"), limitType: .aesthetic,
                limitPhrase: String(localized: "guideline"), healthAdvisory: nil,
                sensitiveGroups: [],
                plainSummary: String(localized: "Iron is common in NC groundwater. It is not a health concern at typical well levels, but it stains and changes the taste."),
                practicalImpact: String(localized: "orange-brown stains, a metallic taste and clogged plumbing"),
                practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Consider an iron filter (oxidation/filtration) or a water softener if staining bothers you."),
                actionIfWatch: String(localized: "No action needed unless staining bothers you."),
                classBands: [])

        case .copper:
            return ContaminantInfo(
                id: id, name: String(localized: "Copper"), unit: .mgL,
                // VERIFY: EPA Lead and Copper Rule action level 1.3 mg/L (MCLG 1.3 mg/L). EPA SMCL is 1.0 mg/L (taste/staining).
                limit: .maximum(1.3), limitSource: String(localized: "EPA action level"), limitType: .health,
                limitPhrase: String(localized: "action level"), healthAdvisory: nil,
                // VERIFY: EPA lists infants and people with Wilson's disease as more sensitive to copper.
                sensitiveGroups: [.infants],
                plainSummary: String(localized: "Copper usually comes from copper pipes that corrode, often because the water is acidic."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Run the cold tap before using water for drinking, check for corroding pipes, and retest."),
                actionIfWatch: String(localized: "Check your pH; acidic water corrodes copper pipes."),
                classBands: [])

        case .fluoride:
            return ContaminantInfo(
                id: id, name: String(localized: "Fluoride"), unit: .mgL,
                // VERIFY: EPA MCL 4.0 mg/L (bone effects); EPA SMCL 2.0 mg/L (dental fluorosis in children).
                limit: .maximum(4.0), limitSource: String(localized: "EPA MCL"), limitType: .health,
                limitPhrase: String(localized: "safe limit"), healthAdvisory: nil,
                // VERIFY: EPA: children under 9 are at risk of dental fluorosis above 2 mg/L.
                sensitiveGroups: [.children],
                plainSummary: String(localized: "Fluoride occurs naturally in some rock. Above 2 mg/L it can spot children's teeth; above 4 mg/L it can affect bones over time."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Use another water source for drinking, especially for children, and retest."),
                actionIfWatch: String(localized: "Above 2 mg/L, use another water source for young children's drinking water."),
                classBands: [])

        case .totalColiform:
            return ContaminantInfo(
                id: id, name: String(localized: "Total coliform"), unit: .presence,
                // VERIFY: EPA Revised Total Coliform Rule: presence triggers corrective action; private wells should test absent.
                limit: .mustBeAbsent, limitSource: String(localized: "EPA"), limitType: .health,
                limitPhrase: String(localized: "standard"), healthAdvisory: nil,
                // VERIFY: CDC: infants, older adults and people with weakened immune systems are most at risk from waterborne germs.
                sensitiveGroups: [.infants, .olderAdults, .weakenedImmunity],
                plainSummary: String(localized: "Coliform bacteria are a warning sign that germs can get into your well, often through a damaged cap or after flooding."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Shock-chlorinate the well, find how germs are getting in, and retest after the chlorine is flushed out."),
                actionIfWatch: String(localized: "Test for bacteria every year and after flooding."),
                classBands: [])

        case .eColi:
            return ContaminantInfo(
                id: id, name: String(localized: "E. coli"), unit: .presence,
                // VERIFY: EPA MCL for E. coli: any confirmed presence is a violation (40 CFR 141.63).
                limit: .mustBeAbsent, limitSource: String(localized: "EPA MCL"), limitType: .health,
                limitPhrase: String(localized: "standard"), healthAdvisory: nil,
                sensitiveGroups: [.infants, .olderAdults, .weakenedImmunity],
                plainSummary: String(localized: "E. coli means human or animal waste is getting into your well. It can cause serious illness."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Do not drink untreated. Use bottled water, call your county health department, shock-chlorinate the well and retest."),
                actionIfWatch: String(localized: "Test for bacteria every year and after flooding."),
                classBands: [])

        case .pH:
            return ContaminantInfo(
                id: id, name: String(localized: "pH"), unit: .pH,
                // VERIFY: EPA secondary standard 6.5–8.5, aesthetic.
                limit: .range(low: 6.5, high: 8.5), limitSource: String(localized: "EPA secondary standard"), limitType: .aesthetic,
                limitPhrase: String(localized: "recommended range"), healthAdvisory: nil,
                sensitiveGroups: [],
                plainSummary: String(localized: "pH tells you how acidic or basic your water is. It has no health limit, but acidic water can corrode pipes."),
                practicalImpact: String(localized: "acidic water can corrode pipes and release lead and copper into your water"),
                practicalImpactHigh: String(localized: "high-pH water can taste bitter and leave scale"),
                seasonalContext: nil,
                actionIfAbove: String(localized: "Consider an acid-neutralizing filter, and test for lead and copper."),
                actionIfWatch: String(localized: "No action needed."),
                classBands: [])

        case .hardness:
            return ContaminantInfo(
                id: id, name: String(localized: "Hardness"), unit: .mgLAsCaCO3,
                // VERIFY: no EPA or NC limit. Bands from USGS water-hardness classification (mg/L as CaCO₃).
                limit: .none, limitSource: String(localized: "No limit (USGS hardness scale)"), limitType: .aesthetic,
                limitPhrase: String(localized: "scale"), healthAdvisory: nil,
                sensitiveGroups: [],
                plainSummary: String(localized: "Hardness is dissolved calcium and magnesium. It is not a health concern but leaves scale."),
                practicalImpact: String(localized: "scale on faucets, kettles and water heaters, and less soap lather"),
                practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Consider a water softener if scale bothers you."),
                actionIfWatch: String(localized: "No action needed."),
                classBands: [
                    // VERIFY: USGS: 0–60 soft, 61–120 moderately hard, 121–180 hard, >180 very hard.
                    ClassBand(upTo: 60, label: String(localized: "Soft"), isNoticeable: false),
                    ClassBand(upTo: 120, label: String(localized: "Moderately hard"), isNoticeable: false),
                    ClassBand(upTo: 180, label: String(localized: "Hard"), isNoticeable: true),
                    ClassBand(upTo: nil, label: String(localized: "Very hard"), isNoticeable: true),
                ])

        case .pfoa, .pfos, .genx:
            return pfasInfo(for: id)

        case .radon:
            return ContaminantInfo(
                id: id, name: String(localized: "Radon in water"), unit: .pCiL,
                // VERIFY: there is NO final federal limit. EPA's 1999 proposal: MCL 300 pCi/L, or an alternative MCL of
                // 4,000 pCi/L where a state runs an indoor-air radon program. NC has no private-well radon standard.
                limit: .maximum(4000), limitSource: String(localized: "EPA proposed alternative limit (not final)"), limitType: .health,
                limitPhrase: String(localized: "proposed limit"), healthAdvisory: nil,
                sensitiveGroups: [],
                plainSummary: String(localized: "Radon is a radioactive gas from uranium in bedrock. It escapes from water into the air when you shower or run water, and breathing it raises lung cancer risk."),
                practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
                actionIfAbove: String(localized: "Consider an aeration system, and test the air in your home for radon."),
                actionIfWatch: String(localized: "Test the air in your home for radon, too."),
                classBands: [])
        }
    }
    // swiftlint:enable function_body_length
}

// MARK: - PFAS

nonisolated extension ContaminantInfo {
    static func pfasInfo(for id: ContaminantID) -> ContaminantInfo {
        let name: String
        let limit: Double
        switch id {
        case .pfoa:
            name = String(localized: "PFOA")
            // VERIFY: EPA PFAS National Primary Drinking Water Regulation (April 2024): PFOA MCL 4.0 ppt (ng/L).
            // In 2025 EPA said it would keep the PFOA/PFOS MCLs but extend compliance to 2031.
            limit = 4.0
        case .pfos:
            name = String(localized: "PFOS")
            // VERIFY: EPA 2024 PFAS rule: PFOS MCL 4.0 ppt.
            limit = 4.0
        default:
            name = String(localized: "GenX (HFPO-DA)")
            // VERIFY: EPA 2024 PFAS rule: HFPO-DA (GenX) MCL 10 ppt. In 2025 EPA announced it intends to rescind and
            // reconsider this limit; NC DEQ PFAS programs may use a different threshold.
            limit = 10
        }
        return ContaminantInfo(
            id: id, name: name, unit: .ppt,
            limit: .maximum(limit), limitSource: String(localized: "EPA MCL (2024 PFAS rule)"), limitType: .health,
            limitPhrase: String(localized: "safe limit"), healthAdvisory: nil,
            // VERIFY: EPA lists pregnancy, infants and children as sensitive to PFAS exposure.
            sensitiveGroups: [.pregnancy, .infants, .children],
            plainSummary: String(localized: "PFAS are \"forever chemicals\" from industry and some products. They build up in the body, and long-term exposure is linked to some cancers and other health effects."),
            practicalImpact: nil, practicalImpactHigh: nil, seasonalContext: nil,
            actionIfAbove: String(localized: "Use bottled water or a filter certified for PFAS reduction (NSF/ANSI 53 or 58) for drinking and cooking. See Get Help: some programs test for free or help pay for treatment."),
            actionIfWatch: String(localized: "Retest, and consider a filter certified for PFAS reduction."),
            classBands: [])
    }
}

// MARK: - Resources

/// External links used by disclaimers and the Learn tab.
nonisolated enum WellResources {
    // VERIFY: all URLs below were current to the best of our knowledge; confirm before release.
    static let ncdhhsPrivateWells = URL(string: "https://epi.dph.ncdhhs.gov/oee/programs/wells.html")!
    static let ncCountyHealthDepartments = URL(string: "https://www.ncdhhs.gov/divisions/public-health/county-health-departments")!
    static let ncStateLab = URL(string: "https://slph.dph.ncdhhs.gov/")!
    static let ncRadon = URL(string: "https://www.ncradon.org/")!
    static let epaPrivateWells = URL(string: "https://www.epa.gov/privatewells")!
    static let epaPrimaryStandards = URL(string: "https://www.epa.gov/ground-water-and-drinking-water/national-primary-drinking-water-regulations")!
    static let epaSecondaryStandards = URL(string: "https://www.epa.gov/sdwa/secondary-drinking-water-standards-guidance-nuisance-chemicals")!
    static let epaLead = URL(string: "https://www.epa.gov/ground-water-and-drinking-water/basic-information-about-lead-drinking-water")!
    static let epaRadon = URL(string: "https://www.epa.gov/radon")!
    static let cdcPrivateWells = URL(string: "https://www.cdc.gov/drinking-water/about/about-private-wells.html")!
    static let epaConsumerConfidenceReports = URL(string: "https://www.epa.gov/ccr")!
    static let nsfCertifiedFilters = URL(string: "https://info.nsf.org/Certified/DWTU/")!
}
