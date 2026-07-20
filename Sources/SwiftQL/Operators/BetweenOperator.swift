//
//  BetweenOperator.swift
//

import Foundation


/// A typed SQLite `BETWEEN` or `NOT BETWEEN` expression.
public struct XLBetweenExpression<T>: XLExpression {

    private let term: any XLExpression

    private let minimum: any XLExpression

    private let maximum: any XLExpression

    private let negated: Bool

    init(
        term: any XLExpression,
        minimum: any XLExpression,
        maximum: any XLExpression,
        negated: Bool = false
    ) {
        self.term = term
        self.minimum = minimum
        self.maximum = maximum
        self.negated = negated
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            if negated {
                context.binaryOperator(
                    "NOT BETWEEN",
                    left: term.makeSQL,
                    right: { context in
                        context.binaryOperator(
                            "AND",
                            left: minimum.makeSQL,
                            right: maximum.makeSQL
                        )
                    }
                )
            }
            else {
                context.between(
                    term: term.makeSQL,
                    minimum: minimum.makeSQL,
                    maximum: maximum.makeSQL
                )
            }
        }
    }
}


extension XLExpression where T: XLComparable {

    /// Returns whether this expression is inclusively between two compatible bounds.
    public func isBetween(
        _ minimum: any XLExpression<T>,
        _ maximum: any XLExpression<T>
    ) -> some XLExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns whether this expression is outside two compatible inclusive bounds.
    public func isNotBetween(
        _ minimum: any XLExpression<T>,
        _ maximum: any XLExpression<T>
    ) -> some XLExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}


extension XLExpression {

    /// Returns `nil` for a `NULL` expression, or whether its value is inclusively between the bounds.
    public func isBetween<Wrapped>(
        _ minimum: any XLExpression<Wrapped>,
        _ maximum: any XLExpression<Wrapped>
    ) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns `nil` for a `NULL` expression, or whether its value is outside the bounds.
    public func isNotBetween<Wrapped>(
        _ minimum: any XLExpression<Wrapped>,
        _ maximum: any XLExpression<Wrapped>
    ) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}
