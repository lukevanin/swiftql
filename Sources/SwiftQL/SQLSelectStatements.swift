//
//  SQLSelectStatements.swift
//  SwiftQL
//
//  Reading statements: SELECT and the compound operators that combine several
//  of them, and the WITH clause that names one.
//
//  Split out of SQLStatements.swift (issue #559).
//

import Foundation


public protocol XLQueryComponent: XLEncodable {

}


///
/// A clause of a statement in one dialect, such as `Select`, `From`, or
/// `Where`.
///
/// A statement's result builder, such as ``XLDialectQueryExpressionBuilder``,
/// takes a clause only when it belongs to the builder's dialect, so a clause
/// built from another dialect's tables or expressions is a compile error at
/// the clause (issue #822). The builder's dialect is also the context in which
/// the clause's initializer is chosen, so a clause built from values alone,
/// such as `Where(true)`, takes the statement's dialect.
///
public protocol XLDialectClause {

    /// The dialect of the statement the clause belongs to.
    associatedtype Dialect: XLSQLDialect
}


// MARK: Select


///
/// A select clause of any dialect, as declared-query lowering reads it.
///
protocol XLSelectProjection {

    /// The static row layout the select projects, when it was built from one.
    var staticLayout: (any XLStaticRowReadable)? { get }
}


///
/// A select statement.
///
/// `Dialect` is the dialect of the statement. The projection must belong to
/// it: a table or a result of a model declared for `Dialect`, a static row
/// layout for `Dialect`, or an expression of `Dialect` (issue #822).
///
public struct Select<Row, Dialect>: XLEncodable, XLRowReadable, XLDialectClause, XLSelectProjection where Dialect: XLSQLDialect {

    private let fields: any XLEncodable

    private let row: (XLRowReader) throws -> Row

    /// The static row layout this select projects, when it was built from
    /// one. Declared-query lowering reads the layout's metadata instead of
    /// replaying a row reader that reads raw dialect values (issue #659).
    var staticLayout: (any XLStaticRowReadable)? {
        fields as? any XLStaticRowReadable
    }

    /// Builds a select directly from immutable static projection metadata.
    ///
    /// This more-specific overload deliberately does not call `readRow` while
    /// constructing the statement. Generated model initializers and
    /// contextual codecs run only when a returned database row is decoded.
    public init<T>(_ layout: T)
    where T: XLStaticRowReadable, T.Row == Row, T.XLModelDialect == Dialect {
        self.fields = layout
        self.row = layout.readRow
    }

    /// Builds a select from dynamic projection metadata.
    ///
    /// The projection is replayed once against a definition reader to capture
    /// its output columns. The definition reader returns SQL defaults, so no
    /// database row is decoded here. The replay runs only for that side effect,
    /// and its value is discarded.
    ///
    /// `readRow(reader:)` is throwing and may be implemented outside this
    /// package. A projection that cannot enumerate its columns against the
    /// definition reader is unsupported here and traps diagnostically, rather
    /// than surfacing an opaque `try!` crash. This matches `Returning.init(_:)`.
    ///
    /// A static row layout belongs to the ``XLStaticRowReadable`` overload
    /// above, which skips the replay. A generic caller that sees a layout only
    /// as `XLRowReadable` reaches this initializer instead, so it checks for a
    /// static layout at run time and uses the same non-replaying path.
    public init<T>(_ meta: T) where T: XLRowReadable & XLDialectBound, T.Row == Row, T.XLModelDialect == Dialect {
        if let layout = meta as? any XLStaticRowReadable {
            self.fields = layout
            self.row = meta.readRow
            return
        }
        let reader = XLColumnsDefinitionRowReader()
        do {
            _ = try meta.readRow(reader: reader)
        }
        catch {
            preconditionFailure(
                "SELECT projection \(String(reflecting: T.self)) could not "
                + "enumerate its columns: \(error). Use a table or @SQLResult "
                + "projection whose columns render against the definition "
                + "reader, or a static row layout."
            )
        }
        self.fields = reader
        self.row = meta.readRow
    }

    public func makeSQL(context: inout XLBuilder) {
        context.unaryPrefix("SELECT", expression: fields.makeSQL)
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try row(reader)
    }

    /// Builds a scalar select from an expression that belongs to `Dialect`.
    /// Used by the generated initializers, which take only `Dialect`'s
    /// expressions.
    ///
    /// The logical result type is unconstrained. Bare contextual values can be
    /// rendered by this initializer, but their row decoding still requires an
    /// ``XLStaticRowLayout`` carrying codec metadata. The legacy path reports
    /// ``XLStaticRowReadError/staticLayoutRequired(valueType:alias:)``
    /// instead of fabricating a value.
    @_spi(XLDialectSurface)
    public init(_dialectSurface expression: any XLExpression<Row>) {
        self.fields = expression
        self.row = { reader in
            try reader.staticColumn(expression, alias: "c0")
        }
    }

    /// Builds a scalar select from a closure that returns an expression that
    /// belongs to `Dialect`. The closure is evaluated again for each row the
    /// select decodes. Used by the generated initializers.
    @_spi(XLDialectSurface)
    public init(_dialectSurfaceBuilder expression: @escaping () -> any XLExpression<Row>) {
        self.fields = expression()
        self.row = { reader in
            try reader.staticColumn(expression(), alias: "c0")
        }
    }
}


// MARK: - Union


///
/// A boolean set operation, such as a union or intersection.
///
internal struct BooleanClause<Row>: XLEncodable, XLRowReadable {
    
    enum Kind {
        case union
        case unionAll
        case except
        case intersect
    }
    
    private let kind: Kind

    private let lhs: any XLEncodable

    private let rhs: any XLEncodable

    private let row: (XLRowReader) throws -> Row

    /// The first clause of the right-hand branch that SQLite would apply to
    /// the whole compound, or that it does not accept after the operator.
    private let unsupportedBranchClause: String?

    ///
    /// Combines two branches, preserving the first branch's existing row reader.
    ///
    /// The compound result decodes with the same reader as its left branch
    /// rather than reconstructing metadata from `Row: XLResult`, so a direct
    /// scalar branch (`select(expr)`) flows through `UNION` / `UNION ALL` /
    /// `INTERSECT` / `EXCEPT` without a boxed `@SQLResult` wrapper.
    ///
    internal init(kind: Kind, lhs: XLQueryStatementComponents<Row>, rhs: any XLEncodable) {
        self.kind = kind
        self.lhs = lhs
        self.rhs = rhs
        self.row = lhs.readRow
        self.unsupportedBranchClause = Self.unsupportedClause(inBranch: rhs)
    }

    /// Finds a `WITH`, `ORDER BY`, `LIMIT`, or `OFFSET` clause in a right-hand
    /// branch, or a right-hand branch that is itself a compound (issue #657).
    ///
    /// The compound methods accept any `XLQueryStatement`, so that callers who
    /// pass an erased statement keep compiling. The check therefore runs here,
    /// and the compound reports the clause when it renders, before SQLite
    /// prepares the statement. Only the branch's own top-level clauses are
    /// read: a subquery or common table inside the branch may have its own.
    ///
    /// A nested compound is rejected because SQLite groups compound operators
    /// from the left: `a EXCEPT (b UNION c)` would render as
    /// `a EXCEPT b UNION c`. Its first branch could also carry a `WITH` list.
    private static func unsupportedClause(inBranch branch: any XLEncodable) -> String? {
        guard let components = branch as? XLQueryStatementComponents<Row> else {
            return nil
        }
        if !components.commonTables.isEmpty {
            return "WITH"
        }
        for component in components.components {
            if let nested = component as? BooleanClause<Row> {
                return nested.operatorKeyword
            }
            // `ORDER BY`, `LIMIT`, and `OFFSET` are generic over the
            // dialect, so they are recognised by a protocol rather than by
            // their types.
            if let clause = component as? any XLCompoundTrailingClause {
                return type(of: clause).sqlKeyword
            }
        }
        return nil
    }

    /// The SQL keyword of this compound operator.
    var operatorKeyword: String {
        switch kind {
        case .union:
            return "UNION"
        case .unionAll:
            return "UNION ALL"
        case .intersect:
            return "INTERSECT"
        case .except:
            return "EXCEPT"
        }
    }

    public func makeSQL(context: inout XLBuilder) {
        let op = operatorKeyword
        if let unsupportedBranchClause {
            context.valueEncodingFailed(
                .unsupportedCompoundBranchClause(
                    compoundOperator: op,
                    clause: unsupportedBranchClause
                )
            )
        }
        context.binaryOperator(op, left: lhs.makeSQL, right: rhs.makeSQL(context:))
    }

    public func readRow(reader: XLRowReader) throws -> Row {
        try row(reader)
    }
}


///
/// Union clause.
///
/// Combines two queries, and returns the rows returned by the first query followed by the rows returned by
/// the second query.
///
/// Duplicate rows are excluded.
///
/// > Note: Both queries must return the same row type.
///
/// `Dialect` is the dialect of the query, which its result builder supplies
/// (issue #822); `Union()` names none. The same holds for `UnionAll`,
/// `Intersect`, and `Except`.
///
public struct Union<Dialect>: XLDialectClause where Dialect: XLSQLDialect {
    public init() {
        
    }
}


///
/// Union all clause.
///
/// Combines two queries, and returns the rows returned by the first query followed by the rows returned by
/// the second query.
///
/// Duplicate rows are included.
///
/// > Note: Both queries must return the same row type.
///
public struct UnionAll<Dialect>: XLDialectClause where Dialect: XLSQLDialect {
    public init() {
        
    }
}


///
/// Intersect clause.
///
/// Combines two queries, and returns only the rows which are returned by both queries.
///
/// > Note: Both queries must return the same row type.
///
public struct Intersect<Dialect>: XLDialectClause where Dialect: XLSQLDialect {
    public init() {
        
    }
}


///
/// Except clause.
///
/// Combines two queries, and returns the rows from the first query which do not exist in the second query.
///
/// > Note: Both queries must return the same row type.
///
public struct Except<Dialect>: XLDialectClause where Dialect: XLSQLDialect {
    public init() {
        
    }
}


// MARK: - With


///
/// With clause.
///
/// Specifies common tables used in a select, update, insert, or delete statement.
///
/// Every common table must belong to `Dialect`, the statement's dialect
/// (issue #822).
///
public struct With<Dialect>: XLDialectClause where Dialect: XLSQLDialect {

    internal let commonTables: [XLCommonTableDependency]

    public init(_ tables: any XLDialectCommonTable<Dialect>...) {
        self.commonTables = tables.map { $0.definition }
    }

    /// Specifies one common table, such as a scalar common table. The same as
    /// the variadic form, which it precedes so that a common table of another
    /// dialect is reported as a mismatch of the two dialects.
    public init<T>(_ table: T) where T: XLDialectCommonTable, T.XLModelDialect == Dialect {
        self.commonTables = [table.definition]
    }

    /// Specifies common tables from definitions that belong to `Dialect`.
    /// A definition does not record its dialect, so this is SwiftQL's
    /// dialect-surface SPI, not public API.
    @_spi(XLDialectSurface)
    public init(_dialectSurface commonTables: [XLCommonTableDependency]) {
        self.commonTables = commonTables
    }
}
