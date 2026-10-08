//
//  GRDBRowDecoding.swift
//  SwiftQL
//
//  `XLRowDecoder`'s one overload that names a GRDB type (issue #113). The
//  decoder itself is driver-generic and lives in XLRowDecoder.swift.
//

package import GRDB


extension XLRowDecoder {

    /// Decodes one GRDB row, reading each column through the GRDB driver's
    /// row handle, as `fetchAll()` does.
    ///
    /// Only the benchmark harness calls it, on rows it fetched with GRDB
    /// directly.
    package func decode(_ row: GRDB.Row) throws -> Output {
        try decode(row: GRDBRowHandle(row: row))
    }
}
