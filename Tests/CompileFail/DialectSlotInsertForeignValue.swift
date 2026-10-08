import Foundation
import SwiftQL

// Issue #825: the values of a model's generated `MetaInsert(...)` take only
// the model's dialect's expressions. A second-dialect insert given a SQLite
// column is refused at the argument. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> SecondDialectPerson.MetaInsert {
    let sqlite = XLSchema().table(DialectPerson.self)
    return SecondDialectPerson.MetaInsert(
        id: 1,
        name: sqlite.name, // expected-error
        nickname: nil as String?,
        age: 2
    )
}
