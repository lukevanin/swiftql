//
//  SQLExpression+SQLite.swift
//
//  SQLite's v1 names for its enum and custom-type compositions. The
//  requirements they compose, `XLEnumRepresentable` and `XLCustomValue`, name
//  no dialect (issue #790).
//

import Foundation


///
/// A custom scalar type: a Swift value that binds to, reads from, and renders
/// into SQL.
///
/// A custom type is a value, so it is an operand in a SQLite query, as an
/// `XLSQLiteExpression`, like `String` or `Int` (issue #789). This is
/// `XLSQLiteCustomType`, SQLite's composition of `XLCustomValue`, under its v1
/// name. A type that conforms to `XLExpression`, `XLBindable`, and `XLLiteral`
/// separately, rather than to this alias, conforms to `XLSQLiteExpression`
/// itself. A type used in another dialect's query conforms to that dialect's
/// composition as well (issue #790).
///
public typealias XLCustomType = XLSQLiteCustomType


///
/// An enum that is used as a column on an `SQLTable` or `SQLResult`.
///
/// To use an enum for a column the enum must adhere to the following conditions:
/// - Use a supported intrinsic type for the `RawValue`.
/// - Conform to `XLEnum` and declare `T` as `Self`.
/// - When using legacy `SQLReader` result introspection, implement
///   `sqlDefault()` and return any valid enum value. Static row layouts do not
///   require or call that placeholder, and it is never a fallback for database
///   decoding.
///
/// `XLEnumRepresentable` provides default implementations for most of the
/// required methods which can be overridden as required. Reading an unknown
/// stored raw value throws `XLColumnReadError`.
///
/// An enum is a value, so it is an operand in a SQLite query, as an
/// `XLSQLiteExpression` (issue #789). This is `XLSQLiteEnum`, SQLite's
/// composition of `XLEnumRepresentable`, under its v1 name. An enum used in
/// another dialect's query conforms to that dialect's composition as well
/// (issue #790).
///
/// `XLEnum` is a composition, not a protocol, so an extension of every enum
/// extends `XLEnumRepresentable` instead.
///
public typealias XLEnum = XLSQLiteEnum
