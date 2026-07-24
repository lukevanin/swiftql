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


/// Computes `value * value` after a short synthetic delay.
///
/// The delay lets `testCustomFunctionCallRegistersOnEveryPooledConnection` force `DatabasePool` to service
/// several calls at once, guaranteeing more than one physical reader connection executes this function.
///
/// `makeSQL` opts into implicit registration by calling `customFunctionCall` instead of `simpleFunction`
/// directly.
private struct ImplicitSquareFunction: XLCustomFunction {
    typealias T = Int

    static let definition = XLCustomFunctionDefinition(
        name: "implicitSquare",
        numberOfArguments: 1
    )

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
        Thread.sleep(forTimeInterval: 0.08)
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
    func testCustomFunctionCallRegistersOnEveryPooledConnection() throws {
        let maximumReaderCount = 4
        let database = try makeDatabase(maximumReaderCount: maximumReaderCount)

        let iterations = 8
        let functionDelay = 0.08
        let resultsLock = NSLock()
        var results: [Int: Result<Int?, Error>] = [:]

        let start = Date()
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            let value = index + 1
            let statement = sql { _ in Select(ImplicitSquareFunction(value)) }
            let outcome: Result<Int?, Error>
            do {
                outcome = .success(try database.makeRequest(with: statement).fetchOne())
            }
            catch {
                outcome = .failure(error)
            }
            resultsLock.lock()
            results[value] = outcome
            resultsLock.unlock()
        }
        let elapsed = Date().timeIntervalSince(start)

        // Every call executes the function-side sleep. Serialized onto one connection this would take at
        // least `iterations * functionDelay`; serviced across `maximumReaderCount` connections it should
        // take roughly `ceil(iterations / maximumReaderCount) * functionDelay`. A generous threshold well
        // below the fully serial figure confirms the pool actually used more than one physical connection
        // concurrently, rather than this test accidentally exercising only a single connection.
        let fullySerialDuration = Double(iterations) * functionDelay
        XCTAssertLessThan(
            elapsed,
            fullySerialDuration * 0.7,
            """
            Expected concurrent pooled reads to overlap across multiple connections; measured \
            \(elapsed)s (fully-serial would be \(fullySerialDuration)s) suggests they ran on just one \
            connection, which would not exercise this test's purpose.
            """
        )

        XCTAssertEqual(results.count, iterations)
        for value in 1...iterations {
            switch results[value] {
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
