//
//  GRDBRequestPhaseProbe.swift
//  SwiftQL
//
//  Package-scoped seams that let the performance harness time the phases of
//  one request's production execution path separately (issue #670).
//

import Foundation
import GRDB


/// A request that a ``GRDBRequestPhaseProbe`` cannot inspect.
package enum GRDBRequestPhaseProbeError: Error, CustomStringConvertible {

    /// The request was not created by a ``GRDBDatabase``.
    case unsupportedRequest(String)

    package var description: String {
        switch self {
        case .unsupportedRequest(let typeName):
            return "\(typeName) is not a GRDBDatabase request"
        }
    }
}


/// Times the phases of one GRDB request's production execution path.
///
/// `fetchAll()` and `execute()` validate the request's binding packet, prepare
/// and bind a statement, step a GRDB row cursor, normalize every column to
/// ``XLSQLiteValue``, and decode each row. This probe calls the same internal
/// functions one phase at a time, so a benchmark never re-implements that work
/// with raw GRDB calls or decodes rows through a path production does not use.
///
/// It is package API for the benchmark target and adds no behavior to a
/// request. Every value it lends is valid only inside the connection access
/// that ``withConnection(_:)`` opens.
package struct GRDBRequestPhaseProbe<Output> {

    private let executor: GRDBInvocationExecutor

    private let bindings: GRDBLegacyBindingAccumulator

    private let reader: (any XLRowReadable<Output>)?

    private let usesWriteConnection: Bool

    /// Probes a read request, including the bindings already set on it.
    package init(request: any XLRequest<Output>) throws {
        guard let request = request as? GRDBRequest<Output> else {
            throw GRDBRequestPhaseProbeError.unsupportedRequest(
                String(reflecting: type(of: request))
            )
        }
        self.executor = request.executor
        self.bindings = request.legacyBindings
        self.reader = request.reader
        self.usesWriteConnection = request.requiresWriteConnection
    }

    /// Decodes normalized rows through ``GRDBRowDecoder/decode(values:)``, the
    /// per-row call that `fetchAll()` makes inside its cursor loop.
    package func decode(_ rows: [[XLSQLiteValue]]) throws -> [Output] {
        guard let reader else {
            return []
        }
        let decoder = GRDBRowDecoder(reader: reader)
        var decoded: [Output] = []
        decoded.reserveCapacity(rows.count)
        for values in rows {
            decoded.append(try decoder.decode(values: values))
        }
        return decoded
    }

    /// Runs `body` inside one connection access: a pooled read access for a
    /// query, or the writer without a transaction for a write, so that the
    /// caller can wrap each sample in its own savepoint.
    package func withConnection<Result>(
        _ body: (GRDBRequestPhaseConnection) throws -> Result
    ) throws -> Result {
        var driver = executor.driver
        let executor = executor
        let bindings = bindings
        let access: (inout GRDBDatabaseDriverConnection) throws -> Result = { connection in
            let phaseConnection = GRDBRequestPhaseConnection(
                executor: executor,
                bindings: bindings,
                connection: connection
            )
            return try body(phaseConnection)
        }
        if usesWriteConnection {
            return try driver.withWriteConnection(access)
        }
        return try driver.withReadConnection(access)
    }
}


extension GRDBRequestPhaseProbe where Output == Void {

    /// Probes a write request, including the bindings already set on it.
    package init(writeRequest: any XLWriteRequest) throws {
        guard let request = writeRequest as? GRDBWriteRequest else {
            throw GRDBRequestPhaseProbeError.unsupportedRequest(
                String(reflecting: type(of: writeRequest))
            )
        }
        self.executor = request.executor
        self.bindings = request.legacyBindings
        self.reader = nil
        self.usesWriteConnection = true
    }
}


/// One statement that ``GRDBRequestPhaseConnection/bind()`` prepared and bound.
package struct GRDBRequestPhaseStatement {

    let physicalStatement: GRDBPhysicalStatement

    /// The number of values the validated packet bound.
    package let bindingCount: Int
}


/// The phases of one request on one open connection.
///
/// Do not keep this value after the ``GRDBRequestPhaseProbe/withConnection(_:)``
/// body that received it returns.
package final class GRDBRequestPhaseConnection {

    private let executor: GRDBInvocationExecutor

    private let bindings: GRDBLegacyBindingAccumulator

    private var connection: GRDBDatabaseDriverConnection

    init(
        executor: GRDBInvocationExecutor,
        bindings: GRDBLegacyBindingAccumulator,
        connection: GRDBDatabaseDriverConnection
    ) {
        self.executor = executor
        self.bindings = bindings
        self.connection = connection
    }

    /// The binding phase: builds the request's invocation packet, validates it
    /// against the parameter layout, takes the connection's cached statement,
    /// binds the validated values, and validates GRDB's arguments.
    package func bind() throws -> GRDBRequestPhaseStatement {
        let packet = try executor.sqlitePacket(bindings.packet())
        let statement = try executor.boundStatement(packet: packet, in: &connection)
        return GRDBRequestPhaseStatement(
            physicalStatement: statement,
            bindingCount: packet.bindings.count
        )
    }

    /// The execution phase of a query: opens the production row cursor on
    /// `statement` and steps every row without reading a column. Returns the
    /// row count.
    package func step(_ statement: GRDBRequestPhaseStatement) throws -> Int {
        try connection.stepAllRows(statement.physicalStatement)
    }

    /// The materialization phase: steps every row and normalizes every column
    /// through the production cursor loop, without decoding. Returns the
    /// number of values materialized.
    package func materialize(_ statement: GRDBRequestPhaseStatement) throws -> Int {
        var valueCount = 0
        try connection.forEachRow(statement.physicalStatement) { values in
            valueCount += values.count
            return .advance
        }
        return valueCount
    }

    /// Every normalized row of `statement`, retained for a decoding phase.
    package func materializedRows(
        _ statement: GRDBRequestPhaseStatement
    ) throws -> [[XLSQLiteValue]] {
        try connection.fetchAll(statement.physicalStatement)
    }

    /// The execution phase of a write: executes `statement` once.
    package func execute(_ statement: GRDBRequestPhaseStatement) throws {
        try connection.execute(statement.physicalStatement)
    }

    /// Runs unmeasured work, such as a savepoint around one sample, on the
    /// same GRDB connection.
    package func withUnmeasuredDatabase<Result>(
        _ body: (Database) throws -> Result
    ) rethrows -> Result {
        try body(connection.grdbDatabase)
    }
}
