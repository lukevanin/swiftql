import Foundation

import SwiftQL

/// The statements behind the demo's live queries.
///
/// A live query observes an `XLRequest`. A declared query does not give you
/// one — `@SQLQueries` generates an executor that renders, binds, and fetches
/// in a single call, and hands back rows. So the three reads a view observes
/// need statement values as well as declarations, and this is where they
/// live.
///
/// The duplication is real: `TodoReads.swift` declares the same three, and a
/// change to one has to be made in both. It is recorded on #469 as the
/// friction it is, rather than papered over. The manifest generator validates
/// these statements, so at least the observed shape is the checked one.
enum TodoLiveReads {

    static let todoID = XLNamedBindingReference<TodoUUID>(name: "id")

    /// Mirrors `Query.todoLists()`.
    static var lists: any XLQueryStatement<TodoList> {
        sql { schema in
            let list = schema.table(TodoList.self)
            Select(list)
            From(list)
            OrderBy(list.position.ascending(), list.name.ascending())
        }
    }

    /// Mirrors `Query.listCounts()`.
    static var listCounts: any XLQueryStatement<TodoListCounts> {
        sql { schema in
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
        }
    }

    /// Mirrors `Query.todo(id:)`.
    static var todoByID: any XLQueryStatement<Todo> {
        sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo)
            From(todo)
            Where(todo.id == todoID)
        }
    }
}

extension TodoDatabase {

    /// The packet a to-do-by-identifier observation captures once.
    public static func todoIDBindings(
        _ id: TodoUUID,
        layout: XLParameterLayout
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        guard let slot = layout.slot(for: .named("id")) else {
            throw TodoStoreError.unknownParameter(
                statement: "to-do by identifier",
                name: "id"
            )
        }
        return try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [try XLInvocationBinding(slot: slot, value: id.sqlValue)]
        ).validatingComplete()
    }
}
