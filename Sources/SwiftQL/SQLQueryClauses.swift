//
//  SQLQueryClauses.swift
//  SwiftQL
//
//  The clauses that narrow, order, group, and bound a query: WHERE, ORDER BY
//  and its ordering terms, LIMIT, OFFSET, GROUP BY, and HAVING.
//
//  Split out of SQLStatements.swift (issue #559).
//

import Foundation


///
/// A clause that renders as one SQL keyword followed by one expression.
///
/// `WHERE`, `ORDER BY`, `LIMIT`, `OFFSET`, `GROUP BY`, and `HAVING` are all
/// this shape. They differ in what they accept -- a boolean, a list of
/// ordering terms, an integer -- which is why each keeps its own initializers,
/// but their rendering was six copies of the same line with a different string
/// in it (issue #559). The keyword is now stated once per clause and the
/// rendering once for all of them.
///
protocol XLKeywordPrefixedClause: XLQueryComponent {

    /// The keyword this clause introduces.
    static var sqlKeyword: String { get }

    /// What follows the keyword.
    var clauseExpression: any XLEncodable { get }
}


extension XLKeywordPrefixedClause {

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix(Self.sqlKeyword, expression: clauseExpression.makeSQL)
    }
}


// MARK: - Where


///
/// Where clause.
///
public struct Where: XLKeywordPrefixedClause {

    static let sqlKeyword: String = "WHERE"

    var clauseExpression: any XLEncodable { condition }

    private let condition: any XLExpression
    
    init(_ condition: any XLExpression) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Bool>) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Optional<Bool>>) {
        self.condition = condition
    }

}


// MARK: - Order


///
/// An ordering term such as ascending or descending.
///
public protocol XLOrderingTerm: XLEncodable {
    
}


///
/// Ascending ordering term used in an OrderBy expression.
///
public struct Ascending: XLOrderingTerm {
    
    private let expression: any XLExpression
    
    public init(@XLScalarExpressionBuilder expression: () -> any XLExpression) {
        self.expression = expression()
    }
    
    public init(expression: any XLExpression) {
        self.expression = expression
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unarySuffix("ASC", expression: expression.makeSQL)
    }
}


///
/// Descending ordering term used in an OrderBy expression.
///
public struct Descending: XLOrderingTerm {
    
    private let expression: any XLExpression
    
    public init(@XLScalarExpressionBuilder expression: () -> any XLExpression) {
        self.expression = expression()
    }
    
    public init(expression: any XLExpression) {
        self.expression = expression
    }
    
    public func makeSQL(context: inout XLBuilder) {
        context.unarySuffix("DESC", expression: expression.makeSQL)
    }
}


///
/// Constructs a list of ordering term sub-expressions.
///
@resultBuilder public struct XLOrderingTermsBuilder {
    public static func buildBlock(_ components: XLOrderingTerm...) -> any XLEncodable {
        XLEncodableList(separator: .list, expressions: components)
    }
}


///
/// OrderBy clause.
///
public struct OrderBy: XLKeywordPrefixedClause {

    static let sqlKeyword: String = "ORDER BY"

    var clauseExpression: any XLEncodable { orderingTerms }

    private let orderingTerms: XLEncodableList
    
    public init(_ terms: any XLOrderingTerm...) {
        self.init(terms: terms)
    }
    
    internal init(terms: [any XLOrderingTerm]) {
        self.orderingTerms = XLEncodableList(separator: .list, expressions: terms)
    }

}


// MARK: - Limit


///
/// Limit clause.
///
public struct Limit: XLKeywordPrefixedClause {

    static let sqlKeyword: String = "LIMIT"

    var clauseExpression: any XLEncodable { count }

    private let count: any XLExpression
    
    public init(_ count: any XLExpression<Int>) {
        self.count = count
    }

    /// Preserves QueryBuilder's type-erased API. SQLite validates at execution time that the expression
    /// evaluates to an integer or a value that can be losslessly converted to one.
    init(unchecked count: any XLExpression) {
        self.count = count
    }
    
    public init(@XLScalarExpressionBuilder _ count: () -> any XLExpression<Int>) {
        self.count = count()
    }
    
}


// MARK: - Offset


///
/// Offset clause.
///
public struct Offset: XLKeywordPrefixedClause {

    static let sqlKeyword: String = "OFFSET"

    var clauseExpression: any XLEncodable { count }

    private let count: any XLExpression
    
    public init(_ count: any XLExpression<Int>) {
        self.count = count
    }

    /// Preserves QueryBuilder's type-erased API. SQLite validates at execution time that the expression
    /// evaluates to an integer or a value that can be losslessly converted to one.
    init(unchecked count: any XLExpression) {
        self.count = count
    }
    
    public init(@XLScalarExpressionBuilder _ count: () -> any XLExpression<Int>) {
        self.count = count()
    }
    
}


// MARK: - Group By


///
/// GroupBy clause.
///
public struct GroupBy: XLKeywordPrefixedClause {

    static let sqlKeyword: String = "GROUP BY"

    var clauseExpression: any XLEncodable { columns }

    private let columns: any XLEncodable
    
    public init(_ columns: any XLExpression...) {
        self.columns = XLEncodableList(separator: .list, expressions: columns)
    }

    public init(_ columns: [any XLExpression]) {
        self.columns = XLEncodableList(separator: .list, expressions: columns)
    }

}


// MARK: - Having


///
/// Having clause.
///
/// Constrains a GroupBy clause.
///
public struct Having: XLKeywordPrefixedClause {

    static let sqlKeyword: String = "HAVING"

    var clauseExpression: any XLEncodable { condition }

    private let condition: any XLExpression
    
    init(_ condition: any XLExpression) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Bool>) {
        self.condition = condition
    }
    
    public init(_ condition: any XLExpression<Optional<Bool>>) {
        self.condition = condition
    }

}
