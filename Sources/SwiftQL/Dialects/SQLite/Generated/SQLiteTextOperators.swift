//
//  SQLiteTextOperators.swift
//
//  Generated for SQLite by scripts/dialect-surface/generate.py
//  from scripts/dialect-surface/Templates/TextOperators.swift.template.
//  Do not edit: edit the template, then run
//  `python3 scripts/dialect-surface/generate.py`.
//

import Foundation


// MARK: - Concatenation


public func +(lhs: any XLSQLiteExpression<String>, rhs: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<String> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLSQLiteExpression<String>, rhs: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLSQLiteExpression<Optional<String>>, rhs: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Optional<String>>{
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}

public func +(lhs: any XLSQLiteExpression<Optional<String>>, rhs: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<String>> {
    XLConcatenationExpression(op: "||", lhs: lhs, rhs: rhs)
}


// MARK: - LIKE


extension XLSQLiteExpression {

    public func like(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    public func like(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "LIKE", lhs: self, rhs: other)
    }

    ///
    /// Matches `other` as a `LIKE` pattern in which `escape` marks the next
    /// character as a literal, so `%` and `_` can be matched exactly.
    ///
    /// SQLite requires `escape` to evaluate to a single character. A longer or
    /// empty value prepares successfully and then fails when the statement is
    /// stepped, with `ESCAPE expression must be a single character`. That is a
    /// constraint on the value, not something the Swift type can express.
    ///
    public func like(
        _ other: any XLSQLiteExpression<String>,
        escape: any XLSQLiteExpression<String>
    ) -> some XLSQLiteExpression<Bool> where T == String {
        XLLikeEscapeExpression<Bool>(term: self, pattern: other, escape: escape)
    }

    public func like(
        _ other: any XLSQLiteExpression<Optional<String>>,
        escape: any XLSQLiteExpression<String>
    ) -> some XLSQLiteExpression<Optional<Bool>> where T == String {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    public func like(
        _ other: any XLSQLiteExpression<String>,
        escape: any XLSQLiteExpression<String>
    ) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }

    public func like(
        _ other: any XLSQLiteExpression<Optional<String>>,
        escape: any XLSQLiteExpression<String>
    ) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLLikeEscapeExpression<Optional<Bool>>(
            term: self,
            pattern: other,
            escape: escape
        )
    }
}


// MARK: - GLOB


extension XLSQLiteExpression {
    
    public func glob(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Bool> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == String {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLSQLiteExpression<String>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
    
    public func glob(_ other: any XLSQLiteExpression<Optional<String>>) -> some XLSQLiteExpression<Optional<Bool>> where T == Optional<String> {
        XLBinaryOperatorExpression(op: "GLOB", lhs: self, rhs: other)
    }
}
