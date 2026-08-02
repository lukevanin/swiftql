import Foundation

import SwiftQL

/// The sidebar's state.
///
/// It owns two live queries — the lists, and the per-list counts — and
/// nothing else. Neither is ever refetched: a write anywhere in the app
/// changes a table these queries read, GRDB notices, and the next snapshot
/// arrives on its own.
@available(iOS 17, macOS 14, *)
@Observable
@MainActor
public final class TodoSidebarModel {

    public let lists: XLObservableQuery<TodoList>

    public let counts: XLObservableQuery<TodoListCounts>

    public init(database: TodoDatabase) {
        lists = XLObservableQuery(database.listsRequest)
        counts = XLObservableQuery(database.listCountsRequest)
    }

    /// Counts for one list, keyed for the view. A list with no to-dos never
    /// appears in the aggregate, so it reads as zero.
    public func counts(for listID: TodoUUID) -> TodoListCounts {
        counts.rows.first { $0.listID == listID }
            ?? TodoListCounts(listID: listID, openCount: 0, totalCount: 0)
    }

    public func stop() {
        lists.stop()
        counts.stop()
    }
}

/// One list's to-dos, under the filter, sort, and search the view is showing.
///
/// The query is not a filter applied in Swift after fetching. Changing the
/// filter, the sort, or the search text replaces the observation with a new
/// one bound to new values, so SQLite does the work and the view only ever
/// renders what it is given.
@available(iOS 17, macOS 14, *)
@Observable
@MainActor
public final class TodoListModel {

    public private(set) var query: TodoQuery

    /// Replaced whenever ``query`` changes. A live query captures its
    /// bindings once, so new values mean a new observation — the same rule
    /// `stream(bindings:)` follows.
    public private(set) var todos: XLObservableQuery<Todo>

    public private(set) var tagsByTodo: [TodoUUID: [Tag]] = [:]

    private let database: TodoDatabase

    public init(database: TodoDatabase, query: TodoQuery) throws {
        self.database = database
        self.query = query
        todos = try Self.observe(query, in: database)
        reloadTags()
    }

    public var filter: TodoFilter {
        get { query.filter }
        set { rebind { $0.filter = newValue } }
    }

    public var sort: TodoSort {
        get { query.sort }
        set { rebind { $0.sort = newValue } }
    }

    public var searchText: String {
        get { query.searchText }
        set { rebind { $0.searchText = newValue } }
    }

    public var listID: TodoUUID {
        get { query.listID }
        set { rebind { $0.listID = newValue } }
    }

    public func stop() {
        todos.stop()
    }

    /// Tag labels for the rows on screen, fetched in one query for the whole
    /// list rather than one per row.
    public func reloadTags() {
        tagsByTodo = (try? database.tagsByTodo(inList: query.listID)) ?? [:]
    }

    public func tags(for todo: Todo) -> [Tag] {
        tagsByTodo[todo.id] ?? []
    }

    private func rebind(_ change: (inout TodoQuery) -> Void) {
        var updated = query
        change(&updated)
        // Explicit Bool annotations: TodoUUID conforms to XLComparable, so a
        // bare == or != would resolve to SwiftQL's SQL-expression operator
        // rather than Swift's.
        let unchanged: Bool = updated == query
        guard !unchanged else {
            return
        }
        let sameList: Bool = updated.listID == query.listID

        // Build the replacement before touching anything. If it fails, the
        // model keeps observing what it was already observing, and `query`
        // still describes it — a half-applied rebind would leave a live view
        // bound to a stopped observation.
        guard let replacement = try? Self.observe(updated, in: database) else {
            return
        }
        let previous = todos
        query = updated
        todos = replacement
        previous.stop()
        if !sameList {
            reloadTags()
        }
    }

    private static func observe(
        _ query: TodoQuery,
        in database: TodoDatabase
    ) throws -> XLObservableQuery<Todo> {
        let request = database.filteredTodosRequest
        return XLObservableQuery(
            request,
            bindings: try TodoFilteredRead.bindings(
                for: query,
                layout: request.parameterLayout
            )
        )
    }
}

/// One to-do, observed by identifier.
///
/// The detail view reads this rather than the row the list handed it, so
/// completing a to-do updates the detail, the list, and the sidebar counts
/// from three independent observations of the same commit — with no reload
/// call anywhere.
@available(iOS 17, macOS 14, *)
@Observable
@MainActor
public final class TodoDetailModel {

    public let todo: XLObservableQueryRow<Todo>

    public private(set) var tags: [Tag] = []

    private let database: TodoDatabase
    private let todoID: TodoUUID

    public init(database: TodoDatabase, todoID: TodoUUID) throws {
        self.database = database
        self.todoID = todoID
        let request = database.todoByIDRequest
        todo = XLObservableQueryRow(
            request,
            bindings: try TodoDatabase.todoIDBindings(
                todoID,
                layout: request.parameterLayout
            )
        )
        reloadTags()
    }

    public func reloadTags() {
        tags = (try? database.tags(forTodo: todoID)) ?? []
    }

    public func stop() {
        todo.stop()
    }
}
