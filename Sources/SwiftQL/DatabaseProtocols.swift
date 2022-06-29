import Foundation
import Combine


enum SQLSuccess {
    case ok
    case row
    case done
}


protocol SQLBindingProtocol {
    func bind(variable: Int, value: Int64) throws
    func bind(variable: Int, value: Double) throws
    func bind(variable: Int, value: String) throws
    func bind(variable: Int, value: Data) throws
}


public protocol SQLRowProtocol {
    func readInt(column: Int) -> Int64
    func readDouble(column: Int) -> Double
    func readString(column: Int) -> String
    func readData(column: Int) -> Data
}


protocol SQLPreparedStatementProtocol {
    typealias Bind = (SQLBindingProtocol) throws -> Void
    typealias Read = (SQLRowProtocol) -> Void
    func sql() -> String
    func execute(bind: Bind?, read: Read?) throws -> Void
}


enum SQLProviderEvent: String {
    case commit
}


protocol SQLTransactionProtocol {
}


protocol SQLProviderProtocol {

    var eventsPublisher: AnyPublisher<SQLProviderEvent, Error> { get }
    func prepare(sql: String) throws -> SQLPreparedStatementProtocol
    @discardableResult func transaction<T>(transaction: @escaping (SQLTransactionProtocol) throws -> T) async throws -> T
}
