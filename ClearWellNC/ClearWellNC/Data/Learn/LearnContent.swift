//
//  LearnContent.swift
//  ClearWellNC
//
//  Educational content for the Learn tab: one article + 3-question quiz per contaminant.
//  Health statements follow EPA / CDC / NC DHHS public guidance. Every effectiveness figure and
//  health claim is marked // VERIFY with its source so a reviewer can confirm it before release.
//

import Foundation

nonisolated struct Treatment: Sendable, Identifiable {
    let name: String
    /// Approximate effectiveness, e.g. "Removes most (often 90%+)".
    let effectiveness: String
    let note: String?
    var id: String { name }
}

nonisolated struct SourceLink: Sendable, Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

nonisolated struct QuizQuestion: Sendable, Identifiable {
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let explanation: String
    var id: String { prompt }
}

nonisolated struct LearnArticle: Sendable, Identifiable {
    let id: String
    let title: String
    let contaminants: [ContaminantID]
    let symbol: String
    let whereFrom: String
    let shortTerm: String
    let longTerm: String
    let mostAtRisk: String
    let treatments: [Treatment]
    let retest: String
    let sources: [SourceLink]
    let quiz: [QuizQuestion]

    /// Shown on every card: symptoms are often absent.
    static var symptomsNote: String {
        String(localized: "Most well contaminants have no taste, smell or early symptoms. Testing is the only way to know.")
    }

    static var footer: String {
        String(localized: "Educational info, not medical advice. Talk to a doctor if you have health concerns.")
    }
}

// MARK: - Content

nonisolated enum LearnLibrary {
    private static let epaWells = SourceLink(title: String(localized: "EPA: Private drinking water wells"), url: WellResources.epaPrivateWells)
    private static let epaPrimary = SourceLink(title: String(localized: "EPA: National primary drinking water regulations"), url: WellResources.epaPrimaryStandards)
    private static let epaSecondary = SourceLink(title: String(localized: "EPA: Secondary drinking water standards"), url: WellResources.epaSecondaryStandards)
    private static let cdcWells = SourceLink(title: String(localized: "CDC: Private water systems"), url: WellResources.cdcPrivateWells)
    private static let ncWells = SourceLink(title: String(localized: "NC DHHS: Private well water"), url: WellResources.ncdhhsPrivateWells)

    // swiftlint:disable function_body_length
    static let articles: [LearnArticle] = [
        LearnArticle(
            id: "arsenic", title: String(localized: "Arsenic"), contaminants: [.arsenic], symbol: "mountain.2",
            // VERIFY: NC DHHS / USGS: arsenic in NC wells is linked to Carolina Slate Belt bedrock in the central Piedmont.
            whereFrom: String(localized: "Arsenic comes from natural bedrock. In North Carolina it is most common in wells on the Carolina Slate Belt, a band of rock across the central Piedmont."),
            // VERIFY: EPA arsenic fact sheet; very high doses cause stomach upset, rarely seen from wells.
            shortTerm: String(localized: "Levels found in wells rarely cause short-term symptoms."),
            // VERIFY: EPA: long-term exposure linked to skin changes and cancers of the skin, bladder and lung, and heart disease.
            longTerm: String(localized: "Drinking it for years raises the risk of skin, bladder and lung cancer, and is linked to heart disease and skin changes."),
            mostAtRisk: String(localized: "Pregnancy and young children, because they are still developing."),
            treatments: [
                // VERIFY: EPA / NSF: RO removal is high for arsenic(V); arsenic(III) may need pre-oxidation.
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58)"), effectiveness: String(localized: "Removes most arsenic (often 90% or more)"),
                          note: String(localized: "Under-sink units treat drinking and cooking water.")),
                // VERIFY: EPA arsenic treatment technologies: iron-based adsorptive media.
                Treatment(name: String(localized: "Adsorptive media (iron-based)"), effectiveness: String(localized: "High, when media is replaced on schedule"), note: nil),
                // VERIFY: EPA: anion exchange effective for arsenic(V) only.
                Treatment(name: String(localized: "Anion exchange"), effectiveness: String(localized: "High for one form of arsenic (arsenic V)"),
                          note: String(localized: "A water professional can tell you which form you have.")),
            ],
            retest: String(localized: "Every 2 years with a metals panel, and a few months after installing treatment to confirm it works."),
            sources: [epaPrimary, epaWells, ncWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "Can you tell if your water has arsenic by its taste or smell?"),
                             options: [String(localized: "Yes, it tastes metallic"), String(localized: "Yes, it smells like eggs"), String(localized: "No, only a test can tell")],
                             correctIndex: 2,
                             explanation: String(localized: "Arsenic has no taste, color or smell. A lab test is the only way to know.")),
                QuizQuestion(prompt: String(localized: "Where does most arsenic in NC wells come from?"),
                             options: [String(localized: "Natural bedrock"), String(localized: "Septic systems"), String(localized: "Old pipes")],
                             correctIndex: 0,
                             explanation: String(localized: "It comes from certain rock, especially the Carolina Slate Belt.")),
                QuizQuestion(prompt: String(localized: "Does boiling water remove arsenic?"),
                             options: [String(localized: "Yes"), String(localized: "No")],
                             correctIndex: 1,
                             explanation: String(localized: "Boiling does not remove arsenic. As water evaporates, the arsenic left behind becomes more concentrated.")),
            ]),

        LearnArticle(
            id: "lead", title: String(localized: "Lead"), contaminants: [.lead], symbol: "wrench.and.screwdriver",
            whereFrom: String(localized: "Lead usually comes from your plumbing, not the ground: old pipes, lead solder, and brass fittings or well parts. It varies from house to house."),
            // VERIFY: EPA basic information about lead in drinking water.
            shortTerm: String(localized: "Usually no short-term symptoms at levels found in tap water."),
            longTerm: String(localized: "In children, lead can cause learning and behavior problems and slowed growth. In adults it is linked to high blood pressure and kidney problems."),
            mostAtRisk: String(localized: "Infants, young children and pregnancy. EPA's health goal is zero because no level is known to be safe."),
            treatments: [
                // VERIFY: NSF/ANSI 53 certification claims for lead reduction.
                Treatment(name: String(localized: "Filter certified to NSF/ANSI 53 for lead"), effectiveness: String(localized: "High, if the filter is changed on schedule"), note: nil),
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58)"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Replace lead parts and fix corrosive water"), effectiveness: String(localized: "Fixes the source"),
                          note: String(localized: "Acidic water (low pH) dissolves lead from plumbing.")),
            ],
            retest: String(localized: "At least once, again after plumbing work, and if young children or a pregnant person live in the home."),
            sources: [SourceLink(title: String(localized: "EPA: Lead in drinking water"), url: WellResources.epaLead), epaWells, ncWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "Where does lead in well water usually come from?"),
                             options: [String(localized: "The bedrock"), String(localized: "Pipes, solder and fittings"), String(localized: "Rainwater")],
                             correctIndex: 1,
                             explanation: String(localized: "Lead usually dissolves from plumbing, so even a neighbor's test can't tell you about your home.")),
                QuizQuestion(prompt: String(localized: "What is EPA's health goal for lead in drinking water?"),
                             options: [String(localized: "Zero"), String(localized: "15 ppb"), String(localized: "50 ppb")],
                             correctIndex: 0,
                             explanation: String(localized: "The goal is zero because no level is known to be safe. 15 ppb is the action level for taking steps.")),
                QuizQuestion(prompt: String(localized: "Which water should you use for drinking and cooking if lead is a concern?"),
                             options: [String(localized: "Hot water"), String(localized: "Cold water")],
                             correctIndex: 1,
                             explanation: String(localized: "Hot water dissolves more lead from pipes. Use cold water.")),
            ]),

        LearnArticle(
            id: "nitrate", title: String(localized: "Nitrate and nitrite"), contaminants: [.nitrate, .nitrite], symbol: "leaf",
            whereFrom: String(localized: "Nitrate comes from fertilizer, manure and septic systems. It soaks into groundwater, especially in shallow wells near farms or septic fields."),
            // VERIFY: EPA / CDC: methemoglobinemia ("blue baby syndrome") in infants under 6 months.
            shortTerm: String(localized: "Babies under 6 months can get seriously ill within days. Nitrate keeps blood from carrying oxygen (\"blue baby syndrome\")."),
            longTerm: String(localized: "Researchers are still studying long-term effects in adults."),
            mostAtRisk: String(localized: "Babies under 6 months, especially if formula is mixed with well water, and pregnancy."),
            treatments: [
                // VERIFY: NSF/ANSI 58 nitrate reduction claims; EPA private well guidance.
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58)"), effectiveness: String(localized: "Removes most nitrate (often 80–95%)"), note: nil),
                Treatment(name: String(localized: "Anion exchange"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Distillation"), effectiveness: String(localized: "High"), note: nil),
            ],
            retest: String(localized: "Every year if a baby or pregnant person lives in the home, after flooding, and in spring when levels can rise."),
            sources: [epaPrimary, cdcWells, ncWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "Who is most at risk from nitrate?"),
                             options: [String(localized: "Teenagers"), String(localized: "Babies under 6 months"), String(localized: "Pets")],
                             correctIndex: 1,
                             explanation: String(localized: "Infants can get very sick, especially when formula is mixed with well water.")),
                QuizQuestion(prompt: String(localized: "Does boiling water remove nitrate?"),
                             options: [String(localized: "Yes"), String(localized: "No, it makes it stronger")],
                             correctIndex: 1,
                             explanation: String(localized: "Boiling evaporates water and concentrates nitrate.")),
                QuizQuestion(prompt: String(localized: "Which is a common source of nitrate?"),
                             options: [String(localized: "Septic systems and fertilizer"), String(localized: "Copper pipes"), String(localized: "Granite")],
                             correctIndex: 0,
                             explanation: String(localized: "Nitrate comes from fertilizer, manure and septic systems.")),
            ]),

        LearnArticle(
            id: "uranium", title: String(localized: "Uranium"), contaminants: [.uranium], symbol: "atom",
            // VERIFY: NC DHHS / USGS: uranium in NC wells associated with granitic bedrock in the Piedmont and mountains.
            whereFrom: String(localized: "Uranium comes from granite and similar bedrock found in parts of the Piedmont and mountains."),
            shortTerm: String(localized: "No short-term symptoms at levels found in wells."),
            // VERIFY: EPA Radionuclides Rule basis: kidney toxicity and increased cancer risk.
            longTerm: String(localized: "Over many years it can damage the kidneys and slightly raise cancer risk."),
            mostAtRisk: String(localized: "Anyone who drinks the water for many years."),
            treatments: [
                // VERIFY: EPA small-system compliance technology list for uranium.
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58)"), effectiveness: String(localized: "Removes most uranium (often 90% or more)"), note: nil),
                Treatment(name: String(localized: "Anion exchange"), effectiveness: String(localized: "High"), note: nil),
            ],
            retest: String(localized: "With your metals panel every 2 years, or sooner if a neighbor's well tested high."),
            sources: [epaPrimary, epaWells, ncWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "What does long-term uranium exposure mainly affect?"),
                             options: [String(localized: "The kidneys"), String(localized: "The teeth"), String(localized: "Eyesight")],
                             correctIndex: 0,
                             explanation: String(localized: "Uranium can harm the kidneys over many years.")),
                QuizQuestion(prompt: String(localized: "Where does uranium in NC wells come from?"),
                             options: [String(localized: "Fertilizer"), String(localized: "Granite and similar bedrock"), String(localized: "Plastic pipes")],
                             correctIndex: 1,
                             explanation: String(localized: "It occurs naturally in some bedrock.")),
                QuizQuestion(prompt: String(localized: "Which treatment removes uranium?"),
                             options: [String(localized: "A water softener alone"), String(localized: "Reverse osmosis"), String(localized: "Boiling")],
                             correctIndex: 1,
                             explanation: String(localized: "Reverse osmosis and anion exchange remove most uranium.")),
            ]),

        LearnArticle(
            id: "manganese", title: String(localized: "Manganese"), contaminants: [.manganese], symbol: "paintbrush",
            whereFrom: String(localized: "Manganese comes from rock and soil and is common in NC groundwater."),
            shortTerm: String(localized: "At common levels it mainly causes black stains and a bitter taste."),
            // VERIFY: EPA manganese health advisory (0.3 mg/L) and infant guidance.
            longTerm: String(localized: "At high levels over time it may affect the nervous system. EPA's health advisory is 300 ppb."),
            mostAtRisk: String(localized: "Infants, especially if formula is mixed with well water."),
            treatments: [
                // VERIFY: manufacturer / extension service guidance for greensand and softeners.
                Treatment(name: String(localized: "Oxidation/filtration (greensand)"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Water softener rated for manganese"), effectiveness: String(localized: "Moderate, at lower levels"), note: nil),
                Treatment(name: String(localized: "Reverse osmosis for drinking water"), effectiveness: String(localized: "High"), note: nil),
            ],
            retest: String(localized: "Every 2 years with a metals panel."),
            sources: [epaSecondary, epaWells, ncWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "What is a common sign of manganese?"),
                             options: [String(localized: "Black or brown stains"), String(localized: "Blue stains"), String(localized: "No sign at all, ever")],
                             correctIndex: 0,
                             explanation: String(localized: "Manganese can stain sinks and laundry black or brown.")),
                QuizQuestion(prompt: String(localized: "Who should avoid water with high manganese?"),
                             options: [String(localized: "Infants"), String(localized: "Nobody")],
                             correctIndex: 0,
                             explanation: String(localized: "High levels are a concern for infants.")),
                QuizQuestion(prompt: String(localized: "Is the 50 ppb manganese level a health limit?"),
                             options: [String(localized: "Yes"), String(localized: "No, it's for stains and taste")],
                             correctIndex: 1,
                             explanation: String(localized: "50 ppb is a cosmetic guideline. EPA's health advisory is 300 ppb.")),
            ]),

        LearnArticle(
            id: "iron", title: String(localized: "Iron"), contaminants: [.iron], symbol: "drop.halffull",
            whereFrom: String(localized: "Iron dissolves from rock and soil and is one of the most common well-water issues in North Carolina."),
            shortTerm: String(localized: "No health effects at typical levels; a metallic taste and orange stains."),
            longTerm: String(localized: "Not a health concern at typical well levels, but it can clog pipes and feed iron bacteria (slime)."),
            mostAtRisk: String(localized: "Not a health risk group issue; it affects plumbing and appliances."),
            treatments: [
                Treatment(name: String(localized: "Oxidation/filtration (iron filter)"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Water softener"), effectiveness: String(localized: "Works at low levels"), note: nil),
            ],
            retest: String(localized: "When staining or taste changes, or with your metals panel."),
            sources: [epaSecondary, epaWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "Is iron in well water usually a health risk?"),
                             options: [String(localized: "Yes"), String(localized: "No, mostly stains and taste")],
                             correctIndex: 1,
                             explanation: String(localized: "Iron's 300 ppb guideline is about staining and taste, not health.")),
                QuizQuestion(prompt: String(localized: "What color stains does iron leave?"),
                             options: [String(localized: "Orange-brown"), String(localized: "Blue-green")],
                             correctIndex: 0,
                             explanation: String(localized: "Iron leaves orange-brown stains. Blue-green usually means copper.")),
                QuizQuestion(prompt: String(localized: "Which treatment is common for iron?"),
                             options: [String(localized: "Iron filter (oxidation/filtration)"), String(localized: "UV light")],
                             correctIndex: 0,
                             explanation: String(localized: "UV kills germs but does not remove iron.")),
            ]),

        LearnArticle(
            id: "copper", title: String(localized: "Copper"), contaminants: [.copper], symbol: "pipe.and.drop",
            whereFrom: String(localized: "Copper usually comes from copper pipes that corrode, often because the water is acidic (low pH)."),
            // VERIFY: EPA copper: short-term gastrointestinal distress; long-term liver/kidney damage; Wilson's disease.
            shortTerm: String(localized: "High levels can cause nausea, vomiting and stomach cramps."),
            longTerm: String(localized: "Over years, high levels can harm the liver and kidneys."),
            mostAtRisk: String(localized: "Infants and people with Wilson's disease."),
            treatments: [
                Treatment(name: String(localized: "Acid-neutralizing filter"), effectiveness: String(localized: "Fixes the cause (corrosive water)"), note: nil),
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58)"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Run the tap before drinking"), effectiveness: String(localized: "Reduces levels in standing water"), note: nil),
            ],
            retest: String(localized: "If you see blue-green stains or after fixing corrosive water."),
            sources: [epaPrimary, epaWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "What often causes copper in tap water?"),
                             options: [String(localized: "Acidic water corroding pipes"), String(localized: "Fertilizer")],
                             correctIndex: 0,
                             explanation: String(localized: "Low-pH water dissolves copper from pipes.")),
                QuizQuestion(prompt: String(localized: "What sign can copper leave?"),
                             options: [String(localized: "Blue-green stains"), String(localized: "Black stains")],
                             correctIndex: 0,
                             explanation: String(localized: "Copper can leave blue-green stains on fixtures.")),
                QuizQuestion(prompt: String(localized: "What can you do right away to lower copper from standing water?"),
                             options: [String(localized: "Run the cold tap first"), String(localized: "Use hot water")],
                             correctIndex: 0,
                             explanation: String(localized: "Water that sat in pipes overnight picks up more copper.")),
            ]),

        LearnArticle(
            id: "fluoride", title: String(localized: "Fluoride"), contaminants: [.fluoride], symbol: "mouth",
            whereFrom: String(localized: "Fluoride occurs naturally in some rock. Some NC wells have more than others."),
            // VERIFY: EPA fluoride MCL 4.0 mg/L (skeletal fluorosis) and SMCL 2.0 mg/L (dental fluorosis).
            shortTerm: String(localized: "No short-term symptoms at levels found in wells."),
            longTerm: String(localized: "Above 2 mg/L, children's teeth can get white or brown spots. Above 4 mg/L for years, it can affect bones."),
            mostAtRisk: String(localized: "Children under 9, while their teeth are forming."),
            treatments: [
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58)"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Activated alumina"), effectiveness: String(localized: "High"), note: nil),
                Treatment(name: String(localized: "Distillation"), effectiveness: String(localized: "High"), note: nil),
            ],
            retest: String(localized: "Once, and again if young children will drink the water."),
            sources: [epaPrimary, epaSecondary],
            quiz: [
                QuizQuestion(prompt: String(localized: "Above what level can fluoride spot children's teeth?"),
                             options: [String(localized: "0.5 mg/L"), String(localized: "2 mg/L"), String(localized: "10 mg/L")],
                             correctIndex: 1,
                             explanation: String(localized: "Above 2 mg/L, children's teeth can develop spots.")),
                QuizQuestion(prompt: String(localized: "What is EPA's health limit for fluoride?"),
                             options: [String(localized: "4 mg/L"), String(localized: "1 mg/L")],
                             correctIndex: 0,
                             explanation: String(localized: "4 mg/L is the health limit; 2 mg/L is the cosmetic guideline.")),
                QuizQuestion(prompt: String(localized: "Who is most affected by high fluoride?"),
                             options: [String(localized: "Young children"), String(localized: "Older adults only")],
                             correctIndex: 0,
                             explanation: String(localized: "Children's developing teeth are most sensitive.")),
            ]),

        LearnArticle(
            id: "bacteria", title: String(localized: "Bacteria (coliform and E. coli)"), contaminants: [.totalColiform, .eColi], symbol: "allergens",
            whereFrom: String(localized: "Germs get in through cracked or missing well caps, poor seals, nearby septic systems or animal waste, and especially floodwater."),
            // VERIFY: CDC: diarrhea, cramps, nausea, vomiting from waterborne pathogens.
            shortTerm: String(localized: "Diarrhea, stomach cramps, nausea and vomiting, sometimes within a day or two. Some types of E. coli can cause serious illness."),
            longTerm: String(localized: "Repeated infections are the main concern; the fix is finding and closing the way germs get in."),
            mostAtRisk: String(localized: "Infants, older adults and people with weakened immune systems."),
            treatments: [
                // VERIFY: NC DHHS shock chlorination guidance.
                Treatment(name: String(localized: "Shock chlorination"), effectiveness: String(localized: "Kills germs in the well for now"),
                          note: String(localized: "Retest after the chlorine is flushed out. Germs come back if the source isn't fixed.")),
                // VERIFY: EPA / NSF/ANSI 55 Class A UV systems.
                Treatment(name: String(localized: "UV disinfection (NSF/ANSI 55)"), effectiveness: String(localized: "High, if the water is clear"), note: nil),
                Treatment(name: String(localized: "Repair the well cap, seal or casing"), effectiveness: String(localized: "Fixes the source"), note: nil),
            ],
            retest: String(localized: "Every year, after any flooding, after well repairs, and if the water's taste, smell or color changes."),
            sources: [cdcWells, epaWells, ncWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "How often should you test for bacteria?"),
                             options: [String(localized: "Every year and after flooding"), String(localized: "Once, when the well is drilled")],
                             correctIndex: 0,
                             explanation: String(localized: "Conditions change. Test every year and after any flooding.")),
                QuizQuestion(prompt: String(localized: "What does E. coli in your well mean?"),
                             options: [String(localized: "Human or animal waste is getting in"), String(localized: "Your pipes are rusty")],
                             correctIndex: 0,
                             explanation: String(localized: "E. coli comes from waste. Don't drink the water untreated.")),
                QuizQuestion(prompt: String(localized: "After shock chlorination, what should you do?"),
                             options: [String(localized: "Retest after the chlorine is flushed out"), String(localized: "Nothing; it's fixed for good")],
                             correctIndex: 0,
                             explanation: String(localized: "Retesting confirms the germs are gone. Fix the source so they don't come back.")),
            ]),

        LearnArticle(
            id: "ph", title: String(localized: "pH"), contaminants: [.pH], symbol: "gauge.with.dots.needle.50percent",
            // VERIFY: NC groundwater, especially Piedmont/mountain wells, is often slightly acidic (USGS / NC DEQ).
            whereFrom: String(localized: "pH depends on the rock and soil around your well. Many NC wells have slightly acidic water."),
            shortTerm: String(localized: "pH itself is not a health risk."),
            longTerm: String(localized: "Acidic water (below 6.5) corrodes pipes and can release lead and copper. High pH can taste bitter and leave scale."),
            mostAtRisk: String(localized: "Homes with copper pipes or older plumbing, because of corrosion."),
            treatments: [
                Treatment(name: String(localized: "Acid-neutralizing (calcite) filter"), effectiveness: String(localized: "Raises pH of mildly acidic water"), note: nil),
                Treatment(name: String(localized: "Soda ash injection"), effectiveness: String(localized: "For more acidic water"), note: nil),
            ],
            retest: String(localized: "With your regular panel, and test lead and copper if pH is low."),
            sources: [epaSecondary, epaWells],
            quiz: [
                QuizQuestion(prompt: String(localized: "What is the recommended pH range?"),
                             options: [String(localized: "6.5–8.5"), String(localized: "3–5"), String(localized: "9–12")],
                             correctIndex: 0,
                             explanation: String(localized: "EPA recommends 6.5 to 8.5.")),
                QuizQuestion(prompt: String(localized: "Why is acidic water a concern?"),
                             options: [String(localized: "It can release lead and copper from pipes"), String(localized: "It makes water hard")],
                             correctIndex: 0,
                             explanation: String(localized: "Low-pH water corrodes plumbing.")),
                QuizQuestion(prompt: String(localized: "Is there a health limit for pH?"),
                             options: [String(localized: "Yes"), String(localized: "No, it's a guideline")],
                             correctIndex: 1,
                             explanation: String(localized: "pH has a cosmetic guideline, not a health limit.")),
            ]),

        LearnArticle(
            id: "hardness", title: String(localized: "Hardness"), contaminants: [.hardness], symbol: "sparkles",
            // VERIFY: USGS: harder groundwater is more common in limestone areas of the NC Coastal Plain.
            whereFrom: String(localized: "Hardness is dissolved calcium and magnesium from rock. It tends to be higher where groundwater flows through limestone, like parts of the Coastal Plain."),
            shortTerm: String(localized: "No health effects."),
            longTerm: String(localized: "No health effects. It leaves scale in kettles and water heaters and makes soap lather less."),
            mostAtRisk: String(localized: "Not a health issue; it affects appliances and cleaning."),
            treatments: [
                Treatment(name: String(localized: "Water softener (ion exchange)"), effectiveness: String(localized: "High"), note: nil),
            ],
            retest: String(localized: "Only if you're deciding on a softener or notice more scale."),
            sources: [epaSecondary],
            quiz: [
                QuizQuestion(prompt: String(localized: "Is hard water a health risk?"),
                             options: [String(localized: "Yes"), String(localized: "No")],
                             correctIndex: 1,
                             explanation: String(localized: "Hardness affects scale and soap, not health.")),
                QuizQuestion(prompt: String(localized: "What causes hardness?"),
                             options: [String(localized: "Calcium and magnesium"), String(localized: "Bacteria")],
                             correctIndex: 0,
                             explanation: String(localized: "Dissolved calcium and magnesium make water hard.")),
                QuizQuestion(prompt: String(localized: "What treats hard water?"),
                             options: [String(localized: "A water softener"), String(localized: "Shock chlorination")],
                             correctIndex: 0,
                             explanation: String(localized: "Softeners swap calcium and magnesium for sodium or potassium.")),
            ]),

        LearnArticle(
            id: "pfas", title: String(localized: "PFAS (\"forever chemicals\")"), contaminants: [.pfoa, .pfos, .genx], symbol: "flask",
            // VERIFY: NC DEQ: PFAS including GenX from the Chemours Fayetteville Works plant has been found in private wells
            // in the lower Cape Fear area; PFAS also come from firefighting foam, landfills and some biosolids.
            whereFrom: String(localized: "PFAS come from industry and some products, like firefighting foam. In North Carolina, PFAS including GenX from a chemical plant near Fayetteville have been found in private wells in the lower Cape Fear area."),
            shortTerm: String(localized: "No short-term symptoms at levels found in wells."),
            // VERIFY: EPA PFAS rule health basis: some cancers, liver, immune and developmental effects, and cholesterol changes.
            longTerm: String(localized: "PFAS build up in the body. Long-term exposure is linked to some cancers, and to effects on the liver, immune system, cholesterol and children's growth."),
            mostAtRisk: String(localized: "Pregnancy, infants and young children."),
            treatments: [
                // VERIFY: EPA / NSF: RO (NSF/ANSI 58) and certified carbon (NSF/ANSI 53) filters reduce PFOA/PFOS.
                Treatment(name: String(localized: "Reverse osmosis (NSF/ANSI 58, certified for PFAS)"), effectiveness: String(localized: "Removes most PFAS (often 90% or more)"), note: nil),
                Treatment(name: String(localized: "Granular activated carbon (NSF/ANSI 53, certified for PFAS)"), effectiveness: String(localized: "High, when the filter is changed on schedule"), note: nil),
                Treatment(name: String(localized: "Anion exchange"), effectiveness: String(localized: "High"), note: nil),
            ],
            retest: String(localized: "If you live in an affected area, and after installing treatment to confirm it works."),
            sources: [epaPrimary, SourceLink(title: String(localized: "NCDEQ: PFAS Treatment System Assistance Program"), url: WellResources.ncdeqPFAS)],
            quiz: [
                QuizQuestion(prompt: String(localized: "Why are PFAS called \"forever chemicals\"?"),
                             options: [String(localized: "They break down very slowly and build up in the body"), String(localized: "They make water last longer")],
                             correctIndex: 0,
                             explanation: String(localized: "PFAS barely break down in the environment or the body.")),
                QuizQuestion(prompt: String(localized: "Does boiling water remove PFAS?"),
                             options: [String(localized: "Yes"), String(localized: "No")],
                             correctIndex: 1,
                             explanation: String(localized: "Boiling does not remove PFAS. Use a filter certified for PFAS reduction.")),
                QuizQuestion(prompt: String(localized: "Which filter type can reduce PFAS?"),
                             options: [String(localized: "Reverse osmosis certified for PFAS"), String(localized: "A sediment filter")],
                             correctIndex: 0,
                             explanation: String(localized: "Look for reverse osmosis or carbon filters certified for PFAS reduction.")),
            ]),

        LearnArticle(
            id: "radon", title: String(localized: "Radon in water"), contaminants: [.radon], symbol: "wind",
            whereFrom: String(localized: "Radon is a radioactive gas made as uranium in bedrock breaks down. It dissolves in groundwater, especially in granite areas."),
            shortTerm: String(localized: "No short-term symptoms."),
            // VERIFY: EPA radon: main risk is lung cancer from inhaling radon released from water; small stomach-cancer risk from drinking.
            longTerm: String(localized: "Radon escapes into the air when you shower, wash dishes or do laundry. Breathing it over years raises lung cancer risk. Drinking it adds a smaller risk."),
            mostAtRisk: String(localized: "Everyone in the home, especially people who smoke."),
            treatments: [
                // VERIFY: EPA: aeration removes up to ~99%; GAC is effective but the filter can become radioactive.
                Treatment(name: String(localized: "Aeration system"), effectiveness: String(localized: "Very high (up to about 99%)"), note: nil),
                Treatment(name: String(localized: "Granular activated carbon (GAC)"), effectiveness: String(localized: "High"),
                          note: String(localized: "Used filters can become radioactive; ask a professional.")),
            ],
            retest: String(localized: "Once, and again if you install treatment. Also test the air in your home."),
            sources: [SourceLink(title: String(localized: "EPA: Radon"), url: WellResources.epaRadon),
                      SourceLink(title: String(localized: "NC Radon Program"), url: WellResources.ncRadon)],
            quiz: [
                QuizQuestion(prompt: String(localized: "How does radon in water mostly harm health?"),
                             options: [String(localized: "By being breathed in after it escapes into the air"), String(localized: "By staining skin")],
                             correctIndex: 0,
                             explanation: String(localized: "Radon released from water during showers and washing is breathed in.")),
                QuizQuestion(prompt: String(localized: "Is there a final federal limit for radon in well water?"),
                             options: [String(localized: "Yes"), String(localized: "No, only a proposed limit")],
                             correctIndex: 1,
                             explanation: String(localized: "EPA proposed limits in 1999 but never finalized them.")),
                QuizQuestion(prompt: String(localized: "Which treatment removes the most radon?"),
                             options: [String(localized: "Aeration"), String(localized: "A sediment filter")],
                             correctIndex: 0,
                             explanation: String(localized: "Aeration systems remove nearly all radon from water.")),
            ]),
    ]
    // swiftlint:enable function_body_length
}
