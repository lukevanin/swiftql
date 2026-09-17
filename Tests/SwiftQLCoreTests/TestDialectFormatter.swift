import Foundation

@testable import SwiftQLCore


///
/// A formatter for the dialects declared by these tests.
///
/// The test dialects exist to exercise identity, capability, and codec rules
/// rather than rendering. This formatter gives them the rendering half of
/// ``XLSQLDialect`` by delegating identifiers and placeholders back to the
/// dialect that vended it, so a test dialect states its spelling once.
///
struct TestDialectFormatter: XLFormatter {

    private let identifier: @Sendable (String) -> String

    private let qualifiedIdentifier: @Sendable ([String]) -> String

    private let placeholder: @Sendable (XLBindingPlaceholder) -> String

    init(
        identifier: @escaping @Sendable (String) -> String,
        qualifiedIdentifier: @escaping @Sendable ([String]) -> String,
        placeholder: @escaping @Sendable (XLBindingPlaceholder) -> String
    ) {
        self.identifier = identifier
        self.qualifiedIdentifier = qualifiedIdentifier
        self.placeholder = placeholder
    }

    func null() -> String {
        "NULL"
    }

    func integer(_ value: Int) -> String {
        String(value)
    }

    func real(_ value: Double) -> String {
        guard value.isFinite else {
            return ""
        }
        return String(value)
    }

    func text(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    func blob(_ value: Data) -> String {
        "x'\(value.map { String(format: "%02x", $0) }.joined())'"
    }

    func name(_ value: String) -> String {
        identifier(value)
    }

    func scopedName(_ values: [String]) -> String {
        qualifiedIdentifier(values)
    }

    func namedBinding(_ named: String) -> String {
        placeholder(.named(named))
    }

    func indexedBinding(_ index: Int) -> String {
        placeholder(.indexed(index))
    }
}


extension XLSQLDialect {

    ///
    /// Borrows SQLite's placeholder rule, which is what these dialects'
    /// `formatPlaceholder` implementations already spell.
    ///
    func makeTestPlaceholderAssigner() -> XLitePlaceholderAssigner {
        XLitePlaceholderAssigner()
    }

    ///
    /// Borrows SQLite's keyword spelling.
    ///
    /// These dialects exercise identity, capability, and codec rules rather
    /// than rendering, so the vocabulary they report is never asserted on.
    ///
    func makeTestVocabulary() -> XLiteVocabulary {
        XLiteVocabulary()
    }

    ///
    /// Builds a ``TestDialectFormatter`` from this dialect's own identifier and
    /// placeholder rules.
    ///
    func makeTestFormatter() -> TestDialectFormatter {
        TestDialectFormatter(
            identifier: formatIdentifier,
            qualifiedIdentifier: formatQualifiedIdentifier,
            placeholder: formatPlaceholder
        )
    }
}
