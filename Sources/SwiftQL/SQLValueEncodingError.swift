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


/// Structured failures at SQLite's real-value rendering and binding boundary.
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

    public var errorDescription: String? {
        switch self {
        case .nonFiniteRealLiteral(let value, let expressionType):
            return "Cannot render \(value) from \(expressionType) as an inline SQLite real literal. SQLite has no valid bare numeric token for this value; use a bound parameter when its SQLite binding semantics are acceptable."
        case .realBindingWouldBecomeNull(let value, let valueType, let context):
            return "Cannot bind \(value) from \(valueType) at \(context): SQLite would normalize the value to SQL NULL."
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
