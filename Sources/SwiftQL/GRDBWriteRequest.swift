//
//  GRDBWriteRequest.swift
//  SwiftQL
//
//  The untyped write request: a statement that changes the database and
//  returns no rows.
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


struct GRDBWriteRequest: XLWriteRequest {

    let executor: GRDBInvocationExecutor

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration
    
    let logger: XLLogger?
    
    /// Bindings set through the v1 mutable `set(parameter:value:)` facade.
    var legacyBindings: GRDBLegacyBindingAccumulator
    
    init(
        driver: GRDBDatabaseDriver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        customFunctions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [:]
    ) {
        self.executor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError,
            customFunctions: customFunctions
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.legacyBindings = GRDBLegacyBindingAccumulator(
            layout: logicalStatement.parameterLayout,
            initialError: parameterLayoutError
        )
    }

    var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        legacyBindings.set(optional: value, named: reference.name)
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        legacyBindings.set(value, named: reference.name)
    }
    
    func execute() throws {
        try execute(bindings: try legacyBindings.packet())
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "execute: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        try executor.execute(packet: packet)
    }
}
