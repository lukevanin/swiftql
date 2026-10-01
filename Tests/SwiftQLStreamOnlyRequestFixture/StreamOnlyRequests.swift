//
//  StreamOnlyRequests.swift
//  SwiftQLStreamOnlyRequestFixture
//
//  Request adapters that implement only the live-query stream members
//  (issue #684).
//
//  This target must never import Combine or OpenCombine, directly or through
//  `canImport`. That it compiles is the proof that an `XLRequest` conformer
//  needs neither: SwiftQL supplies every publish member from the streams.
//  `XLRequestCombineDefaultsTests` checks the import rule, and drives these
//  conformers through the publish members SwiftQL gives them.
//

import Foundation
import SwiftQL


/// A hand-driven source of live-query streams, standing in for an adapter's
/// own change notification.
///
/// Each ``makeStream()`` call is one observation. A test sends values to every
/// observation still running, finishes them, and counts how many observations
/// were started and how many have ended.
public final class StreamOnlySource<Value: Sendable>: @unchecked Sendable {

    private let lock = NSLock()

    private var continuations: [Int: AsyncThrowingStream<Value, Error>.Continuation] = [:]

    private var nextIdentifier = 0

    private var ended = 0

    public init() {}

    /// How many observations have been started.
    public var startedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nextIdentifier
    }

    /// How many observations have ended, by cancellation or by finishing.
    public var endedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return ended
    }

    /// Starts one observation. It holds at most one undelivered value, as a
    /// live-query stream must.
    public func makeStream() -> AsyncThrowingStream<Value, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            lock.lock()
            let identifier = nextIdentifier
            nextIdentifier += 1
            continuations[identifier] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: identifier)
                self.ended += 1
                self.lock.unlock()
            }
        }
    }

    /// Yields `value` to every running observation.
    public func send(_ value: Value) {
        for continuation in runningContinuations() {
            continuation.yield(value)
        }
    }

    /// Ends every running observation, with `error` when there is one.
    public func finish(throwing error: Error? = nil) {
        for continuation in runningContinuations() {
            continuation.finish(throwing: error)
        }
    }

    private func runningContinuations() -> [AsyncThrowingStream<Value, Error>.Continuation] {
        lock.lock()
        defer { lock.unlock() }
        return Array(continuations.values)
    }
}


/// Implements every live-query stream member, and nothing from Combine.
///
/// The `bindings:` members accept any packet and record how many bindings
/// each one carried, as an adapter that binds parameters would read them.
public struct StreamOnlyRequest: XLRequest {

    public let rows: StreamOnlySource<[Int]>

    public let row: StreamOnlySource<Int?>

    private let bindingCounts = StreamOnlyBindingCounts()

    public init(
        rows: StreamOnlySource<[Int]> = StreamOnlySource(),
        row: StreamOnlySource<Int?> = StreamOnlySource()
    ) {
        self.rows = rows
        self.row = row
    }

    /// The binding count of every packet a `bindings:` member was given.
    public var receivedBindingCounts: [Int] {
        bindingCounts.read()
    }

    public mutating func set<T>(
        parameter reference: XLNamedBindingReference<Optional<T>>,
        value: T?
    ) where T: XLBindable {}

    public mutating func set<T>(
        parameter reference: XLNamedBindingReference<T>,
        value: T
    ) where T: XLBindable {}

    public func fetchAll() throws -> [Int] {
        []
    }

    public func fetchOne() throws -> Int? {
        nil
    }

    public func stream() -> AsyncThrowingStream<[Int], Error> {
        rows.makeStream()
    }

    public func stream(bindings: any XLInvocationBindingPacket) -> AsyncThrowingStream<[Int], Error> {
        bindingCounts.record(bindings.bindingCount)
        return rows.makeStream()
    }

    public func streamOne() -> AsyncThrowingStream<Int?, Error> {
        row.makeStream()
    }

    public func streamOne(bindings: any XLInvocationBindingPacket) -> AsyncThrowingStream<Int?, Error> {
        bindingCounts.record(bindings.bindingCount)
        return row.makeStream()
    }
}


/// Implements only `stream()` and `streamOne()`: the least a request adapter
/// writes. Its `bindings:` members are `XLRequest`'s compatibility defaults,
/// which accept only an empty packet.
public struct MinimalStreamOnlyRequest: XLRequest {

    public let rows: StreamOnlySource<[Int]>

    public let row: StreamOnlySource<Int?>

    public init(
        rows: StreamOnlySource<[Int]> = StreamOnlySource(),
        row: StreamOnlySource<Int?> = StreamOnlySource()
    ) {
        self.rows = rows
        self.row = row
    }

    public mutating func set<T>(
        parameter reference: XLNamedBindingReference<Optional<T>>,
        value: T?
    ) where T: XLBindable {}

    public mutating func set<T>(
        parameter reference: XLNamedBindingReference<T>,
        value: T
    ) where T: XLBindable {}

    public func fetchAll() throws -> [Int] {
        []
    }

    public func fetchOne() throws -> Int? {
        nil
    }

    public func stream() -> AsyncThrowingStream<[Int], Error> {
        rows.makeStream()
    }

    public func streamOne() -> AsyncThrowingStream<Int?, Error> {
        row.makeStream()
    }
}


/// A reference, so a non-mutating `bindings:` member can record what it was
/// given.
private final class StreamOnlyBindingCounts: @unchecked Sendable {

    private let lock = NSLock()

    private var counts: [Int] = []

    func record(_ count: Int) {
        lock.lock()
        counts.append(count)
        lock.unlock()
    }

    func read() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return counts
    }
}
