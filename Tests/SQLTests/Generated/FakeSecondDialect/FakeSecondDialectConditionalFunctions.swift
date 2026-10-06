//
//  FakeSecondDialectConditionalFunctions.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ConditionalFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - IIF


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any FakeSecondDialectExpression<U>, then: any FakeSecondDialectExpression<T>, else: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<T> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any FakeSecondDialectExpression<U>, then: any FakeSecondDialectExpression<Optional<T>>, else: any FakeSecondDialectExpression<T>) -> some FakeSecondDialectExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any FakeSecondDialectExpression<U>, then: any FakeSecondDialectExpression<T>, else: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
@_disfavoredOverload
func iif<T, U>(_ condition: any FakeSecondDialectExpression<U>, then: any FakeSecondDialectExpression<Optional<T>>, else: any FakeSecondDialectExpression<Optional<T>>) -> some FakeSecondDialectExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


extension FakeSecondDialectExpression where T: XLBoolean {

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any FakeSecondDialectExpression<V>, else: any FakeSecondDialectExpression<V>) -> some FakeSecondDialectExpression<V> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any FakeSecondDialectExpression<Optional<V>>, else: any FakeSecondDialectExpression<V>) -> some FakeSecondDialectExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any FakeSecondDialectExpression<V>, else: any FakeSecondDialectExpression<Optional<V>>) -> some FakeSecondDialectExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    @_disfavoredOverload
    func iif<V>(then: any FakeSecondDialectExpression<Optional<V>>, else: any FakeSecondDialectExpression<Optional<V>>) -> some FakeSecondDialectExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }
}
