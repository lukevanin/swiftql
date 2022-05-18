//
//  File.swift
//  
//
//  Created by Luke Van In on 2022/05/18.
//

import Foundation


enum SQLSuccess {
    case ok
    case row
    case done
}


protocol SQLBindingProtocol {
    func bind(variable: Int, value: Int) throws
    func bind(variable: Int, value: Double) throws
    func bind<T>(variable: Int, value: T) throws where T: StringProtocol
    func bind<T>(variable: Int, value: T) throws where T: DataProtocol
}


protocol SQLRowProtocol {
    func readInt(column: Int) -> Int
    func readDouble(column: Int) -> Double
    func readString(column: Int) -> String
    func readData(column: Int) -> Data
}

protocol SQLPreparedStatementProtocol {
    func sql() -> String
    func execute(bind: (SQLBindingProtocol) throws -> Void, read: (SQLRowProtocol) -> Void) throws -> Void
}


protocol SQLProviderProtocol {
    
    func prepare(sql: String) throws -> SQLPreparedStatementProtocol
    func transaction<T>(transaction: () throws -> T) throws -> T
}
