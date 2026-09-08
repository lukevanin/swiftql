//
//  GRDBDatabase+Requests.swift
//  SwiftQL
//
//  Turning a SwiftQL statement into something executable: the request factories
//  and the prepared-invocation seams.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


extension GRDBDatabase {

    public func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            customFunctions: encoding.customFunctions,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    /// Prepares an immutable raw-value runtime handle for concurrent
    /// invocations of one rendered statement.
    ///
    /// The handle intentionally does not retain the typed v1 row-reader graph.
    /// Callers that need typed decoding can use `makeRequest(with:)`; static
    /// typed descriptors build on this raw execution seam separately.
    public func prepareInvocation(
        with statement: any XLEncodable
    ) -> GRDBPreparedInvocation {
        let encoding = encoder.makeSQL(statement)
        return GRDBPreparedInvocation(
            executor: GRDBInvocationExecutor(
                driver: driver,
                logicalStatement: logicalStatement(for: encoding),
                parameterLayoutError: preparedParameterLayoutError(for: encoding),
                valueEncodingError: encoding.valueEncodingError,
                customFunctions: encoding.customFunctions
            )
        )
    }

    /// Prepares a database-independent static query descriptor against this
    /// database's dialect and immutable coding snapshot.
    ///
    /// Validation happens before a runtime handle is returned. Physical SQLite
    /// statements remain connection-owned and are created only while executing
    /// through the GRDB driver.
    ///
    /// Only the functions SwiftQL bundles are registered here. A descriptor
    /// carries deterministic metadata alone -- `XLStaticStatementDefinition`'s
    /// `init(validating:)` discards the expression graph, and with it the
    /// `XLCustomFunctionRegistration` closures that implicit registration
    /// carries on the other paths. A *signature* survives that discard, and
    /// SwiftQL can rebuild its own implementation from one, so a statement
    /// using `REGEXP` runs here without any registration by the caller
    /// (issue #615).
    ///
    /// An application's own custom function is still not carried: SwiftQL
    /// cannot rebuild an implementation it did not write. Such a statement must
    /// have that function registered upfront with
    /// `GRDBDatabaseBuilder.addFunction(_:)` before it is executed as a static
    /// descriptor. Implicit registration through
    /// `XLBuilder.customFunctionCall(_:parameters:)` still reaches only the
    /// `makeRequest(with:)` and `prepareInvocation(with: any XLEncodable)`
    /// paths, which hold the rendered encoding.
    public func prepareInvocation(
        with descriptor: XLStaticQueryDescriptor
    ) throws -> GRDBPreparedStaticQuery {
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
            parameterLayout: descriptor.statement.parameterLayout
        )
        let invocation = GRDBPreparedInvocation(
            executor: GRDBInvocationExecutor(
                driver: driver,
                logicalStatement: statement,
                customFunctions: bundledRegistrations(
                    for: descriptor.statement.bundledFunctions
                )
            )
        )
        return GRDBPreparedStaticQuery(
            descriptor: descriptor,
            invocation: invocation,
            codingConfiguration: codingConfiguration,
            dialect: dialect
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

    public func makeRequest<Row>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row> {
        let encoding = encoder.makeSQL(statement)
        return GRDBRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            reader: statement,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            requiresWriteConnection: true,
            customFunctions: encoding.customFunctions,
            liveQueryRetryPolicy: liveQueryRetryPolicy,
            liveQueryRetryScheduler: liveQueryRetryScheduler
        )
    }

    public func makeRequest(with statement: any XLUpdateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLInsertStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLCreateStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }
    
    public func makeRequest(with statement: any XLDeleteStatement) -> XLWriteRequest {
        makeWriteRequest(with: statement)
    }

    func makeWriteRequest(with statement: any XLEncodable) -> XLWriteRequest {
        let encoding = encoder.makeSQL(statement)
        return GRDBWriteRequest(
            driver: driver,
            codingConfiguration: codingConfiguration,
            logger: logger,
            logicalStatement: logicalStatement(for: encoding),
            parameterLayoutError: preparedParameterLayoutError(for: encoding),
            valueEncodingError: encoding.valueEncodingError,
            customFunctions: encoding.customFunctions
        )
    }

}
