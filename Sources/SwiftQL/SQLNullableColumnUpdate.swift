//
//  SQLNullableColumnUpdate.swift
//
//
//  Created by Luke Van In on 2026/08/02.
//

import Foundation


///
/// An expression that renders the SQL `NULL` literal.
///
/// Assigning `nil` to a nullable column inside a `Setting` closure stores this
/// expression, so the column appears in the `SET` clause with an explicit
/// `NULL` rather than being left out of the statement.
///
public struct XLNullExpression<Wrapped>: XLExpression {

    public typealias T = Optional<Wrapped>

    public init() {
    }

    public func makeSQL(context: inout XLBuilder) {
        context.null()
    }
}


///
/// Records the value assigned to a nullable column in an update statement.
///
/// A nullable column has two independent pieces of state: whether the column
/// takes part in the `SET` clause at all, and — if it does — whether the value
/// it is set to is `NULL`. Reusing `Optional` for both makes them collide, so
/// this wrapper tracks participation separately from the value. That lets a
/// nullable column be assigned the same way an ordinary Swift optional is:
///
/// ```swift
/// Setting(person) { row in
///     row.occupationId = "occ-1"  // SET occupationId = 'occ-1'
///     row.occupationId = nil      // SET occupationId = NULL
/// }
/// ```
///
/// A column that is never assigned stays out of the statement entirely.
///
/// The wrapped value is an expression of the column's *wrapped* type, so
/// literals and non-optional expressions assign directly. To assign an
/// expression that is itself optional-typed — a `XLNamedBindingReference<T?>`
/// whose bound value may be `NULL` at runtime, or another nullable column —
/// assign to the projected value instead:
///
/// ```swift
/// let occupation = XLNamedBindingReference<String?>(name: "occupationId")
/// Setting(person) { row in
///     row.$occupationId = occupation
/// }
/// ```
///
@propertyWrapper
public struct XLNullableColumnUpdate<Wrapped> {

    private var wrappedExpression: (any XLExpression<Wrapped>)?

    private var optionalExpression: (any XLExpression<Optional<Wrapped>>)?

    private var isAssigned: Bool

    /// Creates an assignment that leaves the column out of the `SET` clause.
    public init() {
        self.wrappedExpression = nil
        self.optionalExpression = nil
        self.isAssigned = false
    }

    /// The expression assigned to the column, as an expression of the column's
    /// wrapped type.
    ///
    /// Assigning `nil` sets the column to SQL `NULL`; it does not remove the
    /// column from the statement. Reading returns `nil` both for a column that
    /// was never assigned and for one assigned an optional-typed expression
    /// through ``projectedValue``.
    public var wrappedValue: (any XLExpression<Wrapped>)? {
        get {
            wrappedExpression
        }
        set {
            wrappedExpression = newValue
            optionalExpression = newValue?.toNullable()
            isAssigned = true
        }
    }

    /// The expression assigned to the column, as an optional-typed expression.
    ///
    /// Use this to assign an expression whose own type is already optional,
    /// which the wrapped value cannot accept. Assigning `nil` here sets the
    /// column to SQL `NULL`, the same as assigning `nil` to the wrapped value.
    public var projectedValue: (any XLExpression<Optional<Wrapped>>)? {
        get {
            optionalExpression
        }
        set {
            wrappedExpression = nil
            optionalExpression = newValue
            isAssigned = true
        }
    }

    ///
    /// The expression this column contributes to the `SET` clause, or `nil`
    /// when the column was never assigned and takes no part in the statement.
    ///
    /// Generated `makeSQL` implementations read this. It is not part of the
    /// API a caller writes against.
    ///
    public var _xlAssignedExpression: (any XLExpression<Optional<Wrapped>>)? {
        guard isAssigned else {
            return nil
        }
        return optionalExpression ?? XLNullExpression<Wrapped>()
    }
}
