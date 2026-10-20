//
//  TextOperators.swift
//  
//
//  Created by Luke Van In on 2023/08/01.
//

import Foundation



// MARK: - LIKE


///
/// A typed `LIKE` expression with an explicit `ESCAPE` clause.
///
/// Example:
///
/// *Swift:*
/// ```swift
/// name.like(pattern, escape: "\\")
/// ```
///
/// *SQL:*
/// ```SQL
/// (name LIKE pattern ESCAPE '\')
/// ```
///
/// `ESCAPE` binds to its `LIKE`, so the three operands render as one grammar
/// production rather than a nested binary expression.
///
public struct XLLikeEscapeExpression<T>: XLExpression {

    private let term: any XLExpression

    private let pattern: any XLExpression

    private let escape: any XLExpression

    /// SwiftQL's dialect-surface SPI, for a dialect's generated operators: a
    /// node built here belongs to every dialect, so it is not public API
    /// (issue #822).
    @_spi(XLDialectSurface)
    public init(
        term: any XLExpression,
        pattern: any XLExpression,
        escape: any XLExpression
    ) {
        self.term = term
        self.pattern = pattern
        self.escape = escape
    }

    public func makeSQL(context: inout XLBuilder) {
        context.parenthesis { context in
            context.binaryOperator(
                "LIKE",
                left: term.makeSQL,
                right: { context in
                    context.binaryOperator(
                        "ESCAPE",
                        left: pattern.makeSQL,
                        right: escape.makeSQL
                    )
                }
            )
        }
    }
}
