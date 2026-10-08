import Foundation
import SwiftQL

// Issue #825: the values of a model's generated `MetaUpdate(...)` take only
// the model's dialect's expressions. A second-dialect update given a SQLite
// column is refused at the argument. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> SecondDialectPerson.MetaUpdate {
    let sqlite = XLSchema().table(DialectPerson.self)
    return SecondDialectPerson.MetaUpdate(
        age: sqlite.age // expected-error
    )
}
