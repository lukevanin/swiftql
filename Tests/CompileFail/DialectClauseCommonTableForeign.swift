import Foundation
import SwiftQL

// Issue #822: `With` takes only common tables of its statement's dialect. A
// second-dialect common table in a SQLite query is refused. The error names
// both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLQueryStatement<DialectPerson> {
    let second = XLSchema(dialect: CompileFailSecondDialect.self)
    let commonTable = second.commonTableExpression { schema in
        let person = schema.table(SecondDialectPerson.self)
        Select(person)
        From(person)
    }
    return sql { schema in
        With(commonTable) // expected-error
        let person = schema.table(DialectPerson.self)
        Select(person)
        From(person)
    }
}
