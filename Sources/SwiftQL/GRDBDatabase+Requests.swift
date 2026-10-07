//
//  GRDBDatabase+Requests.swift
//  SwiftQL
//
//  Turning a SwiftQL statement into something executable: the request factories
//  and the prepared-invocation seams. Each forwards to `XLDriverRequestFactory`,
//  which `XLDriverDatabase` shares (issue #682).
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//
//  The `GRDB` names of the driver-generic request types are declared here too,
//  with the GRDB adapter, so no driver-generic file names a GRDB type (issue
//  #113).
//

import Foundation


extension GRDBDatabase: XLDriverRequestFactory {}


/// A declared query read from a `GRDBDatabase` renders with its encoder
/// (issue #113).
extension GRDBDatabase: XLEncoderProviding {}


/// Implied by the package request factory, and written out because it is
/// public API and the factory is not (issue #113).
extension GRDBDatabase: XLValueCodingDatabase {}


extension GRDBDatabase {

    public func makeRequest<Row: Sendable>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row> {
        makeQueryRequest(with: statement)
    }

    /// Prepares an immutable raw-value runtime handle for concurrent
    /// invocations of one rendered statement.
    ///
    /// The handle intentionally does not retain the typed v1 row-reader graph.
    /// Callers that need typed decoding can use `makeRequest(with:)`; static
    /// typed descriptors build on this raw execution seam separately.
    public func prepareInvocation(
        with statement: any XLEncodable
    ) -> XLPreparedInvocation {
        makePreparedInvocation(with: statement)
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
    ) throws -> XLPreparedStaticQuery {
        try makePreparedStaticQuery(with: descriptor)
    }

    /// Prepares a typed static query only after its generated row layout has
    /// been proven equal to the descriptor's complete result metadata.
    public func prepareInvocation<Row>(
        with definition: XLTypedStaticQueryDescriptor<
            Row,
            XLSQLiteDialect
        >
    ) throws -> XLPreparedTypedStaticQuery<Row> {
        try makePreparedTypedStaticQuery(with: definition)
    }
    
    public func makeRequest<Row: Sendable>(with statement: any XLReturningStatement<Row>) -> any XLRequest<Row> {
        makeReturningRequest(with: statement)
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
}


// MARK: - GRDB names

/// The GRDB specialisation of the read request that ``GRDBDatabase`` makes.
typealias GRDBRequest<Row: Sendable> = XLDriverRequest<GRDBDatabaseDriver, Row>


/// The GRDB specialisation of the write request that ``GRDBDatabase`` makes.
typealias GRDBWriteRequest = XLDriverWriteRequest<GRDBDatabaseDriver>


/// The GRDB specialisation every GRDB-backed path builds on.
typealias GRDBInvocationExecutor = XLInvocationExecutor<GRDBDatabaseDriver>


/// The name this handle had before it stopped naming its driver (issue #682).
public typealias GRDBPreparedInvocation = XLPreparedInvocation


/// The name this handle had before it stopped naming its driver (issue #682).
public typealias GRDBPreparedStaticQuery = XLPreparedStaticQuery


/// The name this handle had before it stopped naming its driver (issue #682).
public typealias GRDBPreparedTypedStaticQuery<Row> = XLPreparedTypedStaticQuery<Row>


/// The name this error had before it stopped naming GRDB (issue #113).
@available(*, deprecated, renamed: "XLStaticQueryInvocationError")
public typealias GRDBStaticQueryError = XLStaticQueryInvocationError


/// The name this argument had before it stopped naming GRDB (issue #113).
@available(*, deprecated, renamed: "XLStaticQueryArgument")
public typealias GRDBStaticQueryArgument = XLStaticQueryArgument


/// The name this builder had before it stopped naming GRDB (issue #113).
@available(*, deprecated, renamed: "XLStaticQueryInvocationBuilder")
public typealias GRDBStaticQueryInvocationBuilder = XLStaticQueryInvocationBuilder
