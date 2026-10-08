//
//  SQLDialectExpression.swift
//  SwiftQL
//
//  The expression an API returns when it knows its dialect only as a generic
//  parameter (issue #789).
//

import Foundation


///
/// An expression of `Dialect`'s queries.
///
/// An operator or a function composes expressions of one dialect, so it takes
/// and returns that dialect's expression protocol, such as
/// ``XLSQLiteExpression``. An API that knows its dialect only as a generic
/// parameter, such as a scalar subquery on an ``XLSchema`` or the expression of
/// an ``XLStaticSelectField``, cannot name that protocol, so it returns its
/// expression as an `XLDialectExpression` instead. Each dialect's surface
/// declares `XLDialectExpression` one of its expressions where `Dialect` is
/// that dialect, so the expression composes with that dialect's columns and
/// values, and with no other dialect's.
///
/// Only SwiftQL creates one, from an expression it knows belongs to `Dialect`.
///
public struct XLDialectExpression<T, Dialect>: XLExpression {

    /// The expression this one renders, which belongs to `Dialect`.
    let wrapped: any XLEncodable

    /// Whether SwiftQL knows that every part of ``wrapped`` belongs to
    /// `Dialect`. A run-time dialect check trusts a verified expression and
    /// walks into one that is not (issue #825).
    let isVerified: Bool

    init(_ wrapped: any XLEncodable) {
        self.init(wrapped, verified: true)
    }

    private init(_ wrapped: any XLEncodable, verified: Bool) {
        self.wrapped = wrapped
        self.isVerified = verified
    }

    ///
    /// `expression` as an expression of `Dialect`, or `expression` itself
    /// when it already is one, so an expression is never wrapped twice.
    ///
    /// `verified` says that SwiftQL has checked every part of `expression`.
    /// A verified expression is returned as it is; an expression that is
    /// already one of `Dialect`'s but not verified is wrapped once more as a
    /// verified one.
    ///
    static func wrapping(
        _ expression: any XLEncodable,
        verified: Bool
    ) -> XLDialectExpression<T, Dialect> {
        if let existing = expression as? XLDialectExpression<T, Dialect>, existing.isVerified || !verified {
            return existing
        }
        return XLDialectExpression(expression, verified: verified)
    }

    ///
    /// The expression a generated `MetaUpdate` slot holds, read back as an
    /// expression of the model's dialect (issue #825).
    ///
    /// The slot's setter took only `Dialect`'s expressions, but a node built
    /// through its public initializer, a legacy value, or a slot of a dialect
    /// whose `XLAnyExpression` is `any XLExpression` holds parts of no
    /// recorded dialect, so the read is not verified: a run-time check walks
    /// into it. A read assigned back and read again is not wrapped again.
    ///
    static func reading(_ expression: any XLEncodable) -> XLDialectExpression<T, Dialect> {
        wrapping(expression, verified: false)
    }

    public func makeSQL(context: inout XLBuilder) {
        wrapped.makeSQL(context: &context)
    }
}


///
/// An expression that records the dialect it belongs to: a column of a model,
/// or a value encoded for one dialect.
///
/// The compiler keeps such an expression out of another dialect's operators
/// and functions. An API that takes an expression erased, such as a static
/// row layout's field factory, checks the dialect at run time instead.
///
protocol XLDialectTaggedExpression {

    /// The dialect the expression belongs to.
    var expressionDialect: Any.Type { get }
}


extension XLColumnReference: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


extension XLColumnResult: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


extension XLDialectExpression: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


///
/// An expression that records a dialect it has not verified, so a run-time
/// dialect check walks into the expression it wraps instead of trusting the
/// record (issue #825).
///
protocol XLUnverifiedDialectExpression {

    /// The wrapped expression when the record is not verified, or `nil` when
    /// it is.
    var unverifiedExpression: (any XLEncodable)? { get }
}


extension XLDialectExpression: XLUnverifiedDialectExpression {
    var unverifiedExpression: (any XLEncodable)? {
        isVerified ? nil : wrapped
    }
}


// A check that recognises a function by its name, such as the JSON value
// check that lets a `jsonb` result into a JSON function, sees through the
// wrapper. A wrapper of anything else has no name.
extension XLDialectExpression: XLNamedFunction {
    var functionName: String {
        (wrapped as? any XLNamedFunction)?.functionName ?? ""
    }
}


extension XLQueryCapture: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


extension XLContextualBindingReference: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


// A `CASE` expression keeps its arms in closures, which a walk of its stored
// properties cannot see into, so it records its dialect itself.

extension ConstantCaseWhenThen: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


extension ConstantCaseWhenThenElse: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


extension VariableCaseWhenThen: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}


extension VariableCaseElse: XLDialectTaggedExpression {
    var expressionDialect: Any.Type { Dialect.self }
}
