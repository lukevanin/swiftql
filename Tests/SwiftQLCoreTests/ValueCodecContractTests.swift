import Foundation
import XCTest

import SwiftQLCore


final class ValueCodecContractTests: XCTestCase {

    private let dialect = CodecTestDialect()

    private let parameterContext = XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath(["lookup", "token"])
    )

    private let resultContext = XLValueCodingContext(
        site: .result,
        path: XLValueCodingPath(["row", "token"])
    )

    func testStableIdentityContainsCodecValueDialectAndStorageComponents() {
        let codec = makeCodec(
            key: key("text", 3),
            storage: .text,
            encode: { .text("\($0.rawValue)") },
            decode: { value in
                guard case .text(let text) = value, let rawValue = Int64(text) else {
                    throw CodecTestFailure.invalidValue
                }
                return CodecToken(rawValue: rawValue)
            }
        )

        XCTAssertEqual(
            codec.identity,
            XLValueCodecIdentity(
                key: key("text", 3),
                valueTypeIdentifier: tokenTypeIdentifier,
                dialectIdentifier: CodecTestDialect.identity,
                storageIdentifier: storageIdentifier(.text)
            )
        )
        XCTAssertEqual(
            codec.identity.stableIdentityComponents,
            [
                "test.text",
                "3",
                tokenTypeIdentifier.rawValue,
                CodecTestDialect.identity.rawValue,
                CodecTestStorage.text.rawValue,
            ]
        )
    }

    func testSelectionPrecedenceIsExplicitThenQueryThenDefaultThenLegacy() throws {
        let explicit = makeMarkerCodec("explicit")
        let query = makeMarkerCodec("query")
        let defaultCodec = makeMarkerCodec("default")
        let legacy = makeMarkerCodec("legacy")
        let registry = try register([explicit, query, defaultCodec, legacy])
        let configured = try XLValueCodingConfiguration(
            registry: registry,
            defaultCodecKeys: [defaultCodec.identity.key]
        )
        let unconfigured = try XLValueCodingConfiguration(registry: registry)
        let allSelectors = XLValueCodecSelection(
            explicitCodecKey: explicit.identity.key,
            queryCodecKey: query.identity.key,
            legacyCodecKey: legacy.identity.key
        )

        XCTAssertEqual(
            try configured.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: allSelectors
            ),
            .text("explicit")
        )
        XCTAssertEqual(
            try configured.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(
                    queryCodecKey: query.identity.key,
                    legacyCodecKey: legacy.identity.key
                )
            ),
            .text("query")
        )
        XCTAssertEqual(
            try configured.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(legacyCodecKey: legacy.identity.key)
            ),
            .text("default")
        )
        XCTAssertEqual(
            try unconfigured.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(legacyCodecKey: legacy.identity.key)
            ),
            .text("legacy")
        )
    }

    func testInvalidHigherPrecedenceSelectorNeverFallsThrough() throws {
        let fallback = makeMarkerCodec("fallback")
        let configuration = try XLValueCodingConfiguration(
            registry: try register([fallback]),
            defaultCodecKeys: [fallback.identity.key]
        )
        let unknown = key("unknown")

        assertCodecError(
            try configuration.encode(
                CodecToken(rawValue: 9),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(
                    explicitCodecKey: unknown,
                    queryCodecKey: fallback.identity.key,
                    legacyCodecKey: fallback.identity.key
                )
            ),
            equals: .unknownCodec(
                key: unknown,
                source: .explicit,
                context: parameterContext
            )
        )
    }

    func testRegistrationAloneNeverChangesRepresentationSelection() throws {
        let first = makeMarkerCodec("only")
        let oneCodecConfiguration = try XLValueCodingConfiguration(
            registry: try register([first])
        )

        assertCodecError(
            try oneCodecConfiguration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext
            ),
            equals: .missingCodec(
                valueType: String(reflecting: CodecToken.self),
                dialect: CodecTestDialect.identity,
                context: parameterContext
            )
        )

        let second = makeMarkerCodec("second")
        let ambiguousConfiguration = try XLValueCodingConfiguration(
            registry: try register([first, second])
        )
        assertCodecError(
            try ambiguousConfiguration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext
            ),
            equals: .ambiguousCodec(
                valueType: String(reflecting: CodecToken.self),
                dialect: CodecTestDialect.identity,
                candidates: [first.identity.key, second.identity.key].sorted(by: codecKeyOrder),
                context: parameterContext
            )
        )
    }

    func testOptionalNullResolvesSelectionButBypassesNonoptionalClosures() throws {
        let codec = XLValueCodec<CodecToken, CodecTestDialect>(
            key: key("null-bypass"),
            valueTypeIdentifier: tokenTypeIdentifier,
            dialectIdentifier: CodecTestDialect.identity,
            storageIdentifier: storageIdentifier(.text),
            encode: { _, _, _ in
                XCTFail("nil must bypass the nonoptional encoder")
                return .text("unexpected")
            },
            decode: { _, _, _ in
                XCTFail("SQL NULL must bypass the nonoptional decoder")
                return CodecToken(rawValue: -1)
            }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try register([codec]),
            defaultCodecKeys: [codec.identity.key]
        )

        XCTAssertEqual(
            try configuration.encodeOptional(
                Optional<CodecToken>.none,
                using: dialect,
                context: parameterContext
            ),
            .null
        )
        let decoded: CodecToken? = try configuration.decodeOptional(
            CodecToken.self,
            from: .null,
            using: dialect,
            context: resultContext
        )
        XCTAssertNil(decoded)

        let unknown = key("unknown-null")
        assertCodecError(
            try configuration.encodeOptional(
                Optional<CodecToken>.none,
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(explicitCodecKey: unknown)
            ),
            equals: .unknownCodec(
                key: unknown,
                source: .explicit,
                context: parameterContext
            )
        )
    }

    func testDuplicateAndUnknownConfigurationEntriesFailDeterministically() throws {
        let first = makeMarkerCodec("a")
        let second = makeMarkerCodec("b")
        let registry = try register([first, second])
        let configurationContext = XLValueCodingContext(
            site: .configuration,
            path: XLValueCodingPath("defaults")
        )

        assertCodecError(
            try registry.registering(first),
            equals: .duplicateCodec(
                key: first.identity.key,
                context: configurationContext
            )
        )
        assertCodecError(
            try XLValueCodingConfiguration(
                registry: registry,
                defaultCodecKeys: [second.identity.key, first.identity.key]
            ),
            equals: .duplicateDefault(
                valueTypeIdentifier: tokenTypeIdentifier.rawValue,
                dialect: CodecTestDialect.identity,
                keys: [first.identity.key, second.identity.key].sorted(by: codecKeyOrder),
                context: configurationContext
            )
        )

        let unknown = key("absent")
        assertCodecError(
            try XLValueCodingConfiguration(
                registry: registry,
                defaultCodecKeys: [unknown]
            ),
            equals: .unknownCodec(
                key: unknown,
                source: .configurationDefault,
                context: configurationContext
            )
        )
    }

    func testDefaultsDistinguishDescriptorIdentitiesOfOneDialectType() throws {
        let firstIdentity = XLDialectIdentifier(rawValue: "codec-test-a")
        let secondIdentity = XLDialectIdentifier(rawValue: "codec-test-b")
        let first = makeCodec(
            key: key("identity-a"),
            dialectIdentifier: firstIdentity,
            storage: .text,
            encode: { _ in .text("a") },
            decode: { _ in CodecToken(rawValue: 1) }
        )
        let second = makeCodec(
            key: key("identity-b"),
            dialectIdentifier: secondIdentity,
            storage: .text,
            encode: { _ in .text("b") },
            decode: { _ in CodecToken(rawValue: 2) }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try register([first, second]),
            defaultCodecKeys: [first.identity.key, second.identity.key]
        )

        XCTAssertEqual(
            try configuration.encode(
                CodecToken(rawValue: 0),
                using: CodecTestDialect(identity: firstIdentity),
                context: parameterContext
            ),
            .text("a")
        )
        XCTAssertEqual(
            try configuration.encode(
                CodecToken(rawValue: 0),
                using: CodecTestDialect(identity: secondIdentity),
                context: parameterContext
            ),
            .text("b")
        )
    }

    func testMultipleDuplicateDefaultGroupsAlwaysReportCanonicalCodecKeys() throws {
        let firstIdentity = XLDialectIdentifier(rawValue: "codec-test-z")
        let secondIdentity = XLDialectIdentifier(rawValue: "codec-test-a")
        let z1 = makeCodec(
            key: key("z-one"),
            dialectIdentifier: firstIdentity,
            storage: .text,
            encode: { _ in .text("z1") },
            decode: { _ in CodecToken(rawValue: 1) }
        )
        let z2 = makeCodec(
            key: key("z-two"),
            dialectIdentifier: firstIdentity,
            storage: .text,
            encode: { _ in .text("z2") },
            decode: { _ in CodecToken(rawValue: 2) }
        )
        let a1 = makeCodec(
            key: key("a-one"),
            dialectIdentifier: secondIdentity,
            storage: .text,
            encode: { _ in .text("a1") },
            decode: { _ in CodecToken(rawValue: 3) }
        )
        let a2 = makeCodec(
            key: key("a-two"),
            dialectIdentifier: secondIdentity,
            storage: .text,
            encode: { _ in .text("a2") },
            decode: { _ in CodecToken(rawValue: 4) }
        )
        let registry = try register([z2, a2, z1, a1])
        let configurationContext = XLValueCodingContext(
            site: .configuration,
            path: XLValueCodingPath("defaults")
        )

        for defaults in [
            [z2.identity.key, a2.identity.key, z1.identity.key, a1.identity.key],
            [a1.identity.key, z1.identity.key, a2.identity.key, z2.identity.key],
        ] {
            assertCodecError(
                try XLValueCodingConfiguration(
                    registry: registry,
                    defaultCodecKeys: defaults
                ),
                equals: .duplicateDefault(
                    valueTypeIdentifier: tokenTypeIdentifier.rawValue,
                    dialect: secondIdentity,
                    keys: [a1.identity.key, a2.identity.key],
                    context: configurationContext
                )
            )
        }
    }

    func testTypeDialectAndStorageMismatchesContainUseContext() throws {
        let tokenCodec = makeMarkerCodec("token")
        let configuration = try XLValueCodingConfiguration(
            registry: try register([tokenCodec])
        )

        assertCodecError(
            try configuration.encode(
                OtherCodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(explicitCodecKey: tokenCodec.identity.key)
            ),
            equals: .valueTypeMismatch(
                codec: tokenCodec.identity.key,
                expected: tokenTypeIdentifier.rawValue,
                actual: String(reflecting: OtherCodecToken.self),
                context: parameterContext
            )
        )

        let wrongIdentity = makeCodec(
            key: key("wrong-dialect-id"),
            dialectIdentifier: XLDialectIdentifier(rawValue: "other-dialect"),
            storage: .text,
            encode: { _ in .text("wrong") },
            decode: { _ in CodecToken(rawValue: 0) }
        )
        let wrongIdentityConfiguration = try XLValueCodingConfiguration(
            registry: try register([wrongIdentity])
        )
        assertCodecError(
            try wrongIdentityConfiguration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(explicitCodecKey: wrongIdentity.identity.key)
            ),
            equals: .dialectMismatch(
                codec: wrongIdentity.identity.key,
                expected: XLDialectIdentifier(rawValue: "other-dialect"),
                actual: CodecTestDialect.identity,
                context: parameterContext
            )
        )

        let alternateCodec = XLValueCodec<CodecToken, AlternateCodecTestDialect>(
            key: key("wrong-dialect-type"),
            valueTypeIdentifier: tokenTypeIdentifier,
            dialectIdentifier: CodecTestDialect.identity,
            storageIdentifier: storageIdentifier(.text),
            encode: { _, _, _ in .text("alternate") },
            decode: { _, _, _ in CodecToken(rawValue: 0) }
        )
        let alternateConfiguration = try XLValueCodingConfiguration(
            registry: try XLValueCodecRegistry().registering(alternateCodec)
        )
        assertCodecError(
            try alternateConfiguration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext,
                selection: XLValueCodecSelection(explicitCodecKey: alternateCodec.identity.key)
            ),
            equals: .dialectTypeMismatch(
                codec: alternateCodec.identity.key,
                expected: String(reflecting: AlternateCodecTestDialect.self),
                actual: String(reflecting: CodecTestDialect.self),
                context: parameterContext
            )
        )

        let wrongStorage = makeCodec(
            key: key("wrong-storage"),
            storage: .text,
            encode: { .integer($0.rawValue) },
            decode: { _ in CodecToken(rawValue: 0) }
        )
        let wrongStorageConfiguration = try XLValueCodingConfiguration(
            registry: try register([wrongStorage]),
            defaultCodecKeys: [wrongStorage.identity.key]
        )
        assertCodecError(
            try wrongStorageConfiguration.encode(
                CodecToken(rawValue: 4),
                using: dialect,
                context: parameterContext
            ),
            equals: .storageMismatch(
                codec: wrongStorage.identity.key,
                expected: storageIdentifier(.text),
                actual: storageIdentifier(.integer),
                context: parameterContext
            )
        )
        assertCodecError(
            try wrongStorageConfiguration.decode(
                CodecToken.self,
                from: .integer(4),
                using: dialect,
                context: resultContext
            ),
            equals: .storageMismatch(
                codec: wrongStorage.identity.key,
                expected: storageIdentifier(.text),
                actual: storageIdentifier(.integer),
                context: resultContext
            )
        )
    }

    func testNonoptionalCodecRejectsSQLNullBeforeAndAfterItsClosures() throws {
        let producesNull = makeCodec(
            key: key("produces-null"),
            storage: .text,
            encode: { _ in .null },
            decode: { _ in CodecToken(rawValue: 0) }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try register([producesNull]),
            defaultCodecKeys: [producesNull.identity.key]
        )

        assertCodecError(
            try configuration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext
            ),
            equals: .unexpectedNull(
                codec: producesNull.identity.key,
                context: parameterContext
            )
        )
        assertCodecError(
            try configuration.decode(
                CodecToken.self,
                from: .null,
                using: dialect,
                context: resultContext
            ),
            equals: .unexpectedNull(
                codec: producesNull.identity.key,
                context: resultContext
            )
        )
    }

    func testClosureErrorsAreWrappedWithActiveCodecAndContext() throws {
        let bogusContext = XLValueCodingContext(
            site: .property,
            path: XLValueCodingPath("bogus")
        )
        let underlying = XLValueCodecError.unknownCodec(
            key: key("bogus"),
            source: .query,
            context: bogusContext
        )
        let codec = makeCodec(
            key: key("wrapping"),
            storage: .text,
            encode: { _ in throw underlying },
            decode: { _ in throw underlying }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try register([codec]),
            defaultCodecKeys: [codec.identity.key]
        )

        assertCodecError(
            try configuration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext
            ),
            equals: .encodingFailed(
                codec: codec.identity.key,
                context: parameterContext,
                message: String(describing: underlying)
            )
        )
        assertCodecError(
            try configuration.decode(
                CodecToken.self,
                from: .text("1"),
                using: dialect,
                context: resultContext
            ),
            equals: .decodingFailed(
                codec: codec.identity.key,
                context: resultContext,
                message: String(describing: underlying)
            )
        )
    }

    func testConfigurationSnapshotsRemainIndependentAcrossConcurrentUses() async throws {
        let first = makeMarkerCodec("snapshot-a")
        let second = makeMarkerCodec("snapshot-b")
        let firstRegistry = try register([first])
        let firstConfiguration = try XLValueCodingConfiguration(
            registry: firstRegistry,
            defaultCodecKeys: [first.identity.key]
        )
        let secondRegistry = try firstRegistry.registering(second)
        let secondConfiguration = try XLValueCodingConfiguration(
            registry: secondRegistry,
            defaultCodecKeys: [second.identity.key]
        )

        XCTAssertEqual(firstConfiguration.registry.identities, [first.identity])
        XCTAssertEqual(secondConfiguration.registry.identities.count, 2)
        XCTAssertEqual(
            try firstConfiguration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext
            ),
            .text("snapshot-a")
        )
        XCTAssertEqual(
            try secondConfiguration.encode(
                CodecToken(rawValue: 1),
                using: dialect,
                context: parameterContext
            ),
            .text("snapshot-b")
        )

        let resolvedSnapshot = try firstConfiguration.resolvedCodec(
            for: CodecToken.self,
            using: dialect,
            context: parameterContext
        )
        XCTAssertEqual(resolvedSnapshot.identity, first.identity)
        XCTAssertEqual(
            try resolvedSnapshot.encode(CodecToken(rawValue: 99)),
            .text("snapshot-a")
        )

        let values = try await withThrowingTaskGroup(
            of: CodecTestValue.self,
            returning: [CodecTestValue].self
        ) { group in
            for index in 0 ..< 32 {
                group.addTask {
                    return try resolvedSnapshot.encode(
                        CodecToken(rawValue: Int64(index))
                    )
                }
            }
            var values: [CodecTestValue] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }
        XCTAssertEqual(values, Array(repeating: .text("snapshot-a"), count: 32))
    }

    func testCodecRoundTripsAcrossFakeDriverBoundary() throws {
        let codec = makeCodec(
            key: key("driver-text"),
            storage: .text,
            encode: { .text("wire:\($0.rawValue)") },
            decode: { value in
                guard case .text(let text) = value,
                      text.hasPrefix("wire:"),
                      let rawValue = Int64(text.dropFirst("wire:".count)) else {
                    throw CodecTestFailure.invalidValue
                }
                return CodecToken(rawValue: rawValue)
            }
        )
        let configuration = try XLValueCodingConfiguration(
            registry: try register([codec]),
            defaultCodecKeys: [codec.identity.key]
        )
        let databaseIdentifier = XLDatabaseIdentifier(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000188")!
        )
        var connection = CodecTestConnection(databaseIdentifier: databaseIdentifier)
        let logical = XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: XLDialectRequirement(identity: CodecTestDialect.identity),
            sql: "SELECT :token"
        )

        var physical = try connection.prepareValidated(logical)
        let encoded = try configuration.encode(
            CodecToken(rawValue: 188),
            using: connection.dialect,
            context: parameterContext
        )
        XCTAssertEqual(encoded, .text("wire:188"))
        physical = try connection.bindValidated(
            encoded,
            to: .named("token"),
            in: physical
        )
        XCTAssertEqual(physical.bindings[.named("token")], .text("wire:188"))

        let normalizedRow = try XCTUnwrap(
            try connection.fetchOneValidated(physical)
        )
        XCTAssertEqual(normalizedRow, [.text("wire:188")])
        let decoded: CodecToken = try configuration.decode(
            CodecToken.self,
            from: try XCTUnwrap(normalizedRow.first),
            using: connection.dialect,
            context: resultContext
        )
        XCTAssertEqual(decoded, CodecToken(rawValue: 188))
    }

    private func makeMarkerCodec(
        _ marker: String
    ) -> XLValueCodec<CodecToken, CodecTestDialect> {
        makeCodec(
            key: key(marker),
            storage: .text,
            encode: { _ in .text(marker) },
            decode: { _ in CodecToken(rawValue: 0) }
        )
    }

    private func makeCodec(
        key: XLValueCodecKey,
        dialectIdentifier: XLDialectIdentifier = CodecTestDialect.identity,
        storage: CodecTestStorage,
        encode: @escaping @Sendable (CodecToken) throws -> CodecTestValue,
        decode: @escaping @Sendable (CodecTestValue) throws -> CodecToken
    ) -> XLValueCodec<CodecToken, CodecTestDialect> {
        XLValueCodec(
            key: key,
            valueTypeIdentifier: tokenTypeIdentifier,
            dialectIdentifier: dialectIdentifier,
            storageIdentifier: storageIdentifier(storage),
            encode: { value, _, _ in try encode(value) },
            decode: { value, _, _ in try decode(value) }
        )
    }

    private func register(
        _ codecs: [XLValueCodec<CodecToken, CodecTestDialect>]
    ) throws -> XLValueCodecRegistry {
        try codecs.reduce(into: XLValueCodecRegistry()) { registry, codec in
            registry = try registry.registering(codec)
        }
    }

    private func assertCodecError<T>(
        _ expression: @autoclosure () throws -> T,
        equals expected: XLValueCodecError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? XLValueCodecError, expected, file: file, line: line)
            XCTAssertFalse(error.localizedDescription.isEmpty, file: file, line: line)
        }
    }
}


private struct CodecToken: Equatable, Sendable {
    let rawValue: Int64
}


private struct OtherCodecToken: Equatable, Sendable {
    let rawValue: Int64
}


private enum CodecTestFailure: Error {
    case invalidValue
}


private enum CodecTestStorage: String, Hashable, Sendable {
    case null
    case integer
    case text
}


private enum CodecTestValue: XLDialectValue {
    case null
    case integer(Int64)
    case text(String)

    var storageType: CodecTestStorage {
        switch self {
        case .null:
            return .null
        case .integer:
            return .integer
        case .text:
            return .text
        }
    }
}


private struct CodecTestDialect: XLValueCodingDialect {

    typealias Value = CodecTestValue

    static let identity = XLDialectIdentifier(rawValue: "codec-test")

    let descriptor: XLDialectDescriptor

    init(identity: XLDialectIdentifier = Self.identity) {
        self.descriptor = XLDialectDescriptor(identity: identity)
    }

    func formatIdentifier(_ identifier: String) -> String {
        "\"\(identifier)\""
    }

    func formatQualifiedIdentifier(_ components: [String]) -> String {
        components.map(formatIdentifier).joined(separator: ".")
    }

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        switch placeholder {
        case .named(let name):
            return ":\(name)"
        case .indexed(let index):
            return "?\(index + 1)"
        }
    }

    func isNull(_ value: CodecTestValue) -> Bool {
        value == .null
    }

    var nullValue: CodecTestValue {
        .null
    }

    func stableStorageIdentifier(
        for value: CodecTestValue
    ) -> XLValueStorageIdentifier {
        storageIdentifier(value.storageType)
    }
}


private struct AlternateCodecTestDialect: XLValueCodingDialect {

    typealias Value = CodecTestValue

    let descriptor = XLDialectDescriptor(identity: CodecTestDialect.identity)

    func formatIdentifier(_ identifier: String) -> String {
        identifier
    }

    func formatQualifiedIdentifier(_ components: [String]) -> String {
        components.joined(separator: ".")
    }

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        "?"
    }

    func isNull(_ value: CodecTestValue) -> Bool {
        value == .null
    }

    var nullValue: CodecTestValue {
        .null
    }

    func stableStorageIdentifier(
        for value: CodecTestValue
    ) -> XLValueStorageIdentifier {
        storageIdentifier(value.storageType)
    }
}


private struct CodecTestPhysicalStatement {
    let logical: XLLogicalPreparedStatement
    var bindings: [XLBindingKey: CodecTestValue]
}


private struct CodecTestConnection: XLDatabaseDriverConnection {

    typealias Dialect = CodecTestDialect
    typealias PhysicalStatement = CodecTestPhysicalStatement

    let driverIdentifier = XLDriverIdentifier(rawValue: "codec-test-driver")
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect = CodecTestDialect()

    mutating func preparePhysical(
        _ statement: XLValidatedLogicalPreparedStatement
    ) throws -> CodecTestPhysicalStatement {
        CodecTestPhysicalStatement(
            logical: statement.logicalStatement,
            bindings: [:]
        )
    }

    mutating func bind(
        _ value: CodecTestValue,
        to key: XLBindingKey,
        in statement: CodecTestPhysicalStatement
    ) throws -> CodecTestPhysicalStatement {
        var copy = statement
        copy.bindings[key] = value
        return copy
    }

    mutating func fetchAll(
        _ statement: CodecTestPhysicalStatement
    ) throws -> [[CodecTestValue]] {
        try fetchOne(statement).map { [$0] } ?? []
    }

    mutating func fetchOne(
        _ statement: CodecTestPhysicalStatement
    ) throws -> [CodecTestValue]? {
        statement.bindings[.named("token")].map { [$0] }
    }

    mutating func execute(_ statement: CodecTestPhysicalStatement) throws {
        _ = statement
    }
}


private let tokenTypeIdentifier = XLValueTypeIdentifier(
    rawValue: "swiftql.tests.codec-token"
)


private func key(_ suffix: String, _ version: UInt = 1) -> XLValueCodecKey {
    XLValueCodecKey(id: "test.\(suffix)", version: version)
}


private func storageIdentifier(
    _ storage: CodecTestStorage
) -> XLValueStorageIdentifier {
    XLValueStorageIdentifier(rawValue: storage.rawValue)
}


private func codecKeyOrder(_ lhs: XLValueCodecKey, _ rhs: XLValueCodecKey) -> Bool {
    if lhs.id != rhs.id {
        return lhs.id < rhs.id
    }
    return lhs.version < rhs.version
}
