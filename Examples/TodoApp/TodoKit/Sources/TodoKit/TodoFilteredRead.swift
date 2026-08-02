import Foundation

import SwiftQL

/// The list view's read: one statement covering every filter, sort, and
/// search the app offers.
///
/// This is the only read in the demo that is not an `@SQLQuery` declaration,
/// and the reason is `LIKE`. A declared query's frozen-literal guard rejects
/// a parameter passed as an argument to a call, and `like(_:)` is a method —
/// `todo.title.like(searchPattern)` fails to compile with
///
///     'searchPattern' is passed as an argument to a function call in the
///     '@SQLQueries' body.
///
/// SwiftQL offers no operator spelling of `LIKE` that would satisfy the
/// guard. Splitting search into a second declared query would mean two
/// copies of the same filter and sort logic drifting apart, so the whole read
/// uses named bindings instead. Recorded on #469.
///
/// Everything else about it is the point: the filter is three booleans the
/// `Where` clause reads rather than a mode the query branches on, the search
/// is always applied with `%` standing in for an empty box, and the sort
/// selects which ordering keys have any effect. One statement, rendered once,
/// serves all of it.
public enum TodoFilteredRead {

    static let listID = XLNamedBindingReference<TodoUUID>(name: "listID")
    static let includesCompleted = XLNamedBindingReference<Bool>(name: "includesCompleted")
    static let includesActive = XLNamedBindingReference<Bool>(name: "includesActive")
    static let overdueOnly = XLNamedBindingReference<Bool>(name: "overdueOnly")
    static let referenceDate = XLNamedBindingReference<TodoDate>(name: "referenceDate")
    static let searchPattern = XLNamedBindingReference<String>(name: "searchPattern")
    static let sortOrder = XLNamedBindingReference<Int>(name: "sortOrder")

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
                && (todo.title.like(searchPattern)
                    || todo.notes.like(searchPattern))
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
