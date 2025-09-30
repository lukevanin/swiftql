//
//  ConditionalFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/28.
//

import Foundation


// MARK: - IIF


public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<T>, else: any XLExpression<T>) -> some XLExpression<T> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<Optional<T>>, else: any XLExpression<T>) -> some XLExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<T>, else: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}


public func iif<T, U>(_ condition: any XLExpression<U>, then: any XLExpression<Optional<T>>, else: any XLExpression<Optional<T>>) -> some XLExpression<Optional<T>> where U: XLBoolean {
    XLIfExpression(condition: condition, trueResult: then, falseResult: `else`)
}
