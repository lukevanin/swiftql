import Foundation

/// Hand-written error surface shared by every generated raw-SQLite accessor.
/// This file is fixed: only `Tables.swift` and `Queries.swift` scale.
public enum ConsumerError: Error {
    case prepareFailed(Int32)
    case stepFailed(Int32)
    case unexpectedNullColumn(Int32)
}

/// SQLite's `SQLITE_TRANSIENT`, which is not imported into Swift.
public let consumerTransientDestructor = unsafeBitCast(
    -1,
    to: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?.self
)
