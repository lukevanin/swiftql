import Foundation


///
/// Where one parameter reference appears in a rendered statement, and how it
/// is spelled there.
///
/// The logical key is the identity Swift code chose. The placeholder is what
/// the dialect wrote into the SQL text. The two are not the same thing:
/// PostgreSQL has no named placeholders on the wire, so a named key is
/// rendered `$1` by position.
///
public struct XLParameterPlaceholderAssignment: Hashable, Sendable {

    ///
    /// The placeholder rendered into the SQL text.
    ///
    public let placeholder: XLBindingPlaceholder

    ///
    /// The one-based position the engine binds this parameter by.
    ///
    public let physicalIndex: Int

    public init(placeholder: XLBindingPlaceholder, physicalIndex: Int) {
        self.placeholder = placeholder
        self.physicalIndex = physicalIndex
    }
}


///
/// Assigns rendered placeholders to logical binding keys for one statement.
///
/// An assigner is created per statement and consumed while rendering it, so
/// it can number placeholders in first-encounter order. Asking for the same
/// key twice must return the same assignment: a named parameter used twice
/// occupies one slot and is bound once.
///
public protocol XLPlaceholderAssigner {

    ///
    /// Returns the assignment for `key`, creating it on first encounter.
    ///
    mutating func assignment(for key: XLBindingKey) -> XLParameterPlaceholderAssignment
}


///
/// Assigns placeholders the way SQLite does.
///
/// A named parameter is rendered by name and takes the next physical index.
/// An indexed parameter is rendered `?NNN` and takes `NNN` directly, which is
/// why a named parameter followed by an explicit index can alias one physical
/// slot. Reproducing that rule here keeps the aliasing detectable.
///
public struct XLitePlaceholderAssigner: XLPlaceholderAssigner {

    private var assignmentsByKey: [XLBindingKey: XLParameterPlaceholderAssignment] = [:]

    private var largestPhysicalIndex = 0

    public init() {}

    public mutating func assignment(
        for key: XLBindingKey
    ) -> XLParameterPlaceholderAssignment {
        if let existing = assignmentsByKey[key] {
            return existing
        }

        let physicalIndex: Int
        switch key {
        case .named:
            physicalIndex = largestPhysicalIndex + 1
        case .indexed(let zeroBasedIndex):
            physicalIndex = zeroBasedIndex + 1
        }

        // SQLite spells the placeholder from the key itself: a named key is
        // written `:name`, an indexed key `?NNN`.
        let assignment = XLParameterPlaceholderAssignment(
            placeholder: key.asPlaceholder,
            physicalIndex: physicalIndex
        )
        assignmentsByKey[key] = assignment
        largestPhysicalIndex = max(largestPhysicalIndex, physicalIndex)
        return assignment
    }
}


///
/// Assigns every key a positional placeholder, numbered in first-encounter
/// order.
///
/// PostgreSQL and MySQL have no named placeholders on the wire. A dialect for
/// either uses this rule, so a declared query written with named parameters
/// still renders and still binds.
///
public struct XLPositionalPlaceholderAssigner: XLPlaceholderAssigner {

    private var assignmentsByKey: [XLBindingKey: XLParameterPlaceholderAssignment] = [:]

    private var assignedCount = 0

    public init() {}

    public mutating func assignment(
        for key: XLBindingKey
    ) -> XLParameterPlaceholderAssignment {
        if let existing = assignmentsByKey[key] {
            return existing
        }
        assignedCount += 1
        let assignment = XLParameterPlaceholderAssignment(
            placeholder: .indexed(assignedCount - 1),
            physicalIndex: assignedCount
        )
        assignmentsByKey[key] = assignment
        return assignment
    }
}


extension XLBindingKey {

    ///
    /// The placeholder a dialect writes when it spells a key the same way it
    /// was named.
    ///
    public var asPlaceholder: XLBindingPlaceholder {
        switch self {
        case .named(let name):
            return .named(name)
        case .indexed(let index):
            return .indexed(index)
        }
    }
}
