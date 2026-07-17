import Foundation
import SwiftQL
import SwiftQLCore

#if compiler(<6.0)
#error("The downstream compatibility fixture must use the supported Swift 6 compiler.")
#endif

#if swift(>=6.0)
#error("The downstream compatibility fixture must remain in Swift 5 language mode.")
#endif

@SQLTable(name: "DownstreamPerson")
struct Person: Equatable {
    let id: String
    let name: String
    let age: Int
}

@SQLResult
struct PersonSummary: Equatable {
    let name: String
    let age: Int
}

private struct DownstreamToken: Equatable {
    let rawValue: Int64
}

enum FixtureError: Error {
    case invalidCoreContract
    case invalidCodecValue(XLSQLiteValue)
    case unexpectedPacketResult(Int?)
    case unexpectedStaticQueryResult(Int64)
    case unexpectedResult(PersonSummary?)
}

private func validateCoreContractProduct() throws -> XLValueCodingConfiguration {
    let dialect = XLSQLiteDialect()
    guard dialect.descriptor.identity == XLSQLiteDialect.identity,
          dialect.descriptor.capabilities.contains(.namedBindings),
          dialect.formatPlaceholder(.named("id")) == ":id"
    else {
        throw FixtureError.invalidCoreContract
    }

    let codecKey = XLValueCodecKey(
        id: "swiftql.downstream.token.integer",
        version: 1
    )
    let codec = XLValueCodec<DownstreamToken, XLSQLiteDialect>(
        key: codecKey,
        valueTypeIdentifier: XLValueTypeIdentifier(
            rawValue: "swiftql.downstream.token"
        ),
        dialectIdentifier: XLSQLiteDialect.identity,
        storageIdentifier: XLValueStorageIdentifier(
            rawValue: XLSQLiteStorageClass.integer.rawValue
        ),
        encode: { token, _, _ in
            .integer(token.rawValue)
        },
        decode: { value, _, _ in
            guard case .integer(let rawValue) = value else {
                throw FixtureError.invalidCodecValue(value)
            }
            return DownstreamToken(rawValue: rawValue)
        }
    )
    let registry = try XLValueCodecRegistry().registering(codec)
    let configuration = try XLValueCodingConfiguration(
        registry: registry,
        defaultCodecKeys: [codecKey]
    )
    let context = XLValueCodingContext(
        site: .parameter,
        path: XLValueCodingPath("downstream.token")
    )
    let token = DownstreamToken(rawValue: 42)
    let parameterCodec = try configuration.resolvedCodec(
        for: DownstreamToken.self,
        using: dialect,
        context: context
    )
    let resultCodec = try configuration.resolvedCodec(
        for: DownstreamToken.self,
        using: dialect,
        context: XLValueCodingContext(
            site: .result,
            path: XLValueCodingPath("downstream.token")
        )
    )
    let encoded = try parameterCodec.encode(token)
    let decoded = try resultCodec.decode(encoded)
    let encodedNil = try configuration.encodeOptional(
        Optional<DownstreamToken>.none,
        using: dialect,
        context: context
    )
    guard encoded == .integer(42),
          decoded == token,
          encodedNil == .null,
          configuration.registry.identity(for: codecKey)?.stableIdentityComponents == [
              "swiftql.downstream.token.integer",
              "1",
              "swiftql.downstream.token",
              "sqlite",
              "integer",
          ]
    else {
        throw FixtureError.invalidCoreContract
    }
    return configuration
}

private func executeFixture(
    databaseURL: URL,
    codingConfiguration: XLValueCodingConfiguration
) throws -> PersonSummary? {
    let database = try GRDBDatabase(
        url: databaseURL,
        codingConfiguration: codingConfiguration,
        logger: nil
    )
    guard database.codingConfiguration.registry.identities
        == codingConfiguration.registry.identities else {
        throw FixtureError.invalidCoreContract
    }
    try database.makeRequest(with: sqlCreate(Person.self)).execute()
    try database.makeRequest(
        with: sqlInsert(Person(id: "ada", name: "Ada Lovelace", age: 36))
    ).execute()
    try database.makeRequest(
        with: sqlInsert(Person(id: "grace", name: "Grace Hopper", age: 85))
    ).execute()

    let token = try database.contextualBinding(
        DownstreamToken.self,
        expressedAs: Int.self,
        named: "token"
    )
    let tokenRequest = database.makeRequest(
        with: sql { _ in Select(token) }
    )
    let tokenPacket = try XLInvocationBindings<XLSQLiteValue>(
        layout: tokenRequest.parameterLayout,
        bindings: [
            token.encode(
                DownstreamToken(rawValue: 42),
                in: tokenRequest.parameterLayout
            ),
        ]
    )
    let tokenResult = try tokenRequest.fetchOne(bindings: tokenPacket)
    guard tokenResult == 42 else {
        throw FixtureError.unexpectedPacketResult(tokenResult)
    }

    let staticDialect = XLSQLiteDialect()
    let staticEncoding = try XLiteEncoder(dialect: staticDialect)
        .makeValidatedSQL(sql { _ in Select(token) })
    let staticStatement = try XLStaticStatementDefinition(
        validating: staticEncoding
    )
    let staticParameterIdentity = try XLQuerySlotIdentity(
        path: ["downstream", "parameter", "token"]
    )
    let staticResultIdentity = try XLQuerySlotIdentity(
        path: ["downstream", "result", "token"]
    )
    let staticParameter = try token.staticQueryParameter(
        identity: staticParameterIdentity,
        in: staticStatement.parameterLayout
    )
    let staticResultContext = XLValueCodingContext(
        site: .result,
        path: XLValueCodingPath("downstream.token")
    )
    let staticResultCodec = try codingConfiguration.resolvedCodec(
        for: DownstreamToken.self,
        using: staticDialect,
        context: staticResultContext
    )
    let staticDescriptor = try XLStaticQueryDescriptor(
        definitionIdentity: XLQueryDefinitionIdentity(
            path: ["downstream", "token-round-trip"],
            version: 1
        ),
        statement: staticStatement,
        parameters: [staticParameter],
        results: try XLStaticQueryResultMetadata(slots: [
            XLStaticQueryResultSlot(
                index: XLLogicalResultIndex(0),
                identity: staticResultIdentity,
                valueTypeIdentifier: staticResultCodec.identity
                    .valueTypeIdentifier,
                valueTypeName: String(reflecting: DownstreamToken.self),
                nullability: .required,
                codecIdentity: staticResultCodec.identity,
                storageIdentifier: staticResultCodec.identity
                    .storageIdentifier,
                codingContext: staticResultContext
            )
        ]),
        cardinality: .exactlyOne
    )
    let preparedStaticQuery = try database.prepareInvocation(
        with: staticDescriptor
    )
    let preparedStaticParameter = try preparedStaticQuery.preparedParameter(
        DownstreamToken.self,
        identifiedBy: staticParameterIdentity
    )
    let staticPacket = try XLInvocationBindings<XLSQLiteValue>(
        layout: preparedStaticQuery.parameterLayout,
        bindings: [
            try preparedStaticParameter.encode(
                DownstreamToken(rawValue: 84)
            )
        ]
    ).validatingComplete()
    let staticRow = try preparedStaticQuery.fetchExactlyOneValues(
        bindings: staticPacket
    )
    let preparedStaticResultCodec = try preparedStaticQuery.resultCodec(
        DownstreamToken.self,
        identifiedBy: staticResultIdentity
    )
    let staticResult = try preparedStaticResultCodec.decode(staticRow[0])
    guard staticResult == DownstreamToken(rawValue: 84) else {
        throw FixtureError.unexpectedStaticQueryResult(staticResult.rawValue)
    }

    let id = XLNamedBindingReference<String>(name: "id")
    let statement = sql { schema in
        let person = schema.table(Person.self)
        Select(
            PersonSummary.columns(
                name: person.name,
                age: person.age
            )
        )
        From(person)
        Where(person.id == id)
    }
    var request = database.makeRequest(with: statement)
    request.set(id, "grace")
    return try request.fetchOne()
}

private func runFixture() throws {
    let codingConfiguration = try validateCoreContractProduct()

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftql-swift5-client-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    // Preserve the original pre-1.2 initializer call as a Swift 5 source-
    // compatibility check alongside the new configuration overload below.
    let legacyDatabase = try GRDBDatabase(
        url: directory.appendingPathComponent("legacy.sqlite"),
        logger: nil
    )
    guard legacyDatabase.codingConfiguration.registry.identities.isEmpty else {
        throw FixtureError.invalidCoreContract
    }
    try legacyDatabase.databasePool.close()

    let result = try executeFixture(
        databaseURL: directory.appendingPathComponent("fixture.sqlite"),
        codingConfiguration: codingConfiguration
    )
    guard result == PersonSummary(name: "Grace Hopper", age: 85) else {
        throw FixtureError.unexpectedResult(result)
    }
}

try runFixture()
print("SWIFTQL_DOWNSTREAM_SWIFT5_CLIENT ok")
