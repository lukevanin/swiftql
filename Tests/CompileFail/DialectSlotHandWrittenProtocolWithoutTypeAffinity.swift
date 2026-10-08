import Foundation
import SwiftQL

// Issue #825: a dialect may write its expression protocol by hand rather than
// generate its surface. A read of a model's `Setting` slot returns a value of
// no dialect inside an `XLTypeAffinityExpression`, so the protocol must
// include that node. One that does not is a compile error in the model's
// expansion, at the generated conversion, under a comment that states the
// requirement, rather than a read that stops the program or returns `nil`.
// The error names the node and the protocol.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: XLTypeAffinityExpression HandWrittenExpression

struct HandWrittenDialect: XLSQLDialect {
    typealias Value = CompileFailSecondDialectValue

    let descriptor = XLDialectDescriptor(
        identity: XLDialectIdentifier(rawValue: "compile-fail.hand-written")
    )

    func makeFormatter() -> XLiteFormatter { XLiteFormatter() }
    func makeVocabulary() -> XLiteVocabulary { XLiteVocabulary() }
    func makePlaceholderAssigner() -> XLitePlaceholderAssigner { XLitePlaceholderAssigner() }
    func formatIdentifier(_ identifier: String) -> String { identifier }
    func formatQualifiedIdentifier(_ components: [String]) -> String { components.joined(separator: ".") }
    func formatPlaceholder(_ placeholder: XLBindingPlaceholder) -> String { "?" }
}

protocol HandWrittenExpression<T>: XLExpression {
}

extension HandWrittenDialect {
    typealias XLAnyExpression<T> = any HandWrittenExpression<T>
}

extension XLColumnReference: HandWrittenExpression where Dialect == HandWrittenDialect {
}

extension Int: HandWrittenExpression {
}

extension Optional: HandWrittenExpression where Wrapped: HandWrittenExpression {
}

@SQLTable(name: "HandWritten", dialect: HandWrittenDialect.self)
struct HandWrittenRow {
    var id: Int
}
