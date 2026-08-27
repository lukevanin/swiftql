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
    /// Unlike the encodable overloads, this path deliberately registers no
    /// custom functions. A descriptor carries only deterministic SQL and
    /// immutable parameter metadata -- `XLStaticStatementDefinition`'s
    /// `init(validating:)` discards the expression graph, and with it the
    /// `XLCustomFunctionRegistration` closures that implicit registration
    /// needs -- so there is nothing to register here. A statement that calls a
    /// custom function must therefore have that function registered upfront
    /// with `GRDBDatabaseBuilder.addFunction(_:)` before it is executed as a
    /// static descriptor; implicit registration through
    /// `XLBuilder.customFunctionCall(_:parameters:)` applies only to the
    /// `makeRequest(with:)` and `prepareInvocation(with: any XLEncodable)`
    /// paths, which still hold the rendered encoding.
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
                logicalStatement: statement
            )
        )
        return GRDBPreparedStaticQuery(
            descriptor: descriptor,
            invocation: invocation,
            codingConfiguration: codingConfiguration,
            dialect: dialect
        )
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
