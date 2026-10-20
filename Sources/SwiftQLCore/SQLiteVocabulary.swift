import Foundation


///
/// Spells the divergent SQL vocabulary the way SQLite does.
///
/// Every spelling here is the text SwiftQL rendered before the vocabulary
/// existed. The pinned SQLite corpus is the proof: moving a keyword behind a
/// vocabulary case must not change one rendered byte. That guarantee covers
/// the lexical set this vocabulary spells, and nothing else: issue #791
/// removed the conditional from the vocabulary and changed its rendered bytes
/// on purpose, from `IIF` to `CASE WHEN`. SQLite's own surface, the conflict
/// clause, the collating sequences, and the date modifiers, is spelled by
/// `SwiftQLSQLite`, not here.
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
}
