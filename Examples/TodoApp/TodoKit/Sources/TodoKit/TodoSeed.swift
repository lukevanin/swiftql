import Foundation

/// The rows a fresh database starts with.
///
/// Every identifier is fixed rather than random, so a test can name the row
/// it means, and every date is derived from `referenceDate` rather than the
/// wall clock, so "overdue" means the same thing on every run.
public struct TodoSeed: Sendable {

    public let lists: [TodoList]
    public let tags: [Tag]
    public let todos: [Todo]
    public let todoTags: [TodoTag]

    public static let todayListID = TodoUUID(uuid("11111111-0000-0000-0000-000000000001"))
    public static let homeListID = TodoUUID(uuid("11111111-0000-0000-0000-000000000002"))
    public static let readingListID = TodoUUID(uuid("11111111-0000-0000-0000-000000000003"))

    public static let errandTagID = TodoUUID(uuid("22222222-0000-0000-0000-000000000001"))
    public static let urgentTagID = TodoUUID(uuid("22222222-0000-0000-0000-000000000002"))
    public static let homeTagID = TodoUUID(uuid("22222222-0000-0000-0000-000000000003"))

    /// Overdue: due yesterday, still open, and tagged.
    public static let renewPassportID = TodoUUID(uuid("33333333-0000-0000-0000-000000000001"))
    /// Open, due tomorrow, tagged.
    public static let bookDentistID = TodoUUID(uuid("33333333-0000-0000-0000-000000000002"))
    /// Open, no due date, untagged.
    public static let sharpenKnivesID = TodoUUID(uuid("33333333-0000-0000-0000-000000000003"))
    /// Completed, and past its due date — completed wins over overdue.
    public static let payRentID = TodoUUID(uuid("33333333-0000-0000-0000-000000000004"))
    /// Open, overdue, untagged, in a different list.
    public static let returnLibraryBookID = TodoUUID(uuid("33333333-0000-0000-0000-000000000005"))
    /// Completed, no due date.
    public static let finishNovelID = TodoUUID(uuid("33333333-0000-0000-0000-000000000006"))

    public init(referenceDate: Date) {
        let createdAt = TodoDate(referenceDate.addingTimeInterval(-.week))

        lists = [
            TodoList(
                id: Self.todayListID,
                name: "Today",
                position: 0,
                createdAt: createdAt
            ),
            TodoList(
                id: Self.homeListID,
                name: "Home",
                position: 1,
                createdAt: createdAt
            ),
            TodoList(
                id: Self.readingListID,
                name: "Reading",
                position: 2,
                createdAt: createdAt
            ),
        ]

        tags = [
            Tag(id: Self.errandTagID, name: "errand"),
            Tag(id: Self.urgentTagID, name: "urgent"),
            Tag(id: Self.homeTagID, name: "home"),
        ]

        todos = [
            Todo(
                id: Self.renewPassportID,
                listID: Self.todayListID,
                title: "Renew passport",
                notes: "The appointment queue is long, book early.",
                dueAt: TodoDate(referenceDate.addingTimeInterval(-.day)),
                priority: .high,
                isCompleted: false,
                position: 0,
                createdAt: createdAt
            ),
            Todo(
                id: Self.bookDentistID,
                listID: Self.todayListID,
                title: "Book a dentist appointment",
                notes: "Ask about the chipped molar.",
                dueAt: TodoDate(referenceDate.addingTimeInterval(.day)),
                priority: .normal,
                isCompleted: false,
                position: 1,
                createdAt: createdAt
            ),
            Todo(
                id: Self.sharpenKnivesID,
                listID: Self.homeListID,
                title: "Sharpen the kitchen knives",
                notes: "",
                dueAt: nil,
                priority: .low,
                isCompleted: false,
                position: 0,
                createdAt: createdAt
            ),
            Todo(
                id: Self.payRentID,
                listID: Self.homeListID,
                title: "Pay the rent",
                notes: "Standing order, confirm it cleared.",
                dueAt: TodoDate(referenceDate.addingTimeInterval(-2 * .day)),
                priority: .high,
                isCompleted: true,
                position: 1,
                createdAt: createdAt
            ),
            Todo(
                id: Self.returnLibraryBookID,
                listID: Self.readingListID,
                title: "Return the library book",
                notes: "Two weeks overdue already.",
                dueAt: TodoDate(referenceDate.addingTimeInterval(-3 * .day)),
                priority: .normal,
                isCompleted: false,
                position: 0,
                createdAt: createdAt
            ),
            Todo(
                id: Self.finishNovelID,
                listID: Self.readingListID,
                title: "Finish the novel",
                notes: "",
                dueAt: nil,
                priority: .low,
                isCompleted: true,
                position: 1,
                createdAt: createdAt
            ),
        ]

        todoTags = [
            TodoTag(todoID: Self.renewPassportID, tagID: Self.errandTagID),
            TodoTag(todoID: Self.renewPassportID, tagID: Self.urgentTagID),
            TodoTag(todoID: Self.bookDentistID, tagID: Self.errandTagID),
            TodoTag(todoID: Self.payRentID, tagID: Self.homeTagID),
        ]
    }

    private static func uuid(_ string: String) -> UUID {
        // Force-unwrapping a string literal this file owns. A typo here is a
        // programmer error the first test run catches, not a runtime input.
        UUID(uuidString: string)!
    }
}

private extension TimeInterval {

    static let day: TimeInterval = 24 * 60 * 60

    static let week: TimeInterval = 7 * day
}
