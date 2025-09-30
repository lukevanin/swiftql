//
//  File.swift
//  
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation


public struct XLInsertBuilder<Row> {
    
    enum InternalError: LocalizedError {
        case missingValuesClause
    }
    
    private var commonTables: [XLCommonTableDependency] = []
    
    private var insert: Insert<Row>
    
    private var values: (any XLEncodable)?
    
    public init<T>(insert meta: T) where T: XLMetaNamedResult, T.Row == Row {
        self.init(insert: Insert(meta))
    }
    
    public init(insert: Insert<Row>) {
        self.insert = insert
    }
    
    private func copy(modifier: (inout XLInsertBuilder) -> Void) -> XLInsertBuilder {
        var newInstance = XLInsertBuilder(insert: insert)
        newInstance.values = values
        modifier(&newInstance)
        return newInstance
    }
    
    public func values(_ values: Row) -> XLInsertBuilder where Row: XLTable, Row.MetaInsert.Row == Row  {
        copy {
            $0.values = Row.MetaInsert(values)
        }
    }
    
    public func build() throws -> any XLInsertStatement<Row> {
        #warning("TODO: Include common tables and INSERT...SELECT")
        var statement = XLInsertStatementComponents(insert: insert)
        
        guard let values else {
            throw InternalError.missingValuesClause
        }
        
        statement.components.append(values)
        return AbstractXLInsertStatement(components: statement)
    }
}
