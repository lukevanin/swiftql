import Foundation

import SwiftQL

/// Which to-dos a list shows.
public enum TodoFilter: String, CaseIterable, Sendable {

    case all
    case active
    case completed
    case overdue

    /// The three flags the filter becomes in SQL.
    ///
    /// A filter is not a mode the query branches on — it is three booleans
    /// the `Where` clause reads, which is what lets one query serve every
    /// filter instead of one query per filter.
    var flags: (includesCompleted: Bool, includesActive: Bool, overdueOnly: Bool) {
        switch self {
        case .all:
            return (true, true, false)
        case .active:
            return (false, true, false)
        case .completed:
            return (true, false, false)
        case .overdue:
            return (false, true, true)
        }
    }
}

/// The order a list shows them in.
public enum TodoSort: Int, CaseIterable, Sendable {

    /// The order the user arranged them in.
    case manual = 0

    /// Soonest deadline first. A to-do with no deadline sorts last.
    case dueDate = 1

    /// Highest priority first.
    case priority = 2
}

/// Everything a list view asks for at once.
public struct TodoQuery: Equatable, Sendable {

    public var listID: TodoUUID
    public var filter: TodoFilter
    public var sort: TodoSort

    /// Matched against title and notes. Empty matches everything.
    public var searchText: String

    /// What "overdue" is measured against. The app passes the current time;
    /// a test passes a fixed date.
    public var referenceDate: TodoDate

    public init(
        listID: TodoUUID,
        filter: TodoFilter = .all,
        sort: TodoSort = .manual,
        searchText: String = "",
        referenceDate: TodoDate = TodoDate(Date())
    ) {
        self.listID = listID
        self.filter = filter
        self.sort = sort
        self.searchText = searchText
        self.referenceDate = referenceDate
    }

    /// The character that turns a `LIKE` wildcard back into a literal.
    ///
    /// SQLite has no default: without an explicit `ESCAPE`, a backslash in a
    /// pattern is just a backslash and `%` still matches anything. The query
    /// passes this to `like(_:escape:)`, which is what makes the escaping in
    /// ``searchPattern`` mean something.
    static let searchEscape = "\\"

    /// The `LIKE` pattern for ``searchText``.
    ///
    /// Empty search becomes `%`, which every row matches, so the search
    /// clause never has to be added or removed — it is always present and
    /// sometimes vacuous. That is what keeps this one query rather than two.
    ///
    /// A user typing `%`, `_`, or `\` means those characters literally, so
    /// each is escaped. Searching for `50%` finds the row that says `50%`,
    /// not every row.
    var searchPattern: String {
        guard !searchText.isEmpty else {
            return "%"
        }
        let escaped = searchText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}

/// A to-do paired with one of its tags. A to-do with three tags produces
/// three rows.
@SQLResult
public struct TodoTagPair: Equatable, Sendable {

    public var todoID: TodoUUID
    public var tagID: TodoUUID
    public var tagName: String
}

/// How many to-dos a list holds, and how many are still open.
@SQLResult
public struct TodoListCounts: Equatable, Sendable {

    public var listID: TodoUUID
    public var openCount: Int
    public var totalCount: Int
}

/// What SQLite can say about a to-do's checklist without the array leaving
/// the database.
///
/// `itemCount` comes from `json_array_length` and `firstItemTitle` from the
/// `->>` operator, so a list of fifty to-dos costs one query and decodes two
/// small values per row rather than fifty JSON documents.
@SQLResult
public struct TodoChecklistSummary: Equatable, Sendable {

    public var todoID: TodoUUID

    /// `nil` only if the column ever held something that is not an array,
    /// which the schema's default and every write here prevent.
    public var itemCount: Int?

    /// `nil` when the checklist is empty.
    public var firstItemTitle: String?
}
