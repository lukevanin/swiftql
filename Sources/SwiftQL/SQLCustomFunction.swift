//
//  SQLCustomFunction.swift
//  
//
//  Created by Luke Van In on 2023/08/08.
//

import Foundation


/// A SwiftQL expression whose implementation is registered as a SQLite scalar function.
///
/// Supply ``definition`` for the SQL signature, emit a call to that signature from your
/// `makeSQL(context:)` implementation, and implement ``execute(reader:)`` to calculate a result
/// from the SQLite arguments.
public protocol XLCustomFunction<T>: XLExpression {
    /// The name and argument count used to register the function.
    static var definition: XLCustomFunctionDefinition { get }

    /// Evaluates one invocation using values supplied by SQLite.
    ///
    /// - Parameter reader: A reader positioned over the function arguments.
    /// - Returns: The value returned to SQLite.
    static func execute(reader: XLColumnReader) throws -> T
}


extension XLCustomFunctionRegistration {

    /// Creates a registration for one custom function type.
    ///
    /// The function's arguments reach ``XLCustomFunction/execute(reader:)``
    /// through a column reader over the SQLite values, and its result is
    /// bound back to a SQLite value the way a statement parameter is bound,
    /// so a NaN result is an error rather than a silent `NULL`.
    public static func make<F>(_ type: F.Type) -> XLCustomFunctionRegistration
    where F: XLCustomFunction, F.T: XLBindable & Sendable {
        // Captured as plain values rather than the generic metatype `F.Type` itself, so the
        // `@Sendable` evaluator below never needs to carry an unconstrained generic parameter
        // across the isolation boundary. `F.T: Sendable` covers the one metatype that remains.
        let functionDefinition = F.definition
        // `F.execute` is a static function with no captured state -- calling it concurrently
        // from multiple pooled connections is exactly this feature's purpose -- so it is safe to
        // treat as `@Sendable`. `unsafeBitCast` only changes the compile-time `@Sendable`
        // annotation, never the function value's runtime representation, so this is safe
        // regardless of what concrete type `F` turns out to be; the strict-concurrency checker
        // cannot infer that safety for a reference derived from an unconstrained generic type.
        let executeFunction = unsafeBitCast(
            F.execute(reader:) as (XLColumnReader) throws -> F.T,
            to: (@Sendable (XLColumnReader) throws -> F.T).self
        )
        let resultTypeName = String(describing: F.T.self)
        return XLCustomFunctionRegistration(
            definition: functionDefinition,
            makeEvaluator: {
                { arguments in
                    let result = try executeFunction(XLFunctionArgumentReader(values: arguments))
                    return try _xlCaptureSQLiteValue(
                        result,
                        valueType: resultTypeName,
                        codingContext: XLValueCodingContext(
                            site: .result,
                            path: XLValueCodingPath(functionDefinition.name)
                        )
                    )
                }
            }
        )
    }
}


/// Reads a custom function's arguments positionally, as its
/// ``XLCustomFunction/execute(reader:)`` sees them.
///
/// Deliberately only an ``XLColumnReader``: it does not forward
/// ``XLStaticColumnReader/dialectValue(at:using:)`` to the
/// ``XLSQLiteValueReader`` it wraps, so asking it for a raw dialect value
/// throws `rawDialectValuesUnavailable`. That is not a gap. A custom function
/// reads intrinsic values by position; a static row layout is a different
/// contract.
struct XLFunctionArgumentReader: XLColumnReader {

    private let reader: XLSQLiteValueReader

    init(values: [XLSQLiteValue]) {
        self.reader = XLSQLiteValueReader(values: values)
    }

    func isNull(at index: Int) throws -> Bool {
        try reader.isNull(at: index)
    }

    func readInteger(at index: Int) throws -> Int {
        try reader.readInteger(at: index)
    }

    func readReal(at index: Int) throws -> Double {
        try reader.readReal(at: index)
    }

    func readText(at index: Int) throws -> String {
        try reader.readText(at: index)
    }

    func readBlob(at index: Int) throws -> Data {
        try reader.readBlob(at: index)
    }
}


extension XLBuilder {

    /// Adds a call to a registered custom scalar function and records its SQLite registration so
    /// a driver can register the function implicitly.
    ///
    /// Implement `makeSQL(context:)` on an ``XLCustomFunction`` conformer using this method
    /// instead of calling `simpleFunction(name:parameters:)` directly to opt into implicit,
    /// on-demand registration. Conformers that continue calling `simpleFunction` directly keep
    /// working exactly as before -- SwiftQL has no way to know a bare function-name string
    /// identifies a custom function, so those functions still require an upfront
    /// ``GRDBDatabaseBuilder/addFunction(_:)`` call.
    ///
    /// - Parameters:
    ///   - type: The custom function type being called.
    ///   - parameters: Constructs the list of arguments passed to the function.
    public mutating func customFunctionCall<F>(
        _ type: F.Type,
        parameters: ListBuilder
    ) where F: XLCustomFunction, F.T: XLBindable & Sendable {
        customFunction(.make(type))
        simpleFunction(name: type.definition.name, parameters: parameters)
    }
}
