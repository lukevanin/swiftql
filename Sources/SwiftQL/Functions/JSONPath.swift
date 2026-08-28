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
/// XLJSONPath.root.key("address").key("city")   // $."address"."city"
/// XLJSONPath.root.key("items").index(0)        // $."items"[0]
/// XLJSONPath.root.key("items").last            // $."items"[#-1]
/// XLJSONPath.root                              // $
/// ```
///
/// A path is a text operand. It renders through the same formatter as every
/// other text value, so it is not a way to put raw SQL into a statement.
///
/// ## Why every key is quoted
///
/// SQLite reads an unquoted key up to the next `.` or `[`, so the key
/// `a.b` written as `$.a.b` selects `b` inside `a` instead of the key named
/// `a.b`. A key may instead be enclosed in double quotes, where SQLite parses
/// it as a JSON string. This type always uses the quoted form and escapes the
/// key with JSON string escapes. One rendering for every key means a key that
/// holds a `.`, a `[`, a `]`, or a `"` names that key, and a caller does not
/// have to know which characters are special.
///
/// See: https://www.sqlite.org/json1.html#path_arguments
///
public struct XLJSONPath: XLExpression, Hashable, Sendable, CustomStringConvertible {

    public typealias T = String

    ///
    /// The rendered path text, for example `$."items"[0]`.
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
    /// The name is always rendered in SQLite's quoted form, so any name selects
    /// the key that carries it.
    ///
    public func key(_ name: String) -> XLJSONPath {
        XLJSONPath(path: path + ".\"" + Self.escaped(name) + "\"")
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
