import Foundation

import SwiftQL

/// The statement behind the list view's live query.
///
/// Mirrors `Query.filteredTodos(...)` in `TodoReads.swift`, the declared form
/// of the same read, which ``TodoDatabase/todos(matching:)`` calls. That
/// declaration explains the filter, search, and sort.
///
/// A live query observes an `XLRequest`, and a declared query does not give
/// you one, so the observed read needs a statement value as well. This is the
/// same duplication `TodoLiveReads.swift` describes for the other observed
/// reads, and a change to one has to be made in both. Recorded on #469.
///
/// Until v1.9 this was the only form of the read: the frozen-literal guard
/// rejected a parameter passed to `regexp(_:)`, so the read could not be a
/// declaration at all (#661).
///
/// Public only so the hand-written manifest fixture in the test target can
/// compare this exact statement with the manifest entry generated from the
/// declaration. Call ``TodoDatabase/todos(matching:)`` instead.
public enum TodoFilteredRead {

    static let listID = XLNamedBindingReference<TodoUUID>(name: "listID")
    static let includesCompleted = XLNamedBindingReference<Bool>(name: "includesCompleted")
    static let includesActive = XLNamedBindingReference<Bool>(name: "includesActive")
    static let overdueOnly = XLNamedBindingReference<Bool>(name: "overdueOnly")
    static let referenceDate = XLNamedBindingReference<TodoDate>(name: "referenceDate")
    static let searchPattern = XLNamedBindingReference<String>(name: "searchPattern")
    static let sortOrder = XLNamedBindingReference<Int>(name: "sortOrder")

    /// Search is `REGEXP`, which v1.7 made usable without the application
    /// registering anything: SwiftQL supplies the `regexp` implementation and
    /// registers it on the connection that runs the statement. The pattern
    /// arrives as a bound parameter, so one rendered statement serves every
    /// search, and SwiftQL compiles that pattern once per execution rather
    /// than once for each row it tests.
    ///
    /// The highest `OrderBy` term wins. A term whose condition is false
    /// collapses to a constant, which orders every row equally and so
    /// contributes nothing — the next term decides. `title` last makes the
    /// order total, so the result is stable between runs.
    ///
    /// A missing due date becomes the distant future rather than staying
    /// `NULL`, because SQLite sorts `NULL` first ascending and a to-do with
    /// no deadline belongs at the end, not the top.
    public static var statement: any XLQueryStatement<Todo> {
        sql { schema in
            let todo = schema.table(Todo.self)
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
        }
    }

    /// Builds the packet for one call. Values live here; the request holds
    /// only the rendered SQL and the shape of its parameters.
    static func bindings(
        for query: TodoQuery,
        layout: XLParameterLayout
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        let flags = query.filter.flags
        return try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try binding(layout, "listID", query.listID.sqlValue),
                try binding(layout, "includesCompleted", .boolean(flags.includesCompleted)),
                try binding(layout, "includesActive", .boolean(flags.includesActive)),
                try binding(layout, "overdueOnly", .boolean(flags.overdueOnly)),
                try binding(layout, "referenceDate", query.referenceDate.sqlValue),
                try binding(layout, "searchPattern", .text(query.searchPattern)),
                try binding(layout, "sortOrder", .integer(Int64(query.sort.rawValue))),
            ]
        ).validatingComplete()
    }

    private static func binding(
        _ layout: XLParameterLayout,
        _ name: String,
        _ value: XLSQLiteValue
    ) throws -> XLInvocationBinding<XLSQLiteValue> {
        guard let slot = layout.slot(for: .named(name)) else {
            throw TodoFilteredReadError.unknownParameter(name)
        }
        return try XLInvocationBinding(slot: slot, value: value)
    }
}

enum TodoFilteredReadError: Error, LocalizedError {

    case unknownParameter(String)

    var errorDescription: String? {
        switch self {
        case .unknownParameter(let name):
            return "The filtered-to-do query has no parameter named \(name)."
        }
    }
}

private extension XLSQLiteValue {

    static func boolean(_ value: Bool) -> XLSQLiteValue {
        .integer(value ? 1 : 0)
    }
}
