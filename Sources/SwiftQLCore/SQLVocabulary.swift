import Foundation


///
/// A comparison whose spelling differs between dialects.
///
/// SQLite accepts `==` for equality and spells a null-safe comparison `IS`.
/// PostgreSQL rejects both: it spells equality `=` and a null-safe comparison
/// `IS NOT DISTINCT FROM`. A node names the comparison it means and the
/// dialect decides the text.
///
public enum XLComparisonOperator: Hashable, Sendable {

    /// Equality between two operands that cannot be `NULL`.
    case equal

    /// Inequality between two operands that cannot be `NULL`.
    case notEqual

    /// Equality that treats `NULL` as a comparable value.
    case nullSafeEqual

    /// Inequality that treats `NULL` as a comparable value.
    case nullSafeNotEqual
}


///
/// A test for `NULL`.
///
/// SQLite accepts the postfix `ISNULL` and `NOTNULL` keywords. Standard SQL
/// spells these `IS NULL` and `IS NOT NULL`.
///
public enum XLNullTest: Hashable, Sendable {
    case isNull
    case isNotNull
}


///
/// The keyword that introduces a common-table expression.
///
/// SQLite accepts a recursive common table after a plain `WITH`. Several
/// dialects require `WITH RECURSIVE`.
///
public enum XLCommonTablePrefix: Hashable, Sendable {
    case with
    case withRecursive
}


///
/// A regular-expression match.
///
/// SQLite has no built-in `REGEXP` implementation: the operator is grammar
/// that resolves to an application-supplied function. PostgreSQL spells the
/// same match `~`.
///
public enum XLRegexMatchOperator: Hashable, Sendable {
    case matches
}


///
/// Spells the SQL vocabulary whose text differs between dialects.
///
/// A dialect vends its vocabulary through ``XLSQLDialect/makeVocabulary()``.
/// Expression and statement nodes name the operation they mean and never the
/// keyword, so a second dialect changes the rendered SQL by conforming here
/// rather than by editing every node.
///
/// The vocabulary holds only the lexical set: operations that every dialect
/// performs with identical semantics and that differ only in spelling. A
/// vocabulary can spell a keyword; it cannot refuse an operation. An
/// operation that one dialect lacks, or performs differently, therefore does
/// not belong here, because a dialect that conformed would mis-render it
/// instead of rejecting it (see the dialect surface separation decision
/// record). Such an operation is declared by the dialect's own product, so a
/// dialect that does not have it cannot reach it. The conflict clause of an
/// insert, a collating sequence, and the date modifiers are SQLite's, and
/// live in `SwiftQLSQLite`.
///
public protocol XLSQLVocabulary: Sendable {

    func spelling(for comparison: XLComparisonOperator) -> String

    func spelling(for test: XLNullTest) -> String

    func spelling(for prefix: XLCommonTablePrefix) -> String

    func spelling(for match: XLRegexMatchOperator) -> String

    ///
    /// The functions a statement needs registered on the connection that runs
    /// it, for a given operation.
    ///
    /// SQLite must be given an implementation of `regexp` before it can
    /// prepare a statement that uses the operator. A dialect whose engine
    /// implements the match natively returns an empty set, so the node that
    /// renders the match no longer decides a driver registration.
    ///
    func requiredFunctions(for match: XLRegexMatchOperator) -> Set<XLCustomFunctionDefinition>
}
