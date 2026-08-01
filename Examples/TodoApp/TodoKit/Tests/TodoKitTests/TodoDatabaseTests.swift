import XCTest

import SwiftQL
import TodoKit

/// Covers the database lifecycle and the value round trip. The query layer
/// gets its own suite.
final class TodoDatabaseTests: XCTestCase {

    /// A date with a fractional second and a non-UTC-friendly offset, so a
    /// sloppy formatter shows up as a failure rather than passing by luck.
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000.25)

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoKitTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func databaseURL() -> URL {
        directory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent(TodoDatabase.fileName)
    }

    // MARK: - Creation

    func testAFirstOpenCreatesTheDirectoryAndSeedsTheDatabase() throws {
        let url = databaseURL()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let database = try TodoDatabase(url: url, referenceDate: referenceDate)

        XCTAssertTrue(database.didSeed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try lists(in: database).count, 3)
        XCTAssertEqual(try todos(in: database).count, 6)
        XCTAssertEqual(try tags(in: database).count, 3)
        XCTAssertEqual(try todoTags(in: database).count, 4)
    }

    func testASecondOpenReusesTheFileWithoutReseeding() throws {
        let url = databaseURL()
        let first = try TodoDatabase(url: url, referenceDate: referenceDate)
        try deleteFirstTodo(in: first)
        XCTAssertEqual(try todos(in: first).count, 5)

        let second = try TodoDatabase(url: url, referenceDate: referenceDate)

        XCTAssertFalse(second.didSeed)
        XCTAssertEqual(try todos(in: second).count, 5)
    }

    // MARK: - Value round trip

    func testIdentifiersAndDatesSurviveAWriteAndARead() throws {
        let database = try TodoDatabase(url: databaseURL(), referenceDate: referenceDate)
        let expected = TodoSeed(referenceDate: referenceDate)

        let readBack = try todos(in: database)
            .sorted { $0.id.wrappedValue.uuidString < $1.id.wrappedValue.uuidString }
        let written = expected.todos
            .sorted { $0.id.wrappedValue.uuidString < $1.id.wrappedValue.uuidString }

        XCTAssertEqual(readBack, written)
    }

    func testADueDateKeepsItsFractionalSecond() throws {
        let database = try TodoDatabase(url: databaseURL(), referenceDate: referenceDate)

        let passport = try todo(TodoSeed.renewPassportID, in: database)

        let expected = referenceDate.addingTimeInterval(-24 * 60 * 60)
        XCTAssertEqual(
            try XCTUnwrap(passport.dueAt).wrappedValue.timeIntervalSince1970,
            expected.timeIntervalSince1970,
            accuracy: 0.0005
        )
    }

    func testAToDoWithoutADueDateReadsBackAsNil() throws {
        let database = try TodoDatabase(url: databaseURL(), referenceDate: referenceDate)

        let knives = try todo(TodoSeed.sharpenKnivesID, in: database)

        XCTAssertNil(knives.dueAt)
    }

    func testPrioritiesReadBackAsTheirEnumCases() throws {
        let database = try TodoDatabase(url: databaseURL(), referenceDate: referenceDate)

        XCTAssertEqual(try todo(TodoSeed.renewPassportID, in: database).priority, .high)
        XCTAssertEqual(try todo(TodoSeed.bookDentistID, in: database).priority, .normal)
        XCTAssertEqual(try todo(TodoSeed.sharpenKnivesID, in: database).priority, .low)
    }

    // MARK: - Seed coverage

    func testTheSeedCoversEveryFilterTheAppOffers() throws {
        let database = try TodoDatabase(url: databaseURL(), referenceDate: referenceDate)
        let rows = try todos(in: database)

        XCTAssertTrue(rows.contains { !$0.isCompleted }, "expected an active to-do")
        XCTAssertTrue(rows.contains { $0.isCompleted }, "expected a completed to-do")
        XCTAssertTrue(
            rows.contains { todo in
                guard let dueAt = todo.dueAt else { return false }
                return !todo.isCompleted && dueAt.wrappedValue < referenceDate
            },
            "expected an overdue to-do"
        )
        XCTAssertTrue(rows.contains { $0.dueAt == nil }, "expected a to-do with no due date")

        let tagged = Set(try todoTags(in: database).map(\.todoID))
        XCTAssertFalse(tagged.isEmpty, "expected a tagged to-do")
        XCTAssertTrue(
            rows.contains { !tagged.contains($0.id) },
            "expected an untagged to-do"
        )
    }

    // MARK: - Reset

    #if DEBUG
    func testResetRestoresTheSeededState() throws {
        let database = try TodoDatabase(url: databaseURL(), referenceDate: referenceDate)
        try deleteFirstTodo(in: database)
        XCTAssertEqual(try todos(in: database).count, 5)

        try database.reset(referenceDate: referenceDate)

        XCTAssertEqual(try todos(in: database).count, 6)
        XCTAssertEqual(try lists(in: database).count, 3)
        XCTAssertEqual(try tags(in: database).count, 3)
        XCTAssertEqual(try todoTags(in: database).count, 4)
    }
    #endif

    // MARK: - Helpers

    private func lists(in database: TodoDatabase) throws -> [TodoList] {
        try database.lists()
    }

    private func todos(in database: TodoDatabase) throws -> [Todo] {
        try database.todos()
    }

    private func tags(in database: TodoDatabase) throws -> [Tag] {
        try database.tags()
    }

    private func todoTags(in database: TodoDatabase) throws -> [TodoTag] {
        try database.todoTags()
    }

    private func todo(_ id: TodoUUID, in database: TodoDatabase) throws -> Todo {
        try XCTUnwrap(try todos(in: database).first { $0.id == id })
    }

    private func deleteFirstTodo(in database: TodoDatabase) throws {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        try database.database
            .makeRequest(with: delete(table).where(table.id == TodoSeed.finishNovelID))
            .execute()
    }
}
