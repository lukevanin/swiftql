import Foundation
import SwiftQL

// Issue #789: `INSERT OR` is SQLite's own, so a second-dialect table refuses it.
// The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLInsertStatement {
    sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.table(SecondDialectPerson.self)
        Insert(person, or: .ignore) // expected-error
        Values(SecondDialectPerson.MetaInsert(SecondDialectPerson(id: 1, name: "a", nickname: nil, age: 2)))
    }
}
