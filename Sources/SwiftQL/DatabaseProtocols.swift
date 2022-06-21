import Foundation
import Combine


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


public protocol SQLRowProtocol {
    func readInt(column: Int) -> Int
    func readDouble(column: Int) -> Double
    func readString(column: Int) -> String
    func readData(column: Int) -> Data
}


protocol SQLPreparedStatementProtocol {
    func sql() -> String
    func execute(bind: (SQLBindingProtocol) throws -> Void, read: (SQLRowProtocol) -> Void) throws -> Void
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
