//
//  SQLQueryClauses.swift
//  SwiftQL
//
//  The clauses that narrow, order, group, and bound a query: WHERE, ORDER BY
//  and its ordering terms, LIMIT, OFFSET, GROUP BY, and HAVING.
//
//  Split out of SQLStatements.swift (issue #559).
//
//  Each clause carries the dialect of the statement it belongs to. An
//  initializer that takes an expression takes it as an expression of that
//  dialect, so each dialect's surface declares those initializers, from
//  scripts/dialect-surface/Templates/Clauses.swift.template (issue #822).
//  They call the `_dialectSurface` initializers here, which take any
//  expression and are SwiftQL's dialect-surface SPI, not public API.
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
/// `Dialect` is the dialect of the statement. The clause takes a condition of
/// that dialect only: a column of another dialect's model, or an expression
/// composed from one, is a compile error that names both dialects
/// (issue #822).
///
public struct Where<Dialect>: XLKeywordPrefixedClause, XLDialectClause where Dialect: XLSQLDialect {

    static var sqlKeyword: String { "WHERE" }

    var clauseExpression: any XLEncodable { condition }

    private let condition: any XLExpression

    /// Creates the clause from a condition that belongs to `Dialect`. Used by
    /// the generated initializers, which take only `Dialect`'s expressions.
    @_spi(XLDialectSurface)
    public init(_dialectSurface condition: any XLExpression) {
        self.condition = condition
    }
}


// MARK: - Order


///
/// An ordering term such as ascending or descending.
///
/// `Dialect` is the dialect of the expression the term orders by, so an
/// `ORDER BY` clause takes only terms of its statement's dialect.
///
public protocol XLOrderingTerm<Dialect>: XLEncodable {

    /// The dialect of the expression the term orders by.
    associatedtype Dialect: XLSQLDialect
}


///
/// Ascending ordering term used in an OrderBy expression.
///
public struct Ascending<Dialect>: XLOrderingTerm where Dialect: XLSQLDialect {

    private let expression: any XLExpression

    /// Creates the term from an expression that belongs to `Dialect`. Used by
    /// the generated initializers.
    @_spi(XLDialectSurface)
    public init(_dialectSurface expression: any XLExpression) {
        self.expression = expression
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unarySuffix("ASC", expression: expression.makeSQL)
    }
}


///
/// Descending ordering term used in an OrderBy expression.
///
public struct Descending<Dialect>: XLOrderingTerm where Dialect: XLSQLDialect {

    private let expression: any XLExpression

    /// Creates the term from an expression that belongs to `Dialect`. Used by
    /// the generated initializers.
    @_spi(XLDialectSurface)
    public init(_dialectSurface expression: any XLExpression) {
        self.expression = expression
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unarySuffix("DESC", expression: expression.makeSQL)
    }
}


///
/// Constructs a list of ordering term sub-expressions, all of one dialect.
///
@resultBuilder public struct XLOrderingTermsBuilder {
    public static func buildBlock<Dialect>(_ components: any XLOrderingTerm<Dialect>...) -> any XLEncodable {
        XLEncodableList(separator: .list, expressions: components)
    }
}


///
/// OrderBy clause.
///
/// Its terms order by expressions of `Dialect`, the statement's dialect.
///
public struct OrderBy<Dialect>: XLKeywordPrefixedClause, XLDialectClause where Dialect: XLSQLDialect {

    static var sqlKeyword: String { "ORDER BY" }

    var clauseExpression: any XLEncodable { orderingTerms }

    private let orderingTerms: XLEncodableList

    public init(_ terms: any XLOrderingTerm<Dialect>...) {
        self.init(terms: terms)
    }

    internal init(terms: [any XLOrderingTerm<Dialect>]) {
        self.orderingTerms = XLEncodableList(separator: .list, expressions: terms)
    }

}


// MARK: - Limit


///
/// Limit clause.
///
public struct Limit<Dialect>: XLKeywordPrefixedClause, XLDialectClause where Dialect: XLSQLDialect {

    static var sqlKeyword: String { "LIMIT" }

    var clauseExpression: any XLEncodable { count }

    private let count: any XLExpression

    /// Creates the clause from a count that belongs to `Dialect`. Used by the
    /// generated initializers, and by QueryBuilder's type-erased API, where
    /// SQLite validates at execution time that the expression evaluates to an
    /// integer or a value that can be losslessly converted to one.
    @_spi(XLDialectSurface)
    public init(_dialectSurface count: any XLExpression) {
        self.count = count
    }

}


// MARK: - Offset


///
/// Offset clause.
///
public struct Offset<Dialect>: XLKeywordPrefixedClause, XLDialectClause where Dialect: XLSQLDialect {

    static var sqlKeyword: String { "OFFSET" }

    var clauseExpression: any XLEncodable { count }

    private let count: any XLExpression

    /// Creates the clause from a count that belongs to `Dialect`. Used by the
    /// generated initializers, and by QueryBuilder's type-erased API.
    @_spi(XLDialectSurface)
    public init(_dialectSurface count: any XLExpression) {
        self.count = count
    }

}


// MARK: - Group By


///
/// GroupBy clause.
///
public struct GroupBy<Dialect>: XLKeywordPrefixedClause, XLDialectClause where Dialect: XLSQLDialect {

    static var sqlKeyword: String { "GROUP BY" }

    var clauseExpression: any XLEncodable { columns }

    private let columns: any XLEncodable

    /// Creates the clause from columns that belong to `Dialect`. Used by the
    /// generated initializers.
    @_spi(XLDialectSurface)
    public init(_dialectSurface columns: [any XLExpression]) {
        self.columns = XLEncodableList(separator: .list, expressions: columns)
    }

}


// MARK: - Having


///
/// Having clause.
///
/// Constrains a GroupBy clause.
///
public struct Having<Dialect>: XLKeywordPrefixedClause, XLDialectClause where Dialect: XLSQLDialect {

    static var sqlKeyword: String { "HAVING" }

    var clauseExpression: any XLEncodable { condition }

    private let condition: any XLExpression

    /// Creates the clause from a condition that belongs to `Dialect`. Used by
    /// the generated initializers.
    @_spi(XLDialectSurface)
    public init(_dialectSurface condition: any XLExpression) {
        self.condition = condition
    }

}
