import Foundation

import RegexBuilder
import SwiftQL

/// Finding the to-dos whose notes carry a web link.
///
/// The demo's other regular expression is the search box, which has to be a
/// string pattern: it changes with every keystroke, and it travels as a bound
/// parameter so one rendered statement serves every search. This one is the
/// opposite case, and it is why ``XLRegexPattern`` exists.
///
/// The pattern is fixed, so it is written once, in Swift, with the pieces
/// named:
///
/// ```swift
/// Regex {
///     "http"
///     Optionally("s")
///     "://"
///     OneOrMore(.whitespace.inverted)
/// }
/// ```
///
/// The same thing as a string is `https?://\S+`, which is shorter and worse:
/// nothing checks it, `\S` has to be remembered rather than read, and it
/// cannot be assembled from parts. `RegexBuilder` gives all three back, and
/// SwiftQL can match it in SQLite because ``XLRegexPattern`` registers the
/// compiled `Regex` and sends SQLite a key that names it.
///
/// ## Why this read is not in the validation manifest
///
/// A registry key names a registration in one process. The demo's manifest is
/// a checked-in file, regenerated and compared byte for byte by
/// `scripts/ci/check-todo-demo.sh`, so a statement carrying a key would
/// produce a different manifest on every run and fail that check — correctly.
/// SwiftQL refuses the same thing at the API: building an
/// `XLStaticStatementDefinition` from such a statement throws
/// `processLocalRegexPattern`.
///
/// So a pattern like this belongs in a read executed at runtime, and a search
/// that has to be validated at build time belongs in a string pattern. The
/// demo does both, which is the point of having both.
public enum TodoLinks {

    /// The list whose to-dos are examined.
    static let listID = XLNamedBindingReference<TodoUUID>(name: "listID")

    /// Matches an `http` or `https` URL anywhere in a note.
    ///
    /// Held in a `static let` because the registry does not keep a pattern
    /// alive. One that went out of scope would leave its key unresolvable, and
    /// the next search using it would report that rather than quietly
    /// returning nothing.
    public static let pattern = XLRegexPattern {
        "http"
        Optionally("s")
        "://"
        OneOrMore(.whitespace.inverted)
    }

    /// The identifiers of the to-dos in one list whose notes hold a link.
    ///
    /// Only the identifiers: the view draws a glyph, so no note text needs to
    /// cross the boundary for it.
    public static var statement: any XLQueryStatement<TodoUUID> {
        sql { schema in
            let todo = schema.table(Todo.self)
            Select(todo.id)
            From(todo)
            Where(todo.listID == listID && todo.notes.regexp(pattern))
        }
    }

    /// Builds the packet for one call.
    static func bindings(
        for listID: TodoUUID,
        layout: XLParameterLayout
    ) throws -> XLInvocationBindings<XLSQLiteValue> {
        guard let slot = layout.slot(for: .named("listID")) else {
            throw TodoFilteredReadError.unknownParameter("listID")
        }
        return try XLInvocationBindings<XLSQLiteValue>(
            layout: layout,
            bindings: [
                try XLInvocationBinding(slot: slot, value: listID.sqlValue),
            ]
        ).validatingComplete()
    }
}
