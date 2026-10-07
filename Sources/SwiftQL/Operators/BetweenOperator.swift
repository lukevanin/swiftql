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

    public init(
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
