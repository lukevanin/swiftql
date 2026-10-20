import XCTest
@testable import SwiftQL


///
/// Spells the four lexical categories the way PostgreSQL does.
///
/// This exists to prove the seam: the encoder, the builder, and every node
/// stay the same, and only this type decides the rendered keywords. It
/// conforms with nothing but the lexical set, which is the whole of
/// `XLSQLVocabulary` (issue #791): there is no requirement here for a conflict
/// clause, a collation, a conditional form, or a date modifier, so a dialect
/// cannot spell one it does not have.
///
private struct ProbeVocabulary: XLSQLVocabulary {

    func spelling(for comparison: XLComparisonOperator) -> String {
        switch comparison {
        case .equal:
            return "="
        case .notEqual:
            return "<>"
        case .nullSafeEqual:
            return "IS NOT DISTINCT FROM"
        case .nullSafeNotEqual:
            return "IS DISTINCT FROM"
        }
    }

    func spelling(for test: XLNullTest) -> String {
        switch test {
        case .isNull:
            return "IS NULL"
        case .isNotNull:
            return "IS NOT NULL"
        }
    }

    func spelling(for prefix: XLCommonTablePrefix) -> String {
        switch prefix {
        case .with:
            return "WITH"
        case .withRecursive:
            return "WITH RECURSIVE"
        }
    }

    func spelling(for match: XLRegexMatchOperator) -> String {
        switch match {
        case .matches:
            return "~"
        }
    }

    func requiredFunctions(
        for match: XLRegexMatchOperator
    ) -> Set<XLCustomFunctionDefinition> {
        // PostgreSQL matches natively, so nothing has to be registered.
        []
    }
}


private struct VocabularyProbeValue: XLDialectValue {

    var storageType: String { "text" }
}


///
/// A dialect that renders through ``ProbeVocabulary`` while reusing SQLite's
/// identifier and literal spelling.
///
private struct ProbeDialect: XLSQLDialect {

    typealias Value = VocabularyProbeValue

    let descriptor = XLDialectDescriptor(
        identity: XLDialectIdentifier(rawValue: "swiftql.tests.vocabulary-probe"),
        capabilities: [.namedBindings, .indexedBindings]
    )

    func makeFormatter() -> XLiteFormatter {
        XLiteFormatter()
    }

    func makeVocabulary() -> ProbeVocabulary {
        ProbeVocabulary()
    }

    func makePlaceholderAssigner() -> XLitePlaceholderAssigner {
        // This probe exists to exercise keyword spelling. It keeps SQLite's
        // placeholder rule so the two concerns stay separable.
        XLitePlaceholderAssigner()
    }

    func formatIdentifier(_ identifier: String) -> String {
        XLSQLiteDialect().formatIdentifier(identifier)
    }

    func formatQualifiedIdentifier(_ components: [String]) -> String {
        XLSQLiteDialect().formatQualifiedIdentifier(components)
    }

    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String {
        XLSQLiteDialect().formatPlaceholder(placeholder)
    }
}


private struct ComparisonProbe: XLEncodable {

    let comparison: XLComparisonOperator

    func makeSQL(context: inout XLBuilder) {
        context.comparison(
            comparison,
            left: { $0.integer(1) },
            right: { $0.integer(2) }
        )
    }
}


private struct NullTestProbe: XLEncodable {

    let test: XLNullTest

    func makeSQL(context: inout XLBuilder) {
        context.nullTest(test) { $0.integer(1) }
    }
}


private struct RegexProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        context.regexMatch(
            .matches,
            left: { $0.name(XLName("subject")) },
            right: { $0.text("^a") }
        )
    }
}


private struct IntegerProbe<Value>: XLExpression {

    typealias T = Value

    let value: Int

    func makeSQL(context: inout XLBuilder) {
        context.integer(value)
    }
}


/// A conditional expression, which has no vocabulary case: it renders the
/// standard `CASE WHEN` for every dialect (issue #791).
private struct ConditionalProbe: XLEncodable {

    func makeSQL(context: inout XLBuilder) {
        XLIfExpression<Int>(
            condition: IntegerProbe<Bool>(value: 1),
            trueResult: IntegerProbe<Int>(value: 2),
            falseResult: IntegerProbe<Int>(value: 3)
        )
        .makeSQL(context: &context)
    }
}


final class SQLDialectVocabularyTests: XCTestCase {

    // MARK: - SQLite keeps its spelling

    func testSQLiteSpellsEveryLexicalCategoryAsBefore() {
        let encoder = XLiteEncoder(formatter: XLiteFormatter())

        XCTAssertEqual(encoder.makeSQL(ComparisonProbe(comparison: .equal)).sql, "1 == 2")
        XCTAssertEqual(encoder.makeSQL(ComparisonProbe(comparison: .notEqual)).sql, "1 != 2")
        XCTAssertEqual(encoder.makeSQL(ComparisonProbe(comparison: .nullSafeEqual)).sql, "1 IS 2")
        XCTAssertEqual(
            encoder.makeSQL(ComparisonProbe(comparison: .nullSafeNotEqual)).sql,
            "1 IS NOT 2"
        )
        XCTAssertEqual(encoder.makeSQL(NullTestProbe(test: .isNull)).sql, "1 ISNULL")
        XCTAssertEqual(encoder.makeSQL(NullTestProbe(test: .isNotNull)).sql, "1 NOTNULL")
        XCTAssertEqual(encoder.makeSQL(RegexProbe()).sql, #""subject" REGEXP '^a'"#)
    }

    // MARK: - SQLite's own surface is spelled by SQLite's product

    func testSQLiteSpellsItsDateModifiersWithoutTheVocabulary() {
        XCTAssertEqual(XLDateModifier.days(3).rawValue, "+3 days")
        XCTAssertEqual(XLDateModifier.days(-3).rawValue, "-3 days")
        XCTAssertEqual(XLDateModifier.startOfMonth.rawValue, "start of month")
        XCTAssertEqual(XLDateModifier.weekday(1).rawValue, "weekday 1")
        XCTAssertEqual(XLDateModifier.subsecond.rawValue, "subsec")
        XCTAssertEqual(XLDateModifier("unixepoch").rawValue, "unixepoch")
    }

    func testSQLiteSpellsTheConflictAlgorithmAndCollationsInItsOwnProduct() {
        XCTAssertEqual(XLInsertOrAction.ignore.rawValue, "IGNORE")
        XCTAssertEqual(XLCollation.nocase.rawValue, "NOCASE")
        XCTAssertEqual(XLCollation.rtrim.rawValue, "RTRIM")
        XCTAssertEqual(XLCollation.binary.rawValue, "BINARY")
    }

    // MARK: - A conditional is not a spelling difference

    func testEveryDialectRendersTheStandardCaseWhen() {
        let expected = "CASE WHEN 1 THEN 2 ELSE 3 END"

        XCTAssertEqual(
            XLiteEncoder(formatter: XLiteFormatter()).makeSQL(ConditionalProbe()).sql,
            expected
        )
        XCTAssertEqual(
            XLDialectEncoder(dialect: ProbeDialect()).makeSQL(ConditionalProbe()).sql,
            expected
        )
    }

    // MARK: - A second dialect changes the rendered SQL

    func testASecondDialectRendersItsOwnKeywordsThroughTheSameEncoder() {
        let encoder = XLDialectEncoder(dialect: ProbeDialect())

        XCTAssertEqual(encoder.makeSQL(ComparisonProbe(comparison: .equal)).sql, "1 = 2")
        XCTAssertEqual(encoder.makeSQL(ComparisonProbe(comparison: .notEqual)).sql, "1 <> 2")
        XCTAssertEqual(
            encoder.makeSQL(ComparisonProbe(comparison: .nullSafeEqual)).sql,
            "1 IS NOT DISTINCT FROM 2"
        )
        XCTAssertEqual(
            encoder.makeSQL(ComparisonProbe(comparison: .nullSafeNotEqual)).sql,
            "1 IS DISTINCT FROM 2"
        )
        XCTAssertEqual(encoder.makeSQL(NullTestProbe(test: .isNull)).sql, "1 IS NULL")
        XCTAssertEqual(encoder.makeSQL(NullTestProbe(test: .isNotNull)).sql, "1 IS NOT NULL")
        XCTAssertEqual(encoder.makeSQL(RegexProbe()).sql, #""subject" ~ '^a'"#)
    }

    // MARK: - The vocabulary owns the function requirement

    func testTheVocabularyDecidesWhichFunctionsAMatchRequires() {
        // SQLite has no built-in regexp, so rendering a match records the
        // registration SwiftQL bundles.
        let sqlite = XLiteEncoder(formatter: XLiteFormatter())
        let sqliteEncoding = sqlite.makeSQL(RegexProbe())
        XCTAssertEqual(
            Set(sqliteEncoding.customFunctions.keys),
            [XLiteVocabulary.regexpFunction]
        )

        // A dialect that matches natively records nothing, and the node that
        // rendered the match is the same one.
        let probe = XLDialectEncoder(dialect: ProbeDialect())
        XCTAssertTrue(probe.makeSQL(RegexProbe()).customFunctions.isEmpty)
    }

    func testSQLiteVocabularyNamesTheRegexpSignatureSQLiteNeeds() {
        XCTAssertEqual(XLiteVocabulary.regexpFunction.name, "regexp")
        XCTAssertEqual(XLiteVocabulary.regexpFunction.numberOfArguments, 2)
        XCTAssertEqual(
            XLiteVocabulary().requiredFunctions(for: .matches),
            [XLiteVocabulary.regexpFunction]
        )
    }

    // MARK: - The dialect vends both halves of the seam

    func testTheDialectVendsItsFormatterAndVocabulary() {
        let dialect = XLSQLiteDialect(identifierFormattingOptions: .noEscape)
        XCTAssertEqual(dialect.makeFormatter().name("value"), "value")
        XCTAssertEqual(dialect.makeVocabulary().spelling(for: .nullSafeEqual), "IS")

        // The encoder takes the formatter from the dialect rather than from
        // its own initialiser.
        let encoder = XLDialectEncoder(dialect: dialect)
        XCTAssertEqual(encoder.formatter.identifierFormattingOptions, .noEscape)
    }
}
