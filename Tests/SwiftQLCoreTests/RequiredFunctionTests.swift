import Foundation
import XCTest

import SwiftQLCore


/// Issue #683: a function a statement calls is data the core owns. A
/// connection with no GRDB import installs it from the registration and
/// evaluates it.
final class RequiredFunctionTests: XCTestCase {

    private let databaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())

    private let requirement = XLDialectRequirement(
        identity: XLSQLiteDialect.identity,
        capabilities: []
    )

    func testConnectionWithoutGRDBInstallsTheBundledRegexpFromCore() throws {
        var connection = FunctionConnection(databaseIdentifier: databaseIdentifier)
        let statement = XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: requirement,
            sql: "SELECT regexp(:pattern, :subject)",
            requiredFunctions: [
                XLRegexpFunction.definition: XLCustomFunctionRegistration.bundled[XLRegexpFunction.definition]!,
            ]
        )

        var prepared = try connection.prepare(statement)
        prepared = try connection.bind(.text("[0-9]+$"), to: .named("pattern"), in: prepared)
        prepared = try connection.bind(.text("alpha-123"), to: .named("subject"), in: prepared)

        XCTAssertEqual(connection.installed.keys.sorted(), [XLRegexpFunction.definition])
        XCTAssertEqual(try connection.fetchOne(prepared), [.integer(1)])

        prepared = try connection.bind(.text("^b"), to: .named("pattern"), in: prepared)
        XCTAssertEqual(try connection.fetchOne(prepared), [.integer(0)])

        prepared = try connection.bind(.null, to: .named("pattern"), in: prepared)
        XCTAssertEqual(try connection.fetchOne(prepared), [.null])
    }

    func testBundledTableHoldsRegexpAndDefersToAnExistingFunction() throws {
        let regexp = try XCTUnwrap(XLCustomFunctionRegistration.bundled[XLRegexpFunction.definition])
        XCTAssertEqual(regexp.definition, XLCustomFunctionDefinition(name: "regexp", numberOfArguments: 2))
        XCTAssertTrue(regexp.defersToExistingRegistration)
        XCTAssertTrue(regexp.isPure)
    }

    /// A connection that predates required functions keeps working: it
    /// installs nothing, and a statement that calls a function prepares as it
    /// always did, relying on the connection to have it.
    func testConnectionThatCannotInstallFunctionsPreparesAsBefore() throws {
        var connection = PlainConnection(databaseIdentifier: databaseIdentifier)
        let needsRegexp = XLLogicalPreparedStatement(
            databaseIdentifier: databaseIdentifier,
            dialectRequirement: requirement,
            sql: "SELECT regexp('a', 'b')",
            requiredFunctions: XLCustomFunctionRegistration.bundled
        )
        XCTAssertEqual(try connection.prepare(needsRegexp), needsRegexp.sql)
        XCTAssertEqual(connection.preparedCount, 1)
    }

    /// A registration's evaluator is a closure, so statements compare and hash
    /// their required functions by signature.
    func testLogicalStatementsCompareRequiredFunctionsBySignature() {
        let definition = XLCustomFunctionDefinition(name: "twice", numberOfArguments: 1)
        func statement(_ functions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]) -> XLLogicalPreparedStatement {
            XLLogicalPreparedStatement(
                databaseIdentifier: databaseIdentifier,
                dialectRequirement: requirement,
                sql: "SELECT twice(1)",
                requiredFunctions: functions
            )
        }
        let first = statement([definition: XLCustomFunctionRegistration(definition: definition) { { _ in .integer(2) } }])
        let second = statement([definition: XLCustomFunctionRegistration(definition: definition) { { _ in .integer(3) } }])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertNotEqual(first, statement([:]))
        // The same signature installed another way is another statement.
        XCTAssertNotEqual(
            first,
            statement([definition: XLCustomFunctionRegistration(definition: definition, defersToExistingRegistration: true) { { _ in .integer(2) } }])
        )
        XCTAssertNotEqual(
            first,
            statement([definition: XLCustomFunctionRegistration(definition: definition, isPure: true) { { _ in .integer(2) } }])
        )

        // A registration passed under another key is stored under its own
        // signature, so every adapter installs the same function.
        let misfiled = statement([
            XLCustomFunctionDefinition(name: "other", numberOfArguments: 1):
                XLCustomFunctionRegistration(definition: definition) { { _ in .integer(2) } },
        ])
        XCTAssertEqual(misfiled.requiredFunctions.keys.sorted(), [definition])
        XCTAssertEqual(misfiled, first)

        let other = XLDatabaseIdentifier(rawValue: UUID())
        let rebound = first.rebound(to: other)
        XCTAssertEqual(rebound.databaseIdentifier, other)
        XCTAssertEqual(rebound.requiredFunctions.keys.sorted(), [definition])
        XCTAssertEqual(rebound.sql, first.sql)
    }
}


/// Evaluates one function call with named arguments, using only the
/// functions it installed.
private struct FunctionConnection: XLDatabaseDriverConnection {

    struct Statement {
        var sql: String
        var bindings: [XLBindingKey: XLSQLiteValue] = [:]
    }

    let driverIdentifier = XLDriverIdentifier(rawValue: "function-test")
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect = XLSQLiteDialect()
    var installed: [XLCustomFunctionDefinition: XLCustomFunctionEvaluator] = [:]

    init(databaseIdentifier: XLDatabaseIdentifier) {
        self.databaseIdentifier = databaseIdentifier
    }

    mutating func installRequiredFunctions(
        _ functions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration]
    ) throws {
        for (definition, registration) in functions where installed[definition] == nil {
            installed[definition] = registration.makeEvaluator()
        }
    }

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> Statement {
        Statement(sql: statement.logicalStatement.sql)
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: Statement) throws -> Statement {
        var statement = statement
        statement.bindings[key] = value
        return statement
    }

    mutating func fetchAll(_ statement: Statement) throws -> [[XLSQLiteValue]] {
        [try evaluate(statement)]
    }

    mutating func fetchOne(_ statement: Statement) throws -> [XLSQLiteValue]? {
        try evaluate(statement)
    }

    mutating func execute(_ statement: Statement) throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .read)
    }

    private func evaluate(_ statement: Statement) throws -> [XLSQLiteValue] {
        let evaluate = try XCTUnwrap(installed[XLRegexpFunction.definition])
        return [
            try evaluate([
                statement.bindings[.named("pattern")] ?? .null,
                statement.bindings[.named("subject")] ?? .null,
            ]),
        ]
    }
}


/// A connection written before required functions: it implements no
/// installation, so it gets the default, which installs nothing.
private struct PlainConnection: XLDatabaseDriverConnection {

    let driverIdentifier = XLDriverIdentifier(rawValue: "plain-test")
    let databaseIdentifier: XLDatabaseIdentifier
    let dialect = XLSQLiteDialect()
    var preparedCount = 0

    init(databaseIdentifier: XLDatabaseIdentifier) {
        self.databaseIdentifier = databaseIdentifier
    }

    mutating func preparePhysical(_ statement: XLValidatedLogicalPreparedStatement) throws -> String {
        preparedCount += 1
        return statement.logicalStatement.sql
    }

    mutating func bind(_ value: XLSQLiteValue, to key: XLBindingKey, in statement: String) throws -> String {
        statement
    }

    mutating func fetchAll(_ statement: String) throws -> [[XLSQLiteValue]] {
        []
    }

    mutating func fetchOne(_ statement: String) throws -> [XLSQLiteValue]? {
        nil
    }

    mutating func execute(_ statement: String) throws -> XLExecutionResult {
        XLExecutionResult(rowsAffected: 0, access: .read)
    }
}
