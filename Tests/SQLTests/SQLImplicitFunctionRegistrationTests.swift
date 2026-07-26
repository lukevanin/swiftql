//
//  SQLImplicitFunctionRegistrationTests.swift
//
//  Exercises implicit custom-function registration (issue #16): a custom function that opts in by
//  calling `XLBuilder.customFunctionCall(_:parameters:)` from its `makeSQL(context:)` implementation is
//  registered on whatever physical SQLite connection executes it, the first time that connection runs it,
//  without an upfront `GRDBDatabaseBuilder.addFunction` call.
//

import Foundation
import GRDB
import XCTest
@testable import SwiftQL


/// Computes `value * value`.
///
/// `testCustomFunctionCallRegistersOnEveryPooledConnection` installs a ``ConcurrencyRendezvous`` in
/// ``rendezvous`` to force -- and directly observe -- simultaneous execution across several pooled
/// connections. Every other test leaves it `nil`, so the function does no synchronization at all.
///
/// `makeSQL` opts into implicit registration by calling `customFunctionCall` instead of `simpleFunction`
/// directly.
private struct ImplicitSquareFunction: XLCustomFunction {
    typealias T = Int

    static let definition = XLCustomFunctionDefinition(
        name: "implicitSquare",
        numberOfArguments: 1
    )

    /// Optional barrier that blocks each invocation inside the function body until enough
    /// invocations are executing at once. `nil` unless a test explicitly installs one.
    static let rendezvous = LockedValue<ConcurrencyRendezvous?>(nil)

    private let value: any XLExpression<Int>

    init(_ value: any XLExpression<Int>) {
        self.value = value
    }

    func makeSQL(context: inout XLBuilder) {
        context.customFunctionCall(Self.self) { list in
            list.listItem(expression: value.makeSQL)
        }
    }

    static func execute(reader: XLColumnReader) throws -> Int {
        let value = try reader.readInteger(at: 0)
        rendezvous.read()?.arriveAndWait()
        return value * value
    }
}


/// A custom function rendered the pre-existing way, with `simpleFunction` directly -- the same spelling
/// `HaversineDistance` and `ColumnReadIntegerFunction` already use elsewhere in the test suite. It never
/// opts into implicit registration, so it should behave exactly as it did before this issue: SQLite's "no
/// such function" error unless the caller registers it upfront with `GRDBDatabaseBuilder.addFunction`.
private struct ExplicitOnlyIdentityFunction: XLCustomFunction {
    typealias T = Int

    static let definition = XLCustomFunctionDefinition(
        name: "explicitOnlyIdentity",
        numberOfArguments: 1
    )

    private let value: any XLExpression<Int>

    init(_ value: any XLExpression<Int>) {
        self.value = value
    }

    func makeSQL(context: inout XLBuilder) {
        context.simpleFunction(name: Self.definition.name) { list in
            list.listItem(expression: value.makeSQL)
        }
    }

    static func execute(reader: XLColumnReader) throws -> Int {
        try reader.readInteger(at: 0)
    }
}


final class XLImplicitFunctionRegistrationTests: XCTestCase {

    private var databaseDirectoryURL: URL!

    override func setUpWithError() throws {
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if let databaseDirectoryURL {
            try? FileManager.default.removeItem(at: databaseDirectoryURL)
        }
        databaseDirectoryURL = nil
    }

    /// Builds a database without registering any custom function upfront. Every test in this file relies
    /// on that: the caller never calls `builder.addFunction(_:)`.
    private func makeDatabase(maximumReaderCount: Int? = nil) throws -> GRDBDatabase {
        let fileURL = databaseDirectoryURL.appendingPathComponent(
            "database.sqlite",
            isDirectory: false
        )
        var configuration = Configuration()
        if let maximumReaderCount {
            configuration.maximumReaderCount = maximumReaderCount
        }
        let builder = try GRDBDatabaseBuilder(
            url: fileURL,
            configuration: configuration,
            logger: nil
        )
        return try builder.build()
    }

    // MARK: - Baseline

    /// Confirms the pre-existing failure mode this issue fixes for functions that opt in: a custom
    /// function rendered with plain `simpleFunction` (the unchanged, pre-existing spelling, with no
    /// implicit registration) still fails with SQLite's "no such function" error when it is never
    /// registered upfront. This documents the baseline behavior the issue improves on, and guards against
    /// implicit registration ever becoming unconditional for every custom function regardless of opt-in.
    func testFunctionRenderedWithoutCustomFunctionCallStillRequiresUpfrontRegistration() throws {
        let database = try makeDatabase()
        let statement = sql { _ in Select(ExplicitOnlyIdentityFunction(1)) }

        XCTAssertThrowsError(
            try database.makeRequest(with: statement).fetchOne()
        ) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("no such function"), message)
        }
    }

    // MARK: - Implicit registration correctness

    /// The issue's real correctness test: build a `GRDBDatabase` without calling `addFunction` upfront,
    /// execute a query that references a custom function opted into implicit registration, and confirm it
    /// just works.
    func testCustomFunctionCallRegistersImplicitlyWithoutAddFunction() throws {
        let database = try makeDatabase()
        let statement = sql { _ in Select(ImplicitSquareFunction(6)) }

        XCTAssertEqual(try database.makeRequest(with: statement).fetchOne(), 36)
    }

    /// Registration has to survive repeated, independent executions -- not just the very first call --
    /// guarding against a design that (incorrectly) registers only once globally in a way that could be
    /// scoped to a single request or connection incorrectly.
    func testCustomFunctionCallRegistersImplicitlyAcrossRepeatedExecutions() throws {
        let database = try makeDatabase()
        for value in 1...5 {
            let statement = sql { _ in Select(ImplicitSquareFunction(value)) }
            XCTAssertEqual(try database.makeRequest(with: statement).fetchOne(), value * value)
        }
    }

    // MARK: - Pool concurrency

    /// `DatabasePool` maintains several persistent reader connections and hands any given read to whichever
    /// is idle; `Database.add(function:)` only registers on the one physical connection it runs on. This
    /// test forces genuine concurrent use of more than one reader connection and confirms the implicitly
    /// registered function works correctly no matter which connection actually served a given call -- not
    /// just whichever connection happened to run first.
    ///
    /// Concurrency is **observed**, never inferred from elapsed time. A ``ConcurrencyRendezvous``
    /// installed into the function body blocks each invocation until `maximumReaderCount` of them are
    /// inside it simultaneously. Because SQLite runs at most one statement at a time per physical
    /// connection, `maximumReaderCount` simultaneous executions prove at least that many *distinct*
    /// connections each executed the implicitly registered function. A loaded CI runner only makes the
    /// rendezvous take longer to complete, never changes the verdict; a genuinely serialized pool can
    /// never reach it and fails on the barrier's own timeout with a precise diagnosis.
    func testCustomFunctionCallRegistersOnEveryPooledConnection() throws {
        let maximumReaderCount = 4
        let database = try makeDatabase(maximumReaderCount: maximumReaderCount)

        let iterations = 8
        let results = LockedValue<[Int: Result<Int?, Error>]>([:])
        let rendezvous = ConcurrencyRendezvous(target: maximumReaderCount, timeout: 30)
        ImplicitSquareFunction.rendezvous.withValue { $0 = rendezvous }
        defer { ImplicitSquareFunction.rendezvous.withValue { $0 = nil } }

        // Dedicated threads rather than `DispatchQueue.concurrentPerform`: the rendezvous needs
        // `maximumReaderCount` genuinely simultaneous callers, and `concurrentPerform` is free to run
        // its iterations on fewer threads than that (it sizes itself to the machine's active core
        // count), which would stall the barrier for reasons unrelated to the pool.
        let completed = DispatchGroup()
        for index in 0 ..< iterations {
            completed.enter()
            let worker = Thread {
                defer { completed.leave() }
                let value = index + 1
                let statement = sql { _ in Select(ImplicitSquareFunction(value)) }
                let outcome: Result<Int?, Error>
                do {
                    outcome = .success(try database.makeRequest(with: statement).fetchOne())
                }
                catch {
                    outcome = .failure(error)
                }
                results.withValue { $0[value] = outcome }
            }
            worker.name = "implicit-registration-\(index)"
            worker.start()
        }

        XCTAssertEqual(
            completed.wait(timeout: .now() + 60),
            .success,
            "Concurrent pooled reads did not all finish."
        )

        XCTAssertTrue(
            rendezvous.didReachTarget,
            """
            Only \(rendezvous.peakConcurrency) invocation(s) of the custom function ever executed at \
            once, short of the \(maximumReaderCount) required to rendezvous. The pool served these \
            reads on fewer physical connections than expected, so this test would not have exercised \
            registration across multiple connections.
            """
        )
        XCTAssertGreaterThanOrEqual(
            rendezvous.peakConcurrency,
            maximumReaderCount,
            "Expected at least \(maximumReaderCount) distinct pooled connections to execute the function."
        )

        let finalResults = results.read()
        XCTAssertEqual(finalResults.count, iterations)
        for value in 1...iterations {
            switch finalResults[value] {
            case .success(let squared):
                XCTAssertEqual(squared, value * value, "value \(value)")
            case .failure(let error):
                XCTFail("value \(value) failed: \(error)")
            case nil:
                XCTFail("value \(value) never completed")
            }
        }
    }
}


/// A one-shot barrier that makes genuine concurrency directly observable instead of inferring it
/// from elapsed time.
///
/// Each caller announces its arrival and blocks until `target` callers are inside simultaneously,
/// at which point every waiter is released and the barrier stays open for the rest of the run. The
/// highest simultaneous occupancy is recorded in ``peakConcurrency``.
///
/// This is deliberately a synchronization proof rather than a timing measurement: a slow or loaded
/// machine only delays the rendezvous, it cannot change the outcome. If the work under test is
/// actually serialized, the first caller is never joined and every waiter unblocks on `timeout`
/// with ``didReachTarget`` still `false`, so the test fails deterministically and says why.
private final class ConcurrencyRendezvous: @unchecked Sendable {

    private let condition = NSCondition()

    private let target: Int

    private let timeout: TimeInterval

    private var currentlyInside = 0

    private var peak = 0

    private var isOpen = false

    /// - Parameters:
    ///   - target: The number of simultaneous callers required to release the barrier.
    ///   - timeout: How long a caller waits for the others before giving up. Generous by design --
    ///     it is a deadlock backstop, not a performance assertion.
    init(target: Int, timeout: TimeInterval) {
        self.target = target
        self.timeout = timeout
    }

    /// Records this caller as executing, then blocks until `target` callers are executing at once
    /// (or the barrier has already opened, or `timeout` elapses).
    func arriveAndWait() {
        condition.lock()
        defer { condition.unlock() }

        currentlyInside += 1
        peak = max(peak, currentlyInside)
        if currentlyInside >= target {
            isOpen = true
            condition.broadcast()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !isOpen {
            guard condition.wait(until: deadline) else {
                break
            }
        }

        currentlyInside -= 1
    }

    /// Whether `target` callers were ever inside simultaneously.
    var didReachTarget: Bool {
        condition.lock()
        defer { condition.unlock() }
        return isOpen
    }

    /// The highest number of callers observed executing simultaneously.
    var peakConcurrency: Int {
        condition.lock()
        defer { condition.unlock() }
        return peak
    }
}


/// Manually synchronized mutable state safe to capture in a `@Sendable` closure -- the
/// strict-concurrency checker cannot see that a lock makes cross-closure access safe.
private final class LockedValue<Value>: @unchecked Sendable {

    private let lock = NSLock()

    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func read() -> Value {
        withValue { $0 }
    }
}
