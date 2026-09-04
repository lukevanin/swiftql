//
//  SQLRegexpStaticQueryTests.swift
//
//  Issue #615: a statement that uses REGEXP runs as a static query descriptor
//  without the caller registering anything, while an application's own custom
//  function still has to be registered upfront.
//

import Foundation
import GRDB
import SwiftQLCore
import XCTest
@testable import SwiftQL


@SQLTable(name: "StaticPhrase")
struct RegexpStaticPhrase: Equatable {
    let id: String
    let text: String
}


/// An application's own custom function, opted into implicit registration.
/// SwiftQL cannot rebuild it from a signature, so a descriptor must not carry
/// it.
private struct StaticOnlyDoubleFunction: XLCustomFunction {
    typealias T = Int

    static let definition = XLCustomFunctionDefinition(
        name: "staticOnlyDouble",
        numberOfArguments: 1
    )

    private let value: any XLExpression<Int>

    init(_ value: any XLExpression<Int>) {
        self.value = value
    }

    func makeSQL(context: inout XLBuilder) {
        context.customFunctionCall(Self.self) { list in
            list.listItem(expression: value.makeSQL)
        }
    }

    static func execute(reader: XLColumnReader) throws -> Int {
        try reader.readInteger(at: 0) * 2
    }
}


final class XLRegexpStaticQueryTests: XCTestCase {

    private var database: GRDBDatabase!
    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    override func tearDownWithError() throws {
        try? database?.databasePool.close()
        database = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    private func makeSeededDatabase() throws -> GRDBDatabase {
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: Configuration(),
            logger: nil
        )
        let database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexpStaticPhrase.self)).execute()
        for phrase in [
            RegexpStaticPhrase(id: "1", text: "alpha-123"),
            RegexpStaticPhrase(id: "2", text: "beta"),
            RegexpStaticPhrase(id: "3", text: "gamma-456"),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }
        return database
    }

    /// Takes the rendered encoding rather than the statement: passing a
    /// statement through a generic `some XLEncodable` parameter renders it as a
    /// subquery expression, in parentheses, which SQLite will not prepare.
    private func makeDescriptor(
        for encoding: XLEncoding,
        path: [String]
    ) throws -> XLStaticQueryDescriptor {
        try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(path: path, version: 1),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: try XLStaticQueryResultMetadata(
                slots: [
                    XLStaticQueryResultSlot(
                        index: XLLogicalResultIndex(0),
                        identity: try XLQuerySlotIdentity(path: ["result", "id"]),
                        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.string"),
                        valueTypeName: String(reflecting: String.self),
                        nullability: .required,
                        codecIdentity: nil,
                        storageIdentifier: XLValueStorageIdentifier(rawValue: "text"),
                        codingContext: XLValueCodingContext(
                            site: .result,
                            path: XLValueCodingPath(["id"])
                        )
                    )
                ]
            ),
            cardinality: .many
        )
    }

    // MARK: - The descriptor records the signature

    /// A descriptor cannot carry a registration closure, so it carries the
    /// signature instead.
    func testADescriptorRecordsTheBundledSignature() throws {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpStaticPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.regexp("[0-9]+$"))
            }
        )
        let statement = try XLStaticStatementDefinition(validating: encoding)

        XCTAssertEqual(statement.bundledFunctions, [XLRegexpFunction.definition])
    }

    /// An application's own function is not recorded, because SwiftQL cannot
    /// rebuild an implementation it did not write. This is the gap that stays
    /// open.
    func testADescriptorDoesNotRecordAnApplicationFunction() throws {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { _ in Select(StaticOnlyDoubleFunction(21)) }
        )
        let statement = try XLStaticStatementDefinition(validating: encoding)

        XCTAssertTrue(statement.bundledFunctions.isEmpty)
    }

    /// An application function that reuses a bundled *signature* is still not
    /// recorded. Keying on the signature alone would have the static path
    /// register SwiftQL's `regexp` in place of the type the statement named.
    func testADescriptorDoesNotRecordAnApplicationFunctionOnABundledSignature() throws {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { _ in Select(ApplicationRegexpFunction()) }
        )

        XCTAssertNotNil(encoding.customFunctions[XLRegexpFunction.definition])
        let statement = try XLStaticStatementDefinition(validating: encoding)
        XCTAssertTrue(statement.bundledFunctions.isEmpty)
    }

    /// A statement with no custom function records none, so an ordinary
    /// descriptor's identity is unchanged by issue #615.
    func testAStatementWithoutACustomFunctionRecordsNoSignature() throws {
        let encoding = XLiteEncoder(formatter: XLiteFormatter()).makeSQL(
            sql { schema in
                let phrase = schema.table(RegexpStaticPhrase.self)
                Select(phrase.id)
                From(phrase)
                Where(phrase.text.like("a%"))
            }
        )
        let statement = try XLStaticStatementDefinition(validating: encoding)

        XCTAssertTrue(statement.bundledFunctions.isEmpty)
    }

    /// The signature is part of the statement's identity: two otherwise
    /// identical statements that differ only in whether they need a bundled
    /// function are different statements to prepare.
    func testTheRecordedSignatureIsPartOfStatementIdentity() {
        let withFunction = XLStaticStatementDefinition(
            sql: "SELECT 1",
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity),
            bundledFunctions: [XLRegexpFunction.definition]
        )
        let withoutFunction = XLStaticStatementDefinition(
            sql: "SELECT 1",
            dialectRequirement: XLDialectRequirement(identity: XLSQLiteDialect.identity)
        )

        XCTAssertNotEqual(withFunction, withoutFunction)
    }

    // MARK: - Execution

    /// The behaviour the issue asks for: a static descriptor using REGEXP runs
    /// with no registration by the caller.
    func testAStaticDescriptorUsingRegexpExecutes() throws {
        database = try makeSeededDatabase()
        let descriptor = try makeDescriptor(
            for: try XLiteEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(
                sql { schema in
                    let phrase = schema.table(RegexpStaticPhrase.self)
                    Select(phrase.id)
                    From(phrase)
                    Where(phrase.text.regexp("[0-9]+$"))
                    OrderBy(phrase.id.ascending())
                }
            ),
            path: ["tests", "regexp", "static"]
        )

        let prepared = try database.prepareInvocation(with: descriptor)
        let rows = try prepared.fetchAllValues(
            bindings: try XLInvocationBindings<XLSQLiteValue>(
                layout: prepared.parameterLayout,
                bindings: []
            ).validatingComplete()
        )

        XCTAssertEqual(rows, [[.text("1")], [.text("3")]])
    }

    /// The narrowing is for bundled functions only. An application's own
    /// function still fails on the static path without an upfront
    /// `addFunction(_:)` call, exactly as before.
    func testAnApplicationFunctionStillNeedsUpfrontRegistration() throws {
        database = try makeSeededDatabase()
        let encoding = try XLiteEncoder(dialect: XLSQLiteDialect())
            .makeValidatedSQL(sql { _ in Select(StaticOnlyDoubleFunction(21)) })
        let descriptor = try XLStaticQueryDescriptor(
            definitionIdentity: XLQueryDefinitionIdentity(
                path: ["tests", "regexp", "application-function"],
                version: 1
            ),
            statement: XLStaticStatementDefinition(validating: encoding),
            parameters: [],
            results: try XLStaticQueryResultMetadata(
                slots: [
                    XLStaticQueryResultSlot(
                        index: XLLogicalResultIndex(0),
                        identity: try XLQuerySlotIdentity(path: ["result", "value"]),
                        valueTypeIdentifier: XLValueTypeIdentifier(rawValue: "swift.int"),
                        valueTypeName: String(reflecting: Int.self),
                        nullability: .required,
                        codecIdentity: nil,
                        storageIdentifier: XLValueStorageIdentifier(rawValue: "integer"),
                        codingContext: XLValueCodingContext(
                            site: .result,
                            path: XLValueCodingPath(["value"])
                        )
                    )
                ]
            ),
            cardinality: .many
        )

        let prepared = try database.prepareInvocation(with: descriptor)
        XCTAssertThrowsError(
            try prepared.fetchAllValues(
                bindings: try XLInvocationBindings<XLSQLiteValue>(
                    layout: prepared.parameterLayout,
                    bindings: []
                ).validatingComplete()
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error).lowercased().contains("no such function"),
                "unexpected error: \(error)"
            )
        }
    }

    /// An application that supplies its own `regexp` keeps it on this path too,
    /// which the inverted implementation makes visible in the rows.
    func testAnApplicationRegexpStillWinsOnTheStaticPath() throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            db.add(
                function: DatabaseFunction("regexp", argumentCount: 2) { values in
                    guard
                        let pattern = String.fromDatabaseValue(values[0]),
                        let subject = String.fromDatabaseValue(values[1])
                    else {
                        return nil
                    }
                    return subject.range(of: pattern, options: .regularExpression) == nil
                }
            )
        }
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: configuration,
            logger: nil
        )
        database = try builder.build()
        try database.makeRequest(with: sqlCreate(RegexpStaticPhrase.self)).execute()
        for phrase in [
            RegexpStaticPhrase(id: "1", text: "alpha-123"),
            RegexpStaticPhrase(id: "2", text: "beta"),
            RegexpStaticPhrase(id: "3", text: "gamma-456"),
        ] {
            try database.makeRequest(with: sqlInsert(phrase)).execute()
        }

        let descriptor = try makeDescriptor(
            for: try XLiteEncoder(dialect: XLSQLiteDialect()).makeValidatedSQL(
                sql { schema in
                    let phrase = schema.table(RegexpStaticPhrase.self)
                    Select(phrase.id)
                    From(phrase)
                    Where(phrase.text.regexp("[0-9]+$"))
                    OrderBy(phrase.id.ascending())
                }
            ),
            path: ["tests", "regexp", "static-application"]
        )
        let prepared = try database.prepareInvocation(with: descriptor)
        let rows = try prepared.fetchAllValues(
            bindings: try XLInvocationBindings<XLSQLiteValue>(
                layout: prepared.parameterLayout,
                bindings: []
            ).validatingComplete()
        )

        XCTAssertEqual(rows, [[.text("2")]])
    }
}


///
/// Invariants tying `XLCustomFunctionRegistration.bundled` to the precedence
/// flag, so the table and the flag cannot drift apart.
///
final class XLCustomFunctionRegistrationInvariantTests: XCTestCase {

    /// Everything SwiftQL supplies is a default rather than an instruction, so
    /// every entry has to defer to an implementation already on the connection.
    func testEveryBundledRegistrationDefersToAnExistingOne() {
        for (definition, registration) in XLCustomFunctionRegistration.bundled {
            XCTAssertTrue(
                registration.defersToExistingRegistration,
                "\(definition.name)/\(definition.numberOfArguments) does not defer"
            )
            XCTAssertEqual(registration.definition, definition)
        }
        XCTAssertFalse(XLCustomFunctionRegistration.bundled.isEmpty)
    }

    /// An application's own function is registered even when it reuses a
    /// signature SwiftQL bundles. The caller named that type in the statement,
    /// so registering it is what they asked for.
    func testAnApplicationRegistrationNeverDefersEvenOnABundledSignature() {
        let registration = XLCustomFunctionRegistration.make(
            ApplicationRegexpFunction.self
        )

        XCTAssertEqual(registration.definition, XLRegexpFunction.definition)
        XCTAssertNotNil(
            XLCustomFunctionRegistration.bundled[registration.definition]
        )
        XCTAssertFalse(registration.defersToExistingRegistration)
    }
}


/// An application function that deliberately reuses the bundled `regexp/2`
/// signature.
private struct ApplicationRegexpFunction: XLCustomFunction {
    typealias T = Bool

    static let definition = XLRegexpFunction.definition

    func makeSQL(context: inout XLBuilder) {
        context.customFunctionCall(Self.self) { _ in }
    }

    static func execute(reader: XLColumnReader) throws -> Bool {
        true
    }
}
