//
//  ReferenceDataTests.swift
//  AquaShieldTests
//
//  The JSON reference tables load, are versioned, and match the compiled fallback values, so moving
//  data to JSON changes nothing about scoring or interpretation.
//

import XCTest
@testable import AquaShield

final class ReferenceDataTests: XCTestCase {

    private func describe(_ limit: RegulatoryLimit) -> String {
        switch limit {
        case .maximum(let v): "max \(v)"
        case .range(let low, let high): "range \(low)-\(high)"
        case .mustBeAbsent: "absent"
        case .none: "none"
        }
    }

    func testLimitsJSONMatchesCompiledValues() {
        XCTAssertGreaterThanOrEqual(ReferenceLimits.version, 1)
        for id in ContaminantID.allCases {
            let record = ReferenceLimits.table[id]
            XCTAssertNotNil(record, "\(id) missing from ContaminantLimits.json")
            let compiled = ContaminantInfo.compiledInfo(for: id)
            let live = ContaminantInfo.info(for: id)
            XCTAssertEqual(describe(live.limit), describe(compiled.limit), "\(id)")
            XCTAssertEqual(live.healthAdvisory?.value, compiled.healthAdvisory?.value, "\(id)")
            XCTAssertTrue(record?.source.needsVerification ?? false)
        }
    }

    func testStandardsJSONMatchesCompiledValues() {
        for standard in CertificationStandard.allCases {
            XCTAssertNotNil(ReferenceStandards.table[standard], "\(standard) missing")
            XCTAssertEqual(standard.allowedTargets, standard.compiledAllowedTargets, "\(standard)")
        }
        XCTAssertEqual(CertificationStandard.nsf177.allowedTargets, [.freeChlorine])
    }

    func testVerificationRegisterHasEveryNote() {
        XCTAssertGreaterThanOrEqual(VerificationRegister.entries.count, 60)
        XCTAssertTrue(VerificationRegister.entries.allSatisfy(\.needsVerification))
        XCTAssertEqual(Set(VerificationRegister.entries.map(\.id)).count, VerificationRegister.entries.count)
    }

    @MainActor
    func testSampleFiltersLoadThroughReferenceStore() {
        let store = ReferenceDataStore()
        XCTAssertGreaterThanOrEqual(store.filterCatalogVersion, 1)
        XCTAssertFalse(store.sampleFilters.isEmpty)
        XCTAssertNotNil(store.product(id: "sample-pitcher-a", custom: []))
        XCTAssertNil(store.product(id: "", custom: []))
    }
}
