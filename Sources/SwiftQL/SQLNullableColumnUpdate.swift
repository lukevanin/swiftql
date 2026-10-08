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
    /// it to the dialect's type itself, so a dialect whose expression
    /// protocol does not include `XLTypeAffinityExpression` is a compile
    /// error in the model rather than a read that fails. It is not part of
    /// the API a caller writes against.
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
        guard let expression else {
            return nil
        }
        return XLTypeAffinityExpression<Wrapped>(expression: expression)
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
    /// ``expression`` as `ExpressionType`, the model's dialect's expression
    /// type of the column's wrapped type, for a generated `MetaUpdate`'s read
    /// of the slot (issue #825), or `nil` when it holds a value of no dialect.
    /// See ``XLColumnUpdate/_xlReadExpression(as:)``.
    ///
    /// It is also `nil` when the column was never assigned, was assigned
    /// `NULL`, or was assigned an optional-typed expression, which is not an
    /// expression of the wrapped type: reading it as one would let a value
    /// that can be `NULL` be assigned to a column that cannot. So assigning
    /// this read back sets the column to `NULL` (issue #828); read the column
    /// through its optional-typed overload to copy it.
    ///
    public func _xlReadExpression<ExpressionType>(as type: ExpressionType.Type) -> ExpressionType? {
        expression as? ExpressionType
    }

    ///
    /// ``expression`` inside an `XLTypeAffinityExpression`, for a generated
    /// getter when ``_xlReadExpression(as:)`` is `nil` (issue #825). See
    /// ``XLColumnUpdate/_xlReadUntypedExpression``.
    ///
    public var _xlReadUntypedExpression: XLTypeAffinityExpression<Wrapped>? {
        guard let expression else {
            return nil
        }
        return XLTypeAffinityExpression<Wrapped>(expression: expression)
    }

    ///
    /// ``optionalExpression`` as `ExpressionType`, or `NULL` when it is `nil`,
    /// for a generated `MetaUpdate`'s read of the slot as an optional-typed
    /// expression (issue #825); `nil` when that is not one of
    /// `ExpressionType`, such as `NULL` in a dialect whose expression
    /// protocol does not include `XLNullExpression`. A column never assigned
    /// also reads as `NULL`, so assigning that read back adds the column to
    /// the statement as `NULL`.
    ///
    public func _xlReadOptionalExpression<ExpressionType>(as type: ExpressionType.Type) -> ExpressionType? {
        (optionalExpression ?? XLNullExpression<Wrapped>()) as? ExpressionType
    }

    ///
    /// ``optionalExpression``, or `NULL` when it is `nil`, inside an
    /// `XLTypeAffinityExpression`, for a generated getter when
    /// ``_xlReadOptionalExpression(as:)`` is `nil` (issue #825).
    ///
    public var _xlReadUntypedOptionalExpression: XLTypeAffinityExpression<Optional<Wrapped>> {
        XLTypeAffinityExpression<Optional<Wrapped>>(
            expression: optionalExpression ?? XLNullExpression<Wrapped>()
        )
    }
}
