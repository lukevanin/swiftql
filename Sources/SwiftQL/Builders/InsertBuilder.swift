//
//  InsertBuilder.swift
//
//
//  Created by Luke Van In on 2024/10/25.
//

import Foundation


///
/// InsertBuilder is a helper class used to construct insert statements when the structure of the statement is
/// not known at compile time.
///
/// Currently InsertBuilder is used to construct insert statements with a variable number of
/// parameters.
///
public struct InsertBuilder<Row> {
    
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

    ///
    /// Creates an insert using a common table expression.
    ///
    public func with<T>(_ commonTable: T) -> InsertBuilder where T: XLMetaCommonTable {
        copy {
            $0.commonTables.append(commonTable.definition)
        }
    }
    
    private func copy(modifier: (inout InsertBuilder) -> Void) -> InsertBuilder {
        var newInstance = self
        modifier(&newInstance)
        return newInstance
    }
    
    public func values(_ values: Row) -> InsertBuilder where Row: XLTable, Row.MetaInsert.Row == Row  {
        copy {
            $0.values = Row.MetaInsert(values)
        }
    }
    
    public func build() throws -> any XLInsertStatement<Row> {
        var statement = XLInsertStatementComponents(commonTables: commonTables, insert: insert)
        
        guard let values else {
            throw InternalError.missingValuesClause
        }
        
        statement.components.append(values)
        return AbstractXLInsertStatement(components: statement)
    }
}
