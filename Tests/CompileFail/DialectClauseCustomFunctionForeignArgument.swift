import Foundation
import SwiftQL

// Issue #822: a custom function runs inside SQLite, so the initializer
// `@SQLFunction` generates takes each argument as a SQLite expression, though
// the property stores any expression. A column of a second-dialect model is
// refused. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

@SQLFunction(name: "shout")
struct Shout: XLCustomFunction {
    typealias T = String

    let text: any XLExpression<String>

    static func execute(reader: XLColumnReader) throws -> String {
        try reader.readText(at: 0).uppercased()
    }
}

func refusal() -> Shout {
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return Shout(text: other.name) // expected-error
}
