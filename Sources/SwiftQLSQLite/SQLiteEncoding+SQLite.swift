//
//  SQLiteEncoding+SQLite.swift
//
//  SQLite's encoder: XLiteEncoder, and its initializer from a formatter.
//  Split from SQLiteEncoding.swift, whose encoder and builders are every
//  dialect's (issue #790).
//

import Foundation


///
/// Encodes SwiftQL statements into SQL that can be executed by SQLite.
///
/// The SQLite conformance of ``XLDialectEncoder``.
///
public typealias XLiteEncoder = XLDialectEncoder<XLSQLiteDialect>


extension XLDialectEncoder where Dialect == XLSQLiteDialect {

    ///
    /// Creates a SQLite encoder from a formatter.
    ///
    /// The formatter carries the identifier quoting, which is the only part of
    /// the dialect it can express; everything else takes its default.
    ///
    public init(formatter: XLiteFormatter) {
        self.init(
            dialect: XLSQLiteDialect(
                identifierFormattingOptions: formatter.identifierFormattingOptions
            )
        )
    }
}
