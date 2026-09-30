//
//  SQLCustomFunctionRegistration.swift
//  SwiftQLCore
//
//  A scalar function a statement needs, as data any adapter can install
//  (issue #683). The registration used to hold a GRDB `DatabaseFunction`
//  closure, so only the GRDB adapter could execute a statement that called a
//  custom function or used `REGEXP`.
//

import Foundation


///
/// Evaluates one call of a custom scalar function.
///
/// It receives the call's arguments as SQLite values, in order, and returns
/// the result as one. An error it throws fails the statement that made the
/// call.
///
public typealias XLCustomFunctionEvaluator = @Sendable ([XLSQLiteValue]) throws -> XLSQLiteValue


///
/// One scalar function a rendered statement calls, and how to evaluate it.
///
/// The renderer records one every time a statement calls a function SwiftQL can
/// supply: an application's own `XLCustomFunction`, or a function SwiftQL
/// bundles, such as `regexp` for the `REGEXP` operator. The statement carries
/// its registrations to the driver (see
/// ``XLLogicalPreparedStatement/requiredFunctions``), and the connection makes
/// each one available before it prepares the statement, on whatever physical
/// connection executes it (see
/// ``XLDatabaseDriverConnection/installRequiredFunctions(_:)``). No caller has
/// to register the function upfront.
///
/// A registration holds no database library's types, so any adapter can build
/// its own function object from it.
///
/// Two registrations are equal when they install the same way: the same
/// ``definition``, ``defersToExistingRegistration``, and ``isPure``. The
/// evaluator is a closure, which cannot be compared, and registrations that
/// share a definition are interchangeable anyway.
///
public struct XLCustomFunctionRegistration: Hashable, Sendable {

    /// The SQLite registration signature. Two registrations sharing a
    /// definition register the same SQLite function and are interchangeable.
    public let definition: XLCustomFunctionDefinition

    /// Whether a function already on the connection wins over this one.
    ///
    /// "Already on the connection" is decided by signature, not by name alone:
    /// the same name and either the same argument count or the `-1` SQLite
    /// reports for a variadic function, which can serve a fixed-arity call.
    ///
    /// `false` for a registration made from an application's own
    /// `XLCustomFunction`: the caller referenced that type in the statement, so
    /// registering it is what the caller asked for. That holds even when the
    /// caller's function reuses a signature SwiftQL bundles -- an application
    /// that writes its own `regexp/2` as an `XLCustomFunction` and calls it
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
    public let defersToExistingRegistration: Bool

    /// Whether the function's result depends only on its arguments.
    ///
    /// A pure function lets SQLite evaluate a call whose arguments do not
    /// change between rows once, rather than once per row.
    public let isPure: Bool

    /// Makes the evaluator for one installation of the function.
    ///
    /// An adapter calls it once each time it installs the function on a
    /// physical connection, so an evaluator can keep state that belongs to
    /// that connection, such as the compiled-pattern cache the bundled
    /// `regexp` keeps.
    public let makeEvaluator: @Sendable () -> XLCustomFunctionEvaluator

    /// Values the rendered statement depends on for as long as it can execute.
    ///
    /// Held, never read. The encoding carries registrations to every request
    /// and prepared invocation made from it, so a value stored here lives as
    /// long as the longest of those. `REGEXP` stores each `XLRegexPattern`
    /// the statement matches against here: the pattern registry holds a
    /// pattern weakly, and the rendered SQL carries only its key (issue #646).
    package let retainedValues: [any Sendable]

    /// Creates a registration.
    ///
    /// - Parameters:
    ///   - definition: The SQLite registration signature.
    ///   - defersToExistingRegistration: Whether a function the connection
    ///     already provides for `definition` wins over this one.
    ///   - isPure: Whether the result depends only on the arguments.
    ///   - makeEvaluator: Makes the evaluator for one installation.
    public init(
        definition: XLCustomFunctionDefinition,
        defersToExistingRegistration: Bool = false,
        isPure: Bool = false,
        makeEvaluator: @escaping @Sendable () -> XLCustomFunctionEvaluator
    ) {
        self.init(
            definition: definition,
            defersToExistingRegistration: defersToExistingRegistration,
            isPure: isPure,
            retainedValues: [],
            makeEvaluator: makeEvaluator
        )
    }

    package init(
        definition: XLCustomFunctionDefinition,
        defersToExistingRegistration: Bool,
        isPure: Bool,
        retainedValues: [any Sendable],
        makeEvaluator: @escaping @Sendable () -> XLCustomFunctionEvaluator
    ) {
        self.definition = definition
        self.defersToExistingRegistration = defersToExistingRegistration
        self.isPure = isPure
        self.retainedValues = retainedValues
        self.makeEvaluator = makeEvaluator
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.definition == rhs.definition
            && lhs.defersToExistingRegistration == rhs.defersToExistingRegistration
            && lhs.isPure == rhs.isPure
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(definition)
        hasher.combine(defersToExistingRegistration)
        hasher.combine(isPure)
    }

    /// This registration, additionally holding `values`.
    ///
    /// The function registered is unchanged: only what the registration keeps
    /// alive grows.
    package func retaining(_ values: [any Sendable]) -> XLCustomFunctionRegistration {
        XLCustomFunctionRegistration(
            definition: definition,
            defersToExistingRegistration: defersToExistingRegistration,
            isPure: isPure,
            retainedValues: retainedValues + values,
            makeEvaluator: makeEvaluator
        )
    }

    /// Every function SwiftQL supplies itself, by its SQLite signature.
    ///
    /// Three things read this. A driver skips a bundled registration when the
    /// application already provides that function. A static query descriptor,
    /// which records only the signatures it needs, resolves them back through
    /// this table when the statement is prepared -- see
    /// `XLStaticStatementDefinition.bundledFunctions`. And the SQLite build
    /// validator installs exactly these on the connection it prepares
    /// statements against, so it and the runtime cannot disagree.
    ///
    /// A function belongs here only if SwiftQL can reconstruct it from its
    /// signature alone. An application's own `XLCustomFunction` cannot be,
    /// which is why implicit registration still does not reach the static path
    /// for those.
    public static let bundled: [XLCustomFunctionDefinition: XLCustomFunctionRegistration] = [
        XLRegexpFunction.definition: .bundledRegexp,
    ]

    ///
    /// Registration for the bundled ``XLRegexpFunction``.
    ///
    /// Recorded by every `XLExpression.regexp(_:)` overload while a statement
    /// renders, so the driver registers the function on whichever connection
    /// executes that statement.
    ///
    /// ``defersToExistingRegistration`` is `true`: an application that already
    /// provides `regexp` keeps it. Without that, registering here would replace
    /// the caller's function, because `sqlite3_create_function` replaces any
    /// earlier registration of the same name and argument count, and every
    /// caller-supplied registration necessarily runs earlier -- both
    /// `GRDBDatabaseBuilder.addFunction(_:)` and GRDB's
    /// `Configuration.prepareDatabase(_:)` run when a connection opens, and
    /// this runs before the first statement that needs it on a connection.
    ///
    /// The function is pure. Its result depends only on its two arguments,
    /// which lets SQLite hoist a call whose arguments do not change between
    /// rows.
    ///
    public static let bundledRegexp = XLCustomFunctionRegistration(
        definition: XLRegexpFunction.definition,
        defersToExistingRegistration: true,
        isPure: true,
        makeEvaluator: {
            // A fresh cache per installation. The driver installs the function
            // once per physical connection, so the cache belongs to that
            // connection and lasts as long as the installation. See
            // `XLRegexpPatternCache` for why it is not process-wide.
            let cache = XLRegexpPatternCache()
            return { arguments in
                guard let matches = try XLRegexpFunction.evaluate(arguments, cache: cache) else {
                    return .null
                }
                return .integer(matches ? 1 : 0)
            }
        }
    )
}
