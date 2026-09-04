//
//  GRDBValueAdapters.swift
//  SwiftQL
//
//  Reading GRDB values back as SwiftQL sees them: a positional column reader
//  for custom functions, and the row decoder every fetch path decodes through.
//
//  Split out of GRDBSQLDatabase.swift (issue #560).
//

import Foundation
import GRDB
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif


/// Reads a GRDB row's values positionally, as a custom function's
/// `execute(reader:)` sees them.
///
/// Deliberately only an ``XLColumnReader``: it does not forward
/// ``XLStaticColumnReader/dialectValue(at:using:)`` to the
/// ``XLSQLiteValueReader`` it wraps, so asking it for a raw dialect value
/// throws `rawDialectValuesUnavailable`. That is not a gap. A custom function
/// reads intrinsic values by position; a static row layout is a different
/// contract, and production decoding reaches the reader that supports it
/// directly through ``GRDBRowDecoder``.
struct GRDBValuesAdapter: XLColumnReader {

    private let reader: XLSQLiteValueReader

    init(values: [GRDB.DatabaseValue]) {
        self.reader = XLSQLiteValueReader(
            values: values.map(\.sqliteDialectValue)
        )
    }

    init(row: GRDB.Row) {
        self.init(values: Array(row.databaseValues))
    }
    
    func isNull(at index: Int) throws -> Bool {
        try reader.isNull(at: index)
    }
    
    func readInteger(at index: Int) throws -> Int {
        try reader.readInteger(at: index)
    }
    
    func readReal(at index: Int) throws -> Double {
        try reader.readReal(at: index)
    }
    
    func readText(at index: Int) throws -> String {
        try reader.readText(at: index)
    }
    
    func readBlob(at index: Int) throws -> Data {
        try reader.readBlob(at: index)
    }
}


/// Package-scoped decoding seam shared by the GRDB adapter and performance harness.
///
/// Keeping the adapter and sequential column reader behind this type lets benchmarks exercise the
/// production decoding path without exposing GRDB implementation details as public SwiftQL API.
package struct GRDBRowDecoder<Output> {

    private let reader: any XLRowReadable<Output>

    package init(reader: any XLRowReadable<Output>) {
        self.reader = reader
    }

    package func decode(_ row: GRDB.Row) throws -> Output {
        try decode(values: row.databaseValues.map(\.sqliteDialectValue))
    }

    func decode(values: [XLSQLiteValue]) throws -> Output {
        try XLColumnValuesRowReader<Output>.withReader(
            XLSQLiteValueReader(values: values)
        ) { columnReader in
            try reader.readRow(reader: columnReader)
        }
    }
}
