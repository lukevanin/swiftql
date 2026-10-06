//
//  ConditionalFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/28.
//

import Foundation


// MARK: - IIF


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U, Dialect>(_ condition: any XLExpression<U, Dialect>, then: any XLTypedExpression<T>, else: any XLTypedExpression<T>) -> some XLExpression<T, Dialect> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U, Dialect>(_ condition: any XLExpression<U, Dialect>, then: any XLTypedExpression<Optional<T>>, else: any XLTypedExpression<T>) -> some XLExpression<Optional<T>, Dialect> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U, Dialect>(_ condition: any XLExpression<U, Dialect>, then: any XLTypedExpression<T>, else: any XLTypedExpression<Optional<T>>) -> some XLExpression<Optional<T>, Dialect> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U, Dialect>(_ condition: any XLExpression<U, Dialect>, then: any XLTypedExpression<Optional<T>>, else: any XLTypedExpression<Optional<T>>) -> some XLExpression<Optional<T>, Dialect> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


extension XLExpression where T: XLBoolean {

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLTypedExpression<V>, else: any XLTypedExpression<V>) -> some XLExpression<V, Dialect> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLTypedExpression<Optional<V>>, else: any XLTypedExpression<V>) -> some XLExpression<Optional<V>, Dialect> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLTypedExpression<V>, else: any XLTypedExpression<Optional<V>>) -> some XLExpression<Optional<V>, Dialect> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLTypedExpression<Optional<V>>, else: any XLTypedExpression<Optional<V>>) -> some XLExpression<Optional<V>, Dialect> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }
}
