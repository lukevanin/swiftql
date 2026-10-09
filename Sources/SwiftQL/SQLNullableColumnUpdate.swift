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
/// The state of one non-nullable column in an update statement's `SET`
/// clause.
///
/// Generated `MetaUpdate` types store one slot per column and route
/// `row.column = expression` assignments to it through key-path member
/// lookup. A slot whose `expression` is `nil` takes no part in the `SET`
/// clause.
///
public struct XLColumnUpdate<Wrapped> {

    /// The expression assigned to the column, or `nil` when the column is
    /// left out of the `SET` clause.
    public var expression: (any XLExpression<Wrapped>)?

    /// Creates a slot that leaves the column out of the `SET` clause.
    public init() {
        self.expression = nil
    }

    ///
    /// The assigned expression as `ExpressionType`, the model's dialect's
    /// expression type, or `nil` when the column was never assigned or holds
    /// a value of no dialect.
    ///
    /// A generated `MetaUpdate`'s slot takes only its model's dialect's
    /// expressions (issue #825) and stores the one it is given erased, so a
    /// read casts it back and returns the assigned expression itself, with
    /// its type, its dialect record, and what a run-time check sees inside it
    /// unchanged. A value written to the slot directly, such as the one the
    /// generated `UpdateRequest` writes, is no dialect's expression; the
    /// generated getter then reads ``_xlReadUntypedExpression`` and converts
    /// it to the dialect's type with a generated function, so a dialect
    /// whose expression protocol does not include `XLTypeAffinityExpression`
    /// is a compile error in the model rather than a read that fails. It is
    /// not part of the API a caller writes against.
    ///
    public func _xlReadExpression<ExpressionType>(as type: ExpressionType.Type) -> ExpressionType? {
        expression as? ExpressionType
    }

    ///
    /// The assigned expression inside an `XLTypeAffinityExpression`, which
    /// records no dialect, so a run-time dialect check walks into it, or
    /// `nil` when the column was never assigned (issue #825). A generated
    /// getter reads it when ``_xlReadExpression(as:)`` is `nil`. It is not
    /// part of the API a caller writes against.
    ///
    public var _xlReadUntypedExpression: XLTypeAffinityExpression<Wrapped>? {
        _xlUntypedSlotRead(expression)
    }
}


///
/// A slot's expression inside an `XLTypeAffinityExpression`, which records no
/// dialect, so a run-time dialect check walks into it, or `nil` when the slot
/// holds none (issue #825). Both column slots' untyped reads return it.
///
func _xlUntypedSlotRead<T>(_ expression: (any XLExpression<T>)?) -> XLTypeAffinityExpression<T>? {
    guard let expression else {
        return nil
    }
    return XLTypeAffinityExpression<T>(expression: expression)
}


///
/// The state of one nullable column in an update statement's `SET` clause.
///
/// A nullable column has two independent pieces of state: whether the column
/// takes part in the `SET` clause at all, and — if it does — whether the
/// value it is set to is `NULL`. Reusing `Optional` for both makes them
/// collide, so this slot tracks participation separately from the value.
/// Generated `MetaUpdate` types store one slot per nullable column and route
/// assignments to it through overloaded key-path member subscripts, which is
/// what lets a nullable column be assigned the same way an ordinary Swift
/// optional is:
///
/// ```swift
/// Setting(person) { row in
///     row.occupationId = "occ-1"  // SET occupationId = 'occ-1'
///     row.occupationId = nil      // SET occupationId = NULL
/// }
/// ```
///
/// An expression whose own type is already optional — a
/// `XLNamedBindingReference<String?>` whose bound value may be `NULL` at
/// runtime, or another nullable column — assigns the same way, through the
/// slot's ``optionalExpression``. A column that is never assigned stays out
/// of the statement entirely.
///
public struct XLNullableColumnUpdate<Wrapped> {

    private var wrappedExpression: (any XLExpression<Wrapped>)?

    private var storedExpression: (any XLExpression<Optional<Wrapped>>)?

    private var isAssigned: Bool

    /// Creates a slot that leaves the column out of the `SET` clause.
    public init() {
        self.wrappedExpression = nil
        self.storedExpression = nil
        self.isAssigned = false
    }

    /// The expression assigned to the column, as an expression of the
    /// column's wrapped type.
    ///
    /// Assigning `nil` sets the column to SQL `NULL`; it does not remove the
    /// column from the statement. Reading returns `nil` both for a column
    /// that was never assigned and for one assigned an optional-typed
    /// expression through ``optionalExpression``.
    public var expression: (any XLExpression<Wrapped>)? {
        get {
            wrappedExpression
        }
        set {
            wrappedExpression = newValue
            if let newValue {
                // Built directly rather than through the generic
                // `toNullable()` helper: calling a method with an opaque
                // return type on a constrained existential
                // (`any XLExpression<Wrapped>`) type-checks under Swift 6.0+
                // but is ambiguous under the pinned Swift 5.9.2 compiler.
                // `XLTypeAffinityExpression`'s own initializer takes an
                // unconstrained `any XLExpression`, so widening to that
                // sidesteps the limitation entirely.
                storedExpression = XLTypeAffinityExpression<Optional<Wrapped>>(
                    expression: newValue
                )
            }
            else {
                storedExpression = nil
            }
            isAssigned = true
        }
    }

    /// The expression assigned to the column, as an optional-typed
    /// expression.
    ///
    /// Assigning `nil` here sets the column to SQL `NULL`, the same as
    /// assigning `nil` to ``expression``. Assigning the read of a column that
    /// was never assigned leaves the column out of the statement, so
    /// `row.nickname = row.nickname` keeps the stored value (issue #828).
    public var optionalExpression: (any XLExpression<Optional<Wrapped>>)? {
        get {
            storedExpression
        }
        set {
            wrappedExpression = nil
            if let newValue, XLUnassignedColumnExpression<Wrapped>.isRead(of: newValue) {
                storedExpression = nil
                isAssigned = false
                return
            }
            storedExpression = newValue
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
        return storedExpression ?? XLNullExpression<Wrapped>()
    }

    ///
    /// The assigned value as `ExpressionType`, the model's dialect's
    /// expression type of the column's optional type, for a generated
    /// `MetaUpdate`'s read of the slot (issues #825, #828), or `nil` when the
    /// column was never assigned or holds a value of no dialect, or the value
    /// is `NULL` in a dialect whose expression protocol does not include
    /// `XLNullExpression`.
    ///
    /// A nullable column is read only as an optional-typed expression: the
    /// value can be `NULL`, so the generated getter of the wrapped-type
    /// overload is unavailable, and a read cannot be assigned to a column
    /// that is `NOT NULL`. Whichever overload assigned the column, the read
    /// is the assigned value, so assigning it back keeps it. A value of the
    /// wrapped type reads inside the `XLTypeAffinityExpression` it is stored
    /// in, and `NULL` reads as `NULL`.
    ///
    public func _xlReadOptionalExpression<ExpressionType>(as type: ExpressionType.Type) -> ExpressionType? {
        guard isAssigned else {
            return nil
        }
        return (storedExpression ?? XLNullExpression<Wrapped>()) as? ExpressionType
    }

    ///
    /// The assigned value inside an `XLTypeAffinityExpression`, which records
    /// no dialect, for a generated getter when
    /// ``_xlReadOptionalExpression(as:)`` is `nil` (issue #825).
    ///
    /// A column never assigned reads as a value that renders `NULL` and that
    /// ``optionalExpression`` recognises: assigning it to a nullable column,
    /// this one or another, leaves that column out of the statement, so
    /// `row.nickname = row.nickname` keeps the stored value (issue #828).
    ///
    public var _xlReadUntypedOptionalExpression: XLTypeAffinityExpression<Optional<Wrapped>> {
        guard isAssigned else {
            return XLTypeAffinityExpression<Optional<Wrapped>>(
                expression: XLUnassignedColumnExpression<Wrapped>()
            )
        }
        return XLTypeAffinityExpression<Optional<Wrapped>>(
            expression: storedExpression ?? XLNullExpression<Wrapped>()
        )
    }
}


///
/// The read of a nullable column that a `Setting` closure never assigned
/// (issue #828).
///
/// It is only ever held inside an `XLTypeAffinityExpression`, which every
/// dialect's expression protocol includes. Assigned to a nullable column's
/// slot, it leaves the column out of the statement; anywhere else it renders
/// `NULL`, as the read of an unassigned column did before.
///
struct XLUnassignedColumnExpression<Wrapped>: XLExpression {

    typealias T = Optional<Wrapped>

    func makeSQL(context: inout XLBuilder) {
        context.null()
    }

    /// Whether `expression` is the read of a column never assigned.
    static func isRead(of expression: any XLExpression<Optional<Wrapped>>) -> Bool {
        guard let read = expression as? XLTypeAffinityExpression<Optional<Wrapped>> else {
            return false
        }
        return read.wrappedExpression is XLUnassignedColumnExpression<Wrapped>
    }
}
