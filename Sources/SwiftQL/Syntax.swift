import Foundation


enum SQLSyntax {
    
    private static let dateFormatter = ISO8601DateFormatter()

    static func identifier(_ identifier: SQLIdentifier) -> String {
        "`\(identifier.value)`"
    }

    static func string<T>(_ value: T) -> String where T: StringProtocol {
        "'\(value)'"
    }

    static func blob<T>(_ value: T) -> String where T: DataProtocol {
        "x'\(value.hexEncodedString())'"
    }

    static func keyword(_ value: String) -> String {
        value.uppercased()
    }
    
    static func date(from string: String) -> Date {
        dateFormatter.date(from: string)!
    }
    
    static func string(from date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
