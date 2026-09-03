//
//  SQLCustomFunction.swift
//  
//
//  Created by Luke Van In on 2023/08/08.
//

import Foundation
import GRDB


/// A SwiftQL expression whose implementation is registered as a SQLite scalar function.
///
/// Supply ``definition`` for the SQL signature, emit a call to that signature from your
/// `makeSQL(context:)` implementation, and implement ``execute(reader:)`` to calculate a result
/// from the SQLite arguments.
public protocol XLCustomFunction<T>: XLExpression {
    /// The name and argument count used to register the function.
    static var definition: XLCustomFunctionDefinition { get }

    /// Evaluates one invocation using values supplied by SQLite.
    ///
    /// - Parameter reader: A reader positioned over the function arguments.
    /// - Returns: The value returned to SQLite.
    static func execute(reader: XLColumnReader) throws -> T
}


/// Type-erased identity and GRDB registration thunk for one ``XLCustomFunction`` referenced
/// while a statement is rendered to SQL.
///
/// The renderer records one of these every time ``XLBuilder/customFunctionCall(_:parameters:)``
/// emits a call to a custom function. A driver can then register the underlying SQLite function
/// automatically -- the first time a rendered statement references it, on whatever physical
/// connection happens to execute the statement -- without the caller registering it upfront with
/// ``GRDBDatabaseBuilder/addFunction(_:)``.
public struct XLCustomFunctionRegistration: Sendable {

    /// The SQLite registration signature. Two registrations sharing a definition register the
    /// same SQLite function and are interchangeable.
    public let definition: XLCustomFunctionDefinition

    /// Whether a function already on the connection wins over this one.
    ///
    /// "Already on the connection" is decided by signature, not by name alone:
    /// the same name and either the same argument count or the `-1` SQLite
    /// reports for a variadic function, which can serve a fixed-arity call.
    ///
    /// `false` for a registration made from an application's own
    /// ``XLCustomFunction``: the caller referenced that type in the statement, so
    /// registering it is what the caller asked for.
    ///
    /// `true` for a function SwiftQL bundles, such as its own `regexp`
    /// implementation for the `REGEXP` operator. A bundled function is a
    /// default, not an instruction, so it must never replace an implementation
    /// the application registered itself.
    ///
    /// Derived from `bundled` rather than stored, so the two cannot disagree
    /// about which functions SwiftQL supplies.
    var defersToExistingRegistration: Bool {
        Self.bundled[definition] != nil
    }

    let makeDatabaseFunction: @Sendable () -> DatabaseFunction

    init(
        definition: XLCustomFunctionDefinition,
        makeDatabaseFunction: @escaping @Sendable () -> DatabaseFunction
    ) {
        self.definition = definition
        self.makeDatabaseFunction = makeDatabaseFunction
    }

    /// Every function SwiftQL supplies itself, by its SQLite signature.
    ///
    /// Two things read this. The driver skips a bundled registration when the
    /// application already provides that function. And a static query
    /// descriptor, which cannot carry a registration closure, records the
    /// signatures it needs and resolves them back through this table when the
    /// statement is prepared -- see
    /// `XLStaticStatementDefinition.bundledFunctions`.
    ///
    ///
    /// A function belongs here only if SwiftQL can reconstruct it from its
    /// signature alone. An application's own ``XLCustomFunction`` cannot be,
    /// which is why implicit registration still does not reach the static path
    /// for those.
    static let bundled: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [
        XLRegexpFunction.definition: .bundledRegexp,
    ]

    /// Creates a registration for one custom function type.
    public static func make<F>(_ type: F.Type) -> XLCustomFunctionRegistration
    where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        // Captured as plain values rather than the generic metatype `F.Type` itself, so GRDB's
        // `@Sendable` function closure below never needs to carry an unconstrained generic
        // parameter across the isolation boundary.
        let functionDefinition = F.definition
        // `F.execute` is a static function with no captured state -- calling it concurrently
        // from multiple pooled connections is exactly this feature's purpose -- so it is safe to
        // treat as `@Sendable`. `unsafeBitCast` only changes the compile-time `@Sendable`
        // annotation, never the function value's runtime representation, so this is safe
        // regardless of what concrete type `F` turns out to be; the strict-concurrency checker
        // cannot infer that safety for a reference derived from an unconstrained generic type.
        let executeFunction = unsafeBitCast(
            F.execute(reader:) as (XLColumnReader) throws -> F.T,
            to: (@Sendable (XLColumnReader) throws -> F.T).self
        )
        return XLCustomFunctionRegistration(
            definition: functionDefinition,
            makeDatabaseFunction: {
                DatabaseFunction(
                    functionDefinition.name,
                    argumentCount: Int(functionDefinition.numberOfArguments),
                    function: { values in
                        let reader = GRDBValuesAdapter(values: values)
                        return try executeFunction(reader)
                    }
                )
            }
        )
    }
}


extension XLBuilder {

    /// Adds a call to a registered custom scalar function and records its SQLite registration so
    /// a driver can register the function implicitly.
    ///
    /// Implement `makeSQL(context:)` on an ``XLCustomFunction`` conformer using this method
    /// instead of calling `simpleFunction(name:parameters:)` directly to opt into implicit,
    /// on-demand registration. Conformers that continue calling `simpleFunction` directly keep
    /// working exactly as before -- SwiftQL has no way to know a bare function-name string
    /// identifies a custom function, so those functions still require an upfront
    /// ``GRDBDatabaseBuilder/addFunction(_:)`` call.
    ///
    /// - Parameters:
    ///   - type: The custom function type being called.
    ///   - parameters: Constructs the list of arguments passed to the function.
    public mutating func customFunctionCall<F>(
        _ type: F.Type,
        parameters: ListBuilder
    ) where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        customFunction(.make(type))
        simpleFunction(name: type.definition.name, parameters: parameters)
    }
}
