//
//  EquatableExpressionOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


// MARK: - Equality


public func ==<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<Bool, D> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<Bool, D> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<Bool, D> where T: XLEquatable {
    XLComparisonExpression(.equal, lhs: lhs, rhs: rhs)
}

public func ==<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<Bool>, D> where T: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> where T: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<Bool>, D> where T: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

public func ==<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

public func ==<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func ==<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeEqual, lhs: lhs, rhs: rhs)
}


// MARK: - Inequality


public func !=<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, D>) -> some XLExpression<Bool, D> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<T, XLUniversalDialect>) -> some XLExpression<Bool, D> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<T, D>) -> some XLExpression<Bool, D> where T: XLEquatable {
    XLComparisonExpression(.notEqual, lhs: lhs, rhs: rhs)
}

public func !=<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<Bool>, D> where T: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<T, D>(lhs: any XLExpression<T, D>, rhs: any XLExpression<Optional<T>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> where T: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<T, D>(lhs: any XLExpression<T, XLUniversalDialect>, rhs: any XLExpression<Optional<T>, D>) -> some XLExpression<Optional<Bool>, D> where T: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

public func !=<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Wrapped, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Wrapped, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

public func !=<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, D>, rhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}

@_disfavoredOverload
public func !=<Wrapped, D>(lhs: any XLExpression<Optional<Wrapped>, XLUniversalDialect>, rhs: any XLExpression<Optional<Wrapped>, D>) -> some XLExpression<Optional<Bool>, D> where Wrapped: XLEquatable {
    XLComparisonExpression(.nullSafeNotEqual, lhs: lhs, rhs: rhs)
}
