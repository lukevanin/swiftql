import Foundation
import SwiftQL

// Issue #822: a write statement carries the dialect of the table it writes.
// A second-dialect update's `Where` refuses a SQLite condition. The error names
// both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLUpdateStatement {
    let sqlite = XLSchema().table(DialectPerson.self)
    return sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.into(SecondDialectPerson.self)
        Update(person)
        Setting<SecondDialectPerson> { row in
            row.age = 1
        }
        Where(sqlite.nickname.isNull()) // expected-error
    }
}
