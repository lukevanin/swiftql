//
//  XLDatabase.swift
//  
//
//  Created by Luke Van In on 2023/07/31.
//

import Foundation
import Combine


extension Notification.Name {
    static let XLEntitiesChanged = Notification.Name("swiftql.entitiesChanged")
}

extension String {
    static let XLEntities = "swiftql.entities"
}

extension NotificationCenter {
    
    public func sqlEntitiesChangedPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLEntitiesChanged)
    }
    
    public func sqlEntitiesChangedObserver(queue: OperationQueue, observer: @escaping (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLEntitiesChanged,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    public func postSQLEntitiesChangedNotification(entities: Set<String>) {
        post(
            name: .XLEntitiesChanged,
            object: nil,
            userInfo: [
                String.XLEntities: entities
            ]
        )
    }
}


extension Notification.Name {
    static let XLCommit = Notification.Name("swiftql.commit")
}

extension NotificationCenter {
    
    public func sqlCommitPublisher() -> NotificationCenter.Publisher {
        publisher(for: .XLCommit)
    }
    
    public func sqlCommitObserver(queue: OperationQueue, observer: @escaping (Notification) -> Void) -> NSObjectProtocol {
        addObserver(
            forName: .XLCommit,
            object: nil,
            queue: queue,
            using: observer
        )
    }
    
    public func postSQLCommitNotification() {
        post(
            name: .XLCommit,
            object: nil,
            userInfo: [:]
        )
    }
}


///
/// Constructs a prepared select query statement with parameters.
///
public struct XLRequestBuilder<Row> {
    
    public typealias Parameterize = (inout any XLRequest<Row>) -> Void
    
    private let statement: any XLQueryStatement<Row>
    
    private let parameterize: Parameterize
    
    public init(with statement: any XLQueryStatement<Row>, parameterize: @escaping Parameterize) {
        self.statement = statement
        self.parameterize = parameterize
    }
    
    public func build(with database: XLDatabase) -> any XLRequest<Row> {
        var request = database.makeRequest(with: statement)
        parameterize(&request)
        return request
    }
}


///
/// A prepared select query statement.
///
/// Use the set methods to assign variables parameters to the query.
///
/// Use the fetch methods to execute the query, or use the publish methods to create a Combine publisher
/// that executes the query automatically when any of the tables referenced in the query are modified.
///
public protocol XLRequest<Row> {
    associatedtype Row
    
    ///
    /// Assigns a literal value to an optional named variable parameter.
    ///
    /// - Parameter parameter: Named variable parameter to assign.
    /// - Parameter value: Optional value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable
    
    ///
    /// Assigns a literal value to a variable parameter.
    ///
    /// - Parameter parameter: Named variable parameter to assign.
    /// - Parameter value: Value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    
    ///
    /// Fetches all rows returned by the query.
    ///
    func fetchAll() throws -> [Row]
    
    ///
    /// Fetches the first row returned by the query.
    ///
    func fetchOne() throws -> Row?
    
    ///
    /// Creates a Combine Publisher that emits all rows from the query when any of the tables referenced
    /// by the query are modified.
    ///
    func publish() -> AnyPublisher<[Row], Error>
    
    ///
    /// Creates a Combine Ppublisher that emits the first row from the query when any of the tables
    /// referenced by the query are modified.
    ///
    func publishOne() -> AnyPublisher<Row?, Error>
}

extension XLRequest {
    
    ///
    /// Convenience method used to set an optional named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set a named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set the value of a parameter by its literal string name.
    ///
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


///
/// A prepared statement that modifies the database, such as a create, update, insert, or delete statement.
///
/// `XLWriteRequest` differs from `XLRequest` in that it does not provide methods to return results
/// from executing the request.
///
public protocol XLWriteRequest {
    
    ///
    /// Assigns a literal value to an optional named variable parameter.
    ///
    /// - Parameter parameter: Named variable parameter to assign.
    /// - Parameter value: Optional value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<Optional<T>>, value: T?) where T: XLBindable

    ///
    /// Assigns a literal value to a named variable parameter.
    ///
    /// - Parameter parameter: Named variable parameter to assign.
    /// - Parameter value: Value to assign to the named parameter.
    ///
    mutating func set<T>(parameter reference: XLNamedBindingReference<T>, value: T) where T: XLBindable
    
    ///
    /// Executes the statement.
    ///
    func execute() throws
}

extension XLWriteRequest {
    
    ///
    /// Convenience method used to set an optional named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<Optional<T>>, _ value: T?) where T: XLBindable  {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set a named parameter on the request.
    ///
    public mutating func set<T>(_ parameter: XLNamedBindingReference<T>, _ value: T) where T: XLBindable {
        set(parameter: parameter, value: value)
    }
    
    ///
    /// Convenience method used to set the value of a parameter by its literal string name.
    ///
    public mutating func set<T>(_ name: XLName, _ value: T) where T: XLBindable & XLLiteral {
        set(parameter: XLNamedBindingReference(name: name), value: value)
    }
}


///
/// A database that can execute select, update, insert, create, and delete statements.
///
public protocol XLDatabase {
    
    ///
    /// Constructs a prepared query request from a query statement.
    ///
    func makeRequest<Row>(with statement: any XLQueryStatement<Row>) -> any XLRequest<Row>
    
    ///
    /// Constructs a prepared update request from an update statement.
    ///
    func makeRequest(with statement: any XLUpdateStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared insert request from an insert statement.
    ///
    func makeRequest(with statement: any XLInsertStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared create request from a create statement.
    ///
    func makeRequest(with statement: any XLCreateStatement) -> any XLWriteRequest
    
    ///
    /// Creates a prepared delete request from a delete statement.
    ///
    func makeRequest(with statement: any XLDeleteStatement) -> any XLWriteRequest
}

extension XLDatabase {
    
    ///
    /// Convenience method used to make a request for the database using a request builder.
    ///
    func makeRequest<Row>(with builder: XLRequestBuilder<Row>) -> any XLRequest<Row> {
        builder.build(with: self)
    }
}




