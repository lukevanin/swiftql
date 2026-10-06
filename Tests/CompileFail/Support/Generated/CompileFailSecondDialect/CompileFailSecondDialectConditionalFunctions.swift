//
//  CompileFailSecondDialectConditionalFunctions.swift
//
//  Generated for the compile-fail second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ConditionalFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - IIF


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any CompileFailSecondDialectExpression<U>, then: any CompileFailSecondDialectExpression<T>, else: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<T> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any CompileFailSecondDialectExpression<U>, then: any CompileFailSecondDialectExpression<Optional<T>>, else: any CompileFailSecondDialectExpression<T>) -> some CompileFailSecondDialectExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any CompileFailSecondDialectExpression<U>, then: any CompileFailSecondDialectExpression<T>, else: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any CompileFailSecondDialectExpression<U>, then: any CompileFailSecondDialectExpression<Optional<T>>, else: any CompileFailSecondDialectExpression<Optional<T>>) -> some CompileFailSecondDialectExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


extension CompileFailSecondDialectExpression where T: XLBoolean {

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any CompileFailSecondDialectExpression<V>, else: any CompileFailSecondDialectExpression<V>) -> some CompileFailSecondDialectExpression<V> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any CompileFailSecondDialectExpression<Optional<V>>, else: any CompileFailSecondDialectExpression<V>) -> some CompileFailSecondDialectExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any CompileFailSecondDialectExpression<V>, else: any CompileFailSecondDialectExpression<Optional<V>>) -> some CompileFailSecondDialectExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any CompileFailSecondDialectExpression<Optional<V>>, else: any CompileFailSecondDialectExpression<Optional<V>>) -> some CompileFailSecondDialectExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }
}
