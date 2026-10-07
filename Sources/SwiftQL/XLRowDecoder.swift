//
//  XLRowDecoder.swift
//  SwiftQL
//
//  The row decoder every fetch path decodes through, from a row handle or
//  from values. A custom function's arguments are read by
//  `XLFunctionArgumentReader` (issue #683).
//
//  Split out of GRDBSQLDatabase.swift (issue #560), as `GRDBRowDecoder`. It
//  never read a GRDB type beyond the one GRDB row overload, which now lives
//  with the GRDB driver in GRDBRequestPhaseProbe.swift (issue #113).
//


/// Package-scoped decoding seam shared by every driver's requests and the performance harness.
///
/// Keeping the sequential column reader behind this type lets benchmarks exercise the production
/// decoding path without exposing a driver's implementation details as public SwiftQL API.
package struct XLRowDecoder<Output> {

    private let reader: any XLRowReadable<Output>

    package init(reader: any XLRowReadable<Output>) {
        self.reader = reader
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
    ///
    /// A connection that declares no handle of its own lends the contract's
    /// `XLValuesRowHandle`, whose row is already in memory. That row decodes
    /// through ``decode(values:)``, the concrete reader it decoded through
    /// before handles existed, rather than through the handle's reads, which
    /// are generic over every dialect's value.
    package func decode<Handle>(row: Handle) throws -> Output
        where Handle: XLRowHandle, Handle.Value == XLSQLiteValue
    {
        // A metatype comparison, so a connection with its own handle, such
        // as the GRDB driver's, pays no dynamic cast per row.
        if Handle.self == XLValuesRowHandle<XLSQLiteValue>.self,
           let valuesRow = row as? XLValuesRowHandle<XLSQLiteValue> {
            return try decode(values: valuesRow.values)
        }
        return try XLColumnValuesRowReader<Output>.withReader(row) { columnReader in
            try reader.readRow(reader: columnReader)
        }
    }
}
