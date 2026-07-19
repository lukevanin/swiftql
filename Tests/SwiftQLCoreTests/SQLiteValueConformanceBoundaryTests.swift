import Foundation
import XCTest

import SwiftQLCore
import SwiftQLSQLiteConformanceFixtures


final class SQLiteValueConformanceBoundaryTests: XCTestCase {

    func testInventoryAccountsForEveryStableCaseAndPinnedProvenance() throws {
        let inventory = try SQLiteConformanceInventory.load()
        var featuresByID: [
            SQLiteValueConformanceCaseID: [SQLiteConformanceInventory.Feature]
        ] = [:]
        for feature in inventory.features {
            guard let id = SQLiteValueConformanceCaseID(rawValue: feature.id) else {
                continue
            }
            featuresByID[id, default: []].append(feature)
        }
        let valueFeatureCount = featuresByID.values.reduce(0) { $0 + $1.count }
        XCTAssertEqual(inventory.schemaVersion, 1)
        XCTAssertEqual(inventory.inventoryVersion, "1.3.0")
        XCTAssertEqual(inventory.coordinationIssue, 190)
        XCTAssertEqual(valueFeatureCount, 24)
        XCTAssertEqual(
            Set(featuresByID.keys),
            Set(SQLiteValueConformanceCaseID.allCases)
        )

        for id in SQLiteValueConformanceCaseID.allCases {
            let features = try XCTUnwrap(featuresByID[id], id.rawValue)
            XCTAssertEqual(features.count, 1, "Duplicate inventory ID: \(id.rawValue)")
            let feature = try XCTUnwrap(features.first)
            XCTAssertFalse(feature.evidenceIDs.isEmpty, id.rawValue)
            XCTAssertFalse(feature.sqliteDocumentationURLs.isEmpty, id.rawValue)
            XCTAssertFalse(feature.provenance.isEmpty, id.rawValue)

            for documentationURL in feature.sqliteDocumentationURLs {
                XCTAssertEqual(
                    URL(string: documentationURL)?.scheme,
                    "https",
                    id.rawValue
                )
            }

            for provenance in feature.provenance {
                XCTAssertEqual(
                    provenance.commit,
                    SQLiteValueConformanceFixtures
                        .pinnedProvenanceCommitsByRepository[provenance.repository],
                    id.rawValue
                )
                XCTAssertFalse(provenance.path.isEmpty, id.rawValue)
                XCTAssertFalse(provenance.upstreamCase.isEmpty, id.rawValue)
                XCTAssertFalse(provenance.licenseSPDX.isEmpty, id.rawValue)
                XCTAssertFalse(provenance.licenseFilePath.isEmpty, id.rawValue)
                XCTAssertEqual(
                    URL(string: provenance.licenseFileURL)?.scheme,
                    "https",
                    id.rawValue
                )
                XCTAssertFalse(provenance.licenseBlobSHA.isEmpty, id.rawValue)
                XCTAssertFalse(provenance.licenseDisposition.isEmpty, id.rawValue)
                XCTAssertFalse(provenance.adaptationNotes.isEmpty, id.rawValue)
                if provenance.copiedMaterial {
                    XCTAssertFalse(
                        provenance.noticePath?.isEmpty ?? true,
                        id.rawValue
                    )
                }
            }
        }
    }

    func testInventoryRegistersEnvironmentAndSuiteReferences() throws {
        let inventory = try SQLiteConformanceInventory.load()
        let environmentIDs = Set(inventory.sqliteEnvironments.map(\.id))
        let evidenceIDs = Set(inventory.evidence.map(\.id))
        let featureIDs = Set(inventory.features.map(\.id))
        let suiteIDs = Set(inventory.suites.map(\.id))

        XCTAssertFalse(environmentIDs.isEmpty)
        XCTAssertFalse(evidenceIDs.isEmpty)
        XCTAssertFalse(featureIDs.isEmpty)
        XCTAssertFalse(suiteIDs.isEmpty)
        XCTAssertEqual(environmentIDs.count, inventory.sqliteEnvironments.count)
        XCTAssertEqual(evidenceIDs.count, inventory.evidence.count)
        XCTAssertEqual(featureIDs.count, inventory.features.count)
        XCTAssertEqual(suiteIDs.count, inventory.suites.count)

        for evidence in inventory.evidence {
            XCTAssertTrue(
                Set(evidence.environmentIDs).isSubset(of: environmentIDs),
                evidence.id
            )
        }
        for suite in inventory.suites {
            XCTAssertTrue(Set(suite.caseIDs).isSubset(of: featureIDs), suite.id)
            XCTAssertTrue(Set(suite.evidenceIDs).isSubset(of: evidenceIDs), suite.id)
        }
    }

    func testInventoryRegistersCompletedNorthwindCorpusAndPinnedProvenance() throws {
        let inventory = try SQLiteConformanceInventory.load()
        let suite = try XCTUnwrap(
            inventory.suites.first { $0.issue == 254 }
        )
        let expectedCaseIDs = SQLiteNorthwindConformanceCaseID.allCases.map(
            \.rawValue
        )
        let featuresByID = Dictionary(
            uniqueKeysWithValues: inventory.features.map { ($0.id, $0) }
        )
        let suiteEvidenceIDs = Set(suite.evidenceIDs)
        let adapterCaseIDs: Set<SQLiteNorthwindConformanceCaseID> = [
            .crudTemporaryCopy,
            .throwingRollback,
        ]

        XCTAssertEqual(suite.id, "suite.254.northwind-correctness")
        XCTAssertEqual(suite.milestone, "v1.3")
        XCTAssertEqual(suite.status, .completed)
        XCTAssertEqual(suite.caseIDs, expectedCaseIDs)
        XCTAssertEqual(
            suite.evidenceIDs,
            [
                "evidence.northwind.crud-rollback.sqlite",
                "evidence.northwind.fixture-contract.sqlite",
                "evidence.northwind.fixture-failures.sqlite",
                "evidence.northwind.joins-aggregates-views.sqlite",
                "evidence.northwind.reads.sqlite",
                "evidence.northwind.subquery-compound-cte.sqlite",
            ]
        )

        for caseID in SQLiteNorthwindConformanceCaseID.allCases {
            let feature = try XCTUnwrap(
                featuresByID[caseID.rawValue],
                caseID.rawValue
            )
            XCTAssertEqual(feature.status, .supported, caseID.rawValue)
            XCTAssertEqual(feature.adoptionStatus, .alreadyCovered, caseID.rawValue)
            XCTAssertFalse(feature.evidenceIDs.isEmpty, caseID.rawValue)
            XCTAssertTrue(
                Set(feature.evidenceIDs).isSubset(of: suiteEvidenceIDs),
                caseID.rawValue
            )

            XCTAssertEqual(
                feature.kind,
                adapterCaseIDs.contains(caseID)
                    ? .adapterContract
                    : .adoptedBehavior,
                caseID.rawValue
            )
            XCTAssertEqual(feature.provenance.count, 1, caseID.rawValue)
            let provenance = try XCTUnwrap(
                feature.provenance.first,
                caseID.rawValue
            )
            XCTAssertEqual(
                provenance.repository,
                "Northwind-swift/NorthwindSQLite.swift",
                caseID.rawValue
            )
            XCTAssertEqual(
                provenance.commit,
                "865de0872e61692a49cd6069cd2df8f9ac04541e",
                caseID.rawValue
            )
            XCTAssertEqual(provenance.path, "dist/northwind.db", caseID.rawValue)
            XCTAssertEqual(provenance.licenseSPDX, "MIT", caseID.rawValue)
            XCTAssertEqual(provenance.licenseFilePath, "LICENSE", caseID.rawValue)
            XCTAssertEqual(
                provenance.licenseBlobSHA,
                "7b784d8b065952c289f6fe51adf74ed780c4d996",
                caseID.rawValue
            )
            XCTAssertTrue(provenance.copiedMaterial, caseID.rawValue)
            XCTAssertEqual(
                provenance.noticePath,
                "Tests/SwiftQLNorthwindFixtures/Resources/Northwind/LICENSE.txt",
                caseID.rawValue
            )
            XCTAssertTrue(
                provenance.adaptationNotes.contains(
                    "cb6f0071a264e150d3796f75c4b0643e32b2132e4e02370518b50a1eac3381d8"
                ),
                caseID.rawValue
            )
        }
    }

    func testSharedStorageCasesCrossSQLiteDialectAndInvocationBoundaries() throws {
        let dialect = XLSQLiteDialect()
        let cases = SQLiteValueConformanceFixtures.storageCases
        let slots = cases.enumerated().map { offset, testCase in
            parameterSlot(
                index: offset,
                name: testCase.id.rawValue,
                nullability: testCase.expectedStorage == .null ? .nullable : .required
            )
        }
        let layout = try XLParameterLayout(slots: slots)
        var packet = XLInvocationBindings<XLSQLiteValue>(layout: layout)

        for (testCase, slot) in zip(cases, slots) {
            XCTAssertEqual(
                testCase.value.storageType,
                testCase.expectedStorage,
                testCase.id.rawValue
            )
            XCTAssertEqual(
                dialect.stableStorageIdentifier(for: testCase.value),
                storageIdentifier(testCase.expectedStorage),
                testCase.id.rawValue
            )
            packet = try packet.binding(testCase.value, to: slot)
        }

        XCTAssertEqual(packet.bindingCount, cases.count)
        XCTAssertTrue(packet.isComplete)
        for testCase in cases {
            let binding = try XCTUnwrap(
                packet.binding(for: .named(testCase.id.rawValue)),
                testCase.id.rawValue
            )
            XCTAssertEqual(
                binding.value.storageType,
                testCase.expectedStorage,
                testCase.id.rawValue
            )
        }
    }

    func testNamedAndRepeatedBindingsRetainOneLogicalIdentity() throws {
        let namedID = SQLiteValueConformanceCaseID.namedBinding
        let repeatedID = SQLiteValueConformanceCaseID.repeatedNamedBinding
        let named = parameterSlot(index: 0, name: namedID.rawValue)
        let repeated = parameterSlot(index: 1, name: repeatedID.rawValue)
        let layout = try XLParameterLayout(
            slots: [repeated, named, repeated]
        )
        var packet = XLInvocationBindings<XLSQLiteValue>(layout: layout)
        packet = try packet.binding(.text("named"), to: named)
        packet = try packet.binding(.integer(252), to: repeated)

        XCTAssertEqual(layout.count, 2, repeatedID.rawValue)
        XCTAssertEqual(packet.bindings.map(\.slot), [named, repeated])
        XCTAssertEqual(
            packet.binding(for: .named(namedID.rawValue))?.value,
            .text("named")
        )
        XCTAssertEqual(
            packet.binding(for: .named(repeatedID.rawValue))?.value,
            .integer(252)
        )
        XCTAssertNoThrow(try packet.validatingComplete())
    }

    func testOptionalEnumNamedAndDefaultCodecsShareSQLiteStoragePolicy() throws {
        let textCodec = makeTextCodec()
        let integerCodec = makeIntegerCodec()
        let registry = try XLValueCodecRegistry()
            .registering(textCodec)
            .registering(integerCodec)
        let configuration = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [integerCodec.identity.key]
        )
        let dialect = XLSQLiteDialect()
        let context = XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(
                SQLiteValueConformanceCaseID.textRawValueEnum.rawValue
            )
        )

        let namedText = try configuration.encode(
            ConformanceMode.ready,
            using: dialect,
            context: context,
            selection: XLValueCodecSelection(
                explicitCodecKey: textCodec.identity.key
            )
        )
        XCTAssertEqual(
            namedText,
            .text(ConformanceMode.ready.rawValue),
            SQLiteValueConformanceCaseID.namedTextCodec.rawValue
        )

        let defaultInteger = try configuration.encode(
            ConformanceMode.waiting,
            using: dialect,
            context: context
        )
        XCTAssertEqual(
            defaultInteger,
            .integer(2),
            SQLiteValueConformanceCaseID.defaultIntegerCodec.rawValue
        )

        let decodedText: ConformanceMode = try configuration.decode(
            ConformanceMode.self,
            from: namedText,
            using: dialect,
            context: context,
            selection: XLValueCodecSelection(
                explicitCodecKey: textCodec.identity.key
            )
        )
        XCTAssertEqual(decodedText, .ready)

        let encodedNull = try configuration.encodeOptional(
            Optional<ConformanceMode>.none,
            using: dialect,
            context: context
        )
        let decodedNull: ConformanceMode? = try configuration.decodeOptional(
            ConformanceMode.self,
            from: encodedNull,
            using: dialect,
            context: context
        )
        XCTAssertEqual(encodedNull, .null)
        XCTAssertNil(
            decodedNull,
            SQLiteValueConformanceCaseID.optionalNullVersusMissing.rawValue
        )
    }

    func testCodecStorageMismatchRetainsCaseAndCodingContext() throws {
        let codec = makeTextCodec()
        let configuration = try XLValueCodingConfiguration(
            registry: XLValueCodecRegistry().registering(codec)
        )
        let context = XLValueCodingContext(
            site: .result,
            path: XLValueCodingPath(
                SQLiteValueConformanceCaseID.storageMismatch.rawValue
            )
        )

        XCTAssertThrowsError(
            try configuration.decode(
                ConformanceMode.self,
                from: XLSQLiteValue.integer(1),
                using: XLSQLiteDialect(),
                context: context,
                selection: XLValueCodecSelection(
                    explicitCodecKey: codec.identity.key
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? XLValueCodecError,
                .storageMismatch(
                    codec: codec.identity.key,
                    expected: storageIdentifier(.text),
                    actual: storageIdentifier(.integer),
                    context: context
                )
            )
        }
    }
}


private enum ConformanceMode: String, Equatable, Sendable {
    case ready
    case waiting
}


private enum ConformanceCodecFailure: Error {
    case invalidValue
}


private let conformanceValueType = XLValueTypeIdentifier(
    rawValue: "swiftql.conformance.mode"
)


private func makeTextCodec() -> XLValueCodec<ConformanceMode, XLSQLiteDialect> {
    XLValueCodec(
        key: XLValueCodecKey(id: "swiftql.conformance.mode.text", version: 1),
        valueTypeIdentifier: conformanceValueType,
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: storageIdentifier(.text),
        encode: { value, _, _ in
            .text(value.rawValue)
        },
        decode: { value, _, _ in
            guard case .text(let rawValue) = value,
                  let decoded = ConformanceMode(rawValue: rawValue) else {
                throw ConformanceCodecFailure.invalidValue
            }
            return decoded
        }
    )
}


private func makeIntegerCodec() -> XLValueCodec<ConformanceMode, XLSQLiteDialect> {
    XLValueCodec(
        key: XLValueCodecKey(id: "swiftql.conformance.mode.integer", version: 1),
        valueTypeIdentifier: conformanceValueType,
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: storageIdentifier(.integer),
        encode: { value, _, _ in
            .integer(value == .ready ? 1 : 2)
        },
        decode: { value, _, _ in
            guard case .integer(let rawValue) = value else {
                throw ConformanceCodecFailure.invalidValue
            }
            switch rawValue {
            case 1:
                return .ready
            case 2:
                return .waiting
            default:
                throw ConformanceCodecFailure.invalidValue
            }
        }
    )
}


private func parameterSlot(
    index: Int,
    name: String,
    nullability: XLParameterNullability = .required
) -> XLParameterSlot {
    XLParameterSlot(
        index: XLLogicalParameterIndex(index),
        key: .named(name),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "swiftql.conformance.sqlite-value"
        ),
        valueTypeName: String(reflecting: XLSQLiteValue.self),
        nullability: nullability,
        codecIdentity: nil,
        codingContext: XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(name)
        )
    )
}


private func storageIdentifier(
    _ storage: XLSQLiteStorageClass
) -> XLValueStorageIdentifier {
    XLValueStorageIdentifier(rawValue: storage.rawValue)
}
