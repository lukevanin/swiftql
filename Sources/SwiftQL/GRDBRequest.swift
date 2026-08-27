//
//  GRDBRequest.swift
//  SwiftQL
//
//  The typed read request: what it holds, and the legacy mutable
//  `set(parameter:value:)` facade that predates immutable invocation packets.
//
//  Split out of GRDBSQLDatabase.swift (issue #560). Its execution strategies --
//  eager fetch, lazy result set, and live query -- are three different things
//  that happened to live in one 500-line struct, and are now three files.
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


struct GRDBRequest<Row>: XLRequest {

    let executor: GRDBInvocationExecutor

    /// Immutable value-coding policy captured when this request is created.
    let codingConfiguration: XLValueCodingConfiguration
    
    let logger: XLLogger?
    
    let reader: any XLRowReadable<Row>

    /// A `RETURNING` statement writes as it reads, so its rows must be decoded
    /// on a write connection inside a transaction; a plain query reads on a
    /// read-only connection. Observation is unsupported in the write mode
    /// because re-running a data-changing statement on every database change is
    /// never the intended behavior.
    let requiresWriteConnection: Bool

    let liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy

    let liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler

    var compatibilityBindings: XLInvocationBindings<XLSQLiteValue>

    var compatibilityBindingError: XLInvocationBindingError?

    init(
        driver: GRDBDatabaseDriver,
        codingConfiguration: XLValueCodingConfiguration,
        logger: XLLogger?,
        reader: any XLRowReadable<Row>,
        logicalStatement: XLLogicalPreparedStatement,
        parameterLayoutError: XLInvocationBindingError? = nil,
        valueEncodingError: XLSQLValueEncodingError? = nil,
        requiresWriteConnection: Bool = false,
        customFunctions: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [:],
        liveQueryRetryPolicy: GRDBLiveQueryRetryPolicy,
        liveQueryRetryScheduler: GRDBLiveQueryRetryScheduler
    ) {
        self.requiresWriteConnection = requiresWriteConnection
        self.executor = GRDBInvocationExecutor(
            driver: driver,
            logicalStatement: logicalStatement,
            parameterLayoutError: parameterLayoutError,
            valueEncodingError: valueEncodingError,
            customFunctions: customFunctions
        )
        self.codingConfiguration = codingConfiguration
        self.logger = logger
        self.reader = reader
        self.liveQueryRetryPolicy = liveQueryRetryPolicy
        self.liveQueryRetryScheduler = liveQueryRetryScheduler
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
}
