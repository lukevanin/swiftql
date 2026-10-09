//
//  SQLQueryCapture+SQLite.swift
//
//  SQLite's spelling of an intrinsic capture, with a default XLSQLiteDialect.
//  Split from SQLQueryCapture.swift, whose captures are every dialect's
//  (issue #790).
//

import Foundation


extension XLQueryCapture where Dialect == XLSQLiteDialect {

    /// Creates a codec-free capture for SQLite's intrinsic Swift value types:
    /// `Bool`, `Int`, `Double`, `String`, and `Data`.
    ///
    /// The same as ``intrinsic(identifiedBy:using:context:)`` with a default
    /// `XLSQLiteDialect`.
    public static func intrinsic(
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil
    ) throws -> Self {
        try intrinsic(
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            context: context
        )
    }
}
