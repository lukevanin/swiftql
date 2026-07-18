import Foundation
import XCTest

import SwiftQLCore
import SwiftQLSQLiteConformanceFixtures


final class SQLiteValueConformanceBoundaryTests: XCTestCase {

    func testManifestAccountsForEveryStableCaseAndPinnedProvenance() throws {
        let manifest = try SQLiteValueConformanceManifest.load()
        let recordsByID = Dictionary(
            grouping: manifest.records,
            by: \.id
        )
        let pinnedCommits = [
            "groue/GRDB.swift": "b83108d10f42680d78f23fe4d4d80fc88dab3212",
            "stephencelis/SQLite.swift": "ccaae3d01fd655be40f20665f1f61dc6deecec27",
            "Lighter-swift/Lighter": "3486fc08d580aa3a87cd29ede023ba291a90de8b",
            "marcoarment/Blackbird": "0960ffc7649e9c35cfdb5f6b0b98216a34e8c09a",
            "vapor/fluent-kit": "6f8844284df4f797d2a81721511d053357d97b56",
            "lukevanin/swiftql": "03f504a1e47e0580b2c20eeeecea104cb9d7f2a9",
        ]

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.coordinationIssue, 190)
        XCTAssertEqual(
            Set(recordsByID.keys),
            Set(SQLiteValueConformanceCaseID.allCases)
        )

        for id in SQLiteValueConformanceCaseID.allCases {
            let records = try XCTUnwrap(recordsByID[id], id.rawValue)
            XCTAssertEqual(records.count, 1, "Duplicate manifest ID: \(id.rawValue)")
            let record = try XCTUnwrap(records.first)
            XCTAssertFalse(record.category.isEmpty, id.rawValue)
            XCTAssertFalse(record.evidenceLayers.isEmpty, id.rawValue)
            XCTAssertEqual(
                URL(string: record.sqliteDocumentationURL)?.scheme,
                "https",
                id.rawValue
            )
            XCTAssertEqual(
                record.provenance.commit,
                pinnedCommits[record.provenance.repository],
                id.rawValue
            )
            XCTAssertFalse(record.provenance.path.isEmpty, id.rawValue)
            XCTAssertFalse(record.provenance.upstreamCase.isEmpty, id.rawValue)
            XCTAssertFalse(record.provenance.licenseDisposition.isEmpty, id.rawValue)
            XCTAssertFalse(record.provenance.adaptationNotes.isEmpty, id.rawValue)
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
