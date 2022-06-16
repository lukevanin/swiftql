import Foundation


protocol HashKey {
    var rawValue: String { get }
}


func ==(lhs: HashKey, rhs: HashKey) -> Bool {
    lhs.rawValue == rhs.rawValue
}


struct IdentifierHashKey: HashKey {
    let rawValue: String
    
    init(_ value: SQLIdentifier) {
        self.rawValue = value.value
    }
}


struct QualifiedIdentifierHashKey: HashKey {
    let rawValue: String
    
    init(_ identifier: SQLQualifiedFieldIdentifier) {
        self.init(identifier.table, identifier.field)
    }
    
    init(_ context: SQLIdentifier, _ value: SQLIdentifier) {
        self.rawValue = IdentifierHashKey(context).rawValue + "." + IdentifierHashKey(value).rawValue
    }
}


enum SymbolHashKey: String, HashKey {
    case primaryKey = "pk"
    case foreignKey = "fk"
    case null = "nul"

    case and = "&"
    case or = "|"
    case not = "!"
    case equality = "="
    case variable = "?"
    
    case boolean = "b"
    case integer = "i"
    case real = "r"
    case text = "t"
    case data = "d"
    case date = "dte"
    case uuid = "uid"
    case url = "url"
    
    case ascending = "asc"
    case descending = "dsc"

    case create = "crt"
    case insert = "ins"
    case update = "upd"
    case select = "sel"
    case from = "frm"
    case join = "joi"
    case orderBy = "ord"
    case `where` = "whr"
}


struct ListHashKey: HashKey {
    let rawValue: String
    
    init(separator: String, values: [HashKey]) {
        self.rawValue = "(" + values.map { $0.rawValue }.joined(separator: separator) + ")"
    }
}


struct CompositeHashKey: HashKey {
    
    let rawValue: String
    
    init(_ values: HashKey...) {
        self.rawValue = values.map { $0.rawValue }.joined(separator: " ")
    }
}

