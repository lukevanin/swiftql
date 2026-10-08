import Foundation
import SwiftQL

// Issue #825: the arguments of a model's `columns(...)` take only the model's
// dialect's expressions. A SQLite projection given a second-dialect column is
// refused at the argument. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> DialectPerson.MetaResult {
    let sqlite = XLSchema().table(DialectPerson.self)
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return DialectPerson.columns(
        id: sqlite.id,
        name: other.name, // expected-error
        nickname: sqlite.nickname,
        age: sqlite.age
    )
}
