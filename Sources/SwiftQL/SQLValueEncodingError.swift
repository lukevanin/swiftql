import Foundation


/// A non-finite IEEE 754 value that cannot be represented by an inline SQLite
/// numeric literal.
public enum XLNonFiniteRealValue: String, Equatable, Sendable, CustomStringConvertible {
    case notANumber = "NaN"
    case positiveInfinity = "+infinity"
    case negativeInfinity = "-infinity"

    /// Classifies a non-finite `Double`, or returns `nil` for a finite value.
    public init?(_ value: Double) {
        if value.isNaN {
            self = .notANumber
        }
        else if value == .infinity {
            self = .positiveInfinity
        }
        else if value == -.infinity {
            self = .negativeInfinity
        }
        else {
            return nil
        }
    }

    public var description: String {
        rawValue
    }
}


/// Structured failures while SwiftQL renders a statement or binds its values
/// for SQLite, reported before SQLite prepares the statement.
public enum XLSQLValueEncodingError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    /// SQLite has no portable bare numeric token for NaN or infinity.
    case nonFiniteRealLiteral(
        value: XLNonFiniteRealValue,
        expressionType: String
    )

    /// SQLite converts a bound IEEE 754 NaN to SQL `NULL`, which would change
    /// the caller's value semantics.
    case realBindingWouldBecomeNull(
        value: XLNonFiniteRealValue,
        valueType: String,
        context: XLValueCodingContext
    )

    /// A generated v1 `MetaInsert` or `MetaUpdate` value (for example from
    /// `Values(row)` or `UpdateRequest.makeUpdate()`) holds a value whose type
    /// does not conform to `XLEncodable`, such as a `Date` column that only a
    /// contextual codec can encode. The v1 path has no codec context, so the
    /// row must be encoded through `XLStaticRowLayout` instead.
    case contextualOnlyValueInLegacyWrite(valueType: String)

    /// A text value contains U+0000. SQLite reads a text literal, and a text
    /// value bound with the length -1 that GRDB uses, only up to the first
    /// NUL, so the value would be truncated or the statement would not
    /// prepare. `context` is `nil` for an inline literal.
    case nulCharacterInText(valueType: String, context: XLValueCodingContext?)

    /// The right-hand branch of a compound select (`UNION`, `UNION ALL`,
    /// `INTERSECT`, or `EXCEPT`) has a `WITH`, `ORDER BY`, `LIMIT`, or
    /// `OFFSET` clause. SQLite applies `ORDER BY`, `LIMIT`, and `OFFSET` to
    /// the whole compound, and it does not accept `WITH` after the operator.
    case unsupportedCompoundBranchClause(compoundOperator: String, clause: String)

    public var errorDescription: String? {
        switch self {
        case .nulCharacterInText(let valueType, let context):
            let site = context.map { " at \($0)" } ?? ""
            return "Cannot use a \(valueType) text value that contains U+0000\(site): SQLite reads text only up to the first NUL, so the value would be truncated. Store such data as a blob."
        case .unsupportedCompoundBranchClause(let compoundOperator, let clause):
            return "The right-hand branch of \(compoundOperator) has a \(clause) clause. SQLite applies ORDER BY, LIMIT, and OFFSET to the whole compound, and does not accept WITH after the operator. Apply the clause to the whole compound, or put WITH before the first branch."
        case .nonFiniteRealLiteral(let value, let expressionType):
            return "Cannot render \(value) from \(expressionType) as an inline SQLite real literal. SQLite has no valid bare numeric token for this value; use a bound parameter when its SQLite binding semantics are acceptable."
        case .realBindingWouldBecomeNull(let value, let valueType, let context):
            return "Cannot bind \(value) from \(valueType) at \(context): SQLite would normalize the value to SQL NULL."
        case .contextualOnlyValueInLegacyWrite(let valueType):
            return "Cannot write \(valueType) through the v1 MetaInsert/MetaUpdate path: the type does not conform to XLEncodable, so only a contextual codec can encode it. Encode the row through XLStaticRowLayout instead."
        }
    }
}


extension XLSQLValueEncodingError {
    static func bindingFailure(
        for value: Double,
        valueType: String,
        context: XLValueCodingContext
    ) -> Self? {
        guard value.isNaN, let classified = XLNonFiniteRealValue(value) else {
            return nil
        }
        return .realBindingWouldBecomeNull(
            value: classified,
            valueType: valueType,
            context: context
        )
    }
}
