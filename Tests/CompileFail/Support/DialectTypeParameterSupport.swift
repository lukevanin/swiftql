import Foundation
import SwiftQL

// Issue #789: shared by the DialectTypeParameter* fixtures, which
// `scripts/ci/check-dialect-type-parameter-type-safety.sh` compiles with this
// file and with DialectParameterisedSupport.swift, which declares the second
// dialect. It must type-check on its own: an error here is a fault in the
// gate, not evidence.

/// A SQLite model. Nothing names a dialect, so the dialect is SQLite.
@SQLTable struct DialectPerson {
    var id: Int
    var name: String
    var nickname: String?
    var age: Int
}

/// The same table declared for the second dialect. A model is declared once
/// for each dialect that queries it.
@SQLTable(name: "DialectPerson", dialect: CompileFailSecondDialect.self)
struct SecondDialectPerson {
    var id: Int
    var name: String
    var nickname: String?
    var age: Int
}
