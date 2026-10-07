import Foundation
import SwiftQL

// Issue #825: `#row(...)` builds a SQLite row, so its arguments take only
// SQLite expressions. A second-dialect column is refused at the argument. The
// error names both dialects.
// Compiled with Support/DialectParameterisedSupport.swift and
// Support/DialectTypeParameterSupport.swift.
// expected-names: CompileFailSecondDialect XLSQLite

func refusal() -> SQLScalarResult<String>.MetaResult {
    let other = XLSchema(dialect: CompileFailSecondDialect.self).table(SecondDialectPerson.self)
    return #row(other.name) // expected-error
}
