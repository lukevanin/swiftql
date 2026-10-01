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
            requiredFunctions: [XLCustomFunctionRegistration.bundledRegexp]
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
            requiredFunctions: Array(XLCustomFunctionRegistration.bundled.values)
        )
        XCTAssertEqual(try connection.prepare(needsRegexp), needsRegexp.sql)
        XCTAssertEqual(connection.preparedCount, 1)
    }

    /// Two registrations for one signature collapse the same way in either
    /// order: the one that does not defer wins.
    func testRegistrationsSharingASignatureCollapseInEitherOrder() throws {
        let application = XLCustomFunctionRegistration(definition: XLRegexpFunction.definition) { { _ in .integer(7) } }
        for functions in [
            [XLCustomFunctionRegistration.bundledRegexp, application],
            [application, XLCustomFunctionRegistration.bundledRegexp],
        ] {
            let statement = XLLogicalPreparedStatement(
                databaseIdentifier: databaseIdentifier,
                dialectRequirement: requirement,
                sql: "SELECT regexp('a', 'b')",
                requiredFunctions: functions
            )
            let kept = try XCTUnwrap(statement.requiredFunctions[XLRegexpFunction.definition])
            XCTAssertEqual(statement.requiredFunctions.count, 1)
            XCTAssertFalse(kept.defersToExistingRegistration, "The application's function wins.")
            XCTAssertEqual(try kept.makeEvaluator()([]), .integer(7))
        }
    }

    /// Every registration's evaluator refuses a result SQLite would change.
    func testEvaluatorRefusesAResultSQLiteWouldChange() {
        let definition = XLCustomFunctionDefinition(name: "result", numberOfArguments: 0)
        func evaluate(_ result: XLSQLiteValue) throws -> XLSQLiteValue {
            try XLCustomFunctionRegistration(definition: definition) { { _ in result } }.makeEvaluator()([])
        }
        XCTAssertThrowsError(try evaluate(.real(.nan))) { error in
            XCTAssertEqual(error as? XLCustomFunctionResultError, XLCustomFunctionResultError(definition: definition, reason: .notANumber))
        }
        XCTAssertThrowsError(try evaluate(.text("a\u{0}b"))) { error in
            XCTAssertEqual(error as? XLCustomFunctionResultError, XLCustomFunctionResultError(definition: definition, reason: .nulCharacterInText))
        }
        XCTAssertEqual(try evaluate(.real(.infinity)), .real(.infinity))
        XCTAssertEqual(try evaluate(.text("ab")), .text("ab"))
    }

    /// A registration's evaluator is a closure, so statements compare and hash
    /// their required functions by signature.
    func testLogicalStatementsCompareRequiredFunctionsBySignature() {
        let definition = XLCustomFunctionDefinition(name: "twice", numberOfArguments: 1)
        func statement(_ functions: [XLCustomFunctionRegistration]) -> XLLogicalPreparedStatement {
            XLLogicalPreparedStatement(
                databaseIdentifier: databaseIdentifier,
                dialectRequirement: requirement,
                sql: "SELECT twice(1)",
                requiredFunctions: functions
            )
        }
        let first = statement([XLCustomFunctionRegistration(definition: definition) { { _ in .integer(2) } }])
        let second = statement([XLCustomFunctionRegistration(definition: definition) { { _ in .integer(3) } }])

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hashValue, second.hashValue)
        XCTAssertNotEqual(first, statement([]))
        // The same signature installed another way is another statement.
        XCTAssertNotEqual(
            first,
            statement([XLCustomFunctionRegistration(definition: definition, defersToExistingRegistration: true) { { _ in .integer(2) } }])
        )
        XCTAssertNotEqual(
            first,
            statement([XLCustomFunctionRegistration(definition: definition, isPure: true) { { _ in .integer(2) } }])
        )

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
