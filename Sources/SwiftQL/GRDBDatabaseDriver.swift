//
//  GRDBDatabaseDriver.swift
//

import Foundation
import GRDB


/// GRDB transport for SQLite dialect values.
///
/// The driver is internal to the v1 compatibility facade. Public code depends
/// on the adapter-neutral contracts from `SwiftQLCore`.
struct GRDBDatabaseDriver: XLDatabaseDriver {

    typealias Dialect = XLSQLiteDialect

    typealias Connection = GRDBDatabaseDriverConnection

    let driverIdentifier = XLDriverIdentifier(rawValue: "grdb")

    let databaseIdentifier: XLDatabaseIdentifier

    let dialect: XLSQLiteDialect

    let databasePool: DatabasePool

    init(
        databasePool: DatabasePool,
        dialect: XLSQLiteDialect,
        databaseIdentifier: XLDatabaseIdentifier = XLDatabaseIdentifier(rawValue: UUID())
    ) {
        self.databasePool = databasePool
        self.dialect = dialect
        self.databaseIdentifier = databaseIdentifier
    }

    mutating func withReadConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        try databasePool.read { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    mutating func withWriteConnection<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        try databasePool.writeWithoutTransaction { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    mutating func withTransaction<Result>(
        _ operation: (inout GRDBDatabaseDriverConnection) throws -> Result
    ) throws -> Result {
        try databasePool.write { database in
            var connection = makeConnection(database)
            return try operation(&connection)
        }
    }

    func makeConnection(_ database: Database) -> GRDBDatabaseDriverConnection {
        GRDBDatabaseDriverConnection(
            database: database,
            databaseIdentifier: databaseIdentifier,
            driverIdentifier: driverIdentifier,
            dialect: dialect
        )
    }
}


struct GRDBDatabaseDriverConnection: XLDatabaseDriverConnection {

    typealias Dialect = XLSQLiteDialect

    typealias PhysicalStatement = GRDBPhysicalStatement

    let driverIdentifier: XLDriverIdentifier

    let databaseIdentifier: XLDatabaseIdentifier

    let dialect: XLSQLiteDialect

    private let connectionIdentifier = UUID()

    private let database: Database

    init(
        database: Database,
        databaseIdentifier: XLDatabaseIdentifier,
        driverIdentifier: XLDriverIdentifier,
        dialect: XLSQLiteDialect
    ) {
        self.database = database
        self.databaseIdentifier = databaseIdentifier
        self.driverIdentifier = driverIdentifier
        self.dialect = dialect
    }

    mutating func preparePhysical(
        _ validatedStatement: XLValidatedLogicalPreparedStatement
    ) throws -> GRDBPhysicalStatement {
        let statement = validatedStatement.logicalStatement
        return GRDBPhysicalStatement(
            logicalStatement: statement,
            connectionIdentifier: connectionIdentifier,
            statement: try database.cachedStatement(sql: statement.sql),
            bindings: [:]
        )
    }

    mutating func bind(
        _ value: XLSQLiteValue,
        to key: XLBindingKey,
        in statement: GRDBPhysicalStatement
    ) throws -> GRDBPhysicalStatement {
        try validateOwnership(of: statement)
        if case .indexed(let index) = key, index < 0 {
            throw XLDatabaseContractError.bindFailure(
                driver: driverIdentifier,
                key: key,
                message: "Indexed binding positions must be zero or greater."
            )
        }
        var result = statement
        result.bindings[key] = value
        return result
    }

    mutating func fetchAll(
        _ statement: GRDBPhysicalStatement
    ) throws -> [[XLSQLiteValue]] {
        try validateOwnership(of: statement)
        return try Row.fetchAll(
            statement.statement,
            arguments: statementArguments(statement.bindings)
        ).map { row in
            row.databaseValues.map(\.sqliteDialectValue)
        }
    }

    mutating func fetchOne(
        _ statement: GRDBPhysicalStatement
    ) throws -> [XLSQLiteValue]? {
        try validateOwnership(of: statement)
        return try Row.fetchOne(
            statement.statement,
            arguments: statementArguments(statement.bindings)
        )?.databaseValues.map(\.sqliteDialectValue)
    }

    mutating func execute(_ statement: GRDBPhysicalStatement) throws {
        try validateOwnership(of: statement)
        try statement.statement.execute(
            arguments: statementArguments(statement.bindings)
        )
    }

    private func validateOwnership(of statement: GRDBPhysicalStatement) throws {
        guard statement.connectionIdentifier == connectionIdentifier else {
            throw XLDatabaseContractError.prepareFailure(
                driver: driverIdentifier,
                message: "A physical statement cannot leave its owning connection."
            )
        }
    }

    private func statementArguments(
        _ bindings: [XLBindingKey: XLSQLiteValue]
    ) -> StatementArguments {
        var indexed: [Int: DatabaseValue] = [:]
        var named: [String: (any DatabaseValueConvertible)?] = [:]

        for (key, value) in bindings {
            switch key {
            case .indexed(let index):
                indexed[index] = value.databaseValue
            case .named(let name):
                named[name] = value.databaseValue
            }
        }

        let positional: [(any DatabaseValueConvertible)?]
        if let lastIndex = indexed.keys.max() {
            positional = (0 ... lastIndex).map { indexed[$0] ?? DatabaseValue.null }
        }
        else {
            positional = []
        }

        var arguments = StatementArguments(positional)
        _ = arguments.append(contentsOf: StatementArguments(named))
        return arguments
    }
}


struct GRDBPhysicalStatement {

    let logicalStatement: XLLogicalPreparedStatement

    fileprivate let connectionIdentifier: UUID

    fileprivate let statement: Statement

    fileprivate var bindings: [XLBindingKey: XLSQLiteValue]
}


extension DatabaseValue {

    var sqliteDialectValue: XLSQLiteValue {
        switch storage {
        case .null:
            return .null
        case .int64(let value):
            return .integer(value)
        case .double(let value):
            return .real(value)
        case .string(let value):
            return .text(value)
        case .blob(let value):
            return .blob(value)
        }
    }
}


extension XLSQLiteValue {

    var databaseValue: DatabaseValue {
        switch self {
        case .null:
            return .null
        case .integer(let value):
            return value.databaseValue
        case .real(let value):
            return value.databaseValue
        case .text(let value):
            return value.databaseValue
        case .blob(let value):
            return value.databaseValue
        }
    }
}
