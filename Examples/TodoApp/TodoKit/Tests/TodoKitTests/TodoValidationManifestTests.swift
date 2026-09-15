import Foundation
import XCTest

import SwiftQL
import SwiftQLSQLiteBuildValidationDeclaredQueries
import SwiftQLSQLiteBuildValidationManifest
import TodoKit

/// Checks the validation manifest the demo now generates from its
/// declarations.
///
/// Before issue #659 the manifest generator listed every query by hand. That
/// list is kept below as a fixture: each entry it wrote must still be
/// produced, with the same SQL, parameters, and result columns, by the
/// generated `TodoKitDeclaredQueries` registry. The comparison runs one way
/// only, so a query added to TodoKit needs no change here.
final class TodoValidationManifestTests: XCTestCase {

    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
    }

    /// Every query the manifest generator lowers, read from a database built
    /// the way the app builds one.
    private func declaredQueries() throws -> [XLDeclaredQuery] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoManifest-\(UUID().uuidString)", isDirectory: true)
        directories.append(directory)
        let todo = try TodoDatabase(url: directory.appendingPathComponent(TodoDatabase.fileName))
        return try TodoKitDeclaredQueries.queries(for: [todo.database])
    }

    // MARK: - The checked-in manifest

    /// A query added to TodoKit is listed by the generated registry, so the
    /// checked-in manifest goes stale until it is regenerated. This fails
    /// first, before the CI regeneration check does.
    func testTheCheckedInManifestListsEveryDeclaredQuery() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TodoKitBuildValidation/swiftql-build-validation-manifest.json")
        let manifest = try SQLiteBuildValidationManifest.decode(Data(contentsOf: manifestURL))

        XCTAssertEqual(
            manifest.queries.map(\.id),
            try declaredQueries().map(\.id).sorted(),
            "Run Examples/TodoApp/Tools/regenerate-validation-manifest.sh"
        )
    }

    // MARK: - The hand-written fixture

    func testTheEmittedEntriesMatchTheHandWrittenFixture() throws {
        let projection = try SQLiteBuildValidationDeclaredQueryManifest.queryEntries(
            for: try declaredQueries()
        )
        XCTAssertEqual(projection.skippedQueries, [])
        let emitted = projection.entries
        let emittedByID = Dictionary(uniqueKeysWithValues: emitted.map { ($0.id, $0) })
        let encoder = XLiteEncoder(dialect: XLSQLiteDialect())

        for fixture in HandWrittenManifestFixture.queries {
            guard let entry = emittedByID[fixture.declaredID] else {
                XCTFail("no emitted entry for \(fixture.declaredID)")
                continue
            }
            let sql = try encoder.makeValidatedSQL(fixture.statement).sql
            XCTAssertEqual(entry.sql, sql, fixture.declaredID)
            XCTAssertEqual(entry.cardinality, fixture.cardinality.rawValue, fixture.declaredID)
            XCTAssertEqual(
                entry.parameters.map(\.keyName),
                HandWrittenManifestFixture.placeholderNames(in: sql),
                fixture.declaredID
            )
            XCTAssertEqual(
                entry.parameters.map(\.physicalIndex),
                Array(1 ..< entry.parameters.count + 1),
                fixture.declaredID
            )
            XCTAssertEqual(
                entry.parameters.map(\.storageIdentifier),
                entry.parameters.map { fixture.parameters[$0.keyName ?? ""]?.storageIdentifier },
                fixture.declaredID
            )
            XCTAssertEqual(
                entry.results.map(\.declaredAlias),
                fixture.results.map(\.alias),
                fixture.declaredID
            )
            XCTAssertEqual(
                entry.results.map(\.storageIdentifier),
                fixture.results.map(\.storage),
                fixture.declaredID
            )
            XCTAssertEqual(
                entry.results.map(\.nullability),
                fixture.results.map { $0.nullable ? "nullable" : "required" },
                fixture.declaredID
            )
        }
    }
}


/// The query list the demo's manifest generator carried by hand before
/// issue #659, reduced to what the comparison needs.
///
/// It records what the generator claimed about each query. Value type
/// identifiers are not compared: the hand-written list spelled the demo's
/// `TodoUUID` and `TodoDate` as `swift.string`, which the generated manifest
/// no longer invents.
private enum HandWrittenManifestFixture {

    struct Query {
        /// The identifier the generated manifest uses for the same query.
        let declaredID: String
        let statement: any XLEncodable
        let cardinality: XLQueryCardinality
        var parameters: [String: ParameterKind] = [:]
        let results: [Result]
    }

    enum ParameterKind {
        case text
        case integer

        var storageIdentifier: String {
            switch self {
            case .text: return "text"
            case .integer: return "integer"
            }
        }
    }

    struct Result {
        let alias: String
        let storage: String
        var nullable = false
    }

    /// The `:name` placeholders in a rendered statement, in first-encounter
    /// order, skipping quoted text.
    static func placeholderNames(in sql: String) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        let characters = Array(sql)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "'" || character == "\"" {
                index += 1
                while index < characters.count {
                    if characters[index] == character {
                        if index + 1 < characters.count, characters[index + 1] == character {
                            index += 2
                            continue
                        }
                        break
                    }
                    index += 1
                }
                index += 1
                continue
            }
            guard character == ":" else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count,
                  characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
                end += 1
            }
            let name = String(characters[(index + 1)..<end])
            if !name.isEmpty, seen.insert(name).inserted {
                names.append(name)
            }
            index = max(end, index + 1)
        }
        return names
    }

    static let listResults = [
        Result(alias: "id", storage: "text"),
        Result(alias: "name", storage: "text"),
        Result(alias: "position", storage: "integer"),
        Result(alias: "createdAt", storage: "text"),
    ]

    static let todoResults = [
        Result(alias: "id", storage: "text"),
        Result(alias: "listID", storage: "text"),
        Result(alias: "title", storage: "text"),
        Result(alias: "notes", storage: "text"),
        Result(alias: "dueAt", storage: "text", nullable: true),
        Result(alias: "priority", storage: "integer"),
        Result(alias: "isCompleted", storage: "integer"),
        Result(alias: "position", storage: "integer"),
        Result(alias: "createdAt", storage: "text"),
        Result(alias: "checklist", storage: "text"),
    ]

    static let pairResults = [
        Result(alias: "todoID", storage: "text"),
        Result(alias: "tagID", storage: "text"),
        Result(alias: "tagName", storage: "text"),
    ]

    static let queries: [Query] = [
        Query(
            declaredID: "GRDBDatabase.todoLists",
            statement: sql { schema in
                let list = schema.table(TodoList.self)
                Select(list)
                From(list)
                OrderBy(list.position.ascending(), list.name.ascending())
            },
            cardinality: .many,
            results: listResults
        ),
        Query(
            declaredID: "GRDBDatabase.todos",
            statement: sql { schema in
                let todo = schema.table(Todo.self)
                Select(todo)
                From(todo)
                OrderBy(todo.createdAt.ascending(), todo.position.ascending())
            },
            cardinality: .many,
            results: todoResults
        ),
        Query(
            declaredID: "GRDBDatabase.todoList",
            statement: sql { schema in
                let list = schema.table(TodoList.self)
                Select(list)
                From(list)
                Where(list.id == XLNamedBindingReference<TodoUUID>(name: "id"))
            },
            cardinality: .zeroOrOne,
            parameters: ["id": .text],
            results: listResults
        ),
        Query(
            declaredID: "GRDBDatabase.todo",
            statement: sql { schema in
                let todo = schema.table(Todo.self)
                Select(todo)
                From(todo)
                Where(todo.id == XLNamedBindingReference<TodoUUID>(name: "id"))
            },
            cardinality: .zeroOrOne,
            parameters: ["id": .text],
            results: todoResults
        ),
        Query(
            declaredID: "GRDBDatabase.filteredTodos",
            statement: sql { schema in
                let todo = schema.table(Todo.self)
                let listID = XLNamedBindingReference<TodoUUID>(name: "listID")
                let includesCompleted = XLNamedBindingReference<Bool>(name: "includesCompleted")
                let includesActive = XLNamedBindingReference<Bool>(name: "includesActive")
                let overdueOnly = XLNamedBindingReference<Bool>(name: "overdueOnly")
                let referenceDate = XLNamedBindingReference<TodoDate>(name: "referenceDate")
                let searchPattern = XLNamedBindingReference<String>(name: "searchPattern")
                let sortOrder = XLNamedBindingReference<Int>(name: "sortOrder")
                Select(todo)
                From(todo)
                Where(
                    todo.listID == listID
                    && (todo.isCompleted == includesCompleted
                        || todo.isCompleted != includesActive)
                    && (overdueOnly == false
                        || (todo.dueAt < referenceDate
                            && todo.isCompleted == false))
                    && (todo.title.regexp(searchPattern)
                        || todo.notes.regexp(searchPattern))
                )
                OrderBy(
                    (sortOrder == TodoSort.dueDate.rawValue).iif(
                        then: todo.dueAt ?? TodoDate.distantFuture,
                        else: TodoDate.distantFuture
                    ).ascending(),
                    (sortOrder == TodoSort.priority.rawValue).iif(
                        then: todo.priority,
                        else: TodoPriority.low
                    ).descending(),
                    (sortOrder == TodoSort.manual.rawValue).iif(
                        then: todo.position,
                        else: 0
                    ).ascending(),
                    todo.title.ascending()
                )
            },
            cardinality: .many,
            parameters: [
                "listID": .text,
                "includesCompleted": .integer,
                "includesActive": .integer,
                "overdueOnly": .integer,
                "referenceDate": .text,
                "searchPattern": .text,
                "sortOrder": .integer,
            ],
            results: todoResults
        ),
        Query(
            declaredID: "GRDBDatabase.checklistSummaries",
            statement: sql { schema in
                let todo = schema.table(Todo.self)
                Select(TodoChecklistSummary.columns(
                    todoID: todo.id,
                    itemCount: todo.checklist.jsonArrayLength(),
                    firstItemTitle: todo.checklist.jsonValue(
                        at: TodoChecklist.title(at: 0),
                        as: String.self
                    )
                ))
                From(todo)
                Where(todo.listID == XLNamedBindingReference<TodoUUID>(name: "listID"))
                OrderBy(todo.position.ascending())
            },
            cardinality: .many,
            parameters: ["listID": .text],
            results: [
                Result(alias: "todoID", storage: "text"),
                Result(alias: "itemCount", storage: "integer", nullable: true),
                Result(alias: "firstItemTitle", storage: "text", nullable: true),
            ]
        ),
        Query(
            declaredID: "GRDBDatabase.tagsForTodo",
            statement: sql { schema in
                let link = schema.table(TodoTag.self)
                let tag = schema.table(Tag.self)
                Select(TodoTagPair.columns(
                    todoID: link.todoID,
                    tagID: tag.id,
                    tagName: tag.name
                ))
                From(link)
                Join.Inner(tag, on: tag.id == link.tagID)
                Where(link.todoID == XLNamedBindingReference<TodoUUID>(name: "todoID"))
                OrderBy(tag.name.ascending())
            },
            cardinality: .many,
            parameters: ["todoID": .text],
            results: pairResults
        ),
        Query(
            declaredID: "GRDBDatabase.tagsForList",
            statement: sql { schema in
                let todo = schema.table(Todo.self)
                let link = schema.table(TodoTag.self)
                let tag = schema.table(Tag.self)
                Select(TodoTagPair.columns(
                    todoID: link.todoID,
                    tagID: tag.id,
                    tagName: tag.name
                ))
                From(link)
                Join.Inner(todo, on: todo.id == link.todoID)
                Join.Inner(tag, on: tag.id == link.tagID)
                Where(todo.listID == XLNamedBindingReference<TodoUUID>(name: "listID"))
                OrderBy(tag.name.ascending())
            },
            cardinality: .many,
            parameters: ["listID": .text],
            results: pairResults
        ),
        Query(
            declaredID: "GRDBDatabase.listCounts",
            statement: sql { schema in
                let todo = schema.table(Todo.self)
                Select(TodoListCounts.columns(
                    listID: todo.listID,
                    openCount: when(todo.isCompleted == false, then: 1)
                        .else(0)
                        .sumOrNull() ?? 0,
                    totalCount: all().count()
                ))
                From(todo)
                GroupBy(todo.listID)
            },
            cardinality: .many,
            results: [
                Result(alias: "listID", storage: "text"),
                Result(alias: "openCount", storage: "integer"),
                Result(alias: "totalCount", storage: "integer"),
            ]
        ),
        Query(
            declaredID: "GRDBDatabase.tags",
            statement: sql { schema in
                let tag = schema.table(Tag.self)
                Select(tag)
                From(tag)
                OrderBy(tag.name.ascending())
            },
            cardinality: .many,
            results: [
                Result(alias: "id", storage: "text"),
                Result(alias: "name", storage: "text"),
            ]
        ),
        Query(
            declaredID: "GRDBDatabase.todoTags",
            statement: sql { schema in
                let link = schema.table(TodoTag.self)
                Select(link)
                From(link)
            },
            cardinality: .many,
            results: [
                Result(alias: "todoID", storage: "text"),
                Result(alias: "tagID", storage: "text"),
            ]
        ),
    ]
}
