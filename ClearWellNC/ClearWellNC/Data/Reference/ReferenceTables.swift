//
//  ReferenceTables.swift
//  ClearWellNC
//
//  Versioned JSON reference tables: contaminant limits, certification standards and the verification
//  register (every value or fact that still needs a person to check it against its source).
//

import Foundation

nonisolated struct LimitValue: Codable, Sendable, Equatable {
    let kind: String
    var value: Double?
    var low: Double?
    var high: Double?

    var regulatory: RegulatoryLimit? {
        switch kind {
        case "maximum": value.map(RegulatoryLimit.maximum)
        case "range": low.flatMap { low in high.map { .range(low: low, high: $0) } }
        case "mustBeAbsent": .mustBeAbsent
        case "none": RegulatoryLimit.none
        default: nil
        }
    }
}

nonisolated struct ContaminantLimitRecord: Codable, Sendable {
    let id: String
    let limit: LimitValue
    var healthAdvisory: Double?
    let source: SourceRef
    /// VerificationRegister entry with the original note.
    var register: String?
}

nonisolated struct StandardRecord: Codable, Sendable {
    let id: String
    let allowedTargets: Set<ClaimTarget>
    let source: SourceRef
}

nonisolated struct VerificationEntry: Codable, Sendable, Identifiable {
    let id: String
    let file: String
    let note: String
    let sourceName: String
    let sourceURL: URL?
    let lastVerified: Date?
    let needsVerification: Bool
}

nonisolated struct VersionedReference<T: Codable & Sendable>: Codable, Sendable {
    let version: Int
    let limits: T?
    let standards: T?
    let entries: T?
}

nonisolated enum ReferenceLimits {
    static let file = ReferenceData.load("ContaminantLimits", as: VersionedReference<[ContaminantLimitRecord]>.self)
    static let version = file?.version ?? 0
    static let table: [ContaminantID: ContaminantLimitRecord] = {
        var table: [ContaminantID: ContaminantLimitRecord] = [:]
        for record in file?.limits ?? [] {
            if let id = ContaminantID(rawValue: record.id) { table[id] = record }
        }
        return table
    }()
}

nonisolated enum ReferenceStandards {
    static let file = ReferenceData.load("CertificationStandards", as: VersionedReference<[StandardRecord]>.self)
    static let table: [CertificationStandard: StandardRecord] = {
        var table: [CertificationStandard: StandardRecord] = [:]
        for record in file?.standards ?? [] {
            if let standard = CertificationStandard(rawValue: record.id) { table[standard] = record }
        }
        return table
    }()
}

nonisolated enum VerificationRegister {
    static let entries: [VerificationEntry] =
        ReferenceData.load("VerificationRegister", as: VersionedReference<[VerificationEntry]>.self)?.entries ?? []
}
