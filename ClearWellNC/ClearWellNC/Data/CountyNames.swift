//
//  CountyNames.swift
//  ClearWellNC
//

import Foundation

/// NC county FIPS codes are odd numbers assigned alphabetically (Alamance = 001 … Yancey = 199).
nonisolated enum CountyNames {
    static let all = [
        "Alamance", "Alexander", "Alleghany", "Anson", "Ashe", "Avery", "Beaufort", "Bertie", "Bladen",
        "Brunswick", "Buncombe", "Burke", "Cabarrus", "Caldwell", "Camden", "Carteret", "Caswell",
        "Catawba", "Chatham", "Cherokee", "Chowan", "Clay", "Cleveland", "Columbus", "Craven", "Cumberland",
        "Currituck", "Dare", "Davidson", "Davie", "Duplin", "Durham", "Edgecombe", "Forsyth", "Franklin",
        "Gaston", "Gates", "Graham", "Granville", "Greene", "Guilford", "Halifax", "Harnett", "Haywood",
        "Henderson", "Hertford", "Hoke", "Hyde", "Iredell", "Jackson", "Johnston", "Jones", "Lee", "Lenoir",
        "Lincoln", "Macon", "Madison", "Martin", "McDowell", "Mecklenburg", "Mitchell", "Montgomery",
        "Moore", "Nash", "New Hanover", "Northampton", "Onslow", "Orange", "Pamlico", "Pasquotank",
        "Pender", "Perquimans", "Person", "Pitt", "Polk", "Randolph", "Richmond", "Robeson", "Rockingham",
        "Rowan", "Rutherford", "Sampson", "Scotland", "Stanly", "Stokes", "Surry", "Swain", "Transylvania",
        "Tyrrell", "Union", "Vance", "Wake", "Warren", "Washington", "Watauga", "Wayne", "Wilkes", "Wilson",
        "Yadkin", "Yancey",
    ]

    /// Three-digit county FIPS (e.g. "183") → county name (e.g. "Wake"). Nil for even or out-of-range codes.
    static func name(forFIPS fips: String) -> String? {
        guard let code = Int(fips), code > 0, code % 2 == 1 else { return nil }
        let index = (code - 1) / 2
        return all.indices.contains(index) ? all[index] : nil
    }
}
