//
//  TypeCastFunctions.swift
//  
//
//  Created by Luke Van In on 2023/09/01.
//

import Foundation


// MARK: - Bool


extension XLExpression {

    /// Reinterprets a Boolean expression as its SQLite integer storage value.
    public func cast(to _: Int.Type) -> some XLExpression<Int, Dialect> where T == Bool {
        XLTypeAffinityExpression<Int, Dialect>(expression: self)
    }

    public func toInt() -> some XLExpression<Int, Dialect> where T == Bool {
        cast(to: Int.self)
    }
}


// MARK: - Optional Bool


extension XLExpression {

    /// Reinterprets an optional Boolean expression as its optional SQLite
    /// integer storage value.
    public func cast(to _: Int.Type) -> some XLExpression<Optional<Int>, Dialect> where T == Optional<Bool> {
        XLTypeAffinityExpression<Optional<Int>, Dialect>(expression: self)
    }

    public func toInt() -> some XLExpression<Optional<Int>, Dialect> where T == Optional<Bool> {
        cast(to: Int.self)
    }
}


// MARK: - Int

extension XLExpression {

    /// Casts an integer expression to the requested real-number type.
    public func cast(to _: Double.Type) -> some XLExpression<Double, Dialect> where T == Int {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts an integer expression to the requested text type.
    public func cast(to _: String.Type) -> some XLExpression<String, Dialect> where T == Int {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toDouble() -> some XLExpression<Double, Dialect> where T == Int {
        cast(to: Double.self)
    }

    public func toString() -> some XLExpression<String, Dialect> where T == Int {
        cast(to: String.self)
    }
}


// MARK: - Optional Int

extension XLExpression {

    /// Casts an optional integer expression to optional real, preserving NULL.
    public func cast(
        to _: Double.Type
    ) -> some XLExpression<Optional<Double>, Dialect> where T == Optional<Int> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts an optional integer expression to optional text, preserving NULL.
    public func cast(
        to _: String.Type
    ) -> some XLExpression<Optional<String>, Dialect> where T == Optional<Int> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toDouble() -> some XLExpression<Optional<Double>, Dialect> where T == Optional<Int> {
        cast(to: Double.self)
    }

    public func toString() -> some XLExpression<Optional<String>, Dialect> where T == Optional<Int> {
        cast(to: String.self)
    }
}


// MARK: - Double

extension XLExpression {

    /// Casts a real expression to the requested integer type.
    public func cast(to _: Int.Type) -> some XLExpression<Int, Dialect> where T == Double {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts a real expression to the requested text type.
    public func cast(to _: String.Type) -> some XLExpression<String, Dialect> where T == Double {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toInt() -> some XLExpression<Int, Dialect> where T == Double {
        cast(to: Int.self)
    }

    public func toString() -> some XLExpression<String, Dialect> where T == Double {
        cast(to: String.self)
    }
}


// MARK: - Optional Double


extension XLExpression {

    /// Casts an optional real expression to optional integer, preserving NULL.
    public func cast(
        to _: Int.Type
    ) -> some XLExpression<Optional<Int>, Dialect> where T == Optional<Double> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts an optional real expression to optional text, preserving NULL.
    public func cast(
        to _: String.Type
    ) -> some XLExpression<Optional<String>, Dialect> where T == Optional<Double> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toInt() -> some XLExpression<Optional<Int>, Dialect> where T == Optional<Double> {
        cast(to: Int.self)
    }

    public func toString() -> some XLExpression<Optional<String>, Dialect> where T == Optional<Double> {
        cast(to: String.self)
    }
}


// MARK: - String


extension XLExpression {

    /// Casts a text expression to the requested integer type.
    public func cast(to _: Int.Type) -> some XLExpression<Int, Dialect> where T == String {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts a text expression to the requested real-number type.
    public func cast(to _: Double.Type) -> some XLExpression<Double, Dialect> where T == String {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts a text expression to the requested binary-data type.
    public func cast(to _: Data.Type) -> some XLExpression<Data, Dialect> where T == String {
        XLTypeCastExpression(type: "BLOB", expression: self)
    }

    public func toInt() -> some XLExpression<Int, Dialect> where T == String {
        cast(to: Int.self)
    }

    public func toDouble() -> some XLExpression<Double, Dialect> where T == String {
        cast(to: Double.self)
    }

    public func toData() -> some XLExpression<Data, Dialect> where T == String {
        cast(to: Data.self)
    }
}


// MARK: - Optional String


extension XLExpression {

    /// Casts optional text to optional integer, preserving NULL.
    public func cast(
        to _: Int.Type
    ) -> some XLExpression<Optional<Int>, Dialect> where T == Optional<String> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts optional text to optional real, preserving NULL.
    public func cast(
        to _: Double.Type
    ) -> some XLExpression<Optional<Double>, Dialect> where T == Optional<String> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts optional text to optional binary data, preserving NULL.
    public func cast(
        to _: Data.Type
    ) -> some XLExpression<Optional<Data>, Dialect> where T == Optional<String> {
        XLTypeCastExpression(type: "BLOB", expression: self)
    }

    public func toInt() -> some XLExpression<Optional<Int>, Dialect> where T == Optional<String> {
        cast(to: Int.self)
    }

    public func toDouble() -> some XLExpression<Optional<Double>, Dialect> where T == Optional<String> {
        cast(to: Double.self)
    }

    public func toData() -> some XLExpression<Optional<Data>, Dialect> where T == Optional<String> {
        cast(to: Data.self)
    }
}


// MARK: - Data


extension XLExpression {

    /// Casts a binary-data expression to the requested text type.
    public func cast(to _: String.Type) -> some XLExpression<String, Dialect> where T == Data {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toString() -> some XLExpression<String, Dialect> where T == Data {
        cast(to: String.self)
    }
}


// MARK: - Optional Data


extension XLExpression {

    /// Casts optional binary data to optional text, preserving NULL.
    public func cast(
        to _: String.Type
    ) -> some XLExpression<Optional<String>, Dialect> where T == Optional<Data> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toString() -> some XLExpression<Optional<String>, Dialect> where T == Optional<Data> {
        cast(to: String.self)
    }
}
