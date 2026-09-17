import Foundation


///
/// Spells the divergent SQL vocabulary the way SQLite does.
///
/// Every spelling here is the text SwiftQL rendered before the vocabulary
/// existed. The pinned SQLite corpus is the proof: moving a keyword behind a
/// vocabulary case must not change one rendered byte.
///
public struct XLiteVocabulary: XLSQLVocabulary, Hashable, Sendable {

    public init() {}

    public func spelling(for comparison: XLComparisonOperator) -> String {
        switch comparison {
        case .equal:
            // SQLite accepts `==` as well as `=`, and SwiftQL has always
            // rendered `==`.
            return "=="
        case .notEqual:
            return "!="
        case .nullSafeEqual:
            return "IS"
        case .nullSafeNotEqual:
            return "IS NOT"
        }
    }

    public func spelling(for test: XLNullTest) -> String {
        switch test {
        case .isNull:
            return "ISNULL"
        case .isNotNull:
            return "NOTNULL"
        }
    }

    public func form(for function: XLConditionalFunction) -> XLConditionalForm {
        switch function {
        case .immediateIf:
            return .function("IIF")
        }
    }

    public func spelling(for prefix: XLCommonTablePrefix) -> String {
        switch prefix {
        case .with:
            return "WITH"
        case .withRecursive:
            // SQLite accepts a recursive common table after a plain `WITH`,
            // and has never been given the RECURSIVE token.
            return "WITH"
        }
    }

    public func spelling(for target: XLInsertTarget) -> String {
        switch target {
        case .insert:
            return "INSERT INTO"
        case .insertOr(let action):
            return "INSERT OR \(action.rawValue) INTO"
        case .replace:
            return "REPLACE INTO"
        }
    }

    public func spelling(for collation: XLCollationName) -> String {
        switch collation {
        case .binary:
            return "BINARY"
        case .noCase:
            return "NOCASE"
        case .rTrim:
            return "RTRIM"
        }
    }

    public func spelling(for modifier: XLDateModifierTerm) -> String {
        switch modifier {
        case .offset(let count, let unit):
            // SQLite accepts an optional leading sign; an explicit one is
            // emitted so a positive offset reads the same way a negative one
            // does.
            let sign = count < 0 ? "" : "+"
            return "\(sign)\(count) \(unit.rawValue)"
        case .startOf(let unit):
            return "start of \(Self.singular(unit))"
        case .weekday(let day):
            return "weekday \(day)"
        case .ceiling:
            return "ceiling"
        case .floor:
            return "floor"
        case .localTime:
            return "localtime"
        case .utc:
            return "utc"
        case .subsecond:
            return "subsec"
        case .custom(let text):
            return text
        }
    }

    public func spelling(for match: XLRegexMatchOperator) -> String {
        switch match {
        case .matches:
            return "REGEXP"
        }
    }

    public func requiredFunctions(
        for match: XLRegexMatchOperator
    ) -> Set<XLCustomFunctionDefinition> {
        switch match {
        case .matches:
            // SQLite has no built-in `regexp`. A statement that matches
            // with REGEXP cannot be prepared until one is registered.
            return [Self.regexpFunction]
        }
    }

    /// The registration signature SQLite requires for the `REGEXP` operator.
    public static let regexpFunction = XLCustomFunctionDefinition(
        name: "regexp",
        numberOfArguments: 2
    )

    /// SQLite anchors a truncation to a singular unit: `start of day`, not
    /// `start of days`.
    private static func singular(_ unit: XLDateUnit) -> String {
        switch unit {
        case .seconds:
            return "second"
        case .minutes:
            return "minute"
        case .hours:
            return "hour"
        case .days:
            return "day"
        case .months:
            return "month"
        case .years:
            return "year"
        }
    }
}
