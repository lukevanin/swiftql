//
//  CompileFailSecondDialectBetweenOperator.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/BetweenOperator.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


extension CompileFailSecondDialectExpression where T: XLComparable {

    /// Returns whether this expression is inclusively between two compatible bounds.
    @_disfavoredOverload
    func isBetween(
        _ minimum: any CompileFailSecondDialectExpression<T>,
        _ maximum: any CompileFailSecondDialectExpression<T>
    ) -> some CompileFailSecondDialectExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns whether this expression is outside two compatible inclusive bounds.
    @_disfavoredOverload
    func isNotBetween(
        _ minimum: any CompileFailSecondDialectExpression<T>,
        _ maximum: any CompileFailSecondDialectExpression<T>
    ) -> some CompileFailSecondDialectExpression<Bool> {
        XLBetweenExpression<Bool>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}


extension CompileFailSecondDialectExpression {

    /// Returns `nil` for a `NULL` expression, or whether its value is inclusively between the bounds.
    @_disfavoredOverload
    func isBetween<Wrapped>(
        _ minimum: any CompileFailSecondDialectExpression<Wrapped>,
        _ maximum: any CompileFailSecondDialectExpression<Wrapped>
    ) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum
        )
    }

    /// Returns `nil` for a `NULL` expression, or whether its value is outside the bounds.
    @_disfavoredOverload
    func isNotBetween<Wrapped>(
        _ minimum: any CompileFailSecondDialectExpression<Wrapped>,
        _ maximum: any CompileFailSecondDialectExpression<Wrapped>
    ) -> some CompileFailSecondDialectExpression<Optional<Bool>> where T == Optional<Wrapped>, Wrapped: XLComparable {
        XLBetweenExpression<Optional<Bool>>(
            term: self,
            minimum: minimum,
            maximum: maximum,
            negated: true
        )
    }
}
