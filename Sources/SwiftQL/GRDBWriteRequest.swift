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
    
    var compatibilityBindings: XLInvocationBindings<XLSQLiteValue>

    var compatibilityBindingError: XLInvocationBindingError?
    
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
        self.compatibilityBindings = XLInvocationBindings(
            layout: logicalStatement.parameterLayout
        )
        self.compatibilityBindingError = parameterLayoutError
    }

    var parameterLayout: XLParameterLayout {
        executor.parameterLayout
    }
    
    public mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: Optional<T>.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            if let value {
                value.bind(context: &context)
            }
            else {
                context.bindNull()
            }
        }
    }

    public mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: T.self,
                key: .named(reference.name.rawValue)
            )
        ) { context in
            value.bind(context: &context)
        }
    }
    
    mutating func bindValue(
        declaration: XLParameterDeclaration,
        bind: (inout XLBindingContext) -> Void
    ) {
        guard let slot = parameterLayout.slot(for: declaration.key) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterDeclarationNotInLayout(
                    declaration: declaration
                )
            }
            return
        }
        guard slot.acceptsLegacySet(declaration) else {
            if compatibilityBindingError == nil {
                compatibilityBindingError = .parameterMetadataMismatch(
                    expected: slot,
                    actual: declaration.slot(at: slot.index)
                )
            }
            return
        }
        // No NaN guard here: this legacy setter has no throwing channel, and
        // `compatibilityBindingError` carries an `XLInvocationBindingError`
        // rather than an encoding error. The driver boundary rejects a NaN
        // `REAL` for this path when the packet is executed.
        let value = _xlCapturedSQLiteValue(of: declaration.valueTypeName) { context in
            bind(&context)
        }
        do {
            compatibilityBindings = try replacingBinding(
                value,
                at: slot,
                in: compatibilityBindings
            )
        }
        catch let error as XLInvocationBindingError {
            if compatibilityBindingError == nil {
                compatibilityBindingError = error
            }
        }
        catch {
            preconditionFailure("Unexpected invocation binding error: \(error)")
        }
    }
    
    func execute() throws {
        if let compatibilityBindingError {
            throw compatibilityBindingError
        }
        try execute(bindings: compatibilityBindings)
    }

    func execute(
        bindings: any XLInvocationBindingPacket
    ) throws {
        let packet = try executor.sqlitePacket(bindings)
        logger?.debug(
            "execute: <<<\(executor.logicalStatement.sql)>>> parameters: <<<\(packet.bindings)>>>")
        try executor.execute(bindings: packet)
    }
}
