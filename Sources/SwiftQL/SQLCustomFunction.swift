//
//  SQLCustomFunction.swift
//  
//
//  Created by Luke Van In on 2023/08/08.
//

import Foundation
import GRDB


/// The SQLite registration signature for a custom scalar function.
public struct XLCustomFunctionDefinition: Hashable, Sendable {
    
    /// The function name emitted in SQL and registered with SQLite.
    public var name: String
    
    /// The number of arguments SQLite passes to the function.
    public var numberOfArguments: Int
    
    /// Creates a custom scalar-function signature.
    ///
    /// - Parameters:
    ///   - name: The function name used in SQL.
    ///   - numberOfArguments: The function's fixed argument count.
    public init(name: String, numberOfArguments: Int) {
        self.name = name
        self.numberOfArguments = numberOfArguments
    }
}


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


/// Type-erased identity and GRDB registration thunk for one ``XLCustomFunction`` referenced
/// while a statement is rendered to SQL.
///
/// The renderer records one of these every time ``XLBuilder/customFunctionCall(_:parameters:)``
/// emits a call to a custom function. A driver can then register the underlying SQLite function
/// automatically -- the first time a rendered statement references it, on whatever physical
/// connection happens to execute the statement -- without the caller registering it upfront with
/// ``GRDBDatabaseBuilder/addFunction(_:)``.
public struct XLCustomFunctionRegistration: Sendable {

    /// The SQLite registration signature. Two registrations sharing a definition register the
    /// same SQLite function and are interchangeable.
    public let definition: XLCustomFunctionDefinition

    let makeDatabaseFunction: @Sendable () -> DatabaseFunction

    /// Creates a registration for one custom function type.
    public static func make<F>(_ type: F.Type) -> XLCustomFunctionRegistration
    where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        XLCustomFunctionRegistration(
            definition: F.definition,
            makeDatabaseFunction: {
                DatabaseFunction(
                    F.definition.name,
                    argumentCount: Int(F.definition.numberOfArguments),
                    function: { values in
                        let reader = GRDBValuesAdapter(values: values)
                        return try F.execute(reader: reader)
                    }
                )
            }
        )
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
    ) where F: XLCustomFunction, F.T: DatabaseValueConvertible {
        customFunction(.make(F.self))
        simpleFunction(name: F.definition.name, parameters: parameters)
    }
}
