//
//  StringFunctions.swift
//  
//
//  Created by Luke Van In on 2023/09/08.
//

import Foundation


/// A SQLite collating sequence.
///
/// The three built-in sequences are provided as static members. A collation
/// registered on the connection is named with ``init(rawValue:)``.
///
/// Built-in names render as bare grammar tokens — `COLLATE NOCASE` — while a
/// custom name renders as a quoted identifier — `COLLATE "myCollation"`. Both
/// forms are equivalent to SQLite, which resolves either spelling to the same
/// collating sequence and reports `no such collation sequence` when it is not
/// registered. The distinction exists because a custom name is caller-supplied
/// text: quoting it through the identifier formatter keeps issue #169's
/// guarantee that `collate(_:)` is not an arbitrary raw-SQL escape hatch.
///
/// https://www.sqlite.org/datatype3.html#collation
///
public struct XLCollation: RawRepresentable, Hashable, Sendable {

    public let rawValue: String

    let isBuiltIn: Bool

    ///
    /// Names a collating sequence registered on the connection.
    ///
    /// The name is rendered as a quoted identifier, so it cannot inject SQL.
    /// Registering the sequence is the application's responsibility; SQLite
    /// reports `no such collation sequence` at preparation otherwise.
    ///
    public init(rawValue: String) {
        self.rawValue = rawValue
        self.isBuiltIn = false
    }

    private init(builtIn rawValue: String) {
        self.rawValue = rawValue
        self.isBuiltIn = true
    }

    public static let binary = XLCollation(builtIn: "BINARY")

    public static let nocase = XLCollation(builtIn: "NOCASE")

    public static let rtrim = XLCollation(builtIn: "RTRIM")

    // Equality is the name alone. `isBuiltIn` only selects bare-token versus
    // quoted-identifier rendering, and both spellings resolve to the same
    // collating sequence in SQLite, so synthesised conformances including it
    // would make `.nocase` and `XLCollation(rawValue: "NOCASE")` unequal and
    // hash apart despite naming one sequence.
    public static func ==(lhs: XLCollation, rhs: XLCollation) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}


private struct XLCollationExpression<T>: XLExpression {

    let operand: any XLExpression

    let collation: XLCollation

    func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            if collation.isBuiltIn {
                context.unarySuffix(
                    "COLLATE " + collation.rawValue,
                    expression: operand.makeSQL
                )
            }
            else {
                // Two tokens rather than one interpolated string: the name goes
                // through the identifier formatter, which escapes it. The
                // enclosing builder joins tokens with a space.
                context.unarySuffix("COLLATE", expression: operand.makeSQL)
                context.name(XLName(collation.rawValue))
            }
        }
    }
}


extension XLExpression {
    
    public func collate(_ collation: XLCollation) -> some XLExpression<String> where T == String {
        XLCollationExpression<String>(operand: self, collation: collation)
    }
    
    public func collate(_ collation: XLCollation) -> some XLExpression<Optional<String>> where T == Optional<String> {
        XLCollationExpression<Optional<String>>(
            operand: self,
            collation: collation
        )
    }
}


public func printf(format: String, _ parameters: any XLExpression ...) -> some XLExpression<String> {
    XLFunction(name: "printf", parameters: [format] + parameters)
}


public func printf(format: String, _ parameters: [any XLExpression]) -> some XLExpression<String> {
    XLFunction(name: "printf", parameters: [format] + parameters)
}
