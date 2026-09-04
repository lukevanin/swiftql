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

    @MainActor
    func testInitialSnapshotClearsLoadingAndPopulatesRows() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        let isLoadingInitially = model.isLoading
        XCTAssertTrue(isLoadingInitially)

        await xlWaitForObservedState { !model.isLoading }
        let rowsAfterInitialFetch = model.rows
        XCTAssertEqual(rowsAfterInitialFetch, [ObservableLiveQueryRecord(id: "a", value: 1)])
        let errorAfterInitialFetch = model.error
        XCTAssertNil(errorAfterInitialFetch)
        model.stop()
    }

    @MainActor
    func testRelevantWriteRefreshesRows() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        await xlWaitForObservedState { !model.isLoading }
        let rowsBeforeInsert = model.rows
        XCTAssertEqual(rowsBeforeInsert, [])

        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        await xlWaitForObservedState { model.rows == [ObservableLiveQueryRecord(id: "a", value: 1)] }
        model.stop()
    }

    // MARK: - Terminal error (XLObservableQuery)

    @MainActor
    func testTerminalErrorSetsErrorAndClearsLoadingWithoutMutatingRows() async throws {
        try createRecordTable()
        let schema = XLSchema()
        let table = schema.table(ObservableLiveQueryRecord.self)
        let statement = insert(table)
            .values(ObservableLiveQueryRecord.MetaInsert(ObservableLiveQueryRecord(id: "a", value: 1)))
            .returning(table)
        let model = XLObservableQuery(database.makeRequest(with: statement))

        await xlWaitForObservedState { !model.isLoading }
        let error = model.error
        XCTAssertEqual(error as? XLReturningRequestError, .observationUnsupported)
        let rowsAfterFailure = model.rows
        XCTAssertEqual(rowsAfterFailure, [], "A terminal error must not synthesize a partial result.")

        // The failed stream must not have executed the insert.
        let rows = try database.makeRequest(with: orderedStatement()).fetchAll()
        XCTAssertEqual(rows, [])
        model.stop()
    }

    // MARK: - Cancellation before the initial value

    @MainActor
    func testCancellationBeforeInitialValuePreventsAnyFetch() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        model.stop()

        // What `stop()` guarantees is that nothing fetches *after* it. It cannot promise the initial
        // fetch never started: the model starts its consumer `Task` in `init`, that `Task` is
        // nonisolated, and it can reach the observation start on a cooperative-pool thread inside the
        // window before this main-actor method gets to run `stop()`. This test used to assert a flat
        // zero and claim the interleaving could not happen; #468's repeat run disproved that at
        // roughly 1 run in 50 under load (`("1") is not equal to ("0")`).
        //
        // So the invariant is asserted as a *bound on the total*, not as a delta against a snapshot.
        // A snapshot taken after `stop()` can still be beaten by that initial fetch logging from a
        // GRDB queue afterwards -- `drainMainQueue()` fences the main queue, not GRDB's -- which
        // would just move the same race somewhere new. The bound holds under every interleaving: a
        // torn-down observation can never produce a second fetch, whenever the first one lands.
        await drainMainQueue()
        try insertDirect(ObservableLiveQueryRecord(id: "after-stop", value: 1))
        await drainMainQueue()
        XCTAssertLessThanOrEqual(
            logger.count(containing: "stream:"),
            1,
            "stop() must tear the observation down: at most the initial fetch may ever run, and a "
                + "write afterwards must not add another."
        )
        let isLoadingAfterCancellation = model.isLoading
        XCTAssertTrue(isLoadingAfterCancellation, "A cancelled-before-delivery model never leaves isLoading.")
    }

    /// Negative control for the test above: a model that was *not* stopped must fetch again on a
    /// relevant write, so "the count did not move" is a real check rather than a vacuous one.
    ///
    /// Constants are decoupled from the paired test's: a different row id and value.
    @MainActor
    func testNegativeControlLiveModelFetchesAgainOnAWrite() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        await xlWaitForObservedState { !model.isLoading }

        try insertDirect(ObservableLiveQueryRecord(id: "control-live", value: 7))
        await xlWaitForObservedState {
            model.rows == [ObservableLiveQueryRecord(id: "control-live", value: 7)]
        }

        // Deliberately the same quantity the paired test bounds at 1, so the two assertions speak
        // the same language: a live model exceeds that bound, a stopped one cannot.
        XCTAssertGreaterThan(
            logger.count(containing: "stream:"),
            1,
            "Negative control: a live model must fetch again on a relevant write -- otherwise the "
                + "stopped model's at-most-one-fetch bound cannot fail and proves nothing."
        )
        model.stop()
    }

    // MARK: - Model release stops further work

    @MainActor
    func testReleasedModelPerformsNoFurtherWorkAfterRelease() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        var model: XLObservableQuery<ObservableLiveQueryRecord>? = XLObservableQuery(
            database.makeRequest(with: orderedStatement())
        )
        await xlWaitForObservedState { !(model?.isLoading ?? true) }

        // `weak let` needs Swift 6.2+: the pinned Swift 5.9/6.0 cells reject it ("'weak' must be
        // a mutable variable"), and Swift 6.1 (Xcode 16.4) does too, despite `#if compiler(>=6.1)`
        // gating exactly this pattern successfully elsewhere for other syntax -- 6.2+ instead warns
        // that an unmutated `weak var` should be a `let`, so the binding's own mutability must switch
        // per compiler, both being warnings-as-errors gated.
        #if compiler(>=6.2)
        weak let weakModel = model
        #else
        weak var weakModel = model
        #endif
        model = nil // Drop the only strong reference; deinit must cancel the owned Task deterministically.

        // The one condition in this file nothing can signal: deallocation has no notification to
        // await, so this stays a bounded wait -- now one whose failure names what it was waiting
        // for. Everything else here is resumed by an Observation change.
        try await xlWaitUntil(describing: "the released model to be deallocated") {
            weakModel == nil
        }

        let fetchCountAfterRelease = logger.count(containing: "stream:")
        try insertDirect(ObservableLiveQueryRecord(id: "b", value: 2))
        await drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            fetchCountAfterRelease,
            "A released model's owned Task must stop observing -- no fetch may happen for it afterward."
        )
    }

    @MainActor
    func testExplicitStopPreventsFurtherWorkWithoutWaitingForDeallocation() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        await xlWaitForObservedState { !model.isLoading }

        model.stop()
        let fetchCountAtStop = logger.count(containing: "stream:")
        try insertDirect(ObservableLiveQueryRecord(id: "after-stop", value: 1))
        await drainMainQueue()
        XCTAssertEqual(
            logger.count(containing: "stream:"),
            fetchCountAtStop,
            "stop() must cancel the underlying observation without waiting for deallocation."
        )
    }

    // MARK: - Rapid updates coalesce (#291 bound-1 buffering, exercised end-to-end)

    @MainActor
    func testRapidUpdatesEventuallyReflectTheFinalDurableState() async throws {
        try createRecordTable()
        let model = XLObservableQuery(database.makeRequest(with: orderedStatement()))
        await xlWaitForObservedState { !model.isLoading }

        for index in 0 ..< 20 {
            try insertDirect(ObservableLiveQueryRecord(id: "row-\(index)", value: index))
        }

        await xlWaitForObservedState { model.rows.count == 20 }
        model.stop()
    }

    // MARK: - Immutable packet capture / binding replacement by new model creation

    @MainActor
    func testPacketBackedModelCapturesBindingsAcrossRefresh() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "per-1", value: 1))
        try insertDirect(ObservableLiveQueryRecord(id: "per-2", value: 2))

        let request = database.makeRequest(with: byIDStatement())
        let bindings = try makeIDBindings(request: request, id: "per-1")

        let model = XLObservableQuery(request, bindings: bindings)
        await xlWaitForObservedState { model.rows == [ObservableLiveQueryRecord(id: "per-1", value: 1)] }

        try insertDirect(ObservableLiveQueryRecord(id: "per-3", value: 3))
        await drainMainQueue()
        let rowsAfterUnrelatedInsert = model.rows
        XCTAssertEqual(
            rowsAfterUnrelatedInsert,
            [ObservableLiveQueryRecord(id: "per-1", value: 1)],
            "The packet must keep selecting id == 'per-1', never per-3."
        )
        model.stop()
    }

    @MainActor
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
        await xlWaitForObservedState { modelA?.rows == [ObservableLiveQueryRecord(id: "per-1", value: 1)] }

        // Releasing the first model and constructing a second with a different packet is how binding
        // replacement happens for this Observation-native surface: each model owns one immutable
        // packet for its whole lifetime, exactly like `stream(bindings:)`/`publish(bindings:)`.
        // See the matching compiler(>=6.2) note above for why this binding's mutability is conditional.
        #if compiler(>=6.2)
        weak let weakModelA = modelA
        #else
        weak var weakModelA = modelA
        #endif
        modelA = nil
        // See the deallocation note in testReleasedModelPerformsNoFurtherWorkAfterRelease.
        try await xlWaitUntil(describing: "the released model to be deallocated") {
            weakModelA == nil
        }

        let requestB = database.makeRequest(with: byIDStatement())
        let bindingsB = try makeIDBindings(request: requestB, id: "per-2")
        let modelB = XLObservableQuery(requestB, bindings: bindingsB)
        await xlWaitForObservedState { modelB.rows == [ObservableLiveQueryRecord(id: "per-2", value: 2)] }
        modelB.stop()
    }

    // MARK: - Two models, independent databases

    @MainActor
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
        await xlWaitForObservedState {
            let isLoadingA = modelA.isLoading
            let isLoadingB = modelB.isLoading
            return !isLoadingA && !isLoadingB
        }
        let initialRowsA = modelA.rows
        let initialRowsB = modelB.rows
        XCTAssertEqual(initialRowsA, [])
        XCTAssertEqual(initialRowsB, [])

        try insertDirect(ObservableLiveQueryRecord(id: "only-in-a", value: 1))
        await xlWaitForObservedState { modelA.rows == [ObservableLiveQueryRecord(id: "only-in-a", value: 1)] }

        await drainMainQueue()
        let finalRowsB = modelB.rows
        XCTAssertEqual(finalRowsB, [], "A write to the first database must not appear in the second.")
        modelA.stop()
        modelB.stop()
    }

    // MARK: - XLObservableQueryRow

    @MainActor
    func testObservableQueryRowDeliversInitialAndRefreshedFirstRow() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        let model = XLObservableQueryRow(database.makeRequest(with: orderedStatement()))
        await xlWaitForObservedState { !model.isLoading }
        let initialRow = model.row
        XCTAssertEqual(initialRow, ObservableLiveQueryRecord(id: "a", value: 1))

        // "A-earlier" sorts before "a", so the observed first row changes.
        try insertDirect(ObservableLiveQueryRecord(id: "A-earlier", value: 2))
        await xlWaitForObservedState { model.row == ObservableLiveQueryRecord(id: "A-earlier", value: 2) }
        model.stop()
    }

    @MainActor
    func testObservableQueryRowReleasedModelStopsFurtherWork() async throws {
        try createRecordTable()
        try insertDirect(ObservableLiveQueryRecord(id: "a", value: 1))

        var model: XLObservableQueryRow<ObservableLiveQueryRecord>? = XLObservableQueryRow(
            database.makeRequest(with: orderedStatement())
        )
        await xlWaitForObservedState { !(model?.isLoading ?? true) }

        // See the compiler(>=6.2) note in testReleasedModelPerformsNoFurtherWorkAfterRelease above.
        #if compiler(>=6.2)
        weak let weakModel = model
        #else
        weak var weakModel = model
        #endif
        model = nil
        // The one condition in this file nothing can signal: deallocation has no notification to
        // await, so this stays a bounded wait -- now one whose failure names what it was waiting
        // for. Everything else here is resumed by an Observation change.
        try await xlWaitUntil(describing: "the released model to be deallocated") {
            weakModel == nil
        }

        let fetchCountAfterRelease = logger.count(containing: "streamOne:")
        try insertDirect(ObservableLiveQueryRecord(id: "b", value: 2))
        await drainMainQueue()
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

    // `async`, using a continuation round-tripped through the main dispatch queue, rather than XCTest's
    // synchronous `wait(for:timeout:)`: the blocking waiter deadlocks when called from one of this
    // file's `@MainActor` test methods -- it needs to pump the run loop to let the `DispatchQueue.main
    // .async` block run, but that block competes with the same main-actor executor already suspended
    // resuming the calling test method's own async context, so it never gets a turn within the timeout.
    //
    // A barrier, not a deadline: it resumes when the main queue reaches the block it enqueued. Used
    // only where the assertion is "no *further* work happened", after letting whatever was already
    // scheduled on the delivery queue run. The suite's polling `waitUntil` is gone (#467): every
    // other wait here is resumed by an Observation change through `xlWaitForObservedState`.
    @MainActor
    private func drainMainQueue() async {
        await xlDrainMainQueue()
    }
}
#endif
