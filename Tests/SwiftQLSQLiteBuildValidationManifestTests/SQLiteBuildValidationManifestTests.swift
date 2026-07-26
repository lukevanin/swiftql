import Foundation
import SwiftQLCore
import SwiftQLSQLiteCombinatorialSupport
import SwiftQLSQLiteConformanceFixtures
import XCTest
@testable import SwiftQLSQLiteBuildValidationManifest


final class SQLiteBuildValidationManifestTests: XCTestCase {
    typealias Support = SQLiteBuildValidationManifestTestSupport

    // MARK: - Descriptor projection (Done-When #1)

    func testDescriptorProjectionPreservesStableIdentityPhysicalSlotsAndCodec() throws {
        let descriptorCodec = Support.descriptorCodec()
        let descriptor = try Support.mixedBindingDescriptor(codec: descriptorCodec)

        let projected = try SQLiteBuildValidationQueryEntry(
            id: "projection.mixed-bindings",
            descriptor: descriptor,
            declaredAliases: ["indexed_value", "token"],
            conformanceFeatureIDs: ["binding.named", "binding.indexed"],
            conformanceCaseIDs: [
                "c191.v1.select.j-inner.w-named-binding",
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ],
            northwindAnchorCaseIDs: ["northwind.cte.order-subtotals"],
            requiredCapabilities: ["function:JSON_VALID", "function:ABS"]
        )

        XCTAssertEqual(
            projected.definitionIdentity,
            "tests/build-validation/manifest-projection@1"
        )
        XCTAssertEqual(projected.descriptorIdentity, descriptor.identity.description)
        XCTAssertEqual(projected.sql, "SELECT ?5 AS indexed_value, :token AS token")
        XCTAssertEqual(projected.parameters.map(\.logicalIndex), [0, 1])
        XCTAssertEqual(projected.parameters.map(\.physicalIndex), [5, 6])
        XCTAssertEqual(projected.expectedPhysicalParameterCount, 6)
        XCTAssertEqual(projected.parameters[0].expectedSQLiteSpelling, "?5")
        XCTAssertEqual(projected.parameters[1].expectedSQLiteSpelling, ":token")
        XCTAssertNil(projected.parameters[0].codec)
        XCTAssertEqual(
            projected.parameters[1].codec,
            SQLiteBuildValidationCodecReference(descriptorCodec)
        )
        XCTAssertEqual(
            projected.results.map(\.declaredAlias),
            ["indexed_value", "token"]
        )
        XCTAssertEqual(
            projected.results[1].codec,
            SQLiteBuildValidationCodecReference(descriptorCodec)
        )
        XCTAssertEqual(
            projected.requiredCodecIdentifiers,
            [SQLiteBuildValidationCodecReference(descriptorCodec).stableIdentifier]
        )
        // Reordered/duplicated set-like inputs canonicalize identically.
        XCTAssertEqual(projected.conformanceFeatureIDs, ["binding.indexed", "binding.named"])
        XCTAssertEqual(projected.conformanceCaseIDs, [
            "c191.v1.northwind.cte-order-subtotals",
            "c191.v1.select.j-inner.w-named-binding",
        ])
        XCTAssertEqual(
            projected.requiredCapabilities.map(\.id),
            ["function:ABS", "function:JSON_VALID"]
        )
    }

    func testDescriptorProjectionUsesSQLTokenOrderForPhysicalSlots() throws {
        let descriptor = try Support.mixedBindingDescriptor(
            codec: Support.descriptorCodec(),
            sql: "SELECT :token AS indexed_value, ?5 AS token"
        )
        let projected = try SQLiteBuildValidationQueryEntry(
            id: "projection.sql-token-order",
            descriptor: descriptor
        )

        XCTAssertEqual(projected.parameters.map(\.logicalIndex), [0, 1])
        XCTAssertEqual(projected.parameters.map(\.physicalIndex), [5, 1])
        XCTAssertEqual(
            projected.parameters.map(\.expectedSQLiteSpelling),
            ["?5", ":token"]
        )
        XCTAssertEqual(projected.expectedPhysicalParameterCount, 5)
    }

    func testDescriptorProjectionRejectsAliasCountMismatch() throws {
        let descriptor = try Support.mixedBindingDescriptor(codec: Support.descriptorCodec())
        XCTAssertThrowsError(
            try SQLiteBuildValidationQueryEntry(
                id: "projection.alias-mismatch",
                descriptor: descriptor,
                declaredAliases: ["only-one"]
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .resultAliasCountMismatch(
                    queryID: "projection.alias-mismatch",
                    expected: 2,
                    actual: 1
                )
            )
        }
    }

    func testDescriptorProjectionRejectsNamedParameterAbsentFromSQL() throws {
        let descriptor = try Support.mixedBindingDescriptor(
            codec: Support.descriptorCodec(),
            sql: "SELECT ?5 AS indexed_value, 1 AS token"
        )
        XCTAssertThrowsError(
            try SQLiteBuildValidationQueryEntry(
                id: "projection.missing-named-parameter",
                descriptor: descriptor
            )
        ) { error in
            guard case .invalidQuery(let queryID, let reason) =
                    error as? SQLiteBuildValidationManifestError else {
                return XCTFail("Expected invalid query, received \(error)")
            }
            XCTAssertEqual(queryID, "projection.missing-named-parameter")
            XCTAssertTrue(reason.contains(":token"))
        }
    }

    func testDescriptorProjectionRejectsIndexedParameterAbsentFromSQL() throws {
        let descriptor = try Support.mixedBindingDescriptor(
            codec: Support.descriptorCodec(),
            sql: "SELECT 1 AS indexed_value, :token AS token"
        )
        XCTAssertThrowsError(
            try SQLiteBuildValidationQueryEntry(
                id: "projection.missing-indexed-parameter",
                descriptor: descriptor
            )
        ) { error in
            guard case .invalidQuery(let queryID, let reason) =
                    error as? SQLiteBuildValidationManifestError else {
                return XCTFail("Expected invalid query, received \(error)")
            }
            XCTAssertEqual(queryID, "projection.missing-indexed-parameter")
            XCTAssertTrue(reason.contains("?5"))
        }
    }

    // MARK: - Determinism (Done-When #2)

    func testManifestCanonicalizesOrderingAndIsByteIdenticalAcrossReorderingAndRepeatedRuns() throws {
        let later = Support.query(
            id: "z-later",
            conformanceFeatureIDs: ["syntax.select.core", "binding.named", "syntax.select.core"],
            conformanceCaseIDs: [
                "c191.v1.select.j-inner.w-named-binding",
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ],
            northwindAnchorCaseIDs: ["northwind.cte.order-subtotals", "northwind.cte.order-subtotals"],
            requiredCapabilities: ["function:FLOOR", "function:ABS", "function:FLOOR"]
        )
        let earlier = Support.query(id: "a-earlier")
        let manifest = Support.manifest(queries: [later, earlier])
        let reordered = Support.manifest(queries: [earlier, later])

        let validated = try manifest.validating()
        XCTAssertEqual(validated.queries.map(\.id), ["a-earlier", "z-later"])
        XCTAssertEqual(
            validated.queries[1].conformanceCaseIDs,
            [
                "c191.v1.northwind.cte-order-subtotals",
                "c191.v1.select.j-inner.w-named-binding",
            ]
        )
        XCTAssertEqual(
            validated.queries[1].conformanceFeatureIDs,
            ["binding.named", "syntax.select.core"]
        )
        XCTAssertEqual(
            validated.queries[1].requiredCapabilities.map(\.id),
            ["function:ABS", "function:FLOOR"]
        )

        let data = try manifest.canonicalJSONData()
        let reorderedData = try reordered.canonicalJSONData()
        let repeatedData = try manifest.canonicalJSONData()

        XCTAssertEqual(data, reorderedData)
        XCTAssertEqual(data, repeatedData)
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertNotEqual(data.dropLast().last, 0x0A)
        XCTAssertEqual(try SQLiteBuildValidationManifest.decode(data), validated)
        XCTAssertEqual(
            try SQLiteBuildValidationManifest.decode(data).canonicalJSONData(),
            data
        )

        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let earlierRange = try XCTUnwrap(json.range(of: "a-earlier"))
        let laterRange = try XCTUnwrap(json.range(of: "z-later"))
        XCTAssertLessThan(earlierRange.lowerBound, laterRange.lowerBound)
        XCTAssertTrue(json.contains("\"format_version\" : 1"))

        // No nondeterministic evidence anywhere in the schema.
        for excluded in ["timestamp", "hostname", "host_name", "process_id", "elapsed", "duration"] {
            XCTAssertFalse(json.lowercased().contains(excluded), excluded)
        }
    }

    // MARK: - Fail-closed structural validation (Done-When #3a)

    func testManifestRejectsUnsupportedFormatVersion() {
        let manifest = SQLiteBuildValidationManifest(
            formatVersion: SQLiteBuildValidationManifestFormatVersion(rawValue: 2),
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: Support.schemaSnapshot(),
            queries: [Support.query()]
        )
        XCTAssertThrowsError(try manifest.validating()) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unsupportedFormatVersion(SQLiteBuildValidationManifestFormatVersion(rawValue: 2))
            )
        }
    }

    func testManifestRejectsInvalidSchemaSnapshotAndDuplicateQueryIDs() throws {
        XCTAssertThrowsError(
            try Support.manifest(
                schemaSnapshot: Support.schemaSnapshot(
                    databaseSHA256: String(repeating: "g", count: 64)
                ),
                queries: [Support.query()]
            ).validating()
        ) { error in
            guard case .invalidManifest(let reason) =
                error as? SQLiteBuildValidationManifestError else {
                return XCTFail("Expected invalid manifest, received \(error)")
            }
            XCTAssertTrue(reason.contains("SHA-256"))
        }

        let duplicate = Support.query(id: "duplicate")
        XCTAssertThrowsError(
            try Support.manifest(queries: [duplicate, duplicate]).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .duplicateQueryID("duplicate")
            )
        }
    }

    /// Reports the lexicographically smallest duplicated id rather than an
    /// arbitrary one, so the diagnostic does not vary with Dictionary's
    /// process-randomized iteration order across multiple duplicate groups.
    func testManifestReportsDeterministicDuplicateQueryIDAcrossMultipleGroups() {
        let manifest = Support.manifest(queries: [
            Support.query(id: "zebra"),
            Support.query(id: "zebra"),
            Support.query(id: "apple"),
            Support.query(id: "apple"),
        ])
        XCTAssertThrowsError(try manifest.validating()) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .duplicateQueryID("apple")
            )
        }
    }

    func testManifestRejectsParameterGapsPhysicalCollisionsAndMalformedKeys() {
        let logicalGap = Support.parameter(logicalIndex: 1)
        assertInvalidQuery(
            Support.query(parameters: [logicalGap]),
            contains: "contiguous"
        )

        let first = Support.parameter(
            logicalIndex: 0, physicalIndex: 1, identity: "parameter/first", keyName: "first"
        )
        let collision = Support.parameter(
            logicalIndex: 1, physicalIndex: 1, identity: "parameter/second", keyName: "second"
        )
        assertInvalidQuery(
            Support.query(parameters: [first, collision]),
            contains: "must not share"
        )

        let malformedIndexed = Support.parameter(
            logicalIndex: 0,
            physicalIndex: 3,
            keyKind: .indexed,
            keyName: nil,
            keyIndex: 0
        )
        assertInvalidQuery(
            Support.query(parameters: [malformedIndexed]),
            contains: "matching physical_index"
        )
    }

    func testManifestRejectsIncompleteCodecMetadata() {
        let incompleteCodec = Support.codec(keyID: "")
        assertInvalidQuery(
            Support.query(results: [Support.result(codec: incompleteCodec)]),
            contains: "codec metadata"
        )
    }

    private func assertInvalidQuery(
        _ query: SQLiteBuildValidationQueryEntry,
        contains expectedReason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try Support.manifest(queries: [query]).validating(),
            file: file,
            line: line
        ) { error in
            guard case .invalidQuery(_, let reason) =
                error as? SQLiteBuildValidationManifestError else {
                return XCTFail(
                    "Expected invalid query, received \(error)", file: file, line: line
                )
            }
            XCTAssertTrue(
                reason.contains(expectedReason),
                "Expected '\(reason)' to contain '\(expectedReason)'",
                file: file, line: line
            )
        }
    }

    // MARK: - Reference resolution against real #190/#191/#254 registries (Done-When #3b)

    func testManifestResolvesRepresentativeReferencesAgainstCanonicalRegistries() throws {
        let inventory = try SQLiteConformanceInventory.load()
        let combinatorial = try SQLiteCombinatorialSuite.makeManifest()
        let registry = SQLiteBuildValidationStaticReferenceRegistry(
            conformanceFeatureIDs: Set(inventory.features.map(\.id)),
            conformanceCaseIDs: Set(combinatorial.cases.map(\.id)),
            northwindAnchorCaseIDs: Set(
                SQLiteNorthwindConformanceCaseID.allCases.map(\.rawValue)
            )
        )

        let realFeatureID = try XCTUnwrap(inventory.features.first?.id)
        let realCaseID = try XCTUnwrap(combinatorial.cases.first?.id)
        let realAnchorID = try XCTUnwrap(SQLiteNorthwindConformanceCaseID.allCases.first?.rawValue)

        let manifest = Support.manifest(queries: [
            Support.query(
                id: "real-references",
                conformanceFeatureIDs: [realFeatureID],
                conformanceCaseIDs: [realCaseID],
                northwindAnchorCaseIDs: [realAnchorID]
            ),
        ])

        XCTAssertNoThrow(try manifest.validating(against: registry))
    }

    func testManifestFailsClosedOnUnresolvedFeatureCaseAndAnchorReferences() {
        let registry = SQLiteBuildValidationStaticReferenceRegistry(
            conformanceFeatureIDs: ["syntax.select.core"],
            conformanceCaseIDs: ["c191.v1.select.j-inner.w-named-binding"],
            northwindAnchorCaseIDs: ["northwind.cte.order-subtotals"]
        )

        let badFeature = Support.manifest(queries: [
            Support.query(id: "q", conformanceFeatureIDs: ["not.a.real.feature"]),
        ])
        XCTAssertThrowsError(try badFeature.validating(against: registry)) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unresolvedReference(
                    queryID: "q", kind: .conformanceFeature, id: "not.a.real.feature"
                )
            )
        }

        let badCase = Support.manifest(queries: [
            Support.query(id: "q", conformanceCaseIDs: ["c999.not-real"]),
        ])
        XCTAssertThrowsError(try badCase.validating(against: registry)) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unresolvedReference(queryID: "q", kind: .conformanceCase, id: "c999.not-real")
            )
        }

        let badAnchor = Support.manifest(queries: [
            Support.query(id: "q", northwindAnchorCaseIDs: ["northwind.not-real"]),
        ])
        XCTAssertThrowsError(try badAnchor.validating(against: registry)) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unresolvedReference(queryID: "q", kind: .northwindAnchor, id: "northwind.not-real")
            )
        }
    }

    // MARK: - Unknown schema (format) versions fail closed on decode

    func testDecodeFailsClosedOnUnknownFormatVersion() throws {
        let manifest = SQLiteBuildValidationManifest(
            formatVersion: SQLiteBuildValidationManifestFormatVersion(rawValue: 2),
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: Support.schemaSnapshot(),
            queries: [Support.query()]
        )
        let data = try JSONEncoder().encode(manifest)
        XCTAssertThrowsError(try SQLiteBuildValidationManifest.decode(data)) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unsupportedFormatVersion(SQLiteBuildValidationManifestFormatVersion(rawValue: 2))
            )
        }
    }
}
