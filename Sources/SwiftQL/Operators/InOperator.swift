//
//  InOperator.swift
//  
//
//  Created by Luke Van In on 2023/08/14.
//

import Foundation


// MARK: - IN

extension XLExpression {

//    public func `in`(@XLQueryStatementBuilder expression: (inout XLQueryComposer) -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
//        var query = XLQueryComposer()
//        return XLInExpression(lhs: self, rhs: expression(&query))
//    }

//    public func `in`<Wrapped>(@XLQueryStatementBuilder expression: (inout XLQueryComposer) -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
//        var query = XLQueryComposer()
//        return XLInExpression(lhs: self, rhs: expression(&query))
//    }

    public func `in`(expression: () -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }

    public func `in`(@XLQueryExpressionBuilder expression: (XLSchema) -> any XLQueryStatement<T>) -> some XLExpression<Bool> {
        let schema = XLSchema()
        return XLInValueExpression(lhs: self, rhs: expression(schema))
    }

    // TODO: Support IN operator for expressions where one or both sides contain NULL.
    // Currently this creates ambiguous expressions with the in operator for non-null expressions. Possibly a solution
    // is to remove XLLiteral and/or XLExpression conformance from Optional.
    public func `in`<Wrapped>(expression: () -> any XLQueryStatement<Wrapped>) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        return XLInValueExpression(lhs: self, rhs: expression())
    }
    
//    public func `in`(_ expressions: any XLExpression<T>...) -> some XLExpression<Bool> {
//        XLInExpression(
//            lhs: self,
//            rhs: XLCompoundExpression<Any>(separator: .comma, expressions: expressions)
//        )
//    }

    public func `in`(_ expressions: [any XLExpression<T>]) -> some XLExpression<Bool> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .comma, expressions: expressions)
        )
    }

    public func `in`<Wrapped>(_ expressions: [any XLExpression<Wrapped>]) -> some XLExpression<Optional<Bool>> where T == Optional<Wrapped> {
        XLInValueExpression(
            lhs: self,
            rhs: XLCompoundExpression<Any>(separator: .comma, expressions: expressions)
        )
    }

//    public func `in`(_ expressions: T...) -> some XLExpression<Bool> where T: XLExpression {
//        XLInExpression(
//            lhs: self,
//            rhs: XLCompoundExpression<Any>(separator: .comma, expressions: expressions)
//        )
//    }

//    public func `in`(_ expressions: [T]) -> some XLExpression<Bool> where T: XLExpression {
//        XLInExpression(
//            lhs: self,
//            rhs: XLCompoundExpression<Any>(separator: .comma, expressions: expressions)
//        )
//    }
    
    public func `in`<T>(_ table: T) -> some XLExpression<Bool> where T: XLMetaCommonTable {
        XLInTableExpression(
            lhs: self,
            rhs: table.definition.alias
        )
    }
}
