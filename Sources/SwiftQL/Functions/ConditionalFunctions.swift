//
//  ConditionalFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/28.
//

import Foundation

// SQLite's own: `IIF`. Declared only on a SQLite expression, not generated
// for every dialect (issue #789).


// MARK: - IIF


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLSQLiteExpression<U>, then: any XLSQLiteExpression<T>, else: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLSQLiteExpression<U>, then: any XLSQLiteExpression<Optional<T>>, else: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLSQLiteExpression<U>, then: any XLSQLiteExpression<T>, else: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


@available(*, deprecated, message: "Use condition.iif(then:else:) instead. iif(_:then:else:) will be removed in SwiftQL 2.")
public func iif<T, U>(_ condition: any XLSQLiteExpression<U>, then: any XLSQLiteExpression<Optional<T>>, else: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


extension XLSQLiteExpression where T: XLBoolean {

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLSQLiteExpression<V>, else: any XLSQLiteExpression<V>) -> some XLSQLiteExpression<V> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLSQLiteExpression<Optional<V>>, else: any XLSQLiteExpression<V>) -> some XLSQLiteExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLSQLiteExpression<V>, else: any XLSQLiteExpression<Optional<V>>) -> some XLSQLiteExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }

    /// Returns `then` when `self` is true, `else` otherwise.
    public func iif<V>(then: any XLSQLiteExpression<Optional<V>>, else: any XLSQLiteExpression<Optional<V>>) -> some XLSQLiteExpression<Optional<V>> {
        XLIfExpression(condition: self, trueResult: then, falseResult: `else`)
    }
}
