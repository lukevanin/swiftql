//
//  JSONPath.swift
//
//
//  Milestone v1.6: a typed SQLite JSON path, built from segments instead of
//  written as a string literal at the call site.
//

import Foundation


///
/// A SQLite JSON path.
///
/// A path selects one element inside a JSON document. It starts at the
/// document root and adds one segment for each step down:
///
/// ```swift
/// XLJSONPath.root.key("address").key("city")   // $.address.city
/// XLJSONPath.root.key("items").index(0)        // $.items[0]
/// XLJSONPath.root.key("items").last            // $.items[#-1]
/// XLJSONPath.root                              // $
/// XLJSONPath.root.key("a.b")                   // $."a.b"
/// ```
///
/// A path is a text operand. It renders through the same formatter as every
/// other text value, so it is not a way to put raw SQL into a statement.
///
/// ## How a key is rendered
///
/// SQLite reads an unquoted key up to the next `.` or `[`, so the key `a.b`
/// written as `$.a.b` selects `b` inside `a` instead of the key named `a.b`.
/// A key may instead be enclosed in double quotes, where SQLite parses it as
/// a JSON string.
///
/// A key is quoted only when it has to be: when it is empty, or when it holds
/// a `.` or a `[`. Those are the two characters that end an unquoted label,
/// and an empty name has no unquoted spelling. Every other key is rendered as
/// it is, which keeps the rendered SQL readable.
///
/// ## One key shape is not portable
///
/// A key holding a `"`, a `\`, or a control character has **no** spelling
/// that resolves on every supported SQLite. JSON stores such a key escaped:
/// the key `a"b` is written `"a\"b"` in the document. Older SQLite matches a
/// path label against that raw, still-escaped text, and newer SQLite unescapes
/// both sides first, so the two want different path text and neither accepts
/// the other's.
///
/// SwiftQL renders for the newer behaviour, which is what SQLite documents.
/// On an older engine such a path selects nothing rather than reporting an
/// error. Every other key — including `.`, `[`, `]`, `#`, non-ASCII text, and
/// the empty name — resolves the same way on every supported SQLite.
///
/// See: https://www.sqlite.org/json1.html#path_arguments
///
public struct XLJSONPath: XLExpression, Hashable, Sendable, CustomStringConvertible {

    public typealias T = String

    ///
    /// The rendered path text, for example `$.items[0]`, or `$."a.b"` for a
    /// key the grammar forces into the quoted form.
    ///
    public let path: String

    private init(path: String) {
        self.path = path
    }

    ///
    /// The document root, `$`.
    ///
    public static let root = XLJSONPath(path: "$")

    ///
    /// Adds an object member.
    ///
    /// The name is quoted only when SQLite's path grammar needs it: when the
    /// name is empty, or when it holds a `.` or a `[`. A name holding a `"`,
    /// a `\`, or a control character resolves only on a SQLite that unescapes
    /// JSON labels; see the type's documentation.
    ///
    public func key(_ name: String) -> XLJSONPath {
        guard Self.needsQuoting(name) else {
            return XLJSONPath(path: path + "." + name)
        }
        return XLJSONPath(path: path + ".\"" + Self.escaped(name) + "\"")
    }

    ///
    /// Adds an array element, counted from the start.
    ///
    /// SQLite has no negative array index: `$.items[-1]` is a path error, which
    /// SQLite reports when it prepares the statement. A negative index is
    /// therefore a mistake at the call site, and this method stops with a
    /// diagnostic message rather than building a path that cannot prepare.
    /// Use ``last`` or ``index(fromEnd:)`` to count from the end.
    ///
    public func index(_ index: Int) -> XLJSONPath {
        precondition(
            index >= 0,
            """
            XLJSONPath.index(_:) needs an index of zero or more, and was given \
            \(index). SQLite rejects a negative array index. Use \
            XLJSONPath.last or XLJSONPath.index(fromEnd:) to count backwards \
            from the last element.
            """
        )
        return XLJSONPath(path: path + "[\(index)]")
    }

    ///
    /// Adds the last array element, rendered as `[#-1]`.
    ///
    public var last: XLJSONPath {
        index(fromEnd: 1)
    }

    ///
    /// Names the position one past the last array element, rendered as `[#]`.
    ///
    /// Nothing is there to select, so a read through this path is always
    /// `NULL`. Its use is writing: `json_insert(x, '$[#]', v)` is SQLite's
    /// idiom for appending to an array, and it is the reason `[#]` exists in
    /// the path grammar at all.
    ///
    /// ```swift
    /// XLJSONPath.root.key("items").appended     // $.items[#]
    /// ```
    ///
    /// The write itself is `json_insert`, which this milestone adds
    /// separately; this type only names the position.
    ///
    public var appended: XLJSONPath {
        XLJSONPath(path: path + "[#]")
    }

    ///
    /// Adds an array element, counted back from the end.
    ///
    /// An offset of `1` is the last element, `2` the one before it. SQLite
    /// spells this `[#-N]`, where `#` is the number of elements. An offset of
    /// zero is one place past the last element, which selects nothing, so this
    /// method stops with a diagnostic message instead.
    ///
    public func index(fromEnd offset: Int) -> XLJSONPath {
        precondition(
            offset >= 1,
            """
            XLJSONPath.index(fromEnd:) needs an offset of one or more, and was \
            given \(offset). An offset of one is the last element. An offset of \
            zero is one place past the last element and selects nothing.
            """
        )
        return XLJSONPath(path: path + "[#-\(offset)]")
    }

    public var description: String {
        path
    }

    public func makeSQL(context: inout XLBuilder) {
        context.text(path)
    }

    ///
    /// Reports whether SQLite's path grammar forces this name into the quoted
    /// form. An empty name has no unquoted spelling, and `.` and `[` are the
    /// two characters that end an unquoted label.
    ///
    private static func needsQuoting(_ name: String) -> Bool {
        name.isEmpty || name.contains(".") || name.contains("[")
    }

    ///
    /// Escapes a key with JSON string escapes, which is how SQLite reads a
    /// quoted path label.
    ///
    private static func escaped(_ name: String) -> String {
        var result = ""
        result.reserveCapacity(name.unicodeScalars.count)
        for scalar in name.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\u{08}":
                result += "\\b"
            case "\u{0C}":
                result += "\\f"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += "\\u" + String(format: "%04x", scalar.value)
                }
                else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
