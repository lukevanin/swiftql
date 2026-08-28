import Foundation

import SwiftQL

/// Conditions the database cannot express as a constraint, so the query layer
/// raises them instead.
public enum TodoStoreError: Error, Equatable, LocalizedError {

    case todoNotFound(TodoUUID)
    case listNotFound(TodoUUID)
    case unknownParameter(statement: String, name: String)

    public var errorDescription: String? {
        switch self {
        case .todoNotFound(let id):
            return "No to-do with identifier \(id.wrappedValue)."
        case .listNotFound(let id):
            return "No list with identifier \(id.wrappedValue)."
        case .unknownParameter(let statement, let name):
            return "The \(statement) statement has no parameter named \(name)."
        }
    }
}

/// The demo's data access layer.
///
/// Everything the app reads or writes goes through here, and nothing here
/// contains a SQL string.
extension TodoDatabase {

    // MARK: - Reads

    public func lists() throws -> [TodoList] {
        try database.todoLists()
    }

    public func list(id: TodoUUID) throws -> TodoList? {
        try database.todoList(id: id)
    }

    public func todos() throws -> [Todo] {
        try database.todos()
    }

    public func todo(id: TodoUUID) throws -> Todo? {
        try database.todo(id: id)
    }

    /// The to-dos matching one query, already filtered, searched, and sorted
    /// by SQLite.
    ///
    /// One request serves every combination — see ``TodoFilteredRead`` for
    /// how, and for why this one read is not a declared query.
    public func todos(matching query: TodoQuery) throws -> [Todo] {
        let request = filteredTodosRequest
        return try request.fetchAll(
            bindings: TodoFilteredRead.bindings(
                for: query,
                layout: request.parameterLayout
            )
        )
    }

    public func tags() throws -> [Tag] {
        try database.tags()
    }

    public func todoTags() throws -> [TodoTag] {
        try database.todoTags()
    }

    /// The tags on one to-do.
    public func tags(forTodo id: TodoUUID) throws -> [Tag] {
        try database.tagsForTodo(todoID: id).map { pair in
            Tag(id: pair.tagID, name: pair.tagName)
        }
    }

    /// The tags on every to-do in one list, keyed by to-do.
    ///
    /// One query for the whole list rather than one per row.
    public func tagsByTodo(inList listID: TodoUUID) throws -> [TodoUUID: [Tag]] {
        try database.tagsForList(listID: listID).reduce(into: [:]) { result, pair in
            result[pair.todoID, default: []]
                .append(Tag(id: pair.tagID, name: pair.tagName))
        }
    }

    /// Open and total counts for every list, including the empty ones the
    /// aggregate has nothing to group for.
    public func listCounts() throws -> [TodoUUID: TodoListCounts] {
        var counts = try database.listCounts().reduce(
            into: [TodoUUID: TodoListCounts]()
        ) { result, row in
            result[row.listID] = row
        }
        for list in try lists() where counts[list.id] == nil {
            counts[list.id] = TodoListCounts(
                listID: list.id,
                openCount: 0,
                totalCount: 0
            )
        }
        return counts
    }

    // MARK: - Writes

    /// Adds a to-do to the end of its list.
    ///
    /// Every write here returns the row the database actually holds, through
    /// `RETURNING`, so a caller never has to fetch again to find out what it
    /// wrote.
    ///
    /// Writes are not `@SQLQuery` declarations. Declared queries are
    /// `SELECT`-only in v1.5 — a write cardinality is listed as future work
    /// in the "Declared queries" guide — so they use SwiftQL's functional
    /// statement syntax instead. Still typed, still no SQL strings.
    @discardableResult
    public func createTodo(
        listID: TodoUUID,
        title: String,
        notes: String = "",
        dueAt: TodoDate? = nil,
        priority: TodoPriority = .normal,
        now: TodoDate = TodoDate(Date())
    ) throws -> Todo {
        try database.withTransaction { scope in
            guard try Self.listExists(listID, in: scope) else {
                throw TodoStoreError.listNotFound(listID)
            }
            let todo = Todo(
                id: TodoUUID(),
                listID: listID,
                title: title,
                notes: notes,
                dueAt: dueAt,
                priority: priority,
                isCompleted: false,
                position: try Self.nextPosition(inList: listID, in: scope),
                createdAt: now,
                checklist: TodoChecklist.empty
            )
            let schema = XLSchema()
            let table = schema.table(Todo.self)
            // The statement goes in a local rather than inline in the
            // `makeRequest` call. Swift 6.0 segfaults on the inline form --
            // see COMPATIBILITY.md, "Swift 6.0 crashes on a statement built
            // inline in a fetched request". Every fetched request in this
            // file is written this way for that reason.
            let statement = insert(table)
                .values(Todo.MetaInsert(todo))
                .returning(table)
            let rows = try scope.makeRequest(with: statement).fetchAll()
            guard let written = rows.first else {
                throw TodoStoreError.todoNotFound(todo.id)
            }
            return written
        }
    }

    /// Edits a to-do's fields.
    ///
    /// Every value arrives in a binding packet rather than as an inline
    /// literal, so one rendered statement serves every edit and nothing a
    /// user typed reaches the SQL text. The due date is the reason the
    /// packet is explicit: `nil` there is a present SQL `NULL`, which is not
    /// the same as omitting the binding, and only a nullable slot accepts it.
    @discardableResult
    public func updateTodo(
        id: TodoUUID,
        title: String,
        notes: String,
        dueAt: TodoDate?,
        priority: TodoPriority
    ) throws -> Todo {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        let idParameter = XLNamedBindingReference<TodoUUID>(name: "id")
        let titleParameter = XLNamedBindingReference<String>(name: "title")
        let notesParameter = XLNamedBindingReference<String>(name: "notes")
        let dueAtParameter = XLNamedBindingReference<TodoDate?>(name: "dueAt")
        let priorityParameter = XLNamedBindingReference<TodoPriority>(name: "priority")

        let statement = update(table)
            .set { row in
                row.title = titleParameter
                row.notes = notesParameter
                row.dueAt = dueAtParameter
                row.priority = priorityParameter
            }
            .where(table.id == idParameter)
            .returning(schema.table(Todo.self))
        let request = database.makeRequest(with: statement)
        let layout = request.parameterLayout
        let bindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try Self.binding(layout, "id", id.sqlValue),
                try Self.binding(layout, "title", .text(title)),
                try Self.binding(layout, "notes", .text(notes)),
                try Self.binding(layout, "dueAt", dueAt?.sqlValue ?? .null),
                try Self.binding(
                    layout,
                    "priority",
                    .integer(Int64(priority.rawValue))
                ),
            ]
        ).validatingComplete()

        return try written(request.fetchAll(bindings: bindings), or: id)
    }

    private static func binding(
        _ layout: XLParameterLayout,
        _ name: String,
        _ value: XLSQLiteValue
    ) throws -> XLInvocationBinding<XLSQLiteValue> {
        guard let slot = layout.slot(for: .named(name)) else {
            throw TodoStoreError.unknownParameter(
                statement: "update to-do",
                name: name
            )
        }
        return try XLInvocationBinding(slot: slot, value: value)
    }

    @discardableResult
    public func setCompleted(_ isCompleted: Bool, todoID id: TodoUUID) throws -> Todo {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        let statement = update(table)
            .set { row in row.isCompleted = isCompleted }
            .where(table.id == id)
            .returning(schema.table(Todo.self))
        return try written(
            database.makeRequest(with: statement).fetchAll(),
            or: id
        )
    }

    /// Flips a to-do's completion and returns the row as it now stands.
    @discardableResult
    public func toggleCompleted(todoID id: TodoUUID) throws -> Todo {
        try database.withTransaction { scope in
            guard let current = try Self.find(id, in: scope) else {
                throw TodoStoreError.todoNotFound(id)
            }
            let schema = XLSchema()
            let table = schema.into(Todo.self)
            let statement = update(table)
                .set { row in row.isCompleted = !current.isCompleted }
                .where(table.id == id)
                .returning(schema.table(Todo.self))
            let rows = try scope.makeRequest(with: statement).fetchAll()
            guard let written = rows.first else {
                throw TodoStoreError.todoNotFound(id)
            }
            return written
        }
    }

    // MARK: - Checklist

    /// Appends a sub-task, returning the to-do as it now stands.
    ///
    /// SQLite does the work. `json_insert` with the append path adds the item
    /// to the stored array, so nothing loads the checklist, changes it in
    /// Swift, and writes it back — which is what makes a JSON column worth
    /// having rather than a serialised blob.
    ///
    /// The title arrives in a binding packet, so a sub-task called
    /// `", "isDone": true}` is one title and not a rewritten document.
    ///
    /// `json_insert` returns `NULL` for a `NULL` document, so its result is
    /// optional while the column is not. `coalesce` supplies the row's
    /// current checklist for that case, which cannot arise here — the column
    /// is `NOT NULL` — but has to be spelled out for the types to meet.
    @discardableResult
    public func appendChecklistItem(
        title: String,
        todoID id: TodoUUID
    ) throws -> Todo {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        let idParameter = XLNamedBindingReference<TodoUUID>(name: "id")
        let titleParameter = XLNamedBindingReference<String>(name: "title")
        let statement = update(table)
            .set { row in
                row.checklist = table.checklist
                    .jsonInserting(
                        (
                            TodoChecklist.end,
                            jsonObject(
                                ("title", titleParameter),
                                ("isDone", "false".minifiedJSON())
                            )
                        )
                    )
                    .coalesce(table.checklist)
            }
            .where(table.id == idParameter)
            .returning(schema.table(Todo.self))

        let request = database.makeRequest(with: statement)
        let layout = request.parameterLayout
        let bindings = try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try Self.binding(layout, "id", id.sqlValue),
                try Self.binding(layout, "title", .text(title)),
            ]
        ).validatingComplete()
        return try written(request.fetchAll(bindings: bindings), or: id)
    }

    /// Ticks or unticks one sub-task, returning the to-do as it now stands.
    ///
    /// An index past the end changes nothing: `json_set` leaves a path it
    /// cannot reach alone, so the statement still returns the row unchanged
    /// rather than failing.
    @discardableResult
    public func setChecklistItem(
        at index: Int,
        isDone: Bool,
        todoID id: TodoUUID
    ) throws -> Todo {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        // A JSON boolean, not SQLite's 0 and 1. `json_object('isDone', 0)`
        // stores the number zero, which is not what a JSON reader expects to
        // find behind a flag.
        let flag = (isDone ? "true" : "false").minifiedJSON()
        let statement = update(table)
            .set { row in
                row.checklist = table.checklist
                    .jsonSetting((TodoChecklist.isDone(at: index), flag))
                    .coalesce(table.checklist)
            }
            .where(table.id == id)
            .returning(schema.table(Todo.self))
        return try written(
            database.makeRequest(with: statement).fetchAll(),
            or: id
        )
    }

    /// Deletes one sub-task, returning the to-do as it now stands.
    @discardableResult
    public func removeChecklistItem(
        at index: Int,
        todoID id: TodoUUID
    ) throws -> Todo {
        let schema = XLSchema()
        let table = schema.into(Todo.self)
        let statement = update(table)
            .set { row in
                row.checklist = table.checklist
                    .jsonRemoving(at: TodoChecklist.item(at: index))
                    .coalesce(table.checklist)
            }
            .where(table.id == id)
            .returning(schema.table(Todo.self))
        return try written(
            database.makeRequest(with: statement).fetchAll(),
            or: id
        )
    }

    /// One row per to-do in a list, with what SQLite could tell us about its
    /// checklist without reading the array into Swift.
    public func checklistSummaries(
        inList listID: TodoUUID
    ) throws -> [TodoUUID: TodoChecklistSummary] {
        var summaries: [TodoUUID: TodoChecklistSummary] = [:]
        for summary in try database.checklistSummaries(listID: listID) {
            summaries[summary.todoID] = summary
        }
        return summaries
    }

    /// Deletes a to-do and its tag links, returning the row that went.
    @discardableResult
    public func deleteTodo(id: TodoUUID) throws -> Todo {
        try database.withTransaction { scope in
            let schema = XLSchema()
            let links = schema.into(TodoTag.self)
            try scope.makeRequest(
                with: delete(links).where(links.todoID == id)
            ).execute()

            let table = schema.into(Todo.self)
            let statement = delete(table)
                .where(table.id == id)
                .returning(schema.table(Todo.self))
            let rows = try scope.makeRequest(with: statement).fetchAll()
            guard let removed = rows.first else {
                throw TodoStoreError.todoNotFound(id)
            }
            return removed
        }
    }

    // MARK: - Transaction

    /// Moves a to-do to another list, closing the gap it leaves behind and
    /// appending it to its new one.
    ///
    /// Two writes that only make sense together: renumber every to-do that
    /// sat after this one in the old list, then move the row and give it the
    /// next free position in the new list. The destination needs no
    /// renumbering because the to-do goes on the end.
    ///
    /// `withTransaction` commits when the closure returns and rolls back
    /// everything if it throws, so a failure part-way leaves both lists
    /// exactly as they were.
    @discardableResult
    public func move(
        todoID: TodoUUID,
        toList destinationID: TodoUUID,
        beforeCommit: ((GRDBDatabase) throws -> Void)? = nil
    ) throws -> Todo {
        try database.withTransaction { scope in
            guard let todo = try Self.find(todoID, in: scope) else {
                throw TodoStoreError.todoNotFound(todoID)
            }
            guard try Self.listExists(destinationID, in: scope) else {
                throw TodoStoreError.listNotFound(destinationID)
            }

            let schema = XLSchema()
            let sourceRows = schema.into(Todo.self)
            try scope.makeRequest(
                with: update(sourceRows)
                    .set { row in row.position = sourceRows.position - 1 }
                    .where(
                        sourceRows.listID == todo.listID
                        && sourceRows.position > todo.position
                    )
            ).execute()

            let destinationPosition = try Self.nextPosition(
                inList: destinationID,
                in: scope
            )
            let moved = schema.into(Todo.self)
            let statement = update(moved)
                .set { row in
                    row.listID = destinationID
                    row.position = destinationPosition
                }
                .where(moved.id == todoID)
                .returning(schema.table(Todo.self))
            let rows = try scope.makeRequest(with: statement).fetchAll()
            guard let written = rows.first else {
                throw TodoStoreError.todoNotFound(todoID)
            }

            // A seam for the rollback test, and nothing else. Production
            // callers pass nil and this does not run.
            try beforeCommit?(scope)

            return written
        }
    }

    // MARK: - Helpers

    private func written(_ rows: [Todo], or id: TodoUUID) throws -> Todo {
        guard let row = rows.first else {
            throw TodoStoreError.todoNotFound(id)
        }
        return row
    }

    /// A to-do, read inside a transaction.
    ///
    /// A plain request rather than the declared `todo(id:)` read: a generated
    /// executor opens a transaction of its own, and SwiftQL rejects nesting
    /// one inside another.
    fileprivate static func find(
        _ id: TodoUUID,
        in scope: GRDBDatabase
    ) throws -> Todo? {
        let statement = sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
            Where(todo.id == id)
        }
        return try scope.makeRequest(with: statement).fetchOne()
    }

    fileprivate static func listExists(
        _ id: TodoUUID,
        in scope: GRDBDatabase
    ) throws -> Bool {
        let statement = sql { schema in
            let list = schema.table(TodoList.self)
            Select(list.id)
            From(list)
            Where(list.id == id)
        }
        return try scope.makeRequest(with: statement).fetchOne() != nil
    }

    /// One past the last position in a list, or zero when it is empty.
    fileprivate static func nextPosition(
        inList listID: TodoUUID,
        in scope: GRDBDatabase
    ) throws -> Int {
        let statement = sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
            Where(todo.listID == listID)
            OrderBy(todo.position.descending())
            Limit(1)
        }
        let last = try scope.makeRequest(with: statement).fetchOne()
        return (last?.position ?? -1) + 1
    }
}
