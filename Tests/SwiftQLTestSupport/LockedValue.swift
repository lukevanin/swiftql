//
//  LockedValue.swift
//  SwiftQLTestSupport
//
//  One lock-guarded value for test code that shares state with work running
//  on another thread or executor.
//

import Foundation


/// A value guarded by a lock. `@unchecked Sendable` because every access goes
/// through the lock.
///
/// `Value` is deliberately unconstrained: some tests use the box to hand a
/// non-`Sendable` value, such as a query statement, to one other thread. A
/// copy from ``read()`` is only as safe to share as `Value` itself, so a
/// reference type read out of the box must not be mutated concurrently.
public final class LockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    /// Runs `body` with exclusive access to the value.
    @discardableResult
    public func withValue<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }

    /// A copy of the current value.
    public func read() -> Value {
        withValue { $0 }
    }
}
