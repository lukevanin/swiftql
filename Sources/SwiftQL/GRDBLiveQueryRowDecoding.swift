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
    /// ``XLRowReadable`` documents `readRow(reader:)` as a read of the
    /// borrowed reader that stores nothing, so a conformer holds no state
    /// across calls. SwiftQL already relies on this: `fetchAll()` calls the
    /// same function on whichever pooled reader connection the driver hands
    /// out, and two concurrent fetches on copies of one request already run it
    /// at the same time.
    ///
    /// `unsafeBitCast` changes the compile-time `@Sendable` annotation only.
    /// The function value's runtime representation does not change. This
    /// mirrors ``XLCustomFunctionRegistration/make(_:)``, which crosses the
    /// same boundary for the same reason.
    ///
    /// The cast is deliberately narrow. It covers the row reader and nothing
    /// else, so the remaining live-query captures stay honestly `Sendable`.
    func sendableRowDecode() -> @Sendable ([XLSQLiteValue]) throws -> Row {
        let rowDecoder = GRDBRowDecoder(reader: reader)
        return unsafeBitCast(
            rowDecoder.decode(values:) as ([XLSQLiteValue]) throws -> Row,
            to: (@Sendable ([XLSQLiteValue]) throws -> Row).self
        )
    }
}
