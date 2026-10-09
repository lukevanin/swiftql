//
//  SQLScalarResult.swift
//
//
//  Created by Luke Van In on 2024/10/31.
//

import Foundation


///
/// Scalar result
///
/// Convenience type used where a scalar result (single column) needs to be returned from an expression
/// that returns a table, such as when a scalar result is returned by a common table expression.
///
@SQLTable
public struct SQLScalarResult<T> where T: XLLiteral & XLExpression {
    
    public var scalarValue: T
}



extension SQLScalarResult: Equatable where T: Equatable {
    
}

extension SQLScalarResult: Hashable where T: Hashable {
    
}

///
/// The row crosses an isolation boundary on every observation path, so
/// ``XLRequest`` requires a `Sendable` row. A generic model cannot get this
/// conformance from `@SQLTable`: an extension macro cannot write a `where`
/// clause over its own type's generic signature. The macro documents this
/// exact spelling as the remedy. See `SQLMacro.swift` and issue #685.
///
extension SQLScalarResult: Sendable where T: Sendable {
    
}
