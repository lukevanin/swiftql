import XCTest

import SwiftQL
import TodoKit

/// Covers the query layer: filters, search, sort, the join, the aggregate,
/// the `RETURNING` writes, and the move transaction.
///
/// Every test runs against its own temporary database at a fixed reference
/// date, so "overdue" never depends on when the suite runs.
final class TodoStoreTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000.25)

    private var directory: URL!
    private var database: TodoDatabase!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoStoreTests-\(UUID().uuidString)", isDirectory: true)
        database = try TodoDatabase(
            url: directory.appendingPathComponent(TodoDatabase.fileName),
            referenceDate: referenceDate
        )
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: directory)
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

    private func titles(_ query: TodoQuery) throws -> [String] {
        try database.todos(matching: query).map(\.title)
    }

    // MARK: - Filters

    func testAllReturnsEveryToDoInTheList() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.homeListID, filter: .all)).sorted(),
            ["Pay the rent", "Sharpen the kitchen knives"]
        )
    }

    func testActiveExcludesCompleted() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.homeListID, filter: .active)),
            ["Sharpen the kitchen knives"]
        )
    }

    func testCompletedExcludesActive() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.homeListID, filter: .completed)),
            ["Pay the rent"]
        )
    }

    func testOverdueIsPastDueAndStillOpen() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, filter: .overdue)),
            ["Renew passport"]
        )
    }

    func testACompletedToDoPastItsDueDateIsNotOverdue() throws {
        // "Pay the rent" is two days past due and done. Overdue means work
        // still owed, not a date in the past.
        XCTAssertEqual(
            try titles(query(TodoSeed.homeListID, filter: .overdue)),
            []
        )
    }

    func testAToDoWithNoDueDateIsNeverOverdue() throws {
        XCTAssertFalse(
            try titles(query(TodoSeed.homeListID, filter: .overdue))
                .contains("Sharpen the kitchen knives")
        )
    }

    func testAFilterDoesNotLeakAcrossLists() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.readingListID, filter: .all)).sorted(),
            ["Finish the novel", "Return the library book"]
        )
    }

    // MARK: - Search

    func testSearchMatchesTitle() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "passport")),
            ["Renew passport"]
        )
    }

    func testSearchMatchesNotes() throws {
        // "molar" appears only in the dentist to-do's notes.
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "molar")),
            ["Book a dentist appointment"]
        )
    }

    func testSearchExcludesNonMatches() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "bicycle")),
            []
        )
    }

    func testAnEmptySearchMatchesEverything() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "")).count,
            2
        )
    }

    func testSearchTreatsWildcardsAsText() throws {
        try database.createTodo(
            listID: TodoSeed.todayListID,
            title: "Claim the 50% refund",
            now: TodoDate(referenceDate)
        )
        try database.createTodo(
            listID: TodoSeed.todayListID,
            title: "Rename draft_final",
            now: TodoDate(referenceDate)
        )

        // Each of these is a LIKE wildcard. Escaped, they match the one row
        // that literally contains the character, not every row.
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "%")),
            ["Claim the 50% refund"]
        )
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "_")),
            ["Rename draft_final"]
        )
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "50%")),
            ["Claim the 50% refund"]
        )
    }

    func testSearchStillMatchesAcrossAnEscapedCharacter() throws {
        try database.createTodo(
            listID: TodoSeed.todayListID,
            title: "Claim the 50% refund",
            now: TodoDate(referenceDate)
        )

        // The escape is applied to the user's text, not to the surrounding
        // wildcards, so a substring search still works.
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, search: "the 50% ref")),
            ["Claim the 50% refund"]
        )
    }

    func testSearchComposesWithAFilter() throws {
        XCTAssertEqual(
            try titles(query(
                TodoSeed.todayListID,
                filter: .overdue,
                search: "passport"
            )),
            ["Renew passport"]
        )
        XCTAssertEqual(
            try titles(query(
                TodoSeed.todayListID,
                filter: .completed,
                search: "passport"
            )),
            []
        )
    }

    // MARK: - Sort

    func testDueDateSortPutsTheSoonestFirstAndNoDueDateLast() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.homeListID, sort: .dueDate)),
            ["Pay the rent", "Sharpen the kitchen knives"]
        )
    }

    func testPrioritySortPutsTheHighestFirst() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, sort: .priority)),
            ["Renew passport", "Book a dentist appointment"]
        )
    }

    func testManualSortFollowsPosition() throws {
        XCTAssertEqual(
            try titles(query(TodoSeed.todayListID, sort: .manual)),
            ["Renew passport", "Book a dentist appointment"]
        )
    }

    // MARK: - Join

    func testTagsForOneToDoComeBackThroughTheJoin() throws {
        XCTAssertEqual(
            try database.tags(forTodo: TodoSeed.renewPassportID).map(\.name),
            ["errand", "urgent"]
        )
    }

    func testAnUntaggedToDoHasNoTags() throws {
        XCTAssertEqual(
            try database.tags(forTodo: TodoSeed.sharpenKnivesID),
            []
        )
    }

    func testTagsForAWholeListArriveInOneQuery() throws {
        let byTodo = try database.tagsByTodo(inList: TodoSeed.todayListID)

        XCTAssertEqual(
            byTodo[TodoSeed.renewPassportID]?.map(\.name),
            ["errand", "urgent"]
        )
        XCTAssertEqual(
            byTodo[TodoSeed.bookDentistID]?.map(\.name),
            ["errand"]
        )
    }

    // MARK: - Aggregate

    func testPerListCountsMatchWhatTheFiltersReturn() throws {
        let counts = try database.listCounts()

        for list in try database.lists() {
            let all = try titles(query(list.id, filter: .all)).count
            let active = try titles(query(list.id, filter: .active)).count
            XCTAssertEqual(counts[list.id]?.totalCount, all, list.name)
            XCTAssertEqual(counts[list.id]?.openCount, active, list.name)
        }
    }

    func testAListWithNoToDosCountsZero() throws {
        for todo in try database.todos() where todo.listID == TodoSeed.readingListID {
            try database.deleteTodo(id: todo.id)
        }

        let counts = try database.listCounts()

        XCTAssertEqual(counts[TodoSeed.readingListID]?.totalCount, 0)
        XCTAssertEqual(counts[TodoSeed.readingListID]?.openCount, 0)
    }

    // MARK: - Writes

    func testCreateReturnsTheRowItWrote() throws {
        let created = try database.createTodo(
            listID: TodoSeed.todayListID,
            title: "Water the plants",
            notes: "The fern especially",
            dueAt: TodoDate(referenceDate),
            priority: .high,
            now: TodoDate(referenceDate)
        )

        XCTAssertEqual(created.title, "Water the plants")
        XCTAssertEqual(created.listID, TodoSeed.todayListID)
        XCTAssertEqual(created.priority, .high)
        XCTAssertFalse(created.isCompleted)
        XCTAssertEqual(created.position, 2, "appended after the two seeded rows")
        XCTAssertEqual(try database.todo(id: created.id), created)
    }

    func testCreateRejectsAnUnknownList() throws {
        let missing = TodoUUID()

        XCTAssertThrowsError(
            try database.createTodo(listID: missing, title: "Nowhere")
        ) { error in
            XCTAssertEqual(error as? TodoStoreError, .listNotFound(missing))
        }
    }

    func testUpdateReturnsTheEditedRow() throws {
        let updated = try database.updateTodo(
            id: TodoSeed.renewPassportID,
            title: "Renew passport urgently",
            notes: "Queue is longer than expected",
            dueAt: nil,
            priority: .low
        )

        XCTAssertEqual(updated.title, "Renew passport urgently")
        XCTAssertNil(updated.dueAt, "a nil due date is a present SQL NULL")
        XCTAssertEqual(updated.priority, .low)
        XCTAssertEqual(try database.todo(id: TodoSeed.renewPassportID), updated)
    }

    func testUpdateRejectsAnUnknownToDo() throws {
        let missing = TodoUUID()

        XCTAssertThrowsError(
            try database.updateTodo(
                id: missing,
                title: "x",
                notes: "",
                dueAt: nil,
                priority: .low
            )
        ) { error in
            XCTAssertEqual(error as? TodoStoreError, .todoNotFound(missing))
        }
    }

    func testToggleFlipsCompletionAndReturnsTheRow() throws {
        let toggled = try database.toggleCompleted(todoID: TodoSeed.renewPassportID)
        XCTAssertTrue(toggled.isCompleted)
        XCTAssertEqual(try database.todo(id: TodoSeed.renewPassportID)?.isCompleted, true)

        let back = try database.toggleCompleted(todoID: TodoSeed.renewPassportID)
        XCTAssertFalse(back.isCompleted)
        XCTAssertEqual(try database.todo(id: TodoSeed.renewPassportID)?.isCompleted, false)
    }

    func testDeleteReturnsTheRowItRemovedAndTakesItsTagsWithIt() throws {
        let removed = try database.deleteTodo(id: TodoSeed.renewPassportID)

        XCTAssertEqual(removed.id, TodoSeed.renewPassportID)
        XCTAssertNil(try database.todo(id: TodoSeed.renewPassportID))
        XCTAssertEqual(try database.tags(forTodo: TodoSeed.renewPassportID), [])
        XCTAssertFalse(
            try database.todoTags().contains { $0.todoID == TodoSeed.renewPassportID }
        )
    }

    func testDeleteRejectsAnUnknownToDo() throws {
        let missing = TodoUUID()

        XCTAssertThrowsError(try database.deleteTodo(id: missing)) { error in
            XCTAssertEqual(error as? TodoStoreError, .todoNotFound(missing))
        }
    }

    // MARK: - Move

    func testMovePlacesTheToDoAndClosesTheGapBehindIt() throws {
        let moved = try database.move(
            todoID: TodoSeed.renewPassportID,
            toList: TodoSeed.homeListID
        )

        XCTAssertEqual(moved.listID, TodoSeed.homeListID)
        XCTAssertEqual(moved.position, 2, "appended after the two rows already there")

        let dentist = try XCTUnwrap(try database.todo(id: TodoSeed.bookDentistID))
        XCTAssertEqual(dentist.position, 0, "renumbered down into the gap")
    }

    func testMoveRejectsAnUnknownDestination() throws {
        let missing = TodoUUID()

        XCTAssertThrowsError(
            try database.move(todoID: TodoSeed.renewPassportID, toList: missing)
        ) { error in
            XCTAssertEqual(error as? TodoStoreError, .listNotFound(missing))
        }
    }

    func testAFailureMidMoveLeavesBothListsUntouched() throws {
        struct Interrupted: Error {}

        let before = try database.todos().sorted {
            $0.id.wrappedValue.uuidString < $1.id.wrappedValue.uuidString
        }

        XCTAssertThrowsError(
            try database.move(
                todoID: TodoSeed.renewPassportID,
                toList: TodoSeed.homeListID,
                beforeCommit: { _ in throw Interrupted() }
            )
        ) { error in
            XCTAssertTrue(error is Interrupted)
        }

        let after = try database.todos().sorted {
            $0.id.wrappedValue.uuidString < $1.id.wrappedValue.uuidString
        }
        XCTAssertEqual(after, before, "the rollback undid the renumbering too")
    }

    // MARK: - Determinism

    func testRepeatedRunsOfTheSameQueryAgree() throws {
        let subject = query(TodoSeed.todayListID, sort: .priority)
        let first = try titles(subject)

        for _ in 0..<10 {
            XCTAssertEqual(try titles(subject), first)
        }
    }
}
