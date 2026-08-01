import Foundation

import SwiftQL

/// A named list of to-dos.
@SQLTable
public struct TodoList: Equatable, Identifiable, Sendable {

    public var id: TodoUUID

    public var name: String

    /// Where the list sits in the sidebar. Renumbered when a list moves.
    public var position: Int

    public var createdAt: TodoDate
}

/// One to-do, belonging to exactly one list.
@SQLTable
public struct Todo: Equatable, Identifiable, Sendable {

    public var id: TodoUUID

    public var listID: TodoUUID

    public var title: String

    public var notes: String

    /// `nil` for a to-do with no deadline. Such a to-do is never overdue.
    public var dueAt: TodoDate?

    public var priority: TodoPriority

    public var isCompleted: Bool

    /// Where the to-do sits within its list.
    public var position: Int

    public var createdAt: TodoDate
}

/// A label that can apply to any number of to-dos.
@SQLTable
public struct Tag: Equatable, Identifiable, Sendable {

    public var id: TodoUUID

    public var name: String
}

/// The many-to-many join between to-dos and tags.
@SQLTable
public struct TodoTag: Equatable, Sendable {

    public var todoID: TodoUUID

    public var tagID: TodoUUID
}

/// Every table the demo creates, in dependency order.
///
/// `sqlCreate` emits `CREATE TABLE IF NOT EXISTS` with no primary keys,
/// foreign keys, or indexes — see the SwiftQL "Getting started" guide. The
/// demo relies on the query layer to keep the relations honest rather than on
/// database constraints.
enum TodoSchema {

    static var createStatements: [any XLEncodable] {
        [
            sqlCreate(TodoList.self),
            sqlCreate(Todo.self),
            sqlCreate(Tag.self),
            sqlCreate(TodoTag.self),
        ]
    }
}
