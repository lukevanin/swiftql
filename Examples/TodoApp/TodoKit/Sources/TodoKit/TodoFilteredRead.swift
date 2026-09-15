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
/// Public only so the validation-manifest generator, which is a separate
/// target, can put this exact statement through the validator rather than a
/// hand-copied twin of it. Call ``TodoDatabase/todos(matching:)`` instead.
public enum TodoFilteredRead {

    /// The statement's named bindings.
    ///
    /// `@SQLBindings` gives each property a typed reference, which
    /// ``statement`` reads, and builds the packet that binds the values under
    /// the same names. A misspelled name or a forgotten value does not
    /// compile. Until v1.9 the packet looked each slot up by a string, and a
    /// typo was a runtime error (#663).
    @SQLBindings
    struct Bindings {
        var listID: TodoUUID
        var includesCompleted: Bool
        var includesActive: Bool
        var overdueOnly: Bool
        var referenceDate: TodoDate
        var searchPattern: String
        var sortOrder: Int
    }

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
                todo.listID == Bindings.listID
                && (todo.isCompleted == Bindings.includesCompleted
                    || todo.isCompleted != Bindings.includesActive)
                && (Bindings.overdueOnly == false
                    || (todo.dueAt < Bindings.referenceDate
                        && todo.isCompleted == false))
                && (todo.title.regexp(Bindings.searchPattern)
                    || todo.notes.regexp(Bindings.searchPattern))
            )
            OrderBy(
                (Bindings.sortOrder == TodoSort.dueDate.rawValue).iif(
                    then: todo.dueAt ?? TodoDate.distantFuture,
                    else: TodoDate.distantFuture
                ).ascending(),
                (Bindings.sortOrder == TodoSort.priority.rawValue).iif(
                    then: todo.priority,
                    else: TodoPriority.low
                ).descending(),
                (Bindings.sortOrder == TodoSort.manual.rawValue).iif(
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
        return try Bindings(
            listID: query.listID,
            includesCompleted: flags.includesCompleted,
            includesActive: flags.includesActive,
            overdueOnly: flags.overdueOnly,
            referenceDate: query.referenceDate,
            searchPattern: query.searchPattern,
            sortOrder: query.sort.rawValue
        ).bindings(in: layout)
    }
}
