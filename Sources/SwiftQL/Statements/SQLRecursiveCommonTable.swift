//
//  SQLRecursiveCommonTable.swift
//
//
//  Alias-first, value-semantic construction lifecycle for recursive common
//  table expressions (issue #205).
//
//  A recursive common table expression contains a reference to itself: the
//  recursive body is written in terms of a self-reference that names the very
//  table being defined. That circularity historically forced an internal
//  mutable completion cell (a class with an implicitly-unwrapped body that was
//  populated after the reference had already been handed to the body closure).
//
//  This file replaces that mutable indirection with a two-phase lifecycle whose
//  name, typed reference, completion state, and completed definition all have
//  value semantics:
//
//    1. Reserve an immutable common-table name.
//    2. Derive the typed self-reference from that name plus static result-layout
//       metadata — never from the body. The reference therefore does not retain
//       the definition it is used to build.
//    3. Evaluate the body transactionally; only a completed draft yields a
//       renderable definition.
//
//  Copying a draft copies its completion state, so independent drafts and their
//  copies can be completed concurrently and deterministically.
//

import Foundation


///
/// Structured, adapter-neutral failures raised while constructing a recursive
/// common table expression through the alias-first two-phase lifecycle.
///
/// These errors carry only the reserved common-table name (and, for layout
/// mismatches, the offending column aliases). They never reference GRDB,
/// connections, prepared statements, or any other adapter state, so the same
/// vocabulary applies regardless of which database backend renders the query.
///
public enum XLRecursiveCommonTableConstructionError: Error, Equatable {

    /// The draft has not completed a body, so it has no renderable definition.
    case incomplete(XLName)

    /// The draft already completed a body. A second completion is rejected
    /// before its body closure is evaluated.
    case alreadyCompleted(XLName)

    /// Completion was requested while another completion of the same draft value
    /// was already in progress. Recursive/re-entrant completion of a single
    /// draft value is not permitted.
    case reentrantCompletion(XLName)

    /// Two common tables reserved the same alias within one statement.
    case duplicateAlias(XLName)

    /// A recursive body produced a result layout whose columns do not match the
    /// columns declared by the self-reference layout.
    case resultLayoutMismatch(alias: XLName, expected: [XLName], actual: [XLName])
}


///
/// Immutable metadata needed to derive a fresh typed self-reference for a single
/// completion attempt.
///
/// A layout retains only the value data required to rebuild the reference from
/// the reserved alias — never a generated result, statement body, namespace, or
/// completed definition. Keeping the reference derivable from the alias alone is
/// what allows the self-reference to avoid retaining the body it helps build.
///
/// The associated `Reference` is the typed, `FROM`-able projection of the common
/// table (for the generated composite surface this is
/// `T.MetaCommonTable.Result.MetaNamedResult`). Issue #43 adds a one-column
/// direct-scalar layout by conforming a new type to this same protocol, without
/// introducing another construction mechanism.
///
public protocol XLRecursiveCommonTableReferenceLayout {

    associatedtype Reference

    /// The ordered column aliases the self-reference exposes. Used to validate a
    /// completed body against the declared result layout. Layouts that do not
    /// expose a fixed column list (such as the generated composite surface,
    /// whose columns are validated by the type system) may leave this empty.
    var resultColumns: [XLName] { get }

    /// Builds a fresh self-reference from only the reserved common-table alias.
    func makeReference(cteAlias: XLName) -> Reference
}


extension XLRecursiveCommonTableReferenceLayout {

    /// Composite, macro-generated surfaces validate their column shape through
    /// the type system, so they expose no explicit result-column list.
    public var resultColumns: [XLName] { [] }
}


///
/// An alias-first, two-phase, value-semantic recursive CTE construction draft.
///
/// The reserved alias is fixed at initialization and never changes, even across
/// copies or failed completions. Completion evaluates the body transactionally:
/// a throwing body rolls the draft back to its declared state so it can be
/// retried, and only a completed draft yields a renderable
/// ``XLCommonTableDependency``. Because the draft is a value with no shared
/// mutable indirection, copying it copies its completion state, and independent
/// drafts — including copies — can be completed concurrently and
/// deterministically.
///
public struct XLRecursiveCommonTableDraft<Layout> where Layout: XLRecursiveCommonTableReferenceLayout {

    private enum State: Equatable {
        case declared
        case building
        case completed
    }

    /// The immutable reserved common-table name. Stable across copies, failed
    /// completions, and retries.
    public let alias: XLName

    private let layout: Layout

    private var state: State = .declared

    public init(alias: XLName, layout: Layout) {
        self.alias = alias
        self.layout = layout
    }

    ///
    /// Completes the draft by evaluating a recursive body against a freshly
    /// derived self-reference.
    ///
    /// On success the draft transitions to `completed` and a renderable
    /// definition is returned. If the body throws, the draft is rolled back to
    /// its declared state — leaving it reusable — and the error is rethrown.
    ///
    public mutating func complete(
        _ makeBody: (Layout.Reference) throws -> any XLEncodable
    ) throws -> XLCommonTableDependency {
        let reference = try beginCompletion()
        do {
            let body = try makeBody(reference)
            state = .completed
            return XLCommonTableDependency(alias: alias, statement: body)
        } catch {
            rollbackCompletion()
            throw error
        }
    }

    ///
    /// Completes the draft with a body that cannot fail.
    ///
    /// A fresh draft completed exactly once with a non-throwing body can never
    /// raise a construction error, which is the case for the public recursive
    /// CTE surface. This keeps that surface free of spurious `try`.
    ///
    public mutating func completeWithNonThrowingBody(
        _ makeBody: (Layout.Reference) -> any XLEncodable
    ) -> XLCommonTableDependency {
        do {
            return try complete(makeBody)
        } catch {
            preconditionFailure(
                "A fresh recursive CTE draft completed once with a non-throwing body cannot fail: \(error)"
            )
        }
    }

    ///
    /// Begins a completion attempt and returns the derived self-reference.
    ///
    /// Rejects re-entrant completion (`building`) and re-completion (`completed`)
    /// with structured errors before any body is evaluated.
    ///
    public mutating func beginCompletion() throws -> Layout.Reference {
        switch state {
        case .declared:
            state = .building
            return layout.makeReference(cteAlias: alias)
        case .building:
            throw XLRecursiveCommonTableConstructionError.reentrantCompletion(alias)
        case .completed:
            throw XLRecursiveCommonTableConstructionError.alreadyCompleted(alias)
        }
    }

    ///
    /// Rolls an in-progress completion back to the declared state. A no-op when
    /// the draft is not currently building.
    ///
    public mutating func rollbackCompletion() {
        guard case .building = state else {
            return
        }
        state = .declared
    }

    ///
    /// Returns the reserved alias once the draft has completed, or throws
    /// ``XLRecursiveCommonTableConstructionError/incomplete(_:)`` otherwise.
    ///
    public func completedAlias() throws -> XLName {
        guard case .completed = state else {
            throw XLRecursiveCommonTableConstructionError.incomplete(alias)
        }
        return alias
    }

    ///
    /// Validates a completed body's column aliases against the declared result
    /// layout, throwing ``XLRecursiveCommonTableConstructionError/resultLayoutMismatch(alias:expected:actual:)``
    /// when they differ. Used by callers that can observe the body's columns.
    ///
    public func validateResultLayout(actualColumns: [XLName]) throws {
        guard layout.resultColumns == actualColumns else {
            throw XLRecursiveCommonTableConstructionError.resultLayoutMismatch(
                alias: alias,
                expected: layout.resultColumns,
                actual: actualColumns
            )
        }
    }
}


///
/// Validates that a set of common-table definitions reserve distinct aliases,
/// throwing ``XLRecursiveCommonTableConstructionError/duplicateAlias(_:)`` for
/// the first collision. Alias comparison is case-insensitive, matching SQLite's
/// identifier resolution.
///
public func xlValidateUniqueCommonTableAliases(
    _ definitions: [XLCommonTableDependency]
) throws {
    var seen: Set<String> = []
    for definition in definitions {
        let key = definition.alias.rawValue.lowercased()
        guard seen.insert(key).inserted else {
            throw XLRecursiveCommonTableConstructionError.duplicateAlias(definition.alias)
        }
    }
}


///
/// A never-rendering placeholder body for the alias-only self-reference used
/// during recursive CTE construction.
///
/// A recursive self-reference needs only the reserved alias; it must never
/// retain or render the definition that is completed afterwards. Rendering this
/// body indicates a construction bug (a reference retained a body), so it traps.
///
struct XLAliasOnlyCommonTableBody: XLEncodable {
    func makeSQL(context: inout XLBuilder) {
        preconditionFailure(
            "An alias-only recursive CTE self-reference must not render a definition body."
        )
    }
}


///
/// Reference layout for the generated composite-row recursive CTE surface.
///
/// Derives a `T.MetaCommonTable.Result.MetaNamedResult` self-reference from only
/// the reserved alias, by building an alias-only common-table dependency and
/// projecting it through the body schema's `table(_:)`.
///
struct XLCompositeRecursiveCommonTableLayout<T>: XLRecursiveCommonTableReferenceLayout where T: XLResult {

    let schema: XLSchema
    let commonTableNamespace: XLNamespace

    func makeReference(cteAlias: XLName) -> T.MetaCommonTable.Result.MetaNamedResult {
        let dependency = XLCommonTableDependency(
            alias: cteAlias,
            statement: XLAliasOnlyCommonTableBody()
        )
        let commonTable = T.makeSQLCommonTable(
            namespace: commonTableNamespace,
            dependency: dependency
        )
        return schema.table(commonTable)
    }
}
