//
//  XLObservableLiveQueryTests.swift
//

// See the matching guard in XLObservableLiveQuery.swift: `canImport(Darwin)` excludes Linux, where
// the production type itself is no longer compiled.
#if canImport(Observation) && canImport(Darwin)
import Foundation
import GRDB
import XCTest
@testable import SwiftQL


// MARK: - Fixtures

@SQLTable(name: "ObservableLiveQueryRecord")
private struct ObservableLiveQueryRecord: Equatable, Identifiable {
    let id: String
    let value: Int
}


@available(iOS 17, macOS 14, *)
final class XLObservableLiveQueryTests: XCTestCase {

    private final class RecordingLogger: XLLogger {
        private let lock = NSLock()
        private var messages: [String] = []

        func log(level: XLLogLevel, message: String) {
            lock.lock()
            messages.append(message)
            lock.unlock()
        }

        func count(containing fragment: String) -> Int {
            lock.lock()
            defer { lock.unlock() }
            return messages.filter { $0.contains(fragment) }.count
        }
    }

    private var databaseDirectoryURL: URL!
    private var databasePool: DatabasePool!
    private var database: GRDBDatabase!
    private var logger: RecordingLogger!

    override func setUpWithError() throws {
        databaseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = databaseDirectoryURL.appendingPathComponent(
            "observable-live-query.sqlite",
            isDirectory: false
        )
        databasePool = try DatabasePool(path: fileURL.path)
        logger = RecordingLogger()
        database = try GRDBDatabase(databasePool: databasePool, formatter: XLiteFormatter(), logger: logger)
    }

    override func tearDown() {
        database = nil
        databasePool = nil
        logger = nil
        try? FileManager.default.removeItem(at: databaseDirectoryURL)
        databaseDirectoryURL = nil
    }

    // MARK: - Initial delivery + relevant-write refresh (XLObservableQuery)

    func testInitialSnapshotClearsLoadingAndPopulatesRows() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        let isLoadingInitially = await model.isLoading
        XCTAssertTrue(isLoadingInitially)

        try await waitUntil { await !model.isLoading }
        let rowsAfterInitialFetch = await model.rows
        XCTAssertEqual(rowsAfterInitialFetch, [ObservableLiveQueryRecord(id: "a", value: 1)])
        let errorAfterInitialFetch = await model.error
        XCTAssertNil(errorAfterInitialFetch)
        model.stop()
    }

    func testRelevantWriteRefreshesRows() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        try await waitUntil { await !model.isLoading }
        let rowsBeforeInsert = await model.rows
        XCTAssertEqual(rowsBeforeInsert, [])

        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        try await waitUntil { await model.rows == [ObservableLiveQueryRecord(id: "a", value: 1)] }
        model.stop()
    }

    // MARK: - Terminal error (XLObservableQuery)

    func testTerminalErrorSetsErrorAndClearsLoadingWithoutMutatingRows() async throws {
        try createRecordTable()
        let schema = XLSchema()
        let table = schema.table(ObservableLiveQueryRecord.self)
        let statement = insert(table)
            .values(ObservableLiveQueryRecord.MetaInsert(ObservableLiveQueryRecord(id: "a", value: 1)))
            .returning(table)
        let model = XLObservableQuery(database.makeRequest(with: statement))

        try await waitUntil { await !model.isLoading }
        let error = await model.error
        XCTAssertEqual(error as? XLReturningRequestError, .observationUnsupported)
        let rowsAfterFailure = await model.rows
        XCTAssertEqual(rowsAfterFailure, [], "A terminal error must not synthesize a partial result.")

        // The failed stream must not have executed the insert.
        let rows = try database.makeRequest(with: orderedStatement()).fetchAll()
        XCTAssertEqual(rows, [])
        model.stop()
    }

    // MARK: - Cancellation before the initial value

    func testCancellationBeforeInitialValuePreventsAnyFetch() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        // `stop()` here does not depend on beating the consumer Task's own scheduling: even if that
        // Task had already started running by this point, `stream()`'s own cancellation contract
        // (`GRDBLiveQueryAsyncBridge.next()`, issue #308) checks `Task.isCancelled` *before* starting
        // any GRDB observation, inside `withTaskCancellationHandler`'s `operation` closure -- so no
        // fetch can occur once `stop()` has been called, regardless of the exact interleaving.
        model.stop()

        drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            0,
            "Stopping before the first value is ever delivered must perform no fetch."
        )
        let isLoadingAfterCancellation = await model.isLoading
        XCTAssertTrue(isLoadingAfterCancellation, "A cancelled-before-delivery model never leaves isLoading.")
    }

    // MARK: - Model release stops further work

    func testReleasedModelPerformsNoFurtherWorkAfterRelease() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        var model: XLObservableQuery<ObservableLiveQueryRecord>? = XLObservableQuery(
            database.makeRequest(with: orderedStatement())
        )
        try await waitUntil { await !(model?.isLoading ?? true) }

        weak var weakModel = model
        model = nil // Drop the only strong reference; deinit must cancel the owned Task deterministically.

        try await waitUntil { weakModel == nil }

        let fetchCountAfterRelease = logger.count(containing: "stream:")
        try insertDirect(ObservableLiveQueryRecord(id: "b", value: 2))
        drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            fetchCountAfterRelease,
            "A released model's owned Task must stop observing -- no fetch may happen for it afterward."
        )
    }

    func testExplicitStopPreventsFurtherWorkWithoutWaitingForDeallocation() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        try await waitUntil { await !model.isLoading }

        model.stop()
        let fetchCountAtStop = logger.count(containing: "stream:")
        try insertDirect(ObservableLiveQueryRecord(id: "after-stop", value: 1))
        drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            fetchCountAtStop,
            "stop() must cancel the underlying observation without waiting for deallocation."
        )
    }

    // MARK: - Rapid updates coalesce (#291 bound-1 buffering, exercised end-to-end)

    func testRapidUpdatesEventuallyReflectTheFinalDurableState() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        try await waitUntil { await !model.isLoading }

        for index in 0 ..< 20 {
            try insertDirect(ObservableLiveQueryRecord(id: "row-\(index)", value: index))
        }

        try await waitUntil(timeout: 5) { await model.rows.count == 20 }
        model.stop()
    }

    // MARK: - Immutable packet capture / binding replacement by new model creation

    func testPacketBackedModelCapturesBindingsAcrossRefresh() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "per-1", value: 1))
        try insertDirect(ObservableLiveQueryRecord(id: "per-2", value: 2))

        let request = database.makeRequest(with: byIDStatement())
        let bindings = try makeIDBindings(request: request, id: "per-1")

        let model = XLObservableQuery(request, bindings: bindings)
        try await waitUntil { await model.rows == [ObservableLiveQueryRecord(id: "per-1", value: 1)] }

        try insertDirect(ObservableLiveQueryRecord(id: "per-3", value: 3))
        drainMainQueue()
        let rowsAfterUnrelatedInsert = await model.rows
        XCTAssertEqual(
            rowsAfterUnrelatedInsert,
            [ObservableLiveQueryRecord(id: "per-1", value: 1)],
            "The packet must keep selecting id == 'per-1', never per-3."
        )
        model.stop()
    }

    func testNewModelWithADifferentBindingPacketObservesIndependently() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "per-1", value: 1))
        try insertDirect(ObservableLiveQueryRecord(id: "per-2", value: 2))

        let requestA = database.makeRequest(with: byIDStatement())
        let bindingsA = try makeIDBindings(request: requestA, id: "per-1")
        var modelA: XLObservableQuery<ObservableLiveQueryRecord>? = XLObservableQuery(
            requestA,
            bindings: bindingsA
        )
        try await waitUntil { await modelA?.rows == [ObservableLiveQueryRecord(id: "per-1", value: 1)] }

        // Releasing the first model and constructing a second with a different packet is how binding
        // replacement happens for this Observation-native surface: each model owns one immutable
        // packet for its whole lifetime, exactly like `stream(bindings:)`/`publish(bindings:)`.
        weak var weakModelA = modelA
        modelA = nil
        try await waitUntil { weakModelA == nil }

        let requestB = database.makeRequest(with: byIDStatement())
        let bindingsB = try makeIDBindings(request: requestB, id: "per-2")
        let modelB = XLObservableQuery(requestB, bindings: bindingsB)
        try await waitUntil { await modelB.rows == [ObservableLiveQueryRecord(id: "per-2", value: 2)] }
        modelB.stop()
    }

    // MARK: - Two models, independent databases

    func testTwoModelsObservingIndependentDatabasesDoNotCrossTrigger() async throws {
        try createRecordTable()

        let secondDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: secondDirectory) }
        let secondPool = try DatabasePool(
            path: secondDirectory.appendingPathComponent("second.sqlite").path
        )
        let secondDatabase = try GRDBDatabase(
            databasePool: secondPool,
            formatter: XLiteFormatter(),
            logger: nil
        )
        try await secondPool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE ObservableLiveQueryRecord (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    );
                """
            )
        }

        let modelA = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        let modelB = XLObservableQuery(secondDatabase.makeRequest(with: orderedStatement()))
        try await waitUntil {
            let isLoadingA = await modelA.isLoading
            let isLoadingB = await modelB.isLoading
            return !isLoadingA && !isLoadingB
        }
        let initialRowsA = await modelA.rows
        let initialRowsB = await modelB.rows
        XCTAssertEqual(initialRowsA, [])
        XCTAssertEqual(initialRowsB, [])

        try insertDirect(ObservableLiveQueryRecord(id: "only-in-a", value: 1))
        try await waitUntil { await modelA.rows == [ObservableLiveQueryRecord(id: "only-in-a", value: 1)] }

        drainMainQueue()
        let finalRowsB = await modelB.rows
        XCTAssertEqual(finalRowsB, [], "A write to the first database must not appear in the second.")
        modelA.stop()
        modelB.stop()
    }

    // MARK: - XLObservableQueryRow

    func testObservableQueryRowDeliversInitialAndRefreshedFirstRow() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        let model = XLObservableQueryRow(database.makeRequest(with: orderedStatement()))
        try await waitUntil { await !model.isLoading }
        let initialRow = await model.row
        XCTAssertEqual(initialRow, ObservableLiveQueryRecord(id: "a", value: 1))

        // "A-earlier" sorts before "a", so the observed first row changes.
        try insertDirect(ObservableLiveQueryRecord(id: "A-earlier", value: 2))
        try await waitUntil { await model.row == ObservableLiveQueryRecord(id: "A-earlier", value: 2) }
        model.stop()
    }

    func testObservableQueryRowReleasedModelStopsFurtherWork() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        var model: XLObservableQueryRow<ObservableLiveQueryRecord>? = XLObservableQueryRow(
            database.makeRequest(with: orderedStatement())
        )
        try await waitUntil { await !(model?.isLoading ?? true) }

        weak var weakModel = model
        model = nil
        try await waitUntil { weakModel == nil }

        let fetchCountAfterRelease = logger.count(containing: "streamOne:")
        try insertDirect(ObservableLiveQueryRecord(id: "b", value: 2))
        drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "streamOne:"),
            fetchCountAfterRelease,
            "A released XLObservableQueryRow must stop observing after deinit cancels its Task."
        )
    }

    // MARK: - Helpers

    private func orderedStatement() -> any XLQueryStatement<ObservableLiveQueryRecord> {
        sql { schema in
            let table = schema.table(ObservableLiveQueryRecord.self)
            Select(table)
            From(table)
            OrderBy(table.id.ascending())
        }
    }

    private func byIDStatement() -> any XLQueryStatement<ObservableLiveQueryRecord> {
        let idParameter = XLNamedBindingReference<String>(name: "id")
        return sql { schema in
            let table = schema.table(ObservableLiveQueryRecord.self)
            Select(table)
            From(table)
            Where(table.id == idParameter)
        }
    }

    private func makeIDBindings(
        request: any XLRequest<ObservableLiveQueryRecord>,
        id: String
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        let layout = request.parameterLayout
        let slot = try XCTUnwrap(layout.slot(for: .named("id")))
        return try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: .text(id))]
        ).validatingComplete()
    }

    private func createRecordTable() throws {
        try databasePool.write { database in
            try database.execute(
                literal: """
                    CREATE TABLE ObservableLiveQueryRecord (
                        id TEXT NOT NULL PRIMARY KEY,
                        value INT NOT NULL
                    );
                """
            )
        }
    }

    private func insertDirect(_ row: ObservableLiveQueryRecord) throws {
        try databasePool.write { database in
            try database.execute(
                sql: "INSERT INTO ObservableLiveQueryRecord (id, value) VALUES (?, ?)",
                arguments: [row.id, row.value]
            )
        }
    }

    private func drainMainQueue() {
        let barrier = expectation(description: "main-queue barrier")
        DispatchQueue.main.async {
            barrier.fulfill()
        }
        wait(for: [barrier], timeout: 2)
    }

    /// Bounded, deterministic polling: sleeps in small increments up to `timeout`, checking `condition`
    /// each time, rather than proving anything via one blind sleep. Mirrors
    /// `GRDBLiveQueryAsyncStreamTests.waitUntil`, adapted to an `async` condition closure so it can read
    /// this file's main-actor-isolated `@Observable` state.
    private func waitUntil(
        timeout: TimeInterval = 3,
        pollInterval: UInt64 = 10_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async throws {
        let maxAttempts = max(Int((timeout * 1_000_000_000) / Double(pollInterval)), 1)
        for _ in 0 ..< maxAttempts {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        XCTFail("Condition not met within \(timeout)s", file: file, line: line)
    }
}
#endif
