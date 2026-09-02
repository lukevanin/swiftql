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

    /// Sub-tasks, held as a JSON array of `{"title": …, "isDone": …}`.
    ///
    /// A checklist belongs entirely to its to-do. Nothing queries one on its
    /// own, nothing joins to it, and its length varies from zero to a
    /// handful. A second table would add a foreign key, a join, and an
    /// ordering column to model something no query ever asks about
    /// separately, which is what makes a JSON column the honest choice here
    /// rather than a demonstration for its own sake.
    ///
    /// SQLite reads and rewrites the array in place, so adding, ticking, or
    /// deleting one item is a single `UPDATE`. The app never loads a to-do,
    /// changes an item in Swift, and writes the whole thing back.
    ///
    /// A new to-do starts with ``TodoChecklist/empty``. The property carries
    /// no Swift default, because `@SQLTable`'s generated memberwise
    /// initializer requires every property regardless: a default here would
    /// read as optional at the call site and then not be. Recorded on issue
    /// #469.
    ///
    /// See ``TodoChecklist``.
    public var checklist: String
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
