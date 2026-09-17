import Foundation


///
/// Encodes Swift values into a string representation in an SQL statement.
///
/// A dialect vends its formatter through ``XLSQLDialect/makeFormatter()``, so
/// the spelling of every literal, identifier, and placeholder belongs to the
/// dialect rather than to the encoder that renders a statement.
///
public protocol XLFormatter {

    ///
    /// Formats a `nil` literal into an SQL sub-expression.
    ///
    func null() -> String

    ///
    /// Formats an `Int` literal into an SQL sub-expression.
    ///
    func integer(_ value: Int) -> String

    ///
    /// Formats a `Double` literal into an SQL sub-expression.
    ///
    func real(_ value: Double) -> String

    ///
    /// Formats a `String` literal into an SQL sub-expression.
    ///
    func text(_ value: String) -> String

    ///
    /// Formats a `Data` literal into an SQL sub-expression.
    ///
    func blob(_ value: Data) -> String

    ///
    /// Formats a name, such as of a table or column, into an SQL sub-expression.
    ///
    func name(_ value: String) -> String

    ///
    /// Formats a qualified name, such as a table and column, into an SQL sub-expression. Each
    /// component of the name is provided as an entry in an array.
    ///
    func scopedName(_ values: [String]) -> String

    ///
    /// Formats a named variable into an SQL sub-expression.
    ///
    func namedBinding(_ named: String) -> String

    ///
    /// Formats an index variable into an SQL sub-expression.
    ///
    func indexedBinding(_ index: Int) -> String
}
