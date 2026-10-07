import Foundation
import SwiftQL

// Issue #825: an assignment in `Setting { row in ... }` takes only the model's
// dialect's expressions. A second-dialect update assigning a SQLite column is
// refused at the assignment. The error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> any XLUpdateStatement {
    let sqlite = XLSchema().table(DialectPerson.self)
    return sql(dialect: CompileFailSecondDialect.self) { schema in
        let person = schema.into(SecondDialectPerson.self)
        Update(person)
        Setting<SecondDialectPerson> { row in
            row.name = sqlite.name // expected-error
        }
    }
}
