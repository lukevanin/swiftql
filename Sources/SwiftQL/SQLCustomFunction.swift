//
//  SQLCustomFunction.swift
//  
//
//  Created by Luke Van In on 2023/08/08.
//

import Foundation


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
