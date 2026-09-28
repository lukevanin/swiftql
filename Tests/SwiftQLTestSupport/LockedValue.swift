//
//  LockedValue.swift
//  SwiftQLTestSupport
//
//  One lock-guarded value for test code that shares state with an operation
//  a driver may run on another executor.
//

import Foundation


/// A value guarded by a lock. `@unchecked Sendable` because every access goes
/// through the lock.
public final class LockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: Value

    public init(_ value: Value) {
        storage = value
    }

    /// The current value.
    public var value: Value {
        withLock { $0 }
    }

    /// Runs `body` with exclusive access to the value.
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }
}
