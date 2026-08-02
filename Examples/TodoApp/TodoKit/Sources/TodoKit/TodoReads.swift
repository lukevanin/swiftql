import Foundation

import SwiftQL

/// The demo's reads, declared as functions.
///
/// SwiftQL allows one `@SQLQueries` extension per database type, so this is
/// the single place the demo's declared queries live. The query layer proper
/// — filters, search, joins, and counts — grows here.
@SQLQueries
extension GRDBDatabase {

    private struct Query {

        /// Every list, in sidebar order.
        func todoLists() -> [TodoList] {
            sqlResult { schema in
                let list = schema.table(TodoList.self)
                Select(list)
                From(list)
                OrderBy(list.position.ascending(), list.name.ascending())
            }
        }

        /// Every to-do, oldest first.
        func todos() -> [Todo] {
            sqlResult { schema in
                let todo = schema.table(Todo.self)
                Select(todo)
                From(todo)
                OrderBy(todo.createdAt.ascending(), todo.position.ascending())
            }
        }

        /// Every tag, alphabetically.
        func tags() -> [Tag] {
            sqlResult { schema in
                let tag = schema.table(Tag.self)
                Select(tag)
                From(tag)
                OrderBy(tag.name.ascending())
            }
        }

        /// Every to-do/tag pairing.
        func todoTags() -> [TodoTag] {
            sqlResult { schema in
                let link = schema.table(TodoTag.self)
                Select(link)
                From(link)
            }
        }
    }
}

extension TodoDatabase {

    public func lists() throws -> [TodoList] {
        try database.todoLists()
    }

    public func todos() throws -> [Todo] {
        try database.todos()
    }

    public func tags() throws -> [Tag] {
        try database.tags()
    }

    public func todoTags() throws -> [TodoTag] {
        try database.todoTags()
    }
}
