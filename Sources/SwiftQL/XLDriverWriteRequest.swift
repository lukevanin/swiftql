//
//  XLDriverWriteRequest.swift
//  SwiftQL
//
//  The untyped write request: a statement that changes the database and
//  returns no rows.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation


/// The write request of any blocking driver of the SQLite dialect (issue
/// #682). It runs each statement in a transaction on the writer connection.
package struct XLDriverWriteRequest<Driver: XLBlockingDatabaseDriver>: XLWriteRequest
    where Driver.Dialect == XLSQLiteDialect
{

    package let executor: XLInvocationExecutor<Driver>

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration
    
    let logger: XLLogger?
    
    /// Bindings set through the v1 mutable `set(parameter:value:)` facade.
    package var legacyBindings: XLLegacyBindingAccumulator
    
    init(
        driver: Driver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil
    ) {
        self.executor = XLInvocationExecutor<Driver>(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
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
    
    @discardableResult
    package func execute() throws -> XLExecutionResult {
        try execute(bindings: try legacyBindings.packet())
    }

    @discardableResult
    package func execute(
        bindings: any XLInvocationBindingPacket
    ) throws -> XLExecutionResult {
        try executor.execute(
            packet: executor.validatedPacket(bindings, for: "execute", logger: logger)
        )
    }
}
