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
        XCTAssertTrue(json.contains("\"format_version\" : 2"))

        // No nondeterministic evidence anywhere in the schema.
        for excluded in ["timestamp", "hostname", "host_name", "process_id", "elapsed", "duration"] {
            XCTAssertFalse(json.lowercased().contains(excluded), excluded)
        }
    }

    // MARK: - Fail-closed structural validation (Done-When #3a)

    func testManifestRejectsUnsupportedFormatVersion() {
        let manifest = SQLiteBuildValidationManifest(
            formatVersion: SQLiteBuildValidationManifestFormatVersion(rawValue: 3),
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: Support.schemaSnapshot(),
            queries: [Support.query()]
        )
        XCTAssertThrowsError(try manifest.validating()) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unsupportedFormatVersion(SQLiteBuildValidationManifestFormatVersion(rawValue: 3))
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

    /// `Codable`'s synthesized decoder populates stored properties directly
    /// and never routes through the canonicalizing memberwise initializer,
    /// so JSON whose `parameters`/`results` arrays are not already in
    /// canonical order (but is otherwise a perfectly valid manifest) must
    /// still decode and validate successfully rather than spuriously
    /// failing the contiguity checks in `validateStructure`.
    func testDecodeAcceptsAndNormalizesOutOfOrderJSON() throws {
        let first = Support.parameter(
            logicalIndex: 0, physicalIndex: 1, identity: "parameter/first", keyName: "first"
        )
        let second = Support.parameter(
            logicalIndex: 1, physicalIndex: 2, identity: "parameter/second", keyName: "second"
        )
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT :first AS first, :second AS second",
                parameters: [first, second],
                results: [
                    Support.result(index: 0, identity: "result/first", declaredAlias: "first"),
                    Support.result(index: 1, identity: "result/second", declaredAlias: "second"),
                ]
            ),
        ])
        let canonicalData = try manifest.canonicalJSONData()

        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonicalData) as? [String: Any]
        )
        var queries = try XCTUnwrap(json["queries"] as? [[String: Any]])
        var query = queries[0]
        query["parameters"] = Array(
            (query["parameters"] as? [Any] ?? []).reversed()
        )
        query["results"] = Array(
            (query["results"] as? [Any] ?? []).reversed()
        )
        queries[0] = query
        json["queries"] = queries
        let shuffledData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try SQLiteBuildValidationManifest.decode(shuffledData)
        XCTAssertEqual(decoded, try manifest.validating())
        XCTAssertEqual(try decoded.canonicalJSONData(), canonicalData)
    }

    func testManifestValidatingSucceedsWhenParametersMatchSQLPlaceholders() throws {
        let parameter = Support.parameter(
            logicalIndex: 0, physicalIndex: 1, identity: "parameter/first", keyName: "first"
        )
        let manifest = Support.manifest(queries: [
            Support.query(sql: "SELECT :first AS first", parameters: [parameter]),
        ])
        XCTAssertNoThrow(try manifest.validating())
    }

    /// `validateStructure` cross-checks declared parameters against the raw
    /// SQL, independent of the `init(id:descriptor:...)` projection path —
    /// this is the fail-closed contract for a manifest decoded straight from
    /// externally authored/edited JSON.
    func testManifestRejectsParametersInconsistentWithSQLPlaceholders() {
        // Declared parameter has no corresponding placeholder in the SQL.
        assertInvalidQuery(
            Support.query(sql: "SELECT 1", parameters: [Support.parameter()]),
            contains: "do not match the placeholders found in SQL"
        )
        // SQL contains a placeholder the manifest never declares.
        assertInvalidQuery(
            Support.query(sql: "SELECT :first"),
            contains: "do not match the placeholders found in SQL"
        )
        // The declared spelling disagrees with the actual placeholder at
        // that physical index.
        let wrongSpelling = Support.parameter(
            logicalIndex: 0, physicalIndex: 1, identity: "parameter/first", keyName: "wrong"
        )
        assertInvalidQuery(
            Support.query(sql: "SELECT :first", parameters: [wrongSpelling]),
            contains: "does not match its placeholder occurrence"
        )
    }

    func testManifestRejectsEmptySQL() {
        assertInvalidQuery(
            Support.query(sql: ""),
            contains: "SQL must not be empty"
        )
    }

    func testManifestRejectsUnrecognizedCardinalityRawValue() {
        let manifest = Support.manifest(queries: [
            SQLiteBuildValidationQueryEntry(
                id: "bad-cardinality",
                definitionIdentity: "tests/bad-cardinality@1",
                descriptorIdentity: "swiftql-query-v1-deadbeef",
                sql: "SELECT 1",
                dialectIdentifier: XLSQLiteDialect.identity.rawValue,
                cardinality: 99,
                results: [Support.result()]
            ),
        ])
        XCTAssertThrowsError(try manifest.validating()) { error in
            guard case .invalidQuery(let queryID, let reason) =
                error as? SQLiteBuildValidationManifestError else {
                return XCTFail("Expected invalid query, received \(error)")
            }
            XCTAssertEqual(queryID, "bad-cardinality")
            XCTAssertTrue(reason.contains("cardinality"))
        }
    }

    func testManifestRejectsCardinalityResultCountMismatches() {
        let commandWithResults = Support.manifest(queries: [
            SQLiteBuildValidationQueryEntry(
                id: "command-with-results",
                definitionIdentity: "tests/command-with-results@1",
                descriptorIdentity: "swiftql-query-v1-deadbeef",
                sql: "DELETE FROM t",
                dialectIdentifier: XLSQLiteDialect.identity.rawValue,
                cardinality: XLQueryCardinality.command.rawValue,
                results: [Support.result()]
            ),
        ])
        XCTAssertThrowsError(try commandWithResults.validating()) { error in
            guard case .invalidQuery(_, let reason) =
                error as? SQLiteBuildValidationManifestError else {
                return XCTFail("Expected invalid query, received \(error)")
            }
            XCTAssertTrue(reason.contains("must not declare result slots"))
        }

        let rowWithNoResults = Support.manifest(queries: [
            SQLiteBuildValidationQueryEntry(
                id: "row-with-no-results",
                definitionIdentity: "tests/row-with-no-results@1",
                descriptorIdentity: "swiftql-query-v1-deadbeef",
                sql: "SELECT 1",
                dialectIdentifier: XLSQLiteDialect.identity.rawValue,
                cardinality: XLQueryCardinality.exactlyOne.rawValue,
                results: []
            ),
        ])
        XCTAssertThrowsError(try rowWithNoResults.validating()) { error in
            guard case .invalidQuery(_, let reason) =
                error as? SQLiteBuildValidationManifestError else {
                return XCTFail("Expected invalid query, received \(error)")
            }
            XCTAssertTrue(reason.contains("requires at least one result slot"))
        }
    }

    func testManifestRejectsUnrecognizedNullabilityRawValue() {
        assertInvalidQuery(
            Support.query(parameters: [
                Support.parameter()
            ].map { param in
                SQLiteBuildValidationParameterEntry(
                    logicalIndex: param.logicalIndex,
                    physicalIndex: param.physicalIndex,
                    identity: param.identity,
                    keyKind: param.keyKind,
                    keyName: param.keyName,
                    keyIndex: param.keyIndex,
                    valueTypeIdentifier: param.valueTypeIdentifier,
                    valueTypeName: param.valueTypeName,
                    nullability: "maybe",
                    codec: param.codec,
                    storageIdentifier: param.storageIdentifier
                )
            }),
            contains: "nullability"
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

    // MARK: - Placeholder scanner

    func testPlaceholderScannerTreatsDoubledClosingBracketAsEscapedInsideQuotedIdentifier() {
        // "[x]]y:fake]" is one bracket-quoted identifier ("x]y:fake") where
        // "]]" escapes a literal "]", matching the doubled-delimiter escape
        // already honored for the single-quote, double-quote, and backtick
        // delimiters. A scanner that stops at the first "]"
        // would incorrectly split out ":fake" as a placeholder occurrence.
        let analysis = SQLiteBuildValidationManifestPlaceholderScanner.scan(
            "SELECT [x]]y:fake] AS col, :real AS r"
        )
        XCTAssertEqual(analysis.occurrences.map(\.spelling), [":real"])
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

    /// `validating(against:)` takes `any SQLiteBuildValidationReferenceRegistry`
    /// so a caller that stores its registry as a type-erased existential (e.g.
    /// a property typed `any SQLiteBuildValidationReferenceRegistry`) can pass
    /// it directly, without requiring the concrete conforming type at the call site.
    func testManifestValidatingAgainstAcceptsATypeErasedRegistry() {
        let erased: any SQLiteBuildValidationReferenceRegistry =
            SQLiteBuildValidationStaticReferenceRegistry(
                conformanceFeatureIDs: ["syntax.select.core"],
                conformanceCaseIDs: ["c191.v1.select.j-inner.w-named-binding"],
                northwindAnchorCaseIDs: ["northwind.cte.order-subtotals"]
            )
        let manifest = Support.manifest(queries: [
            Support.query(
                id: "erased-registry",
                conformanceFeatureIDs: ["syntax.select.core"]
            ),
        ])
        XCTAssertNoThrow(try manifest.validating(against: erased))
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
            formatVersion: SQLiteBuildValidationManifestFormatVersion(rawValue: 3),
            conformanceInventoryVersion: "190.1.0",
            combinatorialManifestVersion: "c191-v2",
            schemaSnapshot: Support.schemaSnapshot(),
            queries: [Support.query()]
        )
        let data = try JSONEncoder().encode(manifest)
        XCTAssertThrowsError(try SQLiteBuildValidationManifest.decode(data)) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .unsupportedFormatVersion(SQLiteBuildValidationManifestFormatVersion(rawValue: 3))
            )
        }
    }

    /// `format_version` is read before the body, so a document in a version
    /// this reader does not know reports that version, not a `keyNotFound` or
    /// type mismatch from a body shape it cannot decode. Both entry points
    /// behave the same way.
    func testDecodeReportsUnsupportedVersionBeforeDecodingTheBody() {
        let unsupported = SQLiteBuildValidationManifestError.unsupportedFormatVersion(
            SQLiteBuildValidationManifestFormatVersion(rawValue: 3)
        )
        for document in [
            #"{"format_version": 3}"#,
            #"{"format_version": 3, "queries": "not an array", "surprise": true}"#,
        ] {
            let data = Data(document.utf8)
            XCTAssertThrowsError(try SQLiteBuildValidationManifest.decode(data), document) { error in
                XCTAssertEqual(error as? SQLiteBuildValidationManifestError, unsupported)
            }
            XCTAssertThrowsError(
                try JSONDecoder().decode(SQLiteBuildValidationManifest.self, from: data),
                document
            ) { error in
                XCTAssertEqual(error as? SQLiteBuildValidationManifestError, unsupported)
            }
        }
    }

    // MARK: - Format version 2 (#658)

    /// The shape an application's generated manifest takes (#659): no
    /// fixture provenance, and possibly no declared queries at all.
    func testGeneratedManifestWithoutFixtureProvenanceOrQueriesValidates() throws {
        let manifest = SQLiteBuildValidationManifest(
            schemaSnapshot: Support.schemaSnapshot(),
            queries: []
        )
        XCTAssertEqual(manifest.formatVersion, .v2)

        let validated = try manifest.validating()
        let data = try manifest.canonicalJSONData()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"format_version\" : 2"))
        XCTAssertFalse(json.contains("conformance_inventory_version"))
        XCTAssertFalse(json.contains("combinatorial_manifest_version"))
        XCTAssertFalse(json.contains("null"))

        let decoded = try SQLiteBuildValidationManifest.decode(data)
        XCTAssertEqual(decoded, validated)
        XCTAssertEqual(try decoded.canonicalJSONData(), data)
    }

    func testVersion2AcceptsSlotsWithoutValueTypeNameButVersion1DoesNot() throws {
        let parameter = SQLiteBuildValidationParameterEntry(
            logicalIndex: 0,
            physicalIndex: 1,
            identity: "parameter/first",
            keyKind: .named,
            keyName: "first",
            keyIndex: nil,
            valueTypeIdentifier: "swift.int",
            nullability: "required",
            codec: nil,
            storageIdentifier: "integer"
        )
        let result = SQLiteBuildValidationResultEntry(
            index: 0,
            identity: "result/first",
            declaredAlias: "first",
            valueTypeIdentifier: "swift.int",
            nullability: "required",
            codec: nil,
            storageIdentifier: "integer"
        )
        let query = Support.query(
            sql: "SELECT :first AS first",
            parameters: [parameter],
            results: [result]
        )

        let version2 = Support.manifest(queries: [query])
        let data = try version2.canonicalJSONData()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("value_type_name"))
        XCTAssertEqual(try SQLiteBuildValidationManifest.decode(data), try version2.validating())

        XCTAssertThrowsError(
            try Support.manifest(formatVersion: .v1, queries: [query]).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .invalidQuery(query.id, "parameter metadata must be contiguous and complete")
            )
        }

        let emptyName = SQLiteBuildValidationResultEntry(
            index: 0,
            identity: "result/first",
            declaredAlias: "first",
            valueTypeIdentifier: "swift.int",
            valueTypeName: "",
            nullability: "required",
            codec: nil,
            storageIdentifier: "integer"
        )
        assertInvalidQuery(
            Support.query(results: [emptyName]),
            contains: "result metadata must be contiguous and complete"
        )
    }

    /// Version 1 keeps every check it had before version 2 existed.
    func testVersion1StillRequiresFixtureProvenanceAndQueries() {
        let cases: [(SQLiteBuildValidationManifest, String)] = [
            (
                Support.manifest(
                    formatVersion: .v1,
                    conformanceInventoryVersion: nil,
                    queries: [Support.query()]
                ),
                "conformance_inventory_version must not be empty"
            ),
            (
                Support.manifest(
                    formatVersion: .v1,
                    combinatorialManifestVersion: "",
                    queries: [Support.query()]
                ),
                "combinatorial_manifest_version must not be empty"
            ),
            (
                Support.manifest(formatVersion: .v1, queries: []),
                "queries must not be empty"
            ),
        ]
        for (manifest, reason) in cases {
            XCTAssertThrowsError(try manifest.validating(), reason) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationManifestError,
                    .invalidManifest(reason)
                )
            }
        }
    }

    func testVersion2RejectsEmptyProvenanceAndUntraceableFixtureReferences() {
        XCTAssertThrowsError(
            try Support.manifest(conformanceInventoryVersion: "", queries: []).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .invalidManifest("conformance_inventory_version must be omitted or nonempty")
            )
        }

        XCTAssertThrowsError(
            try Support.manifest(
                conformanceInventoryVersion: nil,
                queries: [Support.query(id: "q", conformanceFeatureIDs: ["binding.named"])]
            ).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .invalidQuery("q", "conformance_feature_ids require conformance_inventory_version")
            )
        }

        XCTAssertThrowsError(
            try Support.manifest(
                combinatorialManifestVersion: nil,
                queries: [Support.query(id: "q", conformanceCaseIDs: ["c191.v1.case"])]
            ).validating()
        ) { error in
            XCTAssertEqual(
                error as? SQLiteBuildValidationManifestError,
                .invalidQuery("q", "conformance_case_ids require combinatorial_manifest_version")
            )
        }
    }

    /// A version 2 reader still reads version 1: the build-plugin fixture is
    /// a checked-in version 1 manifest, and decoding then re-encoding it must
    /// reproduce its bytes exactly.
    func testCheckedInVersion1ManifestDecodesAndReencodesByteIdentically() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "IntegrationTests/BuildValidationPluginFixture/Sources/ValidatedLibrary/swiftql-build-validation-manifest.json"
            )
        let data = try Data(contentsOf: url)

        let manifest = try SQLiteBuildValidationManifest.decode(data)

        XCTAssertEqual(manifest.formatVersion, .v1)
        XCTAssertNotNil(manifest.conformanceInventoryVersion)
        XCTAssertEqual(try manifest.canonicalJSONData(), data)
    }

    // MARK: - Unknown keys fail closed (#658)

    /// Synthesized decoding ignores an unknown key, so a misspelled optional
    /// key would decode as "absent". Every manifest type rejects one instead,
    /// and names where it is.
    func testDecodeRejectsAStrayKeyAtEveryLevel() throws {
        let manifest = Support.manifest(queries: [
            Support.query(
                sql: "SELECT :first AS first",
                parameters: [Support.parameter(codec: Support.codec())],
                results: [Support.result(codec: Support.codec())],
                requiredCapabilities: ["function:ABS"]
            ),
        ])
        let canonical = try XCTUnwrap(
            String(data: try manifest.canonicalJSONData(), encoding: .utf8)
        )
        XCTAssertNoThrow(try SQLiteBuildValidationManifest.decode(Data(canonical.utf8)))

        let cases: [(original: String, replacement: String, path: String)] = [
            (
                #""conformance_inventory_version" :"#,
                #""conformance_inventory_versoin" :"#,
                "conformance_inventory_versoin"
            ),
            (
                #""database_byte_count" :"#,
                #""database_sha_256" : "x", "database_byte_count" :"#,
                "schema_snapshot.database_sha_256"
            ),
            (
                #""definition_identity" :"#,
                #""definition_id" : "x", "definition_identity" :"#,
                "queries[0].definition_id"
            ),
            (
                #""key_kind" :"#,
                #""key_nmae" : "first", "key_kind" :"#,
                "queries[0].parameters[0].key_nmae"
            ),
            (
                #""key_id" :"#,
                #""key_ver" : 1, "key_id" :"#,
                "queries[0].parameters[0].codec.key_ver"
            ),
            (
                #""declared_alias" :"#,
                #""alias" : "first", "declared_alias" :"#,
                "queries[0].results[0].alias"
            ),
            (
                #""id" : "function:ABS""#,
                #""id" : "function:ABS", "name" : "ABS""#,
                "queries[0].required_capabilities[0].name"
            ),
        ]
        for (original, replacement, path) in cases {
            let range = try XCTUnwrap(canonical.range(of: original), original)
            let document = canonical.replacingCharacters(in: range, with: replacement)
            XCTAssertThrowsError(
                try SQLiteBuildValidationManifest.decode(Data(document.utf8)),
                path
            ) { error in
                XCTAssertEqual(
                    error as? SQLiteBuildValidationManifestError,
                    .unknownKey(path: path)
                )
            }
        }
    }
}
