import Foundation
import GRDB
import XCTest

@testable import SwiftQL


final class StaticQueryDescriptorGRDBTests: XCTestCase {

    func testDescriptorPreparedBeforeDatabaseExecutesEveryCardinality() throws {
        let contract = try makeContract()
        let definitions = try makeDefinitions(contract: contract)

        // All descriptor state exists before a database or connection pool is
        // created. Preparation adds only the database-bound executor.
        let fixture = try makeDatabase(configuration: contract.configuration)
        defer { fixture.tearDown() }

        let emptyBindings = XLInvocationBindings<XLSQLiteValue>(layout: .empty)
        let create = try fixture.database.prepareInvocation(
            with: definitions.create
        )
        requireSendable(create)
        try create.execute(bindings: emptyBindings)

        let insert = try fixture.database.prepareInvocation(
            with: definitions.insert
        )
        let insertParameter = try insert.preparedParameter(
            DescriptorToken.self,
            identifiedBy: definitions.parameterIdentity
        )
        for rawValue in [7, 7, 9] {
            try insert.execute(
                bindings: try tokenPacket(
                    rawValue,
                    parameter: insertParameter,
                    layout: insert.parameterLayout
                )
            )
        }

        let many = try fixture.database.prepareInvocation(with: definitions.many)
        let manyCodec = try many.resultCodec(
            DescriptorToken.self,
            identifiedBy: definitions.resultIdentity
        )
        let manyRows = try many.fetchAllValues(bindings: emptyBindings)
        XCTAssertEqual(
            try manyRows.map { try manyCodec.decode($0[0]).rawValue },
            [7, 7, 9]
        )

        let zeroOrOne = try fixture.database.prepareInvocation(
            with: definitions.zeroOrOne
        )
        let zeroOrOneParameter = try zeroOrOne.preparedParameter(
            DescriptorToken.self,
            identifiedBy: definitions.parameterIdentity
        )
        let zeroOrOneCodec = try zeroOrOne.resultCodec(
            DescriptorToken.self,
            identifiedBy: definitions.resultIdentity
        )
        let missing = try zeroOrOne.fetchZeroOrOneValues(
            bindings: try tokenPacket(
                42,
                parameter: zeroOrOneParameter,
                layout: zeroOrOne.parameterLayout
            )
        )
        XCTAssertNil(missing)
        let one = try XCTUnwrap(
            zeroOrOne.fetchZeroOrOneValues(
                bindings: try tokenPacket(
                    9,
                    parameter: zeroOrOneParameter,
                    layout: zeroOrOne.parameterLayout
                )
            )
        )
        XCTAssertEqual(try zeroOrOneCodec.decode(one[0]).rawValue, 9)
        XCTAssertThrowsError(
            try zeroOrOne.fetchZeroOrOneValues(
                bindings: try tokenPacket(
                    7,
                    parameter: zeroOrOneParameter,
                    layout: zeroOrOne.parameterLayout
                )
            )
        ) { error in
            guard case .rowCountMismatch(_, .zeroOrOne, 2) =
                error as? GRDBStaticQueryError else {
                return XCTFail("Expected zero-or-one overflow, received \(error)")
            }
        }

        let exactlyOne = try fixture.database.prepareInvocation(
            with: definitions.exactlyOne
        )
        let exactlyOneParameter = try exactlyOne.preparedParameter(
            DescriptorToken.self,
            identifiedBy: definitions.parameterIdentity
        )
        XCTAssertEqual(
            try exactlyOne.fetchExactlyOneValues(
                bindings: try tokenPacket(
                    9,
                    parameter: exactlyOneParameter,
                    layout: exactlyOne.parameterLayout
                )
            )[0],
            .integer(9)
        )
        for (value, expectedCount) in [(42, 0), (7, 2)] {
            XCTAssertThrowsError(
                try exactlyOne.fetchExactlyOneValues(
                    bindings: try tokenPacket(
                        value,
                        parameter: exactlyOneParameter,
                        layout: exactlyOne.parameterLayout
                    )
                )
            ) { error in
                guard case .rowCountMismatch(_, .exactlyOne, let actualCount) =
                    error as? GRDBStaticQueryError else {
                    return XCTFail("Expected exactly-one row-count failure, received \(error)")
                }
                XCTAssertEqual(actualCount, expectedCount)
            }
        }

        XCTAssertThrowsError(
            try many.fetchExactlyOneValues(bindings: emptyBindings)
        ) { error in
            guard case .operationCardinalityMismatch(_, .exactlyOne, .many) =
                error as? GRDBStaticQueryError else {
                return XCTFail("Expected cardinality mismatch, received \(error)")
            }
        }
    }

    func testOnePreparedDescriptorExecutesContextualPacketsConcurrently() async throws {
        let contract = try makeContract()
        let definition = try makeScalarDefinition(contract: contract)
        let identity = definition.identity
        let sql = definition.statement.sql

        let fixture = try makeDatabase(configuration: contract.configuration)
        defer { fixture.tearDown() }

        let prepared = try fixture.database.prepareInvocation(with: definition)
        let parameter = try prepared.preparedParameter(
            DescriptorToken.self,
            identifiedBy: contract.parameterIdentity
        )
        let resultCodec = try prepared.resultCodec(
            DescriptorToken.self,
            identifiedBy: contract.resultIdentity
        )
        requireSendable(prepared)
        requireSendable(parameter)
        requireSendable(resultCodec)

        let values = try await withThrowingTaskGroup(
            of: Int64.self,
            returning: [Int64].self
        ) { group in
            for rawValue in 0 ..< 32 {
                group.addTask {
                    let packet = try tokenPacket(
                        rawValue,
                        parameter: parameter,
                        layout: prepared.parameterLayout
                    )
                    let row = try prepared.fetchExactlyOneValues(
                        bindings: packet
                    )
                    return try resultCodec.decode(row[0]).rawValue
                }
            }

            var results: [Int64] = []
            for try await value in group {
                results.append(value)
            }
            return results
        }

        XCTAssertEqual(Set(values), Set((0 ..< 32).map(Int64.init)))
        XCTAssertEqual(definition.identity, identity)
        XCTAssertEqual(definition.statement.sql, sql)
    }

    func testPreparationRejectsDialectAndCodingSnapshotMismatches() throws {
        let contract = try makeContract()
        let definition = try makeScalarDefinition(contract: contract)

        let emptyConfiguration = try XLValueCodingConfiguration()
        let emptyFixture = try makeDatabase(configuration: emptyConfiguration)
        defer { emptyFixture.tearDown() }
        XCTAssertThrowsError(
            try emptyFixture.database.prepareInvocation(with: definition)
        ) { error in
            guard case .preparedCodecUnavailable? =
                error as? XLInvocationBindingError else {
                return XCTFail("Expected unavailable parameter codec, received \(error)")
            }
        }

        let mismatchedCodec = XLValueCodec<DescriptorToken, XLSQLiteDialect>(
            key: contract.codec.identity.key,
            valueTypeIdentifier: contract.codec.identity.valueTypeIdentifier,
            dialectIdentifier: XLSQLiteDialect.identity,
            storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
            encode: { value, _, _ in .text(String(value.rawValue)) },
            decode: { value, _, _ in
                guard case .text(let text) = value,
                      let rawValue = Int64(text) else {
                    throw DescriptorFixtureError.invalidValue
                }
                return DescriptorToken(rawValue: rawValue)
            }
        )
        let mismatchedConfiguration = try XLValueCodingConfiguration(
            registry: XLValueCodecRegistry().registering(mismatchedCodec),
            defaultCodecKeys: [mismatchedCodec.identity.key]
        )
        let mismatchedFixture = try makeDatabase(
            configuration: mismatchedConfiguration
        )
        defer { mismatchedFixture.tearDown() }
        XCTAssertThrowsError(
            try mismatchedFixture.database.prepareInvocation(with: definition)
        ) { error in
            guard case .preparedCodecIdentityMismatch? =
                error as? XLInvocationBindingError else {
                return XCTFail("Expected mismatched parameter codec, received \(error)")
            }
        }

        let resultOnly = try makeResultOnlyDefinition(contract: contract)
        XCTAssertThrowsError(
            try emptyFixture.database.prepareInvocation(with: resultOnly)
        ) { error in
            guard case .resultCodecUnavailable? =
                error as? GRDBStaticQueryError else {
                return XCTFail("Expected unavailable result codec, received \(error)")
            }
        }

        let foreignStatement = XLStaticStatementDefinition(
            sql: "SELECT 1",
            dialectRequirement: XLDialectRequirement(
                identity: XLDialectIdentifier(rawValue: "foreign")
            )
        )
        let foreignDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "foreign"],
                version: 1
            ),
            statement: foreignStatement,
            parameters: [],
            results: .empty,
            cardinality: .command
        )
        let validFixture = try makeDatabase(
            configuration: contract.configuration
        )
        defer { validFixture.tearDown() }
        XCTAssertThrowsError(
            try validFixture.database.prepareInvocation(with: foreignDescriptor)
        ) { error in
            guard case .dialectMismatch(let expected, let actual) =
                error as? XLDatabaseContractError else {
                return XCTFail("Expected dialect mismatch, received \(error)")
            }
            XCTAssertEqual(expected, XLDialectIdentifier(rawValue: "foreign"))
            XCTAssertEqual(actual, XLSQLiteDialect.identity)
        }
    }

    func testIntrinsicParameterStorageMismatchFailsBeforeGRDBExecution() throws {
        let parameterIdentity = try XLQuerySlotIdentity(
            path: ["tests", "intrinsic", "parameter"]
        )
        let resultIdentity = try XLQuerySlotIdentity(
            path: ["tests", "intrinsic", "result"]
        )
        let storage = XLValueStorageIdentifier(rawValue: "integer")
        let slot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .named("value"),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("value")
            )
        )
        let layout = try XLParameterLayout(slots: [slot])
        let result = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(0),
            identity: resultIdentity,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            storageIdentifier: storage,
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath("value")
            )
        )
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-query", "intrinsic-storage"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "SELECT :value",
                dialectRequirement: sqliteRequirement,
                parameterLayout: layout
            ),
            parameters: [
                XLStaticQueryParameterMetadata(
                    identity: parameterIdentity,
                    slot: slot,
                    storageIdentifier: storage
                )
            ],
            results: try XLStaticQueryResultMetadata(slots: [result]),
            cardinality: .exactlyOne
        )

        let fixture = try makeDatabase(
            configuration: XLValueCodingConfiguration()
        )
        defer { fixture.tearDown() }
        let prepared = try fixture.database.prepareInvocation(with: descriptor)
        let invalidPacket = try XLInvocationBindings(
            layout: layout,
            bindings: [
                try XLInvocationBinding(
                    slot: slot,
                    value: XLSQLiteValue.text("82")
                )
            ]
        )
        XCTAssertThrowsError(
            try prepared.fetchExactlyOneValues(bindings: invalidPacket)
        ) { error in
            guard case .parameterStorageMismatch(
                _,
                let parameter,
                let actual
            ) = error as? GRDBStaticQueryError else {
                return XCTFail("Expected intrinsic storage mismatch, received \(error)")
            }
            XCTAssertEqual(parameter.identity, parameterIdentity)
            XCTAssertEqual(actual, XLValueStorageIdentifier(rawValue: "text"))
        }

        let validPacket = try XLInvocationBindings(
            layout: layout,
            bindings: [
                try XLInvocationBinding(
                    slot: slot,
                    value: XLSQLiteValue.integer(82)
                )
            ]
        )
        XCTAssertEqual(
            try prepared.fetchExactlyOneValues(bindings: validPacket),
            [.integer(82)]
        )
    }

    func testPreparationRejectsUnsupportedSQLiteStorageMetadata() throws {
        let unsupported = XLValueStorageIdentifier(
            rawValue: "tests.unsupported-sqlite-storage"
        )
        let parameterIdentity = try XLQuerySlotIdentity(
            path: ["tests", "unsupported-storage", "parameter"]
        )
        let parameterSlot = XLParameterSlot(
            index: XLLogicalParameterIndex(0),
            key: .named("value"),
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            codingContext: XLValueCodingContext(
                site: .parameter,
                path: XLValueCodingPath("value")
            )
        )
        let parameterLayout = try XLParameterLayout(slots: [parameterSlot])
        let parameterMetadata = XLStaticQueryParameterMetadata(
            identity: parameterIdentity,
            slot: parameterSlot,
            storageIdentifier: unsupported
        )
        let parameterDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-query", "unsupported-parameter-storage"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "SELECT :value",
                dialectRequirement: sqliteRequirement,
                parameterLayout: parameterLayout
            ),
            parameters: [parameterMetadata],
            results: .empty,
            cardinality: .command
        )

        let resultIdentity = try XLQuerySlotIdentity(
            path: ["tests", "unsupported-storage", "result"]
        )
        let resultSlot = XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(0),
            identity: resultIdentity,
            valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
            valueTypeName: String(reflecting: Int.self),
            nullability: .required,
            codecIdentity: nil,
            storageIdentifier: unsupported,
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath("value")
            )
        )
        let emptyManyDescriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "static-query", "unsupported-result-storage"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(
                sql: "SELECT 1 WHERE 0",
                dialectRequirement: sqliteRequirement
            ),
            parameters: [],
            results: try XLStaticQueryResultMetadata(slots: [resultSlot]),
            cardinality: .many
        )

        let fixture = try makeDatabase(
            configuration: XLValueCodingConfiguration()
        )
        defer { fixture.tearDown() }

        XCTAssertThrowsError(
            try fixture.database.prepareInvocation(with: parameterDescriptor)
        ) { error in
            guard case .unsupportedParameterStorage(
                let identity,
                let parameter
            ) = error as? GRDBStaticQueryError else {
                return XCTFail(
                    "Expected unsupported parameter storage, received \(error)"
                )
            }
            XCTAssertEqual(identity, parameterDescriptor.identity)
            XCTAssertEqual(parameter, parameterMetadata)
        }

        XCTAssertThrowsError(
            try fixture.database.prepareInvocation(with: emptyManyDescriptor)
        ) { error in
            guard case .unsupportedResultStorage(let identity, let slot) =
                error as? GRDBStaticQueryError else {
                return XCTFail(
                    "Expected unsupported result storage, received \(error)"
                )
            }
            XCTAssertEqual(identity, emptyManyDescriptor.identity)
            XCTAssertEqual(slot, resultSlot)
        }
    }

    func testRawRowsAreValidatedAgainstStaticResultMetadata() throws {
        let contract = try makeContract()
        let results = try tokenResults(contract: contract)
        func descriptor(
            named name: String,
            sql: String
        ) throws -> XLStaticQueryDescriptor {
            try XLStaticQueryDescriptor(
                definitionIdentity: XLQueryDefinitionIdentity(
                    path: ["tests", "static-query", "invalid-result", name],
                    version: 1
                ),
                statement: XLStaticStatementDefinition(
                    sql: sql,
                    dialectRequirement: sqliteRequirement
                ),
                parameters: [],
                results: results,
                cardinality: .exactlyOne
            )
        }

        let nullDescriptor = try descriptor(named: "null", sql: "SELECT NULL")
        let storageDescriptor = try descriptor(
            named: "storage",
            sql: "SELECT 'wrong'"
        )
        let columnsDescriptor = try descriptor(
            named: "columns",
            sql: "SELECT 1, 2"
        )

        let fixture = try makeDatabase(configuration: contract.configuration)
        defer { fixture.tearDown() }
        let emptyBindings = XLInvocationBindings<XLSQLiteValue>(layout: .empty)

        let nullPrepared = try fixture.database.prepareInvocation(
            with: nullDescriptor
        )
        XCTAssertThrowsError(
            try nullPrepared.fetchExactlyOneValues(bindings: emptyBindings)
        ) { error in
            guard case .nullForRequiredResult(_, let slot) =
                error as? GRDBStaticQueryError else {
                return XCTFail("Expected required-result NULL failure, received \(error)")
            }
            XCTAssertEqual(slot.identity, contract.resultIdentity)
        }

        let storagePrepared = try fixture.database.prepareInvocation(
            with: storageDescriptor
        )
        XCTAssertThrowsError(
            try storagePrepared.fetchExactlyOneValues(bindings: emptyBindings)
        ) { error in
            guard case .resultStorageMismatch(_, let slot, let actual) =
                error as? GRDBStaticQueryError else {
                return XCTFail("Expected result storage failure, received \(error)")
            }
            XCTAssertEqual(slot.identity, contract.resultIdentity)
            XCTAssertEqual(actual, XLValueStorageIdentifier(rawValue: "text"))
        }

        let columnsPrepared = try fixture.database.prepareInvocation(
            with: columnsDescriptor
        )
        XCTAssertThrowsError(
            try columnsPrepared.fetchExactlyOneValues(bindings: emptyBindings)
        ) { error in
            guard case .resultColumnCountMismatch(_, 0, 1, 2) =
                error as? GRDBStaticQueryError else {
                return XCTFail("Expected result column-count failure, received \(error)")
            }
        }
    }
}


private struct DescriptorContract {
    let dialect: XLSQLiteDialect
    let codec: XLValueCodec<DescriptorToken, XLSQLiteDialect>
    let configuration: XLValueCodingConfiguration
    let parameterIdentity: XLQuerySlotIdentity
    let resultIdentity: XLQuerySlotIdentity
}


private struct DescriptorDefinitions {
    let create: XLStaticQueryDescriptor
    let insert: XLStaticQueryDescriptor
    let exactlyOne: XLStaticQueryDescriptor
    let zeroOrOne: XLStaticQueryDescriptor
    let many: XLStaticQueryDescriptor
    let parameterIdentity: XLQuerySlotIdentity
    let resultIdentity: XLQuerySlotIdentity
}


private struct DescriptorToken: Equatable, Sendable {
    let rawValue: Int64
}


private struct DescriptorDatabaseFixture {
    let directoryURL: URL
    let database: GRDBDatabase

    func tearDown() {
        try? database.databasePool.close()
        try? FileManager.default.removeItem(at: directoryURL)
    }
}


private enum DescriptorFixtureError: Error {
    case invalidValue
}


private func makeContract() throws -> DescriptorContract {
    let dialect = XLSQLiteDialect()
    let codec = XLValueCodec<DescriptorToken, XLSQLiteDialect>(
        key: XLValueCodecKey(id: "tests.static-query.token", version: 1),
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "tests.DescriptorToken"
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
        encode: { value, _, _ in .integer(value.rawValue) },
        decode: { value, _, _ in
            guard case .integer(let rawValue) = value else {
                throw DescriptorFixtureError.invalidValue
            }
            return DescriptorToken(rawValue: rawValue)
        }
    )
    let configuration = try XLValueCodingConfiguration(
        registry: XLValueCodecRegistry().registering(codec),
        defaultCodecKeys: [codec.identity.key]
    )
    return try DescriptorContract(
        dialect: dialect,
        codec: codec,
        configuration: configuration,
        parameterIdentity: XLQuerySlotIdentity(
            path: ["tests", "parameter", "token"]
        ),
        resultIdentity: XLQuerySlotIdentity(
            path: ["tests", "result", "token"]
        )
    )
}


private func makeDefinitions(
    contract: DescriptorContract
) throws -> DescriptorDefinitions {
    let emptyResults = XLStaticQueryResultMetadata.empty
    let create = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "create"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(
            sql: "CREATE TABLE static_query_items (id INTEGER PRIMARY KEY, token INTEGER NOT NULL)",
            dialectRequirement: sqliteRequirement
        ),
        parameters: [],
        results: emptyResults,
        cardinality: .command
    )

    let insertParameter = try preparedTokenParameter(
        contract: contract,
        contextPath: ["insert", "token"]
    )
    let insertLayout = try XLParameterLayout(slots: [insertParameter.slot])
    let insert = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "insert"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(
            sql: "INSERT INTO static_query_items (token) VALUES (:token)",
            dialectRequirement: sqliteRequirement,
            entities: ["static_query_items"],
            parameterLayout: insertLayout
        ),
        parameters: [parameterMetadata(
            contract: contract,
            parameter: insertParameter
        )],
        results: emptyResults,
        cardinality: .command
    )

    let filterParameter = try preparedTokenParameter(
        contract: contract,
        contextPath: ["filter", "token"]
    )
    let filterLayout = try XLParameterLayout(slots: [filterParameter.slot])
    let filterParameters = [parameterMetadata(
        contract: contract,
        parameter: filterParameter
    )]
    let results = try tokenResults(contract: contract)
    let querySQL = "SELECT token FROM static_query_items WHERE token = :token ORDER BY id"
    let exactlyOne = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "exactly-one"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(
            sql: querySQL,
            dialectRequirement: sqliteRequirement,
            entities: ["static_query_items"],
            parameterLayout: filterLayout
        ),
        parameters: filterParameters,
        results: results,
        cardinality: .exactlyOne
    )
    let zeroOrOne = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "zero-or-one"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(
            sql: querySQL,
            dialectRequirement: sqliteRequirement,
            entities: ["static_query_items"],
            parameterLayout: filterLayout
        ),
        parameters: filterParameters,
        results: results,
        cardinality: .zeroOrOne
    )
    let many = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "many"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(
            sql: "SELECT token FROM static_query_items ORDER BY id",
            dialectRequirement: sqliteRequirement,
            entities: ["static_query_items"]
        ),
        parameters: [],
        results: results,
        cardinality: .many
    )
    return DescriptorDefinitions(
        create: create,
        insert: insert,
        exactlyOne: exactlyOne,
        zeroOrOne: zeroOrOne,
        many: many,
        parameterIdentity: contract.parameterIdentity,
        resultIdentity: contract.resultIdentity
    )
}


private func makeScalarDefinition(
    contract: DescriptorContract
) throws -> XLStaticQueryDescriptor {
    let parameterContext = XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath(["scalar", "token"])
    )
    let resolved = try contract.configuration.resolvedCodec(
        for: DescriptorToken.self,
        using: contract.dialect,
        context: parameterContext
    )
    let reference = XLContextualBindingReference<
        DescriptorToken,
        Int,
        XLSQLiteDialect
    >(
        key: .named("token"),
        codec: resolved
    )
    let encoding = try XLiteEncoder(dialect: contract.dialect)
        .makeValidatedSQL(sql { _ in Select(reference) })
    let statement = try XLStaticStatementDefinition(validating: encoding)
    let parameter = try reference.staticQueryParameter(
        identity: contract.parameterIdentity,
        in: statement.parameterLayout
    )
    return try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "scalar"],
            version: 1
        ),
        statement: statement,
        parameters: [parameter],
        results: tokenResults(contract: contract),
        cardinality: .exactlyOne
    )
}


private func makeResultOnlyDefinition(
    contract: DescriptorContract
) throws -> XLStaticQueryDescriptor {
    try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["tests", "static-query", "result-only"],
            version: 1
        ),
        statement: XLStaticStatementDefinition(
            sql: "SELECT 1",
            dialectRequirement: sqliteRequirement
        ),
        parameters: [],
        results: tokenResults(contract: contract),
        cardinality: .many
    )
}


private func preparedTokenParameter(
    contract: DescriptorContract,
    contextPath: [String]
) throws -> XLPreparedParameter<DescriptorToken, XLSQLiteDialect> {
    let codec = try contract.configuration.resolvedCodec(
        for: DescriptorToken.self,
        using: contract.dialect,
        context: XLValueCodingContext(
            site: .parameter,
            path: XLValueCodingPath(contextPath)
        )
    )
    return XLPreparedParameter(
        index: XLLogicalParameterIndex(0),
        key: .named("token"),
        nullability: .required,
        codec: codec
    )
}


private func parameterMetadata(
    contract: DescriptorContract,
    parameter: XLPreparedParameter<DescriptorToken, XLSQLiteDialect>
) -> XLStaticQueryParameterMetadata {
    XLStaticQueryParameterMetadata(
        identity: contract.parameterIdentity,
        slot: parameter.slot,
        storageIdentifier: parameter.codecIdentity.storageIdentifier
    )
}


private func tokenResults(
    contract: DescriptorContract
) throws -> XLStaticQueryResultMetadata {
    try XLStaticQueryResultMetadata(slots: [
        XLStaticQueryResultSlot(
            index: XLLogicalResultIndex(0),
            identity: contract.resultIdentity,
            valueTypeIdentifier: contract.codec.identity.valueTypeIdentifier,
            valueTypeName: String(reflecting: DescriptorToken.self),
            nullability: .required,
            codecIdentity: contract.codec.identity,
            storageIdentifier: contract.codec.identity.storageIdentifier,
            codingContext: XLValueCodingContext(
                site: .result,
                path: XLValueCodingPath(["result", "token"])
            )
        )
    ])
}


private func tokenPacket(
    _ rawValue: Int,
    parameter: XLPreparedParameter<DescriptorToken, XLSQLiteDialect>,
    layout: XLParameterLayout
) throws -> XLInvocationBindings<XLSQLiteValue> {
    try tokenPacket(
        Int64(rawValue),
        parameter: parameter,
        layout: layout
    )
}


private func tokenPacket(
    _ rawValue: Int64,
    parameter: XLPreparedParameter<DescriptorToken, XLSQLiteDialect>,
    layout: XLParameterLayout
) throws -> XLInvocationBindings<XLSQLiteValue> {
    try XLInvocationBindings(
        layout: layout,
        bindings: [parameter.encode(DescriptorToken(rawValue: rawValue))]
    )
}


private func makeDatabase(
    configuration: XLValueCodingConfiguration
) throws -> DescriptorDatabaseFixture {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftql-static-query-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false
    )
    let databasePool = try DatabasePool(
        path: directoryURL.appendingPathComponent("database.sqlite").path
    )
    let database = try GRDBDatabase(
        databasePool: databasePool,
        codingConfiguration: configuration,
        formatter: XLiteFormatter(),
        logger: nil
    )
    return DescriptorDatabaseFixture(
        directoryURL: directoryURL,
        database: database
    )
}


private var sqliteRequirement: XLDialectRequirement {
    XLDialectRequirement(
        identity: XLSQLiteDialect.identity,
        capabilities: [.namedBindings]
    )
}


private func requireSendable<T: Sendable>(_: T) {}
