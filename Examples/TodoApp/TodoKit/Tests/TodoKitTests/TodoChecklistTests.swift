import XCTest

import SwiftQL
import TodoKit

/// The checklist column, which is the demo's one JSON column.
///
/// Every write here is an `UPDATE` that SQLite applies to the stored array.
/// The assertions read the row back, so a statement that renders but does not
/// change what the database holds fails here.
final class TodoChecklistTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000.25)

    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
    }

    private func makeDatabase() throws -> TodoDatabase {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoChecklist-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        return try TodoDatabase(
            url: directory.appendingPathComponent(TodoDatabase.fileName),
            referenceDate: referenceDate
        )
    }

    // MARK: - Seeded state

    func testASeededToDoCarriesItsChecklist() throws {
        let database = try makeDatabase()
        let todo = try XCTUnwrap(try database.todo(id: TodoSeed.renewPassportID))
        XCTAssertEqual(
            TodoChecklist.items(from: todo.checklist),
            [
                TodoChecklistItem(title: "Find the old passport", isDone: true),
                TodoChecklistItem(title: "Book the appointment"),
                TodoChecklistItem(title: "Take a photograph"),
            ]
        )
    }

    func testAToDoWithNoSubTasksHoldsAnEmptyArrayRatherThanNull() throws {
        let database = try makeDatabase()
        let todo = try XCTUnwrap(try database.todo(id: TodoSeed.bookDentistID))
        XCTAssertEqual(todo.checklist, TodoChecklist.empty)
        XCTAssertEqual(TodoChecklist.items(from: todo.checklist), [])
    }

    func testANewToDoStartsWithAnEmptyChecklist() throws {
        let database = try makeDatabase()
        let created = try database.createTodo(
            listID: TodoSeed.todayListID,
            title: "Water the plants"
        )
        XCTAssertEqual(created.checklist, TodoChecklist.empty)
    }

    // MARK: - Writes

    func testAppendingAddsOneItemToTheEnd() throws {
        let database = try makeDatabase()
        let written = try database.appendChecklistItem(
            title: "Collect the new one",
            todoID: TodoSeed.renewPassportID
        )
        let items = TodoChecklist.items(from: written.checklist)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.last, TodoChecklistItem(title: "Collect the new one"))
    }

    func testAppendingToAnEmptyChecklistProducesAOneItemArray() throws {
        let database = try makeDatabase()
        let written = try database.appendChecklistItem(
            title: "Ring the surgery",
            todoID: TodoSeed.bookDentistID
        )
        XCTAssertEqual(
            TodoChecklist.items(from: written.checklist),
            [TodoChecklistItem(title: "Ring the surgery")]
        )
    }

    func testATitleThatLooksLikeJSONIsOneTitle() throws {
        // The title is bound, not interpolated. A sub-task called
        // `", "isDone": true}` has to arrive as that text and change nothing
        // else about the document.
        let database = try makeDatabase()
        let awkward = #"", "isDone": true}"#
        let written = try database.appendChecklistItem(
            title: awkward,
            todoID: TodoSeed.bookDentistID
        )
        XCTAssertEqual(
            TodoChecklist.items(from: written.checklist),
            [TodoChecklistItem(title: awkward)]
        )
    }

    func testTickingAnItemSetsAJSONBooleanRatherThanANumber() throws {
        let database = try makeDatabase()
        let written = try database.setChecklistItem(
            at: 1,
            isDone: true,
            todoID: TodoSeed.renewPassportID
        )
        // Decoding through Codable is the check that matters: `Bool` only
        // decodes from a JSON boolean, so a stored 1 would fail here.
        let items = TodoChecklist.items(from: written.checklist)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[1].isDone)
        XCTAssertTrue(written.checklist.contains("true"))
        XCTAssertFalse(written.checklist.contains(#""isDone":1"#))
    }

    func testUntickingPutsAnItemBack() throws {
        let database = try makeDatabase()
        let written = try database.setChecklistItem(
            at: 0,
            isDone: false,
            todoID: TodoSeed.renewPassportID
        )
        XCTAssertFalse(TodoChecklist.items(from: written.checklist)[0].isDone)
    }

    func testAnIndexPastTheEndChangesNothing() throws {
        let database = try makeDatabase()
        let before = try XCTUnwrap(try database.todo(id: TodoSeed.renewPassportID))
        let written = try database.setChecklistItem(
            at: 99,
            isDone: true,
            todoID: TodoSeed.renewPassportID
        )
        XCTAssertEqual(written.checklist, before.checklist)
    }

    func testRemovingDeletesOneItemAndKeepsTheOrderOfTheRest() throws {
        let database = try makeDatabase()
        let written = try database.removeChecklistItem(
            at: 1,
            todoID: TodoSeed.renewPassportID
        )
        XCTAssertEqual(
            TodoChecklist.items(from: written.checklist).map(\.title),
            ["Find the old passport", "Take a photograph"]
        )
    }

    func testChecklistWritesLeaveTheRestOfTheToDoAlone() throws {
        let database = try makeDatabase()
        let before = try XCTUnwrap(try database.todo(id: TodoSeed.renewPassportID))
        let after = try database.appendChecklistItem(
            title: "Check the expiry date",
            todoID: TodoSeed.renewPassportID
        )
        XCTAssertEqual(after.title, before.title)
        XCTAssertEqual(after.notes, before.notes)
        XCTAssertEqual(after.dueAt, before.dueAt)
        XCTAssertEqual(after.priority, before.priority)
        XCTAssertEqual(after.isCompleted, before.isCompleted)
        XCTAssertEqual(after.position, before.position)
    }

    // MARK: - Reads

    func testSummariesCountItemsWithoutReadingTheArrays() throws {
        let database = try makeDatabase()
        let summaries = try database.checklistSummaries(inList: TodoSeed.todayListID)

        let passport = try XCTUnwrap(summaries[TodoSeed.renewPassportID])
        XCTAssertEqual(passport.itemCount, 3)
        XCTAssertEqual(passport.firstItemTitle, "Find the old passport")

        let dentist = try XCTUnwrap(summaries[TodoSeed.bookDentistID])
        XCTAssertEqual(dentist.itemCount, 0)
        XCTAssertNil(dentist.firstItemTitle)
    }

    func testASummaryFollowsAWrite() throws {
        let database = try makeDatabase()
        try database.appendChecklistItem(
            title: "Sign the form",
            todoID: TodoSeed.bookDentistID
        )
        let summaries = try database.checklistSummaries(inList: TodoSeed.todayListID)
        let dentist = try XCTUnwrap(summaries[TodoSeed.bookDentistID])
        XCTAssertEqual(dentist.itemCount, 1)
        XCTAssertEqual(dentist.firstItemTitle, "Sign the form")
    }

    // MARK: - Conversions

    func testUnreadableJSONReadsAsAnEmptyChecklistRatherThanThrowing() throws {
        XCTAssertEqual(TodoChecklist.items(from: "not json"), [])
        XCTAssertEqual(TodoChecklist.items(from: ""), [])
    }

    func testEncodingAndDecodingRoundTrip() throws {
        let items = [
            TodoChecklistItem(title: "One", isDone: true),
            TodoChecklistItem(title: "Two"),
        ]
        XCTAssertEqual(TodoChecklist.items(from: TodoChecklist.json(items)), items)
    }
}
