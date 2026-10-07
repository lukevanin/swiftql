//
//  XLDriverRequestFactory.swift
//  SwiftQL
//
//  Turning a SwiftQL statement into something a driver executes: the request
//  factories and the prepared-invocation seams, shared by every database over
//  a SQLite driver (issue #682).
//
//  Moved out of GRDBDatabase+Requests.swift, which now forwards to it.
//

import Foundation


///
/// A database that renders statements for one driver (issue #682).
///
/// Package. ``GRDBDatabase`` and ``XLDriverDatabase`` conform, so both build
/// their requests, write requests, prepared invocations, and static queries
/// through one implementation, and differ only in the driver they hold.
///
package protocol XLDriverRequestFactory: XLEncoderProviding, XLValueCodingDatabase
    where Dialect == XLSQLiteDialect
{

    associatedtype Driver: XLBlockingDatabaseDriver & XLObservingDatabaseDriver
        where Driver.Dialect == XLSQLiteDialect

    /// The driver every request this database makes runs on.
    var driver: Driver { get }

    /// The logger every request reports to.
    var logger: XLLogger? { get }
}


extension XLDriverRequestFactory {

    /// A read request for `statement`.
    func makeQueryRequest<Row: Sendable>(
        with statement: any XLQueryStatement<Row>
    ) -> XLDriverRequest<Driver, Row> {
        let encoding = encoder.makeSQL(statement)
        return XLDriverRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError
        )
    }

    /// A request for a `RETURNING` statement, whose fetches run in a
    /// transaction on the writer (issue #643).
    func makeReturningRequest<Row: Sendable>(
        with statement: any XLReturningStatement<Row>
    ) -> XLDriverRequest<Driver, Row> {
        let encoding = encoder.makeSQL(statement)
        return XLDriverRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            requiresWriteConnection: true
        )
    }

    /// A write request for an update, insert, create, or delete statement.
    func makeWriteRequest(with statement: any XLEncodable) -> XLDriverWriteRequest<Driver> {
        let encoding = encoder.makeSQL(statement)
        return XLDriverWriteRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError
        )
    }

    /// An immutable raw-value runtime handle for one rendered statement.
    func makePreparedInvocation(with statement: any XLEncodable) -> XLPreparedInvocation {
        let encoding = encoder.makeSQL(statement)
        return XLPreparedInvocation(
            executor: XLInvocationExecutor(
                driver: driver,
                logicalStatement: logicalStatement(for: encoding),
                parameterLayoutError: preparedParameterLayoutError(for: encoding),
                valueEncodingError: encoding.valueEncodingError
            )
        )
    }

    /// A runtime handle for a static query descriptor, after validating it
    /// against this database's dialect and coding snapshot.
    ///
    /// Only the functions SwiftQL bundles are registered here. See
    /// `GRDBDatabase.prepareInvocation(with:)` for why an application's own
    /// custom function is not carried by a descriptor.
    func makePreparedStaticQuery(
        with descriptor: XLStaticQueryDescriptor
    ) throws -> XLPreparedStaticQuery {
        try descriptor.statement.dialectRequirement.validate(
            dialect.descriptor
        )
        try validateStaticQueryStorage(descriptor)
        try validateStaticQueryCodecs(descriptor)

        let statement = XLLogicalPreparedStatement(
            databaseIdentifier: driver.databaseIdentifier,
            dialectRequirement: descriptor.statement.dialectRequirement,
            sql: descriptor.statement.sql,
            entities: descriptor.statement.entities,
            parameterLayout: descriptor.statement.parameterLayout,
            requiredFunctions: Array(
                bundledRegistrations(for: descriptor.statement.bundledFunctions).values
            )
        )
        let invocation = XLPreparedInvocation(
            executor: XLInvocationExecutor(
                driver: driver,
                logicalStatement: statement
            )
        )
        return XLPreparedStaticQuery(
            descriptor: descriptor,
            invocation: invocation,
            codingConfiguration: codingConfiguration,
            dialect: dialect
        )
    }

    /// A typed static query, prepared only after its generated row layout has
    /// been proven equal to the descriptor's complete result metadata.
    func makePreparedTypedStaticQuery<Row>(
        with definition: XLTypedStaticQueryDescriptor<Row, XLSQLiteDialect>
    ) throws -> XLPreparedTypedStaticQuery<Row> {
        XLPreparedTypedStaticQuery(
            definition: definition,
            query: try makePreparedStaticQuery(with: definition.descriptor)
        )
    }

    /// Resolves the signatures a descriptor recorded back to the registrations
    /// that supply them.
    ///
    /// A signature SwiftQL no longer bundles is dropped rather than failing the
    /// prepare. A descriptor is a build artifact that can outlive the version
    /// that produced it, and a dropped signature surfaces as SQLite's own "no
    /// such function" at execution, which names the function; refusing to
    /// prepare would report a SwiftQL-internal table instead.
    private func bundledRegistrations(
        for definitions: Set<XLCustomFunctionDefinition>
    ) -> [XLCustomFunctionDefinition: XLCustomFunctionRegistration] {
        definitions.reduce(into: [:]) { registrations, definition in
            // Written as an explicit skip rather than assigning the optional
            // through the subscript: both drop an unknown signature, but only
            // this one says so where it is read.
            guard
                let registration = XLCustomFunctionRegistration
                    .bundled[definition]
            else {
                return
            }
            registrations[definition] = registration
        }
    }
}
