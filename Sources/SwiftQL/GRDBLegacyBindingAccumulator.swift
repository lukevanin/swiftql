//
//  GRDBLegacyBindingAccumulator.swift
//  SwiftQL
//
//  The v1 mutable `set(parameter:value:)` facade, in one place (issue #561).
//
//  `GRDBRequest` and `GRDBWriteRequest` carried verbatim-identical copies of
//  it -- the two `set` overloads and the `bindValue` that backs them, about
//  seventy lines including the trap on an unexpected error type. The two
//  request kinds have nothing else in common, so nothing would have caught the
//  copies drifting; what they would produce is one request kind accepting a
//  binding the other rejects.
//

import Foundation


///
/// Accumulates the bindings set through the v1 mutable request facade, and the
/// first error that facade could not report.
///
/// The facade predates immutable invocation packets: `set` is not throwing, so
/// a rejected binding cannot fail where it is written. The first failure is
/// held until the request is executed, and later ones are dropped -- the first
/// is the one that describes what went wrong, and reporting the rest would bury
/// it.
///
struct GRDBLegacyBindingAccumulator {

    /// The bindings set so far.
    private(set) var bindings: XLInvocationBindings<XLSQLiteValue>

    /// The first binding failure, if any.
    private(set) var error: XLInvocationBindingError?

    /// - Parameters:
    ///   - layout: The rendered statement's parameter layout, which every
    ///     binding is checked against.
    ///   - initialError: A layout that failed to render is already an error;
    ///     it is carried here so the request fails on execution rather than
    ///     appearing to accept bindings against a layout that does not exist.
    init(
        layout: XLParameterLayout,
        initialError: XLInvocationBindingError? = nil
    ) {
        self.bindings = XLInvocationBindings(layout: layout)
        self.error = initialError
    }

    /// Binds a value to a named parameter.
    mutating func set<T>(
        _ value: T,
        named name: XLName
    ) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: T.self,
                key: .named(name.rawValue)
            )
        ) { context in
            value.bind(context: &context)
        }
    }

    /// Binds an optional value to a nullable named parameter, writing SQL
    /// `NULL` for `nil`.
    mutating func set<T>(
        optional value: T?,
        named name: XLName
    ) where T: XLBindable {
        bindValue(
            declaration: _xlLegacyParameterDeclaration(
                for: Optional<T>.self,
                key: .named(name.rawValue)
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

    ///
    /// Resolves `declaration` against the layout, captures the value `bind`
    /// writes, and records it -- or records why it could not be.
    ///
    mutating func bindValue(
        declaration: XLParameterDeclaration,
        bind: (inout XLBindingContext) -> Void
    ) {
        guard let slot = bindings.layout.slot(for: declaration.key) else {
            record(.parameterDeclarationNotInLayout(declaration: declaration))
            return
        }
        guard slot.acceptsLegacySet(declaration) else {
            record(
                .parameterMetadataMismatch(
                    expected: slot,
                    actual: declaration.slot(at: slot.index)
                )
            )
            return
        }
        // No NaN guard here: this legacy setter has no throwing channel, and
        // `error` carries an `XLInvocationBindingError` rather than an encoding
        // error. The driver boundary rejects a NaN `REAL` for this path when
        // the packet is executed.
        let value = _xlCapturedSQLiteValue(of: declaration.valueTypeName) { context in
            bind(&context)
        }
        do {
            bindings = try replacingBinding(value, at: slot, in: bindings)
        }
        catch let error as XLInvocationBindingError {
            record(error)
        }
        catch {
            preconditionFailure("Unexpected invocation binding error: \(error)")
        }
    }

    /// The accumulated bindings, or the first failure that stopped them from
    /// being what the caller asked for.
    func packet() throws -> XLInvocationBindings<XLSQLiteValue> {
        if let error {
            throw error
        }
        return bindings
    }

    private mutating func record(_ error: XLInvocationBindingError) {
        guard self.error == nil else {
            return
        }
        self.error = error
    }
}
