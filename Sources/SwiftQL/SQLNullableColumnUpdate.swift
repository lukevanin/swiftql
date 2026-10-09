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
/// A nullable column is read only as an optional-typed expression (issue
/// #828): the value can be `NULL`, so a read cannot be assigned to a column
/// that is `NOT NULL`. The read is the value assigned, so assigning it back
/// keeps it. The read of a column never assigned stands for the column's
/// current value: assigned to a nullable column's slot, it sets that column
/// to this one, so `row.nickname = row.nickname` renders
/// `SET "nickname" = "nickname"`, and `row.alias = row.nickname` copies the
/// stored value. Anywhere else, such as inside a composed expression, it
/// renders `NULL`, as it did before.
///
public struct XLNullableColumnUpdate<Wrapped> {

    private var wrappedExpression: (any XLExpression<Wrapped>)?

    private var storedExpression: (any XLExpression<Optional<Wrapped>>)?

    private var isAssigned: Bool

    /// The column, which the read of the column before it is assigned
    /// carries (issue #828), or `nil` for a slot created with ``init()``.
    private let column: XLSlotColumn?

    /// The column of this slot's model whose read, of the column never
    /// assigned, was assigned to this slot, found when it was assigned
    /// (issue #828), or `nil`.
    private var copiedColumn: XLName?

    /// Creates a slot that leaves the column out of the `SET` clause.
    public init() {
        self.init(column: nil)
    }

    ///
    /// Creates a slot that leaves the column out of the `SET` clause, for the
    /// column named `column` of the model whose generated `MetaUpdate.Columns`
    /// type is `model`. Its read before it is assigned stands for the
    /// column's current value (issue #828). A generated `MetaUpdate` creates
    /// its nullable slots with it. It is not part of the API a caller writes
    /// against.
    ///
    public init(_xlColumn column: XLName, of model: Any.Type) {
        self.init(column: XLSlotColumn(name: column, model: ObjectIdentifier(model)))
    }

    private init(column: XLSlotColumn?) {
        self.wrappedExpression = nil
        self.storedExpression = nil
        self.isAssigned = false
        self.column = column
        self.copiedColumn = nil
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
            copiedColumn = nil
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
            copiedColumn = nil
            if let newValue,
               let read = XLUnassignedColumnRead<Wrapped>.read(in: newValue),
               let column,
               read.column.model == column.model {
                copiedColumn = read.column.name
            }
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
    /// The read of a column never assigned, of this slot's model, assigned
    /// to this slot, renders here, and only here, as that column's
    /// unqualified name: in a `SET` clause it is the row's current value
    /// (issue #828). A read of another model's column renders `NULL`, as it
    /// did before, because the name would be this table's column.
    ///
    public var _xlAssignedExpression: (any XLExpression<Optional<Wrapped>>)? {
        if let copiedColumn {
            return XLUnqualifiedColumnName<Optional<Wrapped>>(name: copiedColumn)
        }
        return assignedValue
    }

    /// The value assigned, `NULL` when that is `nil`, or `nil` when the
    /// column was never assigned.
    private var assignedValue: (any XLExpression<Optional<Wrapped>>)? {
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
    /// generated getter of the wrapped-type overload is unavailable. The
    /// read is the assigned value, whichever overload assigned it: a value of
    /// the wrapped type reads inside the `XLTypeAffinityExpression` it is
    /// stored in, and `NULL` reads as `NULL`. A column never assigned reads
    /// through ``_xlReadUntypedOptionalExpression``.
    ///
    public func _xlReadOptionalExpression<ExpressionType>(as type: ExpressionType.Type) -> ExpressionType? {
        assignedValue as? ExpressionType
    }

    ///
    /// The assigned value inside an `XLTypeAffinityExpression`, which records
    /// no dialect, for a generated getter when
    /// ``_xlReadOptionalExpression(as:)`` is `nil` (issue #825).
    ///
    /// A column never assigned reads as the column's current value (issue
    /// #828): a value that renders `NULL`, as the read did before, except
    /// where a nullable column's slot renders it in a `SET` clause, as this
    /// column's name. A slot created with ``init()`` has no name, and its
    /// column never assigned reads as `NULL`.
    ///
    public var _xlReadUntypedOptionalExpression: XLTypeAffinityExpression<Optional<Wrapped>> {
        let unassigned: any XLExpression<Optional<Wrapped>> = column.map {
            XLUnassignedColumnRead<Wrapped>(column: $0)
        } ?? XLNullExpression<Wrapped>()
        return XLTypeAffinityExpression<Optional<Wrapped>>(expression: assignedValue ?? unassigned)
    }
}


///
/// The read of a nullable column that a `Setting` closure never assigned
/// (issue #828), which stands for the column's current value.
///
/// A read hands it out inside an `XLTypeAffinityExpression`, which every
/// dialect's expression protocol includes. A nullable column's slot that is
/// assigned it, a slot of the same model, renders it in the `SET` clause as
/// the column's unqualified name, the row's current value there. Anywhere
/// else, where an unqualified name could resolve to another table's column
/// or, in SQLite, read as a string, it renders `NULL`, as the read of an
/// unassigned column did before.
///
struct XLUnassignedColumnRead<Wrapped>: XLExpression {

    typealias T = Optional<Wrapped>

    let column: XLSlotColumn

    func makeSQL(context: inout XLBuilder) {
        context.null()
    }

    /// The read `value` is, inside however many `XLTypeAffinityExpression`
    /// nodes, or `nil`.
    static func read(in value: any XLExpression) -> XLUnassignedColumnRead<Wrapped>? {
        var value = value
        while let affinity = value as? XLTypeAffinityExpression<Optional<Wrapped>> {
            value = affinity.expression
        }
        return value as? XLUnassignedColumnRead<Wrapped>
    }
}


///
/// The column a nullable slot belongs to: its name, and its model's
/// generated `MetaUpdate.Columns` type (issue #828).
///
struct XLSlotColumn: Sendable {

    let name: XLName

    let model: ObjectIdentifier
}


///
/// A column by its unqualified name, for a nullable column's slot to render
/// an assigned ``XLUnassignedColumnRead`` in a `SET` clause (issue #828).
///
/// Like `XLColumnReference`, it renders the column through its type's
/// `wrapSQL`, the conversion every read of a column of that type has, so
/// that the `SET` clause's `unwrapSQL` writes back the value it read.
///
struct XLUnqualifiedColumnName<T>: XLExpression {

    let name: XLName

    func makeSQL(context: inout XLBuilder) {
        guard let literalType = T.self as? any XLLiteral.Type else {
            name.makeSQL(context: &context)
            return
        }
        literalType.wrapSQL(context: &context) { context in
            name.makeSQL(context: &context)
        }
    }
}
