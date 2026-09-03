//
//  SQLCustomFunctionDefinition.swift
//  SwiftQLCore
//
//  The SQLite registration signature of a custom scalar function.
//
//  Adapter-neutral (issue #615): a static query descriptor records which
//  functions SwiftQL bundles for the statement, and a descriptor cannot depend
//  on the GRDB adapter that registers them.
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


extension XLCustomFunctionDefinition: Comparable {

    /// Orders by name and then argument count, so a set of definitions can be
    /// written to a manifest or a report in one deterministic order.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.name, lhs.numberOfArguments) < (rhs.name, rhs.numberOfArguments)
    }
}
