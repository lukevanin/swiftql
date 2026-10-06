//
//  FakeSecondDialectTypeCastFunctions.swift
//
//  Generated for the SQLTests second dialect by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/TypeCastFunctions.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation
import SwiftQL


// MARK: - Bool


extension FakeSecondDialectExpression {

    /// Reinterprets a Boolean expression as its SQLite integer storage value.
    @_disfavoredOverload
    func cast(to _: Int.Type) -> some FakeSecondDialectExpression<Int> where T == Bool {
        XLTypeAffinityExpression<Int>(expression: self)
    }

    @_disfavoredOverload
    func toInt() -> some FakeSecondDialectExpression<Int> where T == Bool {
        cast(to: Int.self)
    }
}


// MARK: - Optional Bool


extension FakeSecondDialectExpression {

    /// Reinterprets an optional Boolean expression as its optional SQLite
    /// integer storage value.
    @_disfavoredOverload
    func cast(to _: Int.Type) -> some FakeSecondDialectExpression<Optional<Int>> where T == Optional<Bool> {
        XLTypeAffinityExpression<Optional<Int>>(expression: self)
    }

    @_disfavoredOverload
    func toInt() -> some FakeSecondDialectExpression<Optional<Int>> where T == Optional<Bool> {
        cast(to: Int.self)
    }
}


// MARK: - Int

extension FakeSecondDialectExpression {

    /// Casts an integer expression to the requested real-number type.
    @_disfavoredOverload
    func cast(to _: Double.Type) -> some FakeSecondDialectExpression<Double> where T == Int {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts an integer expression to the requested text type.
    @_disfavoredOverload
    func cast(to _: String.Type) -> some FakeSecondDialectExpression<String> where T == Int {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    @_disfavoredOverload
    func toDouble() -> some FakeSecondDialectExpression<Double> where T == Int {
        cast(to: Double.self)
    }

    @_disfavoredOverload
    func toString() -> some FakeSecondDialectExpression<String> where T == Int {
        cast(to: String.self)
    }
}


// MARK: - Optional Int

extension FakeSecondDialectExpression {

    /// Casts an optional integer expression to optional real, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: Double.Type
    ) -> some FakeSecondDialectExpression<Optional<Double>> where T == Optional<Int> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts an optional integer expression to optional text, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: String.Type
    ) -> some FakeSecondDialectExpression<Optional<String>> where T == Optional<Int> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    @_disfavoredOverload
    func toDouble() -> some FakeSecondDialectExpression<Optional<Double>> where T == Optional<Int> {
        cast(to: Double.self)
    }

    @_disfavoredOverload
    func toString() -> some FakeSecondDialectExpression<Optional<String>> where T == Optional<Int> {
        cast(to: String.self)
    }
}


// MARK: - Double

extension FakeSecondDialectExpression {

    /// Casts a real expression to the requested integer type.
    @_disfavoredOverload
    func cast(to _: Int.Type) -> some FakeSecondDialectExpression<Int> where T == Double {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts a real expression to the requested text type.
    @_disfavoredOverload
    func cast(to _: String.Type) -> some FakeSecondDialectExpression<String> where T == Double {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    @_disfavoredOverload
    func toInt() -> some FakeSecondDialectExpression<Int> where T == Double {
        cast(to: Int.self)
    }

    @_disfavoredOverload
    func toString() -> some FakeSecondDialectExpression<String> where T == Double {
        cast(to: String.self)
    }
}


// MARK: - Optional Double


extension FakeSecondDialectExpression {

    /// Casts an optional real expression to optional integer, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: Int.Type
    ) -> some FakeSecondDialectExpression<Optional<Int>> where T == Optional<Double> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts an optional real expression to optional text, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: String.Type
    ) -> some FakeSecondDialectExpression<Optional<String>> where T == Optional<Double> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    @_disfavoredOverload
    func toInt() -> some FakeSecondDialectExpression<Optional<Int>> where T == Optional<Double> {
        cast(to: Int.self)
    }

    @_disfavoredOverload
    func toString() -> some FakeSecondDialectExpression<Optional<String>> where T == Optional<Double> {
        cast(to: String.self)
    }
}


// MARK: - String


extension FakeSecondDialectExpression {

    /// Casts a text expression to the requested integer type.
    @_disfavoredOverload
    func cast(to _: Int.Type) -> some FakeSecondDialectExpression<Int> where T == String {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts a text expression to the requested real-number type.
    @_disfavoredOverload
    func cast(to _: Double.Type) -> some FakeSecondDialectExpression<Double> where T == String {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts a text expression to the requested binary-data type.
    @_disfavoredOverload
    func cast(to _: Data.Type) -> some FakeSecondDialectExpression<Data> where T == String {
        XLTypeCastExpression(type: "BLOB", expression: self)
    }

    @_disfavoredOverload
    func toInt() -> some FakeSecondDialectExpression<Int> where T == String {
        cast(to: Int.self)
    }

    @_disfavoredOverload
    func toDouble() -> some FakeSecondDialectExpression<Double> where T == String {
        cast(to: Double.self)
    }

    @_disfavoredOverload
    func toData() -> some FakeSecondDialectExpression<Data> where T == String {
        cast(to: Data.self)
    }
}


// MARK: - Optional String


extension FakeSecondDialectExpression {

    /// Casts optional text to optional integer, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: Int.Type
    ) -> some FakeSecondDialectExpression<Optional<Int>> where T == Optional<String> {
        XLTypeCastExpression(type: "INTEGER", expression: self)
    }

    /// Casts optional text to optional real, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: Double.Type
    ) -> some FakeSecondDialectExpression<Optional<Double>> where T == Optional<String> {
        XLTypeCastExpression(type: "REAL", expression: self)
    }

    /// Casts optional text to optional binary data, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: Data.Type
    ) -> some FakeSecondDialectExpression<Optional<Data>> where T == Optional<String> {
        XLTypeCastExpression(type: "BLOB", expression: self)
    }

    @_disfavoredOverload
    func toInt() -> some FakeSecondDialectExpression<Optional<Int>> where T == Optional<String> {
        cast(to: Int.self)
    }

    @_disfavoredOverload
    func toDouble() -> some FakeSecondDialectExpression<Optional<Double>> where T == Optional<String> {
        cast(to: Double.self)
    }

    @_disfavoredOverload
    func toData() -> some FakeSecondDialectExpression<Optional<Data>> where T == Optional<String> {
        cast(to: Data.self)
    }
}


// MARK: - Data


extension FakeSecondDialectExpression {

    /// Casts a binary-data expression to the requested text type.
    @_disfavoredOverload
    func cast(to _: String.Type) -> some FakeSecondDialectExpression<String> where T == Data {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    @_disfavoredOverload
    func toString() -> some FakeSecondDialectExpression<String> where T == Data {
        cast(to: String.self)
    }
}


// MARK: - Optional Data


extension FakeSecondDialectExpression {

    /// Casts optional binary data to optional text, preserving NULL.
    @_disfavoredOverload
    func cast(
        to _: String.Type
    ) -> some FakeSecondDialectExpression<Optional<String>> where T == Optional<Data> {
        XLTypeCastExpression(type: "TEXT", expression: self)
    }

    @_disfavoredOverload
    func toString() -> some FakeSecondDialectExpression<Optional<String>> where T == Optional<Data> {
        cast(to: String.self)
    }
}
