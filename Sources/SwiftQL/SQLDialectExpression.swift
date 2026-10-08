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

    init(_ wrapped: any XLEncodable) {
        self.wrapped = wrapped
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
