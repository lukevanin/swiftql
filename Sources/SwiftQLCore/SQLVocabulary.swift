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
/// A conditional expression.
///
/// SQLite provides `IIF`. Dialects without it spell the same choice as
/// `CASE WHEN`, which is a different shape rather than a different name.
///
public enum XLConditionalFunction: Hashable, Sendable {
    case immediateIf
}


///
/// The grammatical shape a dialect uses for a conditional.
///
/// The two forms are not interchangeable spellings of one token, so a
/// vocabulary chooses the shape and the builder renders it.
///
public enum XLConditionalForm: Hashable, Sendable {

    /// `IIF(condition, whenTrue, whenFalse)`.
    case function(String)

    /// `CASE WHEN condition THEN whenTrue ELSE whenFalse END`.
    case caseWhen
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
/// A conflict-resolution algorithm applied by an `INSERT OR ...` statement.
///
/// SQLite parses the algorithm as part of the `INSERT` keyword, immediately
/// before `INTO`. `replace` is the same algorithm reached by the standalone
/// `REPLACE` statement.
///
public enum XLInsertOrAction: String, CaseIterable, Hashable, Sendable {
    case rollback = "ROLLBACK"
    case abort = "ABORT"
    case fail = "FAIL"
    case ignore = "IGNORE"
    case replace = "REPLACE"
}


///
/// The opening clause of an insert statement.
///
/// `INSERT OR <action> INTO` and `REPLACE INTO` are SQLite spellings. Other
/// dialects express the same intent with `ON CONFLICT`.
///
public enum XLInsertTarget: Hashable, Sendable {

    /// A plain insert with no conflict clause.
    case insert

    /// An insert carrying a conflict-resolution algorithm.
    case insertOr(XLInsertOrAction)

    /// The shorthand for an insert that replaces a conflicting row.
    case replace
}


///
/// A built-in collating sequence.
///
/// Only the sequences the dialect defines belong here. A sequence registered
/// by the application is named by an identifier, not by vocabulary, so it
/// goes through the formatter and never through this enum.
///
public enum XLCollationName: Hashable, Sendable {
    case binary
    case noCase
    case rTrim
}


///
/// One modifier applied to a date or time value.
///
/// The cases name what the modifier means. The dialect renders the text,
/// because the spelling is SQLite's own.
///
public enum XLDateModifierTerm: Hashable, Sendable {

    /// A signed relative offset, such as `+3 days`.
    case offset(count: Int, unit: XLDateUnit)

    /// Truncation back to the start of a day, month, or year.
    case startOf(XLDateUnit)

    /// Advance to the next matching day of week, where 0 is Sunday.
    case weekday(Int)

    /// Round a month or year offset up on overflow.
    case ceiling

    /// Round a month or year offset down on overflow.
    case floor

    /// Interpret the value as UTC and convert it to local time.
    case localTime

    /// Interpret the value as local time and convert it to UTC.
    case utc

    /// Render fractional seconds.
    case subsecond

    /// Exact dialect text for a modifier this vocabulary does not name.
    case custom(String)
}


///
/// A unit of time named by a date modifier.
///
public enum XLDateUnit: String, CaseIterable, Hashable, Sendable {
    case seconds
    case minutes
    case hours
    case days
    case months
    case years
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
public protocol XLSQLVocabulary: Sendable {

    func spelling(for comparison: XLComparisonOperator) -> String

    func spelling(for test: XLNullTest) -> String

    func form(for function: XLConditionalFunction) -> XLConditionalForm

    func spelling(for prefix: XLCommonTablePrefix) -> String

    func spelling(for target: XLInsertTarget) -> String

    func spelling(for collation: XLCollationName) -> String

    func spelling(for modifier: XLDateModifierTerm) -> String

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
