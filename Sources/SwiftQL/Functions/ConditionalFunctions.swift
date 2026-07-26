//
//  ConditionalFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/28.
//

import Foundation


// MARK: - IIF


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<T>, else: any XLExpression<T>) -> some XLExpression<T> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<Optional<T>>, else: any XLExpression<T>) -> some XLExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<T>, else: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<Optional<T>>, else: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


extension XLExpression where T: XLBoolean {

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLExpression<V>, else: any XLExpression<V>) -> some XLExpression<V> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLExpression<Optional<V>>, else: any XLExpression<V>) -> some XLExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLExpression<V>, else: any XLExpression<Optional<V>>) -> some XLExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLExpression<Optional<V>>, else: any XLExpression<Optional<V>>) -> some XLExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }
}
