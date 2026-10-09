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

    /// The column's name, which a read of the slot names when the column was
    /// never assigned (issue #828), or `nil` for a slot created with
    /// ``init()``.
    private let column: XLName?

    /// Creates a slot that leaves the column out of the `SET` clause.
    public init() {
        self.expression = nil
        self.column = nil
    }

    ///
    /// Creates a slot that leaves the column out of the `SET` clause, for the
    /// column named `column`, so that a read of the slot before it is
    /// assigned is the column's current value (issue #828). A generated
    /// `MetaUpdate` creates its slots with it. It is not part of the API a
    /// caller writes against.
    ///
    public init(_xlColumn column: XLName) {
        self.expression = nil
        self.column = column
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
    /// records no dialect, so a run-time dialect check walks into it (issue
    /// #825). A generated getter reads it when ``_xlReadExpression(as:)`` is
    /// `nil`. It is not part of the API a caller writes against.
    ///
    /// A column never assigned reads as the column itself, its current value
    /// (issue #828), which the statement's `SET` clause renders by its name:
    /// `row.name = row.name` keeps the stored value, and
    /// `row.nickname = row.name` copies it. It is `nil` only for a slot
    /// created with ``init()`` and never assigned.
    ///
    public var _xlReadUntypedExpression: XLTypeAffinityExpression<Wrapped>? {
        if let expression {
            return XLTypeAffinityExpression<Wrapped>(expression: expression)
        }
        guard let column else {
            return nil
        }
        return XLTypeAffinityExpression<Wrapped>(
            expression: XLSlotColumnExpression<Wrapped>(name: column)
        )
    }
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

    /// The column's name, which a read of the slot names when the column was
    /// never assigned (issue #828), or `nil` for a slot created with
    /// ``init()``.
    private let column: XLName?

    /// Creates a slot that leaves the column out of the `SET` clause.
    public init() {
        self.wrappedExpression = nil
        self.storedExpression = nil
        self.isAssigned = false
        self.column = nil
    }

    ///
    /// Creates a slot that leaves the column out of the `SET` clause, for the
    /// column named `column`, so that a read of the slot before it is
    /// assigned is the column's current value (issue #828). A generated
    /// `MetaUpdate` creates its slots with it. It is not part of the API a
    /// caller writes against.
    ///
    public init(_xlColumn column: XLName) {
        self.wrappedExpression = nil
        self.storedExpression = nil
        self.isAssigned = false
        self.column = column
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
    /// assigning `nil` to ``expression``.
    public var optionalExpression: (any XLExpression<Optional<Wrapped>>)? {
        get {
            storedExpression
        }
        set {
            wrappedExpression = nil
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
    /// in, and `NULL` reads as `NULL`. A column never assigned reads through
    /// ``_xlReadUntypedOptionalExpression``.
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
    /// A column never assigned reads as the column itself, its current value
    /// (issue #828), which the statement's `SET` clause renders by its name:
    /// `row.nickname = row.nickname` keeps the stored value, and
    /// `row.alias = row.nickname` copies it. A slot created with ``init()``
    /// has no name, and its unassigned column reads as `NULL`.
    ///
    public var _xlReadUntypedOptionalExpression: XLTypeAffinityExpression<Optional<Wrapped>> {
        guard isAssigned else {
            guard let column else {
                return XLTypeAffinityExpression<Optional<Wrapped>>(
                    expression: XLNullExpression<Wrapped>()
                )
            }
            return XLTypeAffinityExpression<Optional<Wrapped>>(
                expression: XLSlotColumnExpression<Optional<Wrapped>>(name: column)
            )
        }
        return XLTypeAffinityExpression<Optional<Wrapped>>(
            expression: storedExpression ?? XLNullExpression<Wrapped>()
        )
    }
}


///
/// The column a `Setting` slot belongs to, by its unqualified name: the read
/// of a column the closure never assigned, which is the column's current
/// value (issue #828).
///
/// It is held only inside an `XLTypeAffinityExpression`, which every
/// dialect's expression protocol includes. An unqualified column name is the
/// row's current value in an `UPDATE` statement's `SET` clause and in an
/// upsert's `DO UPDATE SET`, where a slot's values are rendered.
///
struct XLSlotColumnExpression<T>: XLExpression {

    let name: XLName

    func makeSQL(context: inout XLBuilder) {
        name.makeSQL(context: &context)
    }
}
