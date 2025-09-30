//
//  ComparableExpressionOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/04.
//

import Foundation


// MARK: - >


public func ><T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

public func ><T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

public func ><Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

public func ><Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}


// MARK: - <


public func <<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

public func <<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

public func <<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

public func <<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}


// MARK: - >=

public func >=<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

public func >=<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

public func >=<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

public func >=<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}


// MARK: - <=


public func <=<T>(lhs: any XLExpression<T>, rhs: any XLExpression<T>) -> some XLExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

public func <=<T>(lhs: any XLExpression<T>, rhs: any XLExpression<Optional<T>>) -> some XLExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

public func <=<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Wrapped>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

public func <=<Wrapped>(lhs: any XLExpression<Optional<Wrapped>>, rhs: any XLExpression<Optional<Wrapped>>) -> some XLExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}
