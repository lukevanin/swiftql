//
//  JSONOperators.swift
//
//
//  Milestone v1.6: SQLite's two JSON selection operators, `->` and `->>`.
//

import Foundation


///
/// A SQLite JSON selection expression: `document -> path` or
/// `document ->> path`.
///
/// The two operators select the same element and differ only in what they
/// return. See ``XLExpression/jsonElement(at:)`` and
/// ``XLExpression/jsonValue(at:as:)``.
///
public struct XLJSONSelectionExpression<T>: XLExpression {

    private let `operator`: String

    private let document: any XLExpression

    private let path: any XLExpression

    init(
        operator: String,
        document: any XLExpression,
        path: any XLExpression
    ) {
        self.operator = `operator`
        self.document = document
        self.path = path
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                `operator`,
                left: document.makeSQL,
                right: path.makeSQL
            )
        }
    }
}


///
/// SQLite's JSON selection operators, added in SQLite 3.38.0.
///
/// See: https://www.sqlite.org/json1.html#jptr
///
/// ## Why these are methods and not operators
///
/// `->` cannot be a Swift operator. The compiler reserves the token and
/// reports `cannot declare a custom 'infix' '->' operator`. `->>` could be
/// declared, but one operator and one method for two spellings of the same
/// idea reads worse than two methods, so both are methods.
///
/// ## Why the bare-name form is not exposed
///
/// SQLite also accepts a bare key name or an array index on the right, and
/// expands `'name'` to `$.name` and `3` to `$[3]`. That form names one key
/// only and does not compose. ``XLJSONPath/key(_:)`` already names any single
/// key, and it composes, so the shorthand would be a second way to write what
/// the path type covers.
///
extension XLExpression {

    ///
    /// Selects the element at `path` and returns it as JSON text, rendering
    /// SQLite's `->` operator.
    ///
    /// The result is always text. A selected string keeps its JSON quotes:
    /// `'{"a":"x"}' -> '$.a'` is the three characters `"x"`. A JSON `null` is
    /// the four characters `null`, not SQL `NULL`. Only a path that matches
    /// nothing gives SQL `NULL`, which is why the result is optional.
    ///
    /// Use ``jsonValue(at:as:)`` to read an element as a SQL value instead.
    ///
    public func jsonElement(at path: XLJSONPath) -> some XLExpression<String?>
    where T: XLLiteral {
        XLJSONSelectionExpression<String?>(
            operator: "->",
            document: self,
            path: path
        )
    }

    ///
    /// Selects the element at `path` and returns it as a SQL value, rendering
    /// SQLite's `->>` operator.
    ///
    /// The result type follows the selected element: a JSON string is TEXT
    /// without its quotes, a number is INTEGER or REAL, and a JSON `null` is
    /// SQL `NULL`. An object or an array has no SQL value, so SQLite returns
    /// its JSON text.
    ///
    /// The result is optional for every value type, because a path that
    /// matches nothing and a JSON `null` both give SQL `NULL`.
    ///
    public func jsonValue<Value>(
        at path: XLJSONPath,
        as type: Value.Type
    ) -> some XLExpression<Value?> where T: XLLiteral, Value: XLLiteral {
        XLJSONSelectionExpression<Value?>(
            operator: "->>",
            document: self,
            path: path
        )
    }
}
