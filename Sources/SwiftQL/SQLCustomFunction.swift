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
    /// registering it is what the caller asked for. That holds even when the
    /// caller's function reuses a signature SwiftQL bundles -- an application
    /// that writes its own `regexp/2` as an ``XLCustomFunction`` and calls it
    /// from a statement gets *that* implementation, not SwiftQL's.
    ///
    /// `true` for a function SwiftQL bundles, such as its own `regexp`
    /// implementation for the `REGEXP` operator. A bundled function is a
    /// default, not an instruction, so it must never replace an implementation
    /// the application registered itself.
    ///
    /// Stored rather than derived from ``bundled``, because the two questions
    /// differ: ``bundled`` asks whether SwiftQL can build an implementation for
    /// a signature, which it can even when the caller supplied their own type
    /// for that signature. `XLCustomFunctionRegistrationInvariantTests` pins
    /// that every entry in ``bundled`` sets this.
    let defersToExistingRegistration: Bool

    let makeDatabaseFunction: @Sendable () -> DatabaseFunction

    /// Values the rendered statement depends on for as long as it can execute.
    ///
    /// Held, never read. The encoding carries registrations to every request
    /// and prepared invocation made from it, so a value stored here lives as
    /// long as the longest of those. `REGEXP` stores each ``XLRegexPattern``
    /// the statement matches against here: the pattern registry holds a
    /// pattern weakly, and the rendered SQL carries only its key (issue #646).
    let retainedValues: [any Sendable]

    init(
        definition: XLCustomFunctionDefinition,
        defersToExistingRegistration: Bool = false,
        retainedValues: [any Sendable] = [],
        makeDatabaseFunction: @escaping @Sendable () -> DatabaseFunction
    ) {
        self.definition = definition
        self.defersToExistingRegistration = defersToExistingRegistration
        self.retainedValues = retainedValues
        self.makeDatabaseFunction = makeDatabaseFunction
    }

    /// This registration, additionally holding `values`.
    ///
    /// The function registered is unchanged: only what the registration keeps
    /// alive grows.
    func retaining(_ values: [any Sendable]) -> XLCustomFunctionRegistration {
        XLCustomFunctionRegistration(
            definition: definition,
            defersToExistingRegistration: defersToExistingRegistration,
            retainedValues: retainedValues + values,
            makeDatabaseFunction: makeDatabaseFunction
        )
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
    where F: XLCustomFunction, F.T: DatabaseValueConvertible & Sendable {
        // Captured as plain values rather than the generic metatype `F.Type` itself, so GRDB's
        // `@Sendable` function closure below never needs to carry an unconstrained generic
        // parameter across the isolation boundary. `F.T: Sendable` covers the one metatype that
        // remains: the closure converts an `F.T` result to GRDB's existential return type, and a
        // `Sendable` type has a `Sendable` metatype.
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
    ) where F: XLCustomFunction, F.T: DatabaseValueConvertible & Sendable {
        customFunction(.make(type))
        simpleFunction(name: type.definition.name, parameters: parameters)
    }
}
