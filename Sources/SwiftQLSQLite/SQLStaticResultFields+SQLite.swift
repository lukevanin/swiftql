//
//  SQLStaticResultFields+SQLite.swift
//
//  SQLite's spelling of an intrinsic static select field, with a default
//  XLSQLiteDialect. Split from SQLStaticResultFields.swift, whose fields are
//  every dialect's (issue #790).
//

import Foundation


extension XLStaticSelectField
where Dialect == XLSQLiteDialect, Value: XLLiteral, Storage == Value {

    /// Creates a codec-free SQLite field for an intrinsic v1 literal whose
    /// SQLite storage class is statically known. This never calls
    /// `sqlDefault()`.
    ///
    /// The same as `intrinsic(selecting:identifiedBy:using:context:)` with
    /// a default `XLSQLiteDialect`.
    public static func intrinsic(
        selecting expression: any XLExpression<Value>,
        identifiedBy identity: XLQuerySlotIdentity,
        context: XLValueCodingContext? = nil
    ) throws -> Self {
        try intrinsic(
            selecting: expression,
            identifiedBy: identity,
            using: XLSQLiteDialect(),
            context: context
        )
    }
}
