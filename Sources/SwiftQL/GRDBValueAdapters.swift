//
//  GRDBValueAdapters.swift
//  SwiftQL
//
//  Reading GRDB values back as SwiftQL sees them: the row decoder every fetch
//  path decodes through, from a row handle or from values. A custom function's arguments are read by
//  `XLFunctionArgumentReader` (issue #683).
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

    package func decode(values: [XLSQLiteValue]) throws -> Output {
        try XLColumnValuesRowReader<Output>.withReader(
            XLSQLiteValueReader(values: values)
        ) { columnReader in
            try reader.readRow(reader: columnReader)
        }
    }

    /// Decodes the row a cursor is on, reading each column the row reader
    /// asks for straight from `row`, with no array of values in between
    /// (issue #678).
    package func decode<Handle>(row: Handle) throws -> Output
        where Handle: XLRowHandle, Handle.Value == XLSQLiteValue
    {
        try XLColumnValuesRowReader<Output>.withReader(row) { columnReader in
            try reader.readRow(reader: columnReader)
        }
    }
}
