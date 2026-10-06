//
//  SQLiteComparableExpressionOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/ComparableExpressionOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - >


public func ><T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

public func ><T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

public func ><Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}

public func ><Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">", lhs: lhs, rhs: rhs)
}


// MARK: - <


public func <<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

public func <<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

public func <<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}

public func <<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<", lhs: lhs, rhs: rhs)
}


// MARK: - >=

public func >=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

public func >=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

public func >=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}

public func >=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: ">=", lhs: lhs, rhs: rhs)
}


// MARK: - <=


public func <=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<Bool> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

public func <=<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<Bool>> where T: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

public func <=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}

public func <=<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Bool>> where Wrapped: XLComparable {
    XLBinaryOperatorExpression(op: "<=", lhs: lhs, rhs: rhs)
}
