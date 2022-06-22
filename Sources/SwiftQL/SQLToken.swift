import Foundation


public protocol SQLToken {
    func string() -> String
}

struct KeywordSQLToken: SQLToken {
    
    let value: String
    
    func string() -> String {
        SQLSyntax.keyword(value)
    }
}


struct IdentifierSQLToken: SQLToken {
    
    let value: SQLIdentifier
    
    func string() -> String {
        SQLSyntax.identifier(value)
    }
}


struct QualifiedIdentifierSQLToken: SQLToken {
    
    let value: SQLQualifiedFieldIdentifier
    
    func string() -> String {
        SQLSyntax.identifier(value.table) + "." + SQLSyntax.identifier(value.field)
    }
}


struct VariableSQLToken: SQLToken {
    
    func string() -> String {
        "?"
    }
}


struct CompositeSQLToken: SQLToken {
    
    let separator: String
    let tokens: [SQLToken]
    
    func string() -> String {
        tokens
            .map { $0.string() }
            .filter { $0.isEmpty == false }
            .joined(separator: separator)
    }
}


struct NilSQLToken: SQLToken {
    func string() -> String {
        ""
    }
}
