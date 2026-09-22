//
//  GRDBLiveQueryRowDecoding.swift
//  SwiftQL
//
//  The one concurrency seam between a live-query observation and the v1 row
//  reader graph (issue #792).
//

import Foundation
import SwiftQLCore


extension GRDBRequest {

    /// A `@Sendable` function that turns one raw row into a `Row`.
    ///
    /// ## Why this exists
    ///
    /// GRDB 7 declares an observation's fetch closure `@Sendable`, and
    /// `AsyncThrowingStream`'s `unfolding` closure is `@Sendable` too. Every
    /// value a live query carries must therefore be `Sendable`. Two of the
    /// three are, and honestly so: ``GRDBInvocationExecutor`` is a `Sendable`
    /// struct, and ``XLLogger`` now states the concurrency safety that SwiftQL
    /// has always needed from it. The third is the row reader.
    ///
    /// The reader arrives as `any XLRowReadable<Row>`, and in practice it is
    /// the statement itself (see `GRDBDatabase.makeRequest(with:)`). Making
    /// that type `Sendable` means making the whole statement DSL `Sendable`:
    /// `XLEncodable`, `XLColumnDependency`, the statement component structs,
    /// and the mutable `XLNamespace` alias allocator. That is a large public
    /// API change, and it is not this issue's work.
    ///
    /// ## Why the cast is safe
    ///
    /// The function below reads a `[XLSQLiteValue]` array that SQLite has
    /// already copied out of the statement, and it returns a `Sendable` `Row`.
    /// It touches no connection, no cursor, and no statement handle.
    /// ``XLRowReadable`` already states that `readRow(reader:)` only borrows
    /// the reader it is given, and SwiftQL already calls it concurrently:
    /// `fetchAll()` runs it on whichever pooled reader connection the driver
    /// hands out, and two fetches on copies of one request run it at the same
    /// time. A conformer that is unsafe here was already unsafe there. The
    /// protocol does not require `Sendable`, so this remains a convention the
    /// compiler cannot check, which is why the cast is written out and
    /// explained rather than hidden.
    ///
    /// `unsafeBitCast` changes the compile-time `@Sendable` annotation only.
    /// The function value's runtime representation does not change. This
    /// mirrors ``XLCustomFunctionRegistration/make(_:)``, which crosses the
    /// same boundary for the same reason.
    ///
    /// The cast is deliberately narrow. It covers the row reader and nothing
    /// else, so the remaining live-query captures stay honestly `Sendable`.
    ///
    /// ## What changes for a conformer
    ///
    /// A live query used to decode on the observation's own queue. It now
    /// decodes on whichever thread resumes the stream's iterator, so a
    /// conformer that also runs through `fetchAll()` at the same time sees
    /// `readRow(reader:)` called from two threads. The protocol already
    /// requires a conformer to store nothing from a call, and a pool already
    /// calls it from several reader connections, so this adds no requirement
    /// that was not there. It does change which thread runs the decode.
    func sendableRowDecode() -> @Sendable ([XLSQLiteValue]) throws -> Row {
        let rowDecoder = GRDBRowDecoder(reader: reader)
        return unsafeBitCast(
            rowDecoder.decode(values:) as ([XLSQLiteValue]) throws -> Row,
            to: (@Sendable ([XLSQLiteValue]) throws -> Row).self
        )
    }
}
