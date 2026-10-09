//
//  QueryOnlyDialectBetweenOperator.swift
//
//  Generated for the query-only compile-fail dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/BetweenOperator.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
@_spi(XLDialectSurface) import SwiftQLQuery


extension QueryOnlyDialectExpression where T: XLComparable {

    /// Returns whether this expression is inclusively between two compatible bounds.
    func isBetween(
        _ minimum: any QueryOnlyDialectExpression<T>,
        _ maximum: any QueryOnlyDialectExpression<T>
    ) -> some QueryOnlyDialectExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns whether this expression is outside two compatible inclusive bounds.
    func isNotBetween(
        _ minimum: any QueryOnlyDialectExpression<T>,
        _ maximum: any QueryOnlyDialectExpression<T>
    ) -> some QueryOnlyDialectExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}


extension QueryOnlyDialectExpression {

    /// Returns `nil` for a `NULL` expression, or whether its value is inclusively between the bounds.
    func isBetween<Wrapped>(
        _ minimum: any QueryOnlyDialectExpression<Wrapped>,
        _ maximum: any QueryOnlyDialectExpression<Wrapped>
    ) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns `nil` for a `NULL` expression, or whether its value is outside the bounds.
    func isNotBetween<Wrapped>(
        _ minimum: any QueryOnlyDialectExpression<Wrapped>,
        _ maximum: any QueryOnlyDialectExpression<Wrapped>
    ) -> some QueryOnlyDialectExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}
