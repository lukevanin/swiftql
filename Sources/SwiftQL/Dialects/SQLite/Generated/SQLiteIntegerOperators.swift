//
//  SQLiteIntegerOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/IntegerOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - Bitwise NOT


public prefix func ~<T>(operand: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}

public prefix func ~<Wrapped>(operand: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLUnaryOperatorExpression(op: "~", operand: operand)
}


// MARK: - Addition


public func +<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped>(lhs: any XLSQLiteExpression< Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}

public func +<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "+", lhs: lhs, rhs: rhs)
}


// MARK: - Subtraction


public func -<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}

public func -<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "-", lhs: lhs, rhs: rhs)
}


// MARK: - Multiplication


public func *<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}

public func *<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "*", lhs: lhs, rhs: rhs)
}


// MARK: - Division


public func /<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}

public func /<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "/", lhs: lhs, rhs: rhs)
}


// MARK: - Modulo


public func %<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<T>) -> some XLSQLiteExpression<T> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

public func %<T>(lhs: any XLSQLiteExpression<T>, rhs: any XLSQLiteExpression<Optional<T>>) -> some XLSQLiteExpression<Optional<T>> where T: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

public func %<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Wrapped>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

public func %<Wrapped>(lhs: any XLSQLiteExpression<Optional<Wrapped>>, rhs: any XLSQLiteExpression<Optional<Wrapped>>) -> some XLSQLiteExpression<Optional<Wrapped>> where Wrapped: BinaryInteger {
    XLBinaryOperatorExpression(op: "%", lhs: lhs, rhs: rhs)
}

