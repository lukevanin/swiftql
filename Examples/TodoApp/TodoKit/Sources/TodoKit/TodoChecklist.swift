import Foundation

import SwiftQL

/// One sub-task inside a to-do's checklist.
///
/// The type exists for the view layer. Nothing in the data layer decodes a
/// checklist to change it: adding, ticking, and deleting an item are all
/// `UPDATE` statements that SQLite applies to the stored array.
public struct TodoChecklistItem: Equatable, Codable, Sendable {

    public var title: String

    public var isDone: Bool

    public init(title: String, isDone: Bool = false) {
        self.title = title
        self.isDone = isDone
    }
}

/// The checklist column's shape, its paths, and the two conversions the view
/// layer needs.
public enum TodoChecklist {

    /// What a to-do with no sub-tasks holds. Not `NULL`: an empty array keeps
    /// every path and every count meaningful without a special case.
    public static let empty = "[]"

    /// The array itself, `$`.
    public static let root = XLJSONPath.root

    /// The position one past the last item, which is where an append lands.
    public static let end = XLJSONPath.root.appended

    /// The `isDone` flag of the item at `index`.
    public static func isDone(at index: Int) -> XLJSONPath {
        XLJSONPath.root.index(index).key("isDone")
    }

    /// The item at `index`, whole.
    public static func item(at index: Int) -> XLJSONPath {
        XLJSONPath.root.index(index)
    }

    /// The `title` of the item at `index`.
    public static func title(at index: Int) -> XLJSONPath {
        XLJSONPath.root.index(index).key("title")
    }

    /// Decodes the stored array for the view layer.
    ///
    /// A column that does not parse reads as an empty checklist rather than
    /// throwing. A demo that refuses to draw a to-do because one of its
    /// sub-tasks is malformed would be worse than one that shows the to-do
    /// with nothing under it.
    public static func items(from json: String) -> [TodoChecklistItem] {
        guard let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([TodoChecklistItem].self, from: data)) ?? []
    }

    /// Encodes a checklist, for seed data and for tests.
    public static func json(_ items: [TodoChecklistItem]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard
            let data = try? encoder.encode(items),
            let json = String(data: data, encoding: .utf8)
        else {
            return empty
        }
        return json
    }
}
