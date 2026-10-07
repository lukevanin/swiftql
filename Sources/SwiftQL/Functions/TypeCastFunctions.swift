//
//  TypeCastFunctions.swift
//  
//
//  Created by Luke Van In on 2023/09/01.
//

import Foundation


// The casts name SQLite's storage classes (`INTEGER`, `REAL`, `TEXT`, `BLOB`)
// and rely on its storage affinity, so they are SQLite's own: declared only on
// a SQLite expression (issue #789).


// MARK: - Bool


extension XLSQLiteExpression {

    /// Reinterprets a Boolean expression as its SQLite integer storage value.
    public func cast(to _: Int.Type) -> some XLSQLiteExpression<Int> where T == Bool {
        XLTypeAffinityExpression<Int>(expression: self)
    }

    public func toInt() -> some XLSQLiteExpression<Int> where T == Bool {
        cast(to: Int.self)
    }
}


// MARK: - Optional Bool


extension XLSQLiteExpression {

    /// Reinterprets an optional Boolean expression as its optional SQLite
    /// integer storage value.
    public func cast(to _: Int.Type) -> some XLSQLiteExpression<Optional<Int>> where T == Optional<Bool> {
        XLTypeAffinityExpression<Optional<Int>>(expression: self)
    }

    public func toInt() -> some XLSQLiteExpression<Optional<Int>> where T == Optional<Bool> {
        cast(to: Int.self)
    }
}


// MARK: - Int

extension XLSQLiteExpression {

    /// Casts an integer expression to the requested real-number type.
    public func cast(to _: Double.Type) -> some XLSQLiteExpression<Double> where T == Int {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts an integer expression to the requested text type.
    public func cast(to _: String.Type) -> some XLSQLiteExpression<String> where T == Int {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toDouble() -> some XLSQLiteExpression<Double> where T == Int {
        cast(to: Double.self)
    }

    public func toString() -> some XLSQLiteExpression<String> where T == Int {
        cast(to: String.self)
    }
}


// MARK: - Optional Int

extension XLSQLiteExpression {

    /// Casts an optional integer expression to optional real, preserving NULL.
    public func cast(
        to _: Double.Type
    ) -> some XLSQLiteExpression<Optional<Double>> where T == Optional<Int> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts an optional integer expression to optional text, preserving NULL.
    public func cast(
        to _: String.Type
    ) -> some XLSQLiteExpression<Optional<String>> where T == Optional<Int> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toDouble() -> some XLSQLiteExpression<Optional<Double>> where T == Optional<Int> {
        cast(to: Double.self)
    }

    public func toString() -> some XLSQLiteExpression<Optional<String>> where T == Optional<Int> {
        cast(to: String.self)
    }
}


// MARK: - Double

extension XLSQLiteExpression {

    /// Casts a real expression to the requested integer type.
    public func cast(to _: Int.Type) -> some XLSQLiteExpression<Int> where T == Double {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts a real expression to the requested text type.
    public func cast(to _: String.Type) -> some XLSQLiteExpression<String> where T == Double {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toInt() -> some XLSQLiteExpression<Int> where T == Double {
        cast(to: Int.self)
    }

    public func toString() -> some XLSQLiteExpression<String> where T == Double {
        cast(to: String.self)
    }
}


// MARK: - Optional Double


extension XLSQLiteExpression {

    /// Casts an optional real expression to optional integer, preserving NULL.
    public func cast(
        to _: Int.Type
    ) -> some XLSQLiteExpression<Optional<Int>> where T == Optional<Double> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts an optional real expression to optional text, preserving NULL.
    public func cast(
        to _: String.Type
    ) -> some XLSQLiteExpression<Optional<String>> where T == Optional<Double> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toInt() -> some XLSQLiteExpression<Optional<Int>> where T == Optional<Double> {
        cast(to: Int.self)
    }

    public func toString() -> some XLSQLiteExpression<Optional<String>> where T == Optional<Double> {
        cast(to: String.self)
    }
}


// MARK: - String


extension XLSQLiteExpression {

    /// Casts a text expression to the requested integer type.
    public func cast(to _: Int.Type) -> some XLSQLiteExpression<Int> where T == String {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts a text expression to the requested real-number type.
    public func cast(to _: Double.Type) -> some XLSQLiteExpression<Double> where T == String {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts a text expression to the requested binary-data type.
    public func cast(to _: Data.Type) -> some XLSQLiteExpression<Data> where T == String {
        XLTypeCastExpression(type: "BLOB", expression: self)
    }

    public func toInt() -> some XLSQLiteExpression<Int> where T == String {
        cast(to: Int.self)
    }

    public func toDouble() -> some XLSQLiteExpression<Double> where T == String {
        cast(to: Double.self)
    }

    public func toData() -> some XLSQLiteExpression<Data> where T == String {
        cast(to: Data.self)
    }
}


// MARK: - Optional String


extension XLSQLiteExpression {

    /// Casts optional text to optional integer, preserving NULL.
    public func cast(
        to _: Int.Type
    ) -> some XLSQLiteExpression<Optional<Int>> where T == Optional<String> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts optional text to optional real, preserving NULL.
    public func cast(
        to _: Double.Type
    ) -> some XLSQLiteExpression<Optional<Double>> where T == Optional<String> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts optional text to optional binary data, preserving NULL.
    public func cast(
        to _: Data.Type
    ) -> some XLSQLiteExpression<Optional<Data>> where T == Optional<String> {
        XLTypeCastExpression(type: "BLOB", expression: self)
    }

    public func toInt() -> some XLSQLiteExpression<Optional<Int>> where T == Optional<String> {
        cast(to: Int.self)
    }

    public func toDouble() -> some XLSQLiteExpression<Optional<Double>> where T == Optional<String> {
        cast(to: Double.self)
    }

    public func toData() -> some XLSQLiteExpression<Optional<Data>> where T == Optional<String> {
        cast(to: Data.self)
    }
}


// MARK: - Data


extension XLSQLiteExpression {

    /// Casts a binary-data expression to the requested text type.
    public func cast(to _: String.Type) -> some XLSQLiteExpression<String> where T == Data {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toString() -> some XLSQLiteExpression<String> where T == Data {
        cast(to: String.self)
    }
}


// MARK: - Optional Data


extension XLSQLiteExpression {

    /// Casts optional binary data to optional text, preserving NULL.
    public func cast(
        to _: String.Type
    ) -> some XLSQLiteExpression<Optional<String>> where T == Optional<Data> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    public func toString() -> some XLSQLiteExpression<Optional<String>> where T == Optional<Data> {
        cast(to: String.self)
    }
}
