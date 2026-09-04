import Foundation

import SwiftQL

/// The demo's reads, declared as functions.
///
/// SwiftQL allows one `@SQLQueries` extension per database type, so this is
/// the single place the demo's declared queries live.
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

        /// One list by identifier.
        func todoList(id: TodoUUID) -> TodoList? {
            sqlResult { schema in
                let list = schema.table(TodoList.self)
                Select(list)
                From(list)
                Where(list.id == id)
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

        /// One to-do by identifier.
        func todo(id: TodoUUID) -> Todo? {
            sqlResult { schema in
                let todo = schema.table(Todo.self)
                Select(todo)
                From(todo)
                Where(todo.id == id)
            }
        }

        /// One row per to-do in a list, summarising its checklist.
        ///
        /// The counting happens in SQLite. `json_array_length` reads the
        /// stored array, and `->>` selects the first item's title, so the
        /// view gets what it draws without any checklist crossing the
        /// boundary.
        func checklistSummaries(listID: TodoUUID) -> [TodoChecklistSummary] {
            sqlResult { schema in
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
                Where(todo.listID == listID)
                OrderBy(todo.position.ascending())
            }
        }

        /// The tags attached to one to-do, joined across the link table.
        func tagsForTodo(todoID: TodoUUID) -> [TodoTagPair] {
            sqlResult { schema in
                let link = schema.table(TodoTag.self)
                let tag = schema.table(Tag.self)
                Select(TodoTagPair.columns(
                    todoID: link.todoID,
                    tagID: tag.id,
                    tagName: tag.name
                ))
                From(link)
                Join.Inner(tag, on: tag.id == link.tagID)
                Where(link.todoID == todoID)
                OrderBy(tag.name.ascending())
            }
        }

        /// Every to-do/tag pairing in one list, so a list view can label its
        /// rows without a query per row.
        func tagsForList(listID: TodoUUID) -> [TodoTagPair] {
            sqlResult { schema in
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
                Where(todo.listID == listID)
                OrderBy(tag.name.ascending())
            }
        }

        /// Open and total counts for every list, in one grouped query rather
        /// than a count per list.
        ///
        /// A list with no to-dos does not appear: `GROUP BY` over `Todo` has
        /// nothing to group for it. The sidebar fills those in as zero.
        func listCounts() -> [TodoListCounts] {
            sqlResult { schema in
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
