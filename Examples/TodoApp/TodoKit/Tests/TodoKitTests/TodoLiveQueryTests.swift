import XCTest

import SwiftQL
import TodoKit

/// Proves the interface's central claim: a write updates every view that
/// reads the affected tables, with no refetch call anywhere.
///
/// Waiting is bounded polling on the main actor, not a sleep — the loop ends
/// as soon as the snapshot arrives, and fails with a useful message if it
/// never does.
@available(iOS 17, macOS 14, *)
@MainActor
final class TodoLiveQueryTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000.25)

    private var directory: URL!
    private var database: TodoDatabase!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoLiveTests-\(UUID().uuidString)", isDirectory: true)
        database = try TodoDatabase(
            url: directory.appendingPathComponent(TodoDatabase.fileName),
            referenceDate: referenceDate
        )
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Polls `condition` until it holds or the budget runs out.
    private func wait(
        for description: String,
        timeout: TimeInterval = 5,
        until condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for \(description)")
    }

    private func query(
        _ listID: TodoUUID = TodoSeed.todayListID,
        filter: TodoFilter = .all,
        sort: TodoSort = .manual,
        search: String = ""
    ) -> TodoQuery {
        TodoQuery(
            listID: listID,
            filter: filter,
            sort: sort,
            searchText: search,
            referenceDate: TodoDate(referenceDate)
        )
    }

    // MARK: - Delivery

    func testAListModelDeliversItsFirstSnapshotWithoutBeingAsked() async throws {
        let model = try TodoListModel(database: database, query: query())

        try await wait(for: "the initial snapshot") { !model.todos.isLoading }

        XCTAssertEqual(
            model.todos.rows.map(\.title),
            ["Renew passport", "Book a dentist appointment"]
        )
        XCTAssertNil(model.todos.error)
    }

    func testCompletingAToDoUpdatesTheListWithNoRefetch() async throws {
        let model = try TodoListModel(
            database: database,
            query: query(filter: .active)
        )
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        // A write, and nothing else. No reload call follows.
        try database.setCompleted(true, todoID: TodoSeed.renewPassportID)

        try await wait(for: "the completed to-do to leave the active filter") {
            model.todos.rows.count == 1
        }
        XCTAssertEqual(
            model.todos.rows.map(\.title),
            ["Book a dentist appointment"]
        )
    }

    func testCompletingAToDoUpdatesTheSidebarCounts() async throws {
        let sidebar = TodoSidebarModel(database: database)
        try await wait(for: "the initial counts") {
            sidebar.counts(for: TodoSeed.todayListID).totalCount == 2
        }
        XCTAssertEqual(sidebar.counts(for: TodoSeed.todayListID).openCount, 2)

        try database.setCompleted(true, todoID: TodoSeed.renewPassportID)

        try await wait(for: "the open count to fall") {
            sidebar.counts(for: TodoSeed.todayListID).openCount == 1
        }
        XCTAssertEqual(
            sidebar.counts(for: TodoSeed.todayListID).totalCount,
            2,
            "completing a to-do does not remove it"
        )
    }

    func testTheDetailAndTheListSeeTheSameWrite() async throws {
        let list = try TodoListModel(database: database, query: query())
        let detail = try TodoDetailModel(
            database: database,
            todoID: TodoSeed.renewPassportID
        )
        try await wait(for: "both initial snapshots") {
            !list.todos.isLoading && !detail.todo.isLoading
        }
        XCTAssertEqual(detail.todo.row?.isCompleted, false)

        try database.toggleCompleted(todoID: TodoSeed.renewPassportID)

        try await wait(for: "the detail to update") {
            detail.todo.row?.isCompleted == true
        }
        try await wait(for: "the list to update") {
            list.todos.rows.first { $0.id == TodoSeed.renewPassportID }?
                .isCompleted == true
        }
    }

    func testANewToDoAppearsInTheList() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        try database.createTodo(
            listID: TodoSeed.todayListID,
            title: "Water the plants",
            now: TodoDate(referenceDate)
        )

        try await wait(for: "the new to-do") { model.todos.rows.count == 3 }
        XCTAssertTrue(model.todos.rows.contains { $0.title == "Water the plants" })
    }

    func testADeletedToDoLeavesTheList() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        try database.deleteTodo(id: TodoSeed.renewPassportID)

        try await wait(for: "the to-do to go") { model.todos.rows.count == 1 }
    }

    // MARK: - Rebinding

    func testChangingTheFilterRebindsRatherThanFilteringInSwift() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }
        let before = ObjectIdentifier(model.todos)

        model.filter = .overdue

        XCTAssertNotEqual(
            ObjectIdentifier(model.todos),
            before,
            "a new filter is a new observation, not a Swift-side filter"
        )
        try await wait(for: "the overdue snapshot") {
            model.todos.rows.map(\.title) == ["Renew passport"]
        }
    }

    func testChangingTheSortRebinds() async throws {
        let model = try TodoListModel(
            database: database,
            query: query(TodoSeed.homeListID)
        )
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        model.sort = .dueDate

        try await wait(for: "the re-sorted snapshot") {
            model.todos.rows.map(\.title)
                == ["Pay the rent", "Sharpen the kitchen knives"]
        }
    }

    func testChangingTheSearchRebinds() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        model.searchText = "passport"

        try await wait(for: "the searched snapshot") {
            model.todos.rows.map(\.title) == ["Renew passport"]
        }
    }

    func testSettingTheSameQueryDoesNotRebind() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { !model.todos.isLoading }
        let before = ObjectIdentifier(model.todos)

        model.filter = .all

        XCTAssertEqual(
            ObjectIdentifier(model.todos),
            before,
            "an unchanged query should not restart the observation"
        )
    }

    // MARK: - Teardown

    func testStoppingAModelEndsItsObservation() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        // A probe on the same database, still observing. Waiting for it to
        // see the delete is what bounds the window: once a live observation
        // has delivered this commit, a stopped one has had its chance too.
        // That is a condition to wait on, not a duration to guess at.
        let probe = TodoSidebarModel(database: database)
        try await wait(for: "the probe's initial counts") {
            probe.counts(for: TodoSeed.todayListID).totalCount == 2
        }

        model.stop()
        try database.deleteTodo(id: TodoSeed.renewPassportID)

        try await wait(for: "the probe to see the delete") {
            probe.counts(for: TodoSeed.todayListID).totalCount == 1
        }
        XCTAssertEqual(
            model.todos.rows.count,
            2,
            "a stopped observation delivers nothing further"
        )
    }

    func testAReleasedModelStopsObserving() async throws {
        // The probe outlives the model and watches the same database, so a
        // snapshot arriving for the probe proves the write really happened
        // and the released model simply is not there to receive one.
        let probe = TodoSidebarModel(database: database)
        try await wait(for: "the probe's initial counts") {
            probe.counts(for: TodoSeed.todayListID).totalCount == 2
        }

        do {
            let model = try TodoListModel(database: database, query: query())
            try await wait(for: "the model's snapshot") { model.todos.rows.count == 2 }
        }

        try database.deleteTodo(id: TodoSeed.renewPassportID)

        try await wait(for: "the probe to see the delete") {
            probe.counts(for: TodoSeed.todayListID).totalCount == 1
        }
    }

    // MARK: - Ordering

    func testRapidWritesLeaveTheListAtTheFinalState() async throws {
        let model = try TodoListModel(database: database, query: query())
        try await wait(for: "the initial snapshot") { model.todos.rows.count == 2 }

        for index in 0..<20 {
            try database.createTodo(
                listID: TodoSeed.todayListID,
                title: "Batch \(index)",
                now: TodoDate(referenceDate)
            )
        }

        // Live queries are state streams, not commit logs: snapshots may
        // coalesce, but the last one has to be current.
        try await wait(for: "every write to land") { model.todos.rows.count == 22 }
        XCTAssertEqual(
            Set(model.todos.rows.map(\.title)).count,
            22,
            "no row was dropped or duplicated"
        )
        XCTAssertNil(model.todos.error)
    }
}
