//
//  XLDriverRequest.swift
//  SwiftQL
//
//  The typed read request: what it holds, and the legacy mutable
//  `set(parameter:value:)` facade that predates immutable invocation packets.
//
//  Split out of GRDBSQLDatabase.swift (issue #560). Its execution strategies --
//  eager fetch, lazy result set, and live query -- are three different things
//  that happened to live in one 500-line struct, and are now three files.
//  Generic over the driver since issue #682. Its GRDB specialisation,
//  `GRDBRequest`, is declared in GRDBDatabase+Requests.swift (issue #113).
//

import Foundation


/// The typed read request of any blocking, observing driver of the SQLite
/// dialect (issue #682).
///
/// The synchronous members run on the driver's blocking scopes, the
/// asynchronous view on its asynchronous scopes, and the live-query members on
/// its `observe(_:fetch:)`.
package struct XLDriverRequest<Driver, Row: Sendable>: XLRequest
    where Driver: XLBlockingDatabaseDriver,
          Driver: XLObservingDatabaseDriver,
          Driver.Dialect == XLSQLiteDialect
{

    package let executor: XLInvocationExecutor<Driver>

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration

    let logger: XLLogger?

    package let reader: any XLRowReadable<Row>

    /// A `RETURNING` statement changes the database, and a pooled reader
    /// connection is read-only, so every fetch of its rows -- `fetchAll`,
    /// `fetchOne`, `fetchAtMost`, and `withResultSet` -- runs in a transaction
    /// on the writer connection (issue #643). SQLite applies all of the
    /// statement's changes during its first step; the later steps only return
    /// the `RETURNING` rows. A plain query reads on a read-only connection.
    /// Observation is unsupported in the write mode because re-running a
    /// data-changing statement on every database change is never the intended
    /// behavior.
    package let requiresWriteConnection: Bool

    /// Bindings set through the v1 mutable `set(parameter:value:)` facade.
    package var legacyBindings: XLLegacyBindingAccumulator

    init(
        driver: Driver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        reader: any XLRowReadable<Row>,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        requiresWriteConnection: Bool = false
    ) {
        self.requiresWriteConnection = requiresWriteConnection
        self.executor = XLInvocationExecutor<Driver>(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.reader = reader
        self.legacyBindings = XLLegacyBindingAccumulator(
            layout: logicalStatement.parameterLayout,
            initialError: parameterLayoutError
        )
    }

    package var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        legacyBindings.set(optional: value, named: reference.name)
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        legacyBindings.set(value, named: reference.name)
    }
}


extension XLDriverRequest {

    /// This request, bound to `driver` instead of the driver it was built for
    /// (issue #642).
    ///
    /// Keeps everything rendering produced -- the SQL, the parameter layout,
    /// the row reader, the recorded functions and errors -- and replaces only
    /// what names a connection: the driver, and the database identifier the
    /// logical statement is validated against. Bindings set through the v1
    /// `set(parameter:value:)` facade are not carried over; a render-once
    /// request is value-free.
    package func rebound(to driver: Driver) -> XLDriverRequest<Driver, Row> {
        XLDriverRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: reader,
            logicalStatement: executor.logicalStatement.rebound(
                to: driver.databaseIdentifier
            ),
            parameterLayoutError: executor.parameterLayoutError,
            valueEncodingError: executor.valueEncodingError,
            requiresWriteConnection: requiresWriteConnection
        )
    }
}
