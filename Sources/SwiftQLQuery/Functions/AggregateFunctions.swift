//
//  AggregateFunctions.swift
//
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


/// The unqualified all-columns expression rendered as `*`.
///
/// Use all() with count(_:) to count every input row.
public struct XLAllColumns: XLExpression {

    public typealias T = XLAllColumns

    public init() {
    }

    public func makeSQL(context: inout XLBuilder) {
        context.block(
            beginsWith: "*",
            endsWith: "",
            separator: .elided
        ) { _ in
        }
    }
}


/// Returns the unqualified all-columns expression rendered as `*`.
public func all() -> XLAllColumns {
    XLAllColumns()
}
